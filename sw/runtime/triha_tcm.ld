/* Test-platform memory layout; does not define the production SoC address map. */
ENTRY(_start)
MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128K
}
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
__stack_top = ORIGIN(RAM) + LENGTH(RAM);
__stack_bottom = __stack_top - 16K;
SECTIONS
{
    .text : ALIGN(4)
    {
        KEEP(*(.init))
        *(.text*)
        *(.rodata*)
    } > RAM :text
    .data : ALIGN(4)
    {
        __data_start = .;
        *(.sdata*)
        *(.data*)
        __data_end = .;
    } > RAM :data
    __global_pointer$ = __data_start + 0x800;
    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM :data
    /DISCARD/ : { *(.eh_frame*) }
    ASSERT(__bss_end <= __stack_bottom, "Test TCM code/data overlaps stack reserve")
}
