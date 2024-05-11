#!/bin/bash

ghdl-gcc -m -o test sid_voice_tb

./test --wave=test.ghw
