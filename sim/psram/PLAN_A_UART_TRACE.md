# Plan A diagnostic UART

Only the independent APS QSF enables `SATURN_APS6408_DEBUG_UART`.
The functional BSC, PSRAM protocol, reset gates and RAM ports are unchanged.
The observer uses CLK_50M (50 MHz) and HPS UART1/ttyS1 at 115200 8N1.
Current board pinmux readback UART1USEFPGA at 0xFFD08718 is 1.
COM13 is ttyS0 and must remain available for the Linux console.

Each 11-byte frame is `A5 5A sequence valid ram_lo ram_hi stage cpu_lo cpu_hi input checksum`.
XOR of all 11 bytes is zero. Sequence wraps at 256.
Valid bits 0/1/2 mark fresh RAM/engine/system snapshots respectively.
Snapshots are coherent within each original clock domain, not simultaneous across domains.
Each source freezes data before acknowledgement, holding it until the next request.
The 50MHz observer waits for the synchronized acknowledgement and another cycle before copying.
A stalled source leaves its request pending; frames continue with that domain invalid.

RAM bits:

| Bit | Meaning |
| --- | --- |
| 0 | init_done |
| 1 | init_error |
| 2 | adapter_error |
| 3 | ready |
| 4 | rst_sys |
| 5 | reset |
| 6 | rst_ram |
| 7 | download |
| 8 | bios_download |
| 9 | PSRAM PLL locked |
| 10 | RAMH busy |
| 11 | RAMH read request |
| 13:12 | adapter speed selection |
| 15:14 | OSD clock mode |

CPU bits 15:8 are an 8-bit modulo count of completed instruction fetch bus accesses.
The count resets with CPU reset; it is not a retired instruction count.
Identical counts alone cannot prove a stalled CPU because of wraparound.
CPU bits 7:0 are RES_SYNC_N, CBUS_REQ, CBUS_ID, CACHE_BUSY, MULT_BUSY, CBUS_A[26:24].
Input bit0 is joystick_0[7] (Start), bit1 is Start seen since reset/BIOS download,
bit4 is MSHRES_N, and bit5 is SYSRES_N; other bits are zero.
These Start bits observe the raw first-player joystick bus; absent bits alone
cannot rule out a separate keyboard or lightgun input path.
Stage is the unmodified APS engine stage_code.

Read ttyS1 only after checking that no process owns it. Save `stty -g -F /dev/ttyS1`,
temporarily set raw 115200 8N1 without flow control, use a bounded read, then restore stty.
Do not invoke uartmode kill_all and do not alter the COM13 ttyS0 configuration.
No frames cannot by itself identify a CPU failure; check the UART route/receiver first.

Runner tests cover framing, checksum, sequence, atomic packet contents, mid-packet reset,
stopped engine clock heartbeats, invalid snapshots, and source clock recovery.
The tests include source-stopped resets with acknowledged and pending requests,
and both accelerated 8-cycle and actual 434-cycle baud dividers.
Digital simulation and experimental board observation do not establish timing signoff.
