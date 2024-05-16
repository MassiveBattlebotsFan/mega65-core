#!/bin/bash

ghdl-gcc -m -o sid_coeffs_mux_tb sid_coeffs_mux_tb

./sid_coeffs_mux_tb --wave=sid_coeffs_mux_tb.ghw
