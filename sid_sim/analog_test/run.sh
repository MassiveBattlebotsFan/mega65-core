#!/bin/bash

# lowpass_tb, timer555

RUNFILE="lowpass_tb"

ghdl-gcc -m --std=08 -o $RUNFILE $RUNFILE

sleep 1

./$RUNFILE --wave=$RUNFILE.ghw
