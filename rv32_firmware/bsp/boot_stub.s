# Phase 5.1: the CPU's Program_Counter always resets to 0x00000000
# (BRAM) -- it can never boot directly into SDRAM, no matter what
# fetch_arbiter.vhd can now do. So BRAM's whole job, from here on, is
# to hold this: jump straight to the real program the ESP32 already
# DMA'd into SDRAM at 0x8000_0000 before releasing the CPU from reset
# (bus_interconnect's boot_active mux guarantees the transfer is
# already complete by the time this ever executes).
#
# No stack, no .bss, no C runtime -- reuses bsp/linker.ld unchanged
# (still a fine fit: 4 KiB RAM at 0x0, .text.entry placed first).

.section .text.entry
.global _start

_start:
    li   t0, 0x80000000     # SDRAM firmware base
    jr   t0                 # jalr x0, 0(t0) -- never returns