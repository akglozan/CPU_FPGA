.section .text.entry
.global _start

_start:
    /* 1. Initialize Stack Pointer to Top of RAM (0x00001000) */
    la sp, _estack

    /* 2. Clear .bss Section */
    la t0, _sbss
    la t1, _ebss

bss_check:
    bge t0, t1, bss_clear_done

bss_clear_loop:
    sw zero, 0(t0)
    addi t0, t0, 4
    blt t0, t1, bss_clear_loop

bss_clear_done:
    /* 3. Call main() in C */
    call main

trap_loop:
    j trap_loop
    