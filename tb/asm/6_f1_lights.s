# F1 Starting Lights - Basic Test Version 
# Matches Lab 3 FSM behavior: progressively turn on lights
# Pattern: 0x00 -> 0x01 -> 0x03 -> 0x07 -> 0x0F -> ... -> 0xFF
# Now includes LBU for comprehensive instruction testing

.text
.equ LIGHT_ADDR, 0x100

main:
    LI   s0, LIGHT_ADDR     # Light output address
    LI   a0, 0              # Start with no lights
    
light_on_loop:
    SB   a0, 0(s0)          # Store current pattern
    JAL  ra, increment_light # Call subroutine to get next pattern
    
    LI   t0, 0xFF           # Check if all lights on (0xFF = 0b11111111)
    BNE  a0, t0, light_on_loop
    
    # All lights on (0xFF)
    SB   a0, 0(s0)          # Store final pattern
    
    # Verify the store by reading back (uses LBU)
    LBU  t1, 0(s0)          # Read back the light pattern
    # t1 should now be 0xFF if store worked correctly
    
    # Call lights_off subroutine
    JAL  ra, lights_off
    
    # Return value for test verification
    LI   a0, 255            
    J    end

# Subroutine: Increment light pattern
# Creates sequence: 0 -> 1 -> 3 -> 7 -> 15 -> 31 -> 63 -> 127 -> 255
# Formula: new = (old * 2) + 1
increment_light:
    ADD  a0, a0, a0         # Shift left: a0 = a0 * 2
    ADDI a0, a0, 1          # Add 1: a0 = a0 + 1
    JALR zero, ra, 0        # Return

# Subroutine: Turn lights off
lights_off:
    LI   a0, 0
    SB   a0, 0(s0)
    
    # Verify lights are off by reading back (uses LBU again)
    LBU  t2, 0(s0)          # Read back to confirm
    # t2 should be 0x00
    
    JALR zero, ra, 0        # Return

end:
    J    end                # Infinite loop