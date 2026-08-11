



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
        *(.text.entry)
        *(.text*)
        *(.rodata*)
    } > RAM

    .data : 
    {
        *(.sdata*)
        *(.data*)
    } > RAM

    .bss :
    {
        _sbss = .;
        *(.sbss*)
        *(COMMON)
        *(.bss*)
        _ebss = .;
    } > RAM

}