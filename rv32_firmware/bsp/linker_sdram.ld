ENTRY(_start)

MEMORY
{
    /* .text/.rodata/.data/.bss for the real program. Bounded above by
     * DOOM1.WAD's own load address (0x8010_0000) -- WAD bytes are
     * DMA'd in separately by the ESP32, not part of this ELF, so
     * nothing here may reach that far up. 1 MiB budget: a later
     * "region CODE overflowed" error is this limit, not a bug.
     */
    CODE (rwx) : ORIGIN = 0x80000000, LENGTH = 1M

    /* Heap ("zone" memory, Phase 5.2) and stack. Deliberately NOT
     * contiguous with .bss above -- 0x8010_0000..~0x8050_33CB is
     * DOOM1.WAD. Picks back up just past the WAD (rounded up for
     * headroom) and runs to FB_BASE_ADDR, the 64 KiB framebuffer
     * reserved at the top of the 8 MiB chip (rtl/video/vga_pkg.vhd).
     */
    WORK (rw) : ORIGIN = 0x80504000, LENGTH = 0x2EC000  /* ~2.92 MiB, up to 0x807F0000 */
}

/* WORK is carved into four pieces, top to bottom from _estack:
 *
 *   [ _zone_start .. _zone_end )      Doom's Z_Malloc zone (i_system.c
 *                                     I_ZoneBase). The overwhelming
 *                                     majority of WORK -- vanilla Doom
 *                                     needs ~1MiB total (300KiB static
 *                                     + ~700KiB zone) per the RP2040
 *                                     Doom port writeup; this leaves
 *                                     roughly 2.5x that as headroom.
 *   [ _mischeap_start .. _mischeap_end )  Small newlib _sbrk heap
 *                                     (soc_syscalls.c) for the few
 *                                     leftover libc malloc() call
 *                                     sites outside Doom's own zone
 *                                     allocator (see docs/README.md
 *                                     Phase 5.2 notes).
 *   [ _mischeap_end .. _estack )      C stack, growing down from
 *                                     _estack (crt0.s: la sp, _estack).
 *
 * Doom-only regions (only referenced by rv32_firmware/doom/); plain
 * main.c never touches _zone_start/_mischeap_start and is unaffected
 * by this split.
 */
_estack        = ORIGIN(WORK) + LENGTH(WORK);
_stack_limit   = _estack - 0x40000;        /* 256 KiB stack budget */
_mischeap_end  = _stack_limit;
_mischeap_start = _mischeap_end - 0x10000; /* 64 KiB misc/newlib heap */
_zone_start    = ORIGIN(WORK);
_zone_end      = _mischeap_start;          /* ~2.66 MiB for Doom's zone */

SECTIONS
{
    .text :
    {
        . = ALIGN(4);
        *(.text.entry)
        *(.text*)
        . = ALIGN(4);
    } > CODE

    .rodata :
    {
        . = ALIGN(4);
        *(.rodata*)
        *(.srodata*)
        *(.rodata.str1.*)
        . = ALIGN(4);
    } > CODE

    .data :
    {
        . = ALIGN(4);
        *(.sdata*)
        *(.data*)
        . = ALIGN(4);
    } > CODE

    .bss :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.sbss*)
        *(COMMON)
        *(.bss*)
        _ebss = .;
        . = ALIGN(4);
    } > CODE

    /DISCARD/ :
    {
        *(.comment)
        *(.riscv.attributes)
    }
}
