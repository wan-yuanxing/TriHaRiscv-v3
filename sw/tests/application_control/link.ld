ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x10000, LENGTH = 32768 }
SECTIONS {
    .text : ALIGN(4) { KEEP(*(.init)) *(.text*) *(.rodata*) } > RAM
    .data : ALIGN(4) { *(.sdata*) *(.data*) } > RAM
    .bss (NOLOAD) : ALIGN(4) { *(.sbss*) *(.bss*) *(COMMON) } > RAM
    /DISCARD/ : { *(.eh_frame*) }
}
