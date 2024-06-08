#!/bin/bash

# lowpass_tb, timer555

RUNFILE="sid_filters_tb"

ghdl-gcc -m --std=08 -frelaxed -o $RUNFILE $RUNFILE

sleep 1

./$RUNFILE --wave=$RUNFILE.ghw
