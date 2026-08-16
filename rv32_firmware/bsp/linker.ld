ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
    .text :
    {
        . = ALIGN(4);
        *(.text.entry)
        *(.text*)
        . = ALIGN(4);
    } > RAM

    .rodata :
    {
        . = ALIGN(4);
        *(.rodata*)
        *(.srodata*)
        *(.rodata.str1.*)
        . = ALIGN(4);
    } > RAM

    .data : 
    {
        . = ALIGN(4);
        *(.sdata*)
        *(.data*)
        . = ALIGN(4);
    } > RAM

    .bss :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.sbss*)
        *(COMMON)
        *(.bss*)
        _ebss = .;
        . = ALIGN(4);
    } > RAM

    /* Discard unused metadata sections */
    /DISCARD/ :
    {
        *(.comment)
        *(.riscv.attributes)
    }
}