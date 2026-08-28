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

_estack     = ORIGIN(WORK) + LENGTH(WORK);
_zone_start = ORIGIN(WORK);
_zone_end   = _estack;

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