#!/bin/bash

# lowpass_tb

ghdl-gcc -m -o 555 timer555

sleep 1

./555 --wave=555.ghw
