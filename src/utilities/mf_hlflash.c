#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include <memory.h>

#include "mhexes.h"
#include "mf_hlflash.h"
#include "mf_progress.h"
#include "nohysdc.h"
#include "mf_selectcore.h"
#include "crc32accl.h"
#include "mf_buffers.h"
#include "mf_utility.h"

#include "qspiflash.h"
#include "s25flxxxl.h"
#include "s25flxxxs.h"

#ifdef STANDALONE
#include "mf_screens_solo.h"
#else
#include "mf_screens.h"
#endif

#define MFHF_FLASH_MAX_RETRY 10

uint8_t mfhf_slot0_erase_list[16] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };

uint8_t mfhf_core_file_state = MFHF_LC_NOTLOADED;

static enum qspi_flash_erase_block_size mfhf_erase_block_size;
static void * qspi_flash_device = NULL;

unsigned char slot_count = 0;


#ifdef NO_ATTIC
#define SECTORBUFFER 0x50000L
#define CLUSTERBUFFER 0x40000L
#else
#define SECTORBUFFER 0x8000000L
#endif

#ifdef QSPI_FLASH_INSPECT
void mfhl_flash_inspector(void)
{
  uint8_t clear = 1;
  uint16_t i;
  uint32_t addr = 0;

  while (1) {
    if (clear) {
      mhx_clearscreen(0x20, MHX_A_WHITE);
      lcopy((long)mf_screens_menu.screen_start + MFMENU_INSPECT_HEADER * 40, mhx_base_scr, 40);
      lcopy((long)mf_screens_menu.screen_start + MFMENU_INSPECT_FOOTER * 40, mhx_base_scr + 23*40, 80);
      mhx_hl_lines(0, 0, MHX_A_INVERT | MHX_A_LGREY);
      mhx_hl_lines(23, 24, MHX_A_INVERT | MHX_A_LGREY);
      clear = 0;
    }

    qspi_flash_read(qspi_flash_device, addr, data_buffer, 512);;
    mhx_set_xy(7, 0);
    mhx_writef(MHX_W_REVON MHX_W_LGREY "%07lx" MHX_W_WHITE MHX_W_REVOFF, addr);
    for (i = 0; i < 256; i++) {
      if (!(i & 15))
        mhx_writef("\n  %02x: ", i);
      mhx_writef("%02x", data_buffer[i]);
    }

    mhx_getkeycode(0);
    switch (mhx_lastkey.code.key) {
    case 0x13: // HOME
      addr &= (mfu_slot_size - 1) ^ 0xffffffff;
      break;
    case 0x93: // CLRHOME
      addr = 0;
      break;
    case 0x1d: // RIGHT
      addr += 0x100;
      break;
    case 0x9d: // LEFT
      addr -= 0x100;
      break;
    case 0x91: // DOWN
      addr += 0x1000;
      break;
    case 0x11: // UP
      addr -= 0x1000;
      break;
    case '.': // PERIOD/LESSER
      addr += 0x10000;
      break;
    case ',': // KOMMA/GREATER
      addr -= 0x10000;
      break;
    case ';': // SEMIKOLON
      addr += mfu_slot_size;
      break;
    case ':': // COLON
      addr -= mfu_slot_size;
      break;
    case 0x03:
    case 0x1f:
      return;
    /*
    case 0x50:
    case 0x70:
      query_flash_protection(addr);
      mhx_press_any_key(0, MHX_A_NOCOLOR);
      break;
    */
    case 0xf2: // F2
      clear = 1;
      mhx_writef("\n\nReally?");
      mhx_getkeycode(MHX_GK_WAIT);
      if (mhx_lastkey.code.key != 89)
        break;
      // Erase page, write page, read it back
      mhx_writef("\nErase... ");
      qspi_flash_erase(qspi_flash_device, mfhf_erase_block_size, addr);
      // Some known data
      for (i = 4; i < 256; i++) {
        data_buffer[i] = i;
      }
      data_buffer[0] = addr >> 24L;
      data_buffer[1] = addr >> 16L;
      data_buffer[2] = addr >> 8L;
      data_buffer[3] = addr >> 0L;
      // Now program it
      mhx_writef("Program... \n");
      qspi_flash_program(qspi_flash_device, qspi_flash_page_size_256, addr, data_buffer);
      // dummy read!
      qspi_flash_read(qspi_flash_device, 0, data_buffer, 512);;
      mhx_press_any_key(0, MHX_A_NOCOLOR);
      break;
    }
    if (addr > 0xff0fffff)
      addr = 0;
    else if (addr >= (slot_count * mfu_slot_size))
      addr = (slot_count * mfu_slot_size) - 0x100;
  }
}
#endif

int8_t mfhf_init() {
  unsigned int size;

  // Return an error for hardware models that do not have a flash chip.
  if (hw_model_id == 0x00 || hw_model_id == 0xFE) {
    return 1;
  }

  // Select the flash chip device driver based on the hardware model ID.
#if defined(QSPI_STANDALONE)
  if (hw_model_id == 0x60 || hw_model_id == 0x61 || hw_model_id == 0x62 || hw_model_id == 0xFD) {
    qspi_flash_device = s25flxxxl;
  }
  else {
    qspi_flash_device = s25flxxxs;
  }
#elif defined(QSPI_S25FLXXXL)
  qspi_flash_device = s25flxxxl;
#elif defined(QSPI_S25FLXXXS)
  qspi_flash_device = s25flxxxs;
#else
#error "Failed to select low-level flash chip device driver."
#endif

  if (qspi_flash_init(qspi_flash_device)) {
    return 1;
  }

  if (qspi_flash_get_size(qspi_flash_device, &size) != 0) {
    return 1;
  }

  if (qspi_flash_get_max_erase_block_size(qspi_flash_device, &mfhf_erase_block_size) != 0) {
    return 1;
  }

  slot_count = size / mfu_slot_mb;

#ifdef QSPI_VERBOSE
  {
    uint8_t i;
    enum qspi_flash_page_size page_size;
    unsigned int page_size_bytes;
    BOOL erase_block_sizes[qspi_flash_erase_block_size_last];

    if (qspi_flash_get_page_size(qspi_flash_device, &page_size) != 0) {
      return 1;
    }

    if (get_page_size_in_bytes(page_size, &page_size_bytes) != 0) {
      return 1;
    }

    for (i = 0; i < qspi_flash_erase_block_size_last; ++i) {
      if (qspi_flash_get_erase_block_size_support(qspi_flash_device, (enum qspi_flash_erase_block_size) i,
                                                  &erase_block_sizes[i]) != 0) {
        return 1;
      }
    }

    mhx_writef("Flash size   = %u MB\n"
               "Flash slots  = %u x %u MB\n",
               size, (unsigned int) slot_count, (unsigned int) mfu_slot_mb);
    mhx_writef("Erase sizes  =");
    if (erase_block_sizes[qspi_flash_erase_block_size_4k])
      mhx_writef(" 4K");
    if (erase_block_sizes[qspi_flash_erase_block_size_32k])
      mhx_writef(" 32K");
    if (erase_block_sizes[qspi_flash_erase_block_size_64k])
      mhx_writef(" 64K");
    if (erase_block_sizes[qspi_flash_erase_block_size_256k])
      mhx_writef(" 256K");
    mhx_writef("\n");
    mhx_writef("Page size    = %u\n", page_size_bytes);
    mhx_writef("\n");
    mhx_press_any_key(0, MHX_A_NOCOLOR);
  }
#endif

  return 0;
}

int8_t mfhf_read_core_header_from_flash(uint8_t slot) {
  // Check specified slot index.
  if (slot >= slot_count) return 1;

  // Read core header for the specified slot.
  qspi_flash_read(qspi_flash_device, slot * mfu_slot_size, data_buffer, 512);
  return 0;
}

void mfhf_display_sderror(char *error, uint8_t error_code) {
  mhx_draw_rect(3, 12, 32, 2, "Load Error", MHX_A_ORANGE, 1);
  mhx_write_xy(20 - (mhx_strlen(error) >> 1), 13, error, MHX_A_ORANGE);
  if (error_code != NHSD_ERR_NOERROR) {
    mhx_set_xy(9, 14);
    mhx_writef(MHX_W_ORANGE "SD Card Error Code $%02X", error_code);
  }
  mhx_press_any_key(MHX_AK_NOMESSAGE|MHX_AK_ATTENTION, MHX_A_NOCOLOR);
}

#if 0
void mfhf_debug_memory_block(uint16_t offset, uint32_t dbg_addr)
{
  uint16_t i;

  for (i = 0; i < 256; i++) {
    if (!(i & 15))
      mhx_writef(MHX_W_WHITE "%07lx:", dbg_addr + i);
    if (data_buffer[offset + i] != buffer[offset + i])
      mhx_setattr(MHX_A_RED);
    else
      mhx_setattr(MHX_A_LGREEN);
    mhx_writef("%02x", data_buffer[offset + i]);
  }
  mhx_press_any_key(0, MHX_A_WHITE);
}
#endif

int8_t mfhf_load_core() {
  uint8_t err, first;
  uint16_t length;
  uint32_t addr, addr_len, core_crc;
#ifdef NO_ATTIC
  uint32_t clusterptr;
#endif /* NO_ATTIC */

  mfhf_core_file_state = MFHF_LC_NOTLOADED;

  // cover menu bar keys except STOP
  lfill(mhx_base_scr + 23*40, 0xa0, 60);

  // setup progress bar
  mfp_init_progress(mfu_slot_mb, 17, '-', " Load Core ", MHX_A_WHITE);
  if (mfsc_corehdr_length < mfu_slot_size) {
    // fill unused slot area grey
    length = mfsc_corehdr_length >> 16;
    if (mfsc_corehdr_length & 0xffff)
      length++;
    mfp_set_area(length, 255, 0x69, MHX_A_LGREY);
  }
  else
    length = 128;
  addr_len = mfsc_corehdr_length;

  // open file
  if ((err = nhsd_open(mfsc_corefile_inode))) {
    // Couldn't open the file.
    mfhf_display_sderror("Could not open core file!", err);
    return 0;
  }

  // mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);

  // load file to attic ram
#ifdef NO_ATTIC
  make_crc32_tables(data_buffer, cfi_data);
  init_crc32();
  /* we need a chain of the 64k cluster starts, to iterate backwards later*/
  clusterptr = CLUSTERBUFFER;
  first = 1;
#endif /* NO_ATTIC */
  mfp_start(0, MFP_DIR_UP, 0x5f, MHX_A_WHITE, " Load Core ", MHX_A_WHITE);
  for (addr = 0; addr < mfsc_corehdr_length; addr += 512) {
#ifdef NO_ATTIC
    if ((addr & 0xffffUL) == 0) {
      /*mhx_writef(MHX_W_HOME MHX_W_WHITE "%08lx %08lx %08lx %02x", clusterptr, nhsd_open_pos.cluster, nhsd_open_pos.sector, nhsd_open_pos.sector_in_cluster);*/
      lcopy((long)&nhsd_open_pos, clusterptr, sizeof(nhsd_position_t));
      clusterptr += sizeof(nhsd_position_t);
    }
#endif /* NO_ATTIC */
    if ((err = nhsd_read()))
      break;
#ifdef NO_ATTIC
    if (first) {
      // the first sector has the real length and the CRC32
      addr_len = *(uint32_t *)(buffer + MFSC_COREHDR_LENGTH);
      core_crc = *(uint32_t *)(buffer + MFSC_COREHDR_CRC32);
      // set CRC bytes to pre-calculation value
      *(uint32_t *)(buffer + MFSC_COREHDR_CRC32) = 0xf0f0f0f0UL;
      if (addr_len != mfsc_corehdr_length) {
        err = NHSD_ERR_INVALID_MBR;
        break;
      }
      first = 0;
    }
    update_crc32(addr_len - addr > 255 ? 0 : addr_len - addr, buffer);
    if (addr_len - addr > 255) {
      update_crc32(addr_len - addr - 256 > 255 ? 0 : addr_len - addr - 256, buffer + 256);
    }
#else
    lcopy((long)buffer, 0x8000000L + addr, 512);
#endif
    mfp_progress(addr);
    // let user abort load
    mhx_getkeycode(MHX_GK_PEEK);
    if (mhx_lastkey.code.key == 0x03 || mhx_lastkey.code.key == 0x1b)
      return 0;
  }
  if (err != NHSD_ERR_NOERROR) {
#ifdef NO_ATTIC
    if (err == NHSD_ERR_INVALID_MBR)
      mfhf_display_sderror("Core length header offset error!", err);
    else
#endif /* NO_ATTIC */
      mfhf_display_sderror("Error while loading core file!", err);
    return 0;
  }
  nhsd_close();

#if NO_ATTIC
  if (core_crc != get_crc32() || first) {
    mfhf_display_sderror("CRC32 Checksum Error!", NHSD_ERR_NOERROR);
    return MFHF_LC_NOTLOADED;
  } else
    mfhf_core_file_state = MFHF_LC_ATTICOK;
#endif /* NO_ATTIC */

  if (addr & 0xffff)
    mfp_set_area(addr >> 16, 1, 0x5f, MHX_A_WHITE);

  // mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);

#ifndef NO_ATTIC
  // check crc32 of file as a check for ATTIC RAM, too
  mfp_start(0, MFP_DIR_UP, 0xa0, MHX_A_WHITE, " Checking CRC32 ", MHX_A_WHITE);
  make_crc32_tables(data_buffer, cfi_data);
  init_crc32();
  for (first = 1, addr = 0; addr < mfsc_corehdr_length; addr += 256) {
    // we don't need the part string anymore, so we reuse this buffer
    // note: part is only used in probe_qspi_flash
    lcopy(0x8000000L + addr, (long)buffer, 256);
    if (first) {
      // the first sector has the real length and the CRC32
      addr_len = *(uint32_t *)(buffer + MFSC_COREHDR_LENGTH);
      core_crc = *(uint32_t *)(buffer + MFSC_COREHDR_CRC32);
      // set CRC bytes to pre-calculation value
      *(uint32_t *)(buffer + MFSC_COREHDR_CRC32) = 0xf0f0f0f0UL;
      if (addr_len != mfsc_corehdr_length)
        break;
      first = 0;
    }
    update_crc32(addr_len - addr > 255 ? 0 : addr_len - addr, buffer);
    mfp_progress(addr);
    // let user abort load
    mhx_getkeycode(MHX_GK_PEEK);
    if (mhx_lastkey.code.key == 0x03 || mhx_lastkey.code.key == 0x1b)
      return 0;
  }
  if (core_crc == get_crc32() && !first)
    mfhf_core_file_state = MFHF_LC_ATTICOK;
  mfp_set_area(0, length, mfhf_core_file_state != MFHF_LC_ATTICOK ? 'E' : ' ', MHX_A_INVERT|(mfhf_core_file_state != MFHF_LC_ATTICOK ? MHX_A_RED : MHX_A_GREEN));

  if (mfhf_core_file_state != MFHF_LC_ATTICOK) {
    mfhf_display_sderror("CRC32 Checksum Error!", NHSD_ERR_NOERROR);
    return MFHF_LC_NOTLOADED;
  }
  // set potentially changed flags after load & crc check
  lpoke(0x8000000L + MFSC_COREHDR_BOOTFLAGS, mfsc_corehdr_bootflags);
#endif /* !NO_ATTIC */

  // mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);

  return mfhf_core_file_state;
}

int8_t mfhf_load_core_from_flash(uint8_t slot, uint32_t addr_len) {
  uint32_t addr, flash_addr;

  mfhf_core_file_state = MFHF_LC_NOTLOADED;

  // cover menu bar keys except STOP
  lfill(mhx_base_scr + 23*40, 0xa0, 60);

  // setup progress bar
  mfp_init_progress(mfu_slot_mb, 17, '-', " Read Core Header ", MHX_A_WHITE);

  // load core from qspi to attic ram
  mfp_start(0, MFP_DIR_UP, 0xa0, MHX_A_WHITE, " Read Core Header ", MHX_A_WHITE);
  for (flash_addr = mfu_slot_size * slot, addr = 0; addr < addr_len; flash_addr += 512, addr += 512) {
    qspi_flash_read(qspi_flash_device, flash_addr, data_buffer, 512);;
    lcopy((long)&data_buffer, 0x8000000L + addr, 512);
    mfp_progress(addr);
    if (mhx_lastkey.code.key == 0x03 || mhx_lastkey.code.key == 0x1b)
      return mfhf_core_file_state;
  }

  // set potentially changed flags after load & crc check
  lpoke(0x8000000L + MFSC_COREHDR_BOOTFLAGS, mfsc_corehdr_bootflags);

  mfsc_corehdr_length = addr_len;
  mfhf_core_file_state = MFHF_LC_ATTICOK;

  // do a dummy sdcard action in hope that this resets the bus
  // TODO: solve underlaying problem!
  nhsd_init(NHSD_INIT_BUS0_FB1, buffer);

  return mfhf_core_file_state;
}

#ifdef NO_ATTIC
int8_t mfhf_load_sector_to_buffer(uint32_t addr)
{
  uint32_t offset;
  uint8_t err = 0;
  // load block start from cluster buffer
  offset = ((addr >> 16) & 0x7f) * sizeof(nhsd_position_t);
  lcopy(CLUSTERBUFFER + offset, (long)&nhsd_open_pos, sizeof(nhsd_position_t));

  /* mhx_writef(MHX_W_HOME MHX_W_WHITE "L %08lx %08lx %08lx %08lx %02x", addr, offset, nhsd_open_pos.cluster, nhsd_open_pos.sector, nhsd_open_pos.sector_in_cluster);
  mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR); */

  // now load 64k to bank 5
  for (offset = 0; offset < 0x10000UL && !err; offset += 512) {
    if ((err = nhsd_read()) && err != NHSD_ERR_EOF)
      return err;
    lcopy((long)buffer, SECTORBUFFER + offset, 512);
    /* mhx_set_xy(0, 1);
    mhx_writef("%08lx %08lx ", offset, SECTORBUFFER + offset);
    mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR); */
  }
  return 0;
}
#endif /* NO_ATTIC */

int8_t mfhf_sectors_differ(uint32_t attic_addr, uint32_t flash_addr, uint32_t size)
{
#ifdef NO_ATTIC
  uint8_t err;
#endif /* NO_ATTIC */

  /*mhx_writef(MHX_W_HOME MHX_W_WHITE "C %08lx %08lx %08lx             ", attic_addr, flash_addr, size);
  mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);*/

  while (size > 0) {

#ifdef NO_ATTIC
    // we might need to read the sector into bank 5
    if ((attic_addr & 0xffffUL) == 0)
      if ((err = mfhf_load_sector_to_buffer(attic_addr))) {
        mfhf_display_sderror("Sector read error!", err);
        return 1;
      }
    lcopy(SECTORBUFFER + (attic_addr & 0xffff), (unsigned long)data_buffer, 512);
#else
    lcopy(SECTORBUFFER + attic_addr, (unsigned long)data_buffer, 512);
#endif /* NO_ATTIC */

    if (qspi_flash_verify(qspi_flash_device, flash_addr, data_buffer, 512) != 0) {
#if 0
//#ifdef SHOW_FLASH_DIFF
      mhx_writef("\nVerify error  ");
      mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
      mhx_writef(MHX_W_WHITE MHX_W_CLRHOME "attic_addr=$%08lX, flash_addr=$%08lX\n", attic_addr, flash_addr);
      qspi_flash_read(qspi_flash_device, flash_addr, data_buffer, 512);;
      lcopy(SECTORBUFFER + (attic_addr & 0xffff), (long)buffer, 512);
      debug_memory_block(MHX_AK_NOMESSAGE, flash_addr);
      debug_memory_block(256, flash_addr);
      mhx_writef("comparing read data against reread yields %d\n", qspi_flash_verify(qspi_flash_device, flash_addr, data_buffer, 512));
      mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
      mhx_clearscreen(' ', MHX_A_WHITE);
      mhx_set_xy(0, 0);
#endif
      return 1;
    }
    attic_addr += 512;
    flash_addr += 512;
    size -= 512;
  }
  return 0;
}

int8_t mfhf_erase_some_sectors(uint32_t start_addr, uint32_t end_addr)
{
  uint32_t addr = start_addr;
  uint32_t size;

  if (get_erase_block_size_in_bytes(mfhf_erase_block_size, &size) != 0) {
    return 1;
  }

  while (addr < end_addr) {

#if 0
    mhx_set_xy(0, 4);
    mhx_writef(MHX_W_WHITE
               "start_addr  = %08lx  \n"
               "start_block = %08lx  \n"
               "size        = %08lx  \n"
               "size_blocks = %08lx  \n", start_addr, start_addr >> 16, size, size >> 16);
    mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
#endif

    POKE(0xD020, 2);
    if (qspi_flash_erase(qspi_flash_device, mfhf_erase_block_size, addr) != 0) {
      return 1;
    }
    POKE(0xD020, 0);

    mfp_set_area(addr >> 16, size >> 16, '0', MHX_A_INVERT|MHX_A_LRED);

    addr += size;
  }

  return 0;
}

int8_t mfhf_flash_sector(uint32_t addr, uint32_t end_addr, uint32_t size)
{
  uint32_t wraddr;
  uint8_t tries;
#ifdef NO_ATTIC
  uint8_t err;
#endif /* NO_ATTIC */

  // try 10 times to erase/write the sector
  for (tries = 0; tries < MFHF_FLASH_MAX_RETRY; tries++) {
    // Verify the sector to see if it is already correct
    if (!mfhf_sectors_differ(addr - end_addr, addr, size)) {
      mfp_set_area((addr - end_addr) >> 16, size >> 16, '*', MHX_A_INVERT|MHX_A_WHITE);
      break;
    }

    // Erase Sector
    mfhf_erase_some_sectors(addr, addr + size);

    // Program sector
    for (wraddr = addr + size; wraddr > addr; wraddr -= 256) {
#ifdef NO_ATTIC
      // we might need to read the sector into bank 5
      if ((wraddr & 0xffffUL) == 0) {
        if ((err = mfhf_load_sector_to_buffer(wraddr - end_addr - 0x10000U))) {
          mfhf_display_sderror("Sector read error!", err);
          return 1;
        }
      }

      lcopy(SECTORBUFFER + ((wraddr - 256 - end_addr) & 0xffffU), (unsigned long)data_buffer, 256);

      /* mhx_set_xy(0, 1);
      mhx_writef("%08lx %08lx %08lx ", wraddr - 256, (wraddr - 256 - end_addr) & 0xffffU, SECTORBUFFER + ((wraddr - 256 - end_addr) & 0xffffU));
      mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR); */
#else
      lcopy(SECTORBUFFER + wraddr - 256 - end_addr, (unsigned long)data_buffer, 256);
#endif /* NO_ATTIC */
      // display sector on screen
      // lcopy(SECTORBUFFER+wraddr-mfu_slot_size*slot,0x0400+17*40,256);
      POKE(0xD020, 3);
      if (qspi_flash_program(qspi_flash_device, qspi_flash_page_size_256, wraddr - 256, data_buffer) != 0) {
        break;
      }
      POKE(0xD020, 0);
      mfp_progress(wraddr - 256 - end_addr);
    }
  }

  // if we failed 10 times, we abort with the option for the flash inspector
  if (tries == MFHF_FLASH_MAX_RETRY) {
    mhx_move_xy(0, 10);
    mhx_writef("ERROR: Could not write to flash after\n%d tries.\n", tries);

    // secret Ctrl-F (keycode 0x06) will launch flash inspector,
    // but only if QSPI_FLASH_INSPECTOR is defined!
    // otherwise: endless loop!
#ifdef QSPI_FLASH_INSPECT
    mhx_writef("Press Ctrl-F for Flash Inspector.\n");

    while (PEEK(0xD610))
      POKE(0xD610, 0);
    while (PEEK(0xD610) != 0x06)
      POKE(0xD610, 0);
    while (PEEK(0xD610))
      POKE(0xD610, 0);
    mfhl_flash_inspector();
#else
    // TODO: re-erase start of slot 0, reprogram flash to start slot 1
    mhx_writef("\nPlease turn the system off!\n");
    // don't let the user do anything else
    while (1)
      POKE(0xD020, PEEK(0xD020) & 0xf);
#endif
    // don't do anything else, as this will result in slot 0 corruption
    // as global addr gets changed by flash_inspector
    return 1;
  }

  return 0;
}

void mfhf_calc_el_addr(const uint8_t el_sector, uint32_t *addr, uint32_t *size)
{
  uint32_t mask;

  *addr = ((uint32_t)(el_sector & mfu_slot_pagemask)) << 16;
  get_erase_block_size_in_bytes(mfhf_erase_block_size, size);
  // we need to align the address to the bits
  mask = 0UL - *size; // size to get mask
  *addr &= mask;
}

int8_t mfhf_flash_core(uint8_t selected_file, uint8_t slot) {
  uint32_t addr, end_addr, size, el_addr, el_size;
  uint8_t cnt;
  int8_t el_pos = -1;

  /*
   * Flow of high level flashing progress:
   *
   * - erase first 1M of flash
   * - for each sector starting from top of flash slot going down:
   *   - verify sector with data, if equal: mark as done and got to next sector
   *   - otherwise:
   *     - check if we flashed this sector MFHF_FLASH_MAX_RETRY times, and abort if exceeded
   *     - erase sector (256k, 64k, or even 4k)
   *     - write sector data in 256 byte chunks reading data either from attic or from disk
   *     - start over with verification of sector
   * 
   * How does flashing differ from erasing? Just cut out verfiy and write steps and you have
   * erasing.
   * 
   */

#ifdef NO_ATTIC
  if (selected_file == MFSC_FILE_VALID)
    if ((cnt = nhsd_open(mfsc_corefile_inode))) {
      // Couldn't open the file.
      mfhf_display_sderror("Could not open core file!", cnt);
      return 0;
    }
#endif

  // cover STOP menubar option with warning
  lcopy((long)mf_screens_menu.screen_start + MFMENU_EDIT_FLASHING * 40, mhx_base_scr + 23*40, 80);
  mhx_hl_lines(23, 24, MHX_A_LGREY|MHX_A_INVERT);

  /*
   * Special handling for slot 0
   *
   * first erase all sectors in the slot 0 cores erase list, that
   * was loaded by scan_core_information
   *
   */
  if (!slot) {
    for (cnt = 0; cnt < 16 && mfhf_slot0_erase_list[cnt] != 0xff; cnt++) {
      mfhf_calc_el_addr(mfhf_slot0_erase_list[cnt], &addr, &size);
      mfhf_erase_some_sectors(addr, addr + size);
    }
    // find end of erase list
    for (el_pos = 15; el_pos > -1 && mfsc_corehdr_erase_list[el_pos] == 0xff; el_pos--);
  }
  /*
   * end of special handling for slot 0 erase list
   */

  // set end_addr to the START OF THE SLOT (flashing downwards!)
  end_addr = mfu_slot_size * slot;

  /*
  mhx_set_xy(0, 1);
  mhx_writef(MHX_W_WHITE "SLOT_SIZE = %08lx  \nSLOT      = %d\nend_addr  = %08lx  \n", mfu_slot_size, slot, end_addr);
  */

  // Setup progress bar
  mfp_start(0, MFP_DIR_DOWN, '*', MHX_A_INVERT|MHX_A_WHITE, " Erasing Slot ", MHX_A_WHITE);

  if (selected_file == MFSC_FILE_ERASE)
    // if we are flashing slot 0 or erasing a slot, we
    // erase the full slot first
    size = mfu_slot_size;
  else {
    // if we are not flashing factory slot, just erase the first sector
    // to get rid of the core header and at least the sector after that
    get_erase_block_size_in_bytes(mfhf_erase_block_size, &size);
  }

  // now erase what is needed
  mfhf_erase_some_sectors(end_addr, end_addr + size);

  // if it was erase only, we jump to the end!
  if (selected_file == MFSC_FILE_ERASE)
    goto mfhf_flash_finish;

  mfp_start(0, MFP_DIR_DOWN, '*', MHX_A_INVERT|MHX_A_WHITE, " Flash Core to Slot ", MHX_A_WHITE);

  // only flash up to the files length
  addr = end_addr + mfu_slot_size;

#undef SHORTFLASHDEBUG

#ifdef SHORTFLASHDEBUG
  mhx_set_xy(0,0);
  mhx_writef(MHX_W_WHITE "end  = %08lx\naddr = %08lx\n", end_addr, addr);
  mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
#endif
  get_erase_block_size_in_bytes(mfhf_erase_block_size, &size);
  while (addr > end_addr) {
    addr -= size;

#ifdef SHORTFLASHDEBUG
    mhx_writef(MHX_W_WHITE MHX_W_HOME "addr = %08lx\nsize = %08lx\n                  \n                  \n                     \n", addr, size);
#endif

    // if we are flashing a file, skip over sectors without data
    // this works because at this point addr points at the start of the sector that is being flashed
    if ((addr - end_addr) >= mfsc_corehdr_length) {
#ifdef SHORTFLASHDEBUG
      mhx_writef("skip\n");
#endif
      continue;
    }

    /* check addr against erase list, skip if match, and advance erase_list down */
    if (!slot && el_pos > -1) {
      mfhf_calc_el_addr(mfsc_corehdr_erase_list[el_pos], &el_addr, &el_size);
      if (el_addr == addr) {
        el_pos--;
        continue;
      }
    }

#ifdef SHORTFLASHDEBUG
    mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
#endif

    if (mfhf_flash_sector(addr, end_addr, size))
      return 1;
  }

  /* now flash all sectors from erase list */
  if (!slot)
    for (el_pos = 15; el_pos > -1; el_pos--) {
      if (mfsc_corehdr_erase_list[el_pos] == 0xff || mfsc_corehdr_erase_list[el_pos] == 0x00)
        continue;
      mfhf_calc_el_addr(mfsc_corehdr_erase_list[el_pos], &el_addr, &el_size);
      if (mfhf_flash_sector(el_addr, 0, el_size))
        return 1;
    }

mfhf_flash_finish:
  mhx_draw_rect(4, 12, 30, 2, "Finished Flashing", MHX_A_GREEN, 1);
  mhx_write_xy(5, 13, (selected_file == MFSC_FILE_VALID) ? "Core was successfully flashed." : "Slot was successfully erased.", MHX_A_GREEN);
  mhx_set_xy(5, 14);
  mhx_press_any_key(MHX_AK_ATTENTION, MHX_A_GREEN);

  return 0;
}
