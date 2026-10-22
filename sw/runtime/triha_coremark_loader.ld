/* SRAM loader: reserve 0x16ff0..0x16fff for post-timing area metadata.
 * Stack is the original 4KiB at 0x17000..0x17fff. */
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 0x6ff0 }
__stack_top = 0x00018000;
SECTIONS {
    .text : ALIGN(4) { KEEP(*(.init)) *(.text*) *(.rodata*) } > RAM
    .data : ALIGN(4) { __data_start = .; *(.sdata*) *(.data*) __data_end = .; } > RAM
    __global_pointer$ = __data_start + 0x800;
    .bss (NOLOAD) : ALIGN(4) { __bss_start = .; *(.sbss*) *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > RAM
    /DISCARD/ : { *(.eh_frame*) }
    ASSERT(__bss_end <= 0x00016ff0, "Loader overlaps area metadata or stack")
}
