/* Generated SRAM execution image; ROM jumps to _start. */
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 32768 }
__stack_top = ORIGIN(RAM) + LENGTH(RAM);
__stack_bottom = __stack_top - 4096;
SECTIONS {
    .text : ALIGN(4) { KEEP(*(.init)) *(.text*) *(.rodata*) } > RAM
    .data : ALIGN(4) { __data_start = .; *(.sdata*) *(.data*) __data_end = .; } > RAM
    __global_pointer$ = __data_start + 0x800;
    .bss (NOLOAD) : ALIGN(4) { __bss_start = .; *(.sbss*) *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > RAM
    /DISCARD/ : { *(.eh_frame*) }
    ASSERT(__bss_end <= __stack_bottom, "SRAM image overlaps 4KiB stack")
}
