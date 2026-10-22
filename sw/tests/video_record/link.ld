/* Diagnostic simulation memories, matching the SoC ROM/SRAM address ranges. */
ENTRY(_start)
MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    SRAM (rw) : ORIGIN = 0x00010000, LENGTH = 32K
}
SECTIONS
{
    .text : ALIGN(8) { KEEP(*(.init)) *(.text*) *(.rodata*) } > ROM
    .signature (NOLOAD) : { . = . + 256; } > SRAM
    .data : ALIGN(4) { __data_start = .; *(.sdata*) *(.data*) __data_end = .; } > SRAM AT > ROM
    __data_load = LOADADDR(.data);
    __global_pointer$ = __data_start + 0x800;
    .bss (NOLOAD) : ALIGN(4) { __bss_start = .; *(.sbss*) *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > SRAM
    __stack_top = ORIGIN(SRAM) + LENGTH(SRAM);
    /DISCARD/ : { *(.eh_frame*) *(.comment*) }
    ASSERT(__bss_end < __stack_top - 4096, "diagnostic SRAM overflow")
    ASSERT(LOADADDR(.data) + SIZEOF(.data) <= ORIGIN(ROM) + LENGTH(ROM), "diagnostic ROM overflow")
}
