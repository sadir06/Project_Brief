#!/bin/bash

# Clean up any previous obj_dir
rm -rf obj_dir/
rm -rf test_out/obj_dir/
rm -rf test_out/7_f1_lights_other/obj_dir/

# Assemble the code
./assemble.sh asm/7_f1_lights_other.s

# Create empty data memory file since memory module expects data.hex
touch test_out/7_f1_lights_other/data.hex

# Copy hex files for verilator
cp test_out/7_f1_lights_other/program.hex ./program.hex
cp test_out/7_f1_lights_other/data.hex ./data.hex

# Run Verilator with F1 testbench
verilator -Wall -Wno-fatal --trace \
          -cc ../rtl/top.sv \
          --exe ./tests/f1_lights_tb.cpp \
          -y ../rtl/ \
          --prefix "Vdut" \
          -o Vdut

# Build C++ project
make -j -C obj_dir/ -f Vdut.mk Vdut

# Run executable
./obj_dir/Vdut

# Move waveform and obj_dir to test directory
mv f1_lights.vcd test_out/7_f1_lights_other/waveform.vcd 2>/dev/null
mv obj_dir test_out/

# Clean up
rm -f program.hex data.hex