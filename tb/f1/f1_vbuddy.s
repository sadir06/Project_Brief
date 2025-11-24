# F1 Starting Lights - Vbuddy Demo Version
# Visual display on neopixels with trigger input

.text
.equ LIGHT_ADDR, 0x100
.equ TRIGGER_ADDR, 0x200

main:
    LI   s0, LIGHT_ADDR
    LI   s1, TRIGGER_ADDR
    
wait_trigger:
    LBU  t0, 0(s1)          # Read trigger
    BNE  t0, zero, start_sequence
    J    wait_trigger

start_sequence:
    LI   a0, 0
    
lights_on:
    SB   a0, 0(s0)
    JAL  ra, delay
    
    ADDI t1, a0, 0
    ADD  a0, a0, a0
    ADDI a0, a0, 1
    
    LI   t0, 0xFF
    BNE  a0, t0, lights_on
    
    SB   a0, 0(s0)          # All lights on
    JAL  ra, delay_long     # Hold before off
    
lights_off:
    LI   a0, 0
    SB   a0, 0(s0)
    J    main

delay:
    LI   t2, 100000
delay_loop:
    ADDI t2, t2, -1
    BNE  t2, zero, delay_loop
    JALR zero, ra, 0

delay_long:
    LI   t2, 300000
delay_long_loop:
    ADDI t2, t2, -1
    BNE  t2, zero, delay_long_loop
    JALR zero, ra, 0