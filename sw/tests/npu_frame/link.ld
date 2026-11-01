OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { SRAM (rwx) : ORIGIN = 0x10000, LENGTH = 32K }
SECTIONS {
    .text : { KEEP(*(.init)) *(.text*) *(.rodata*) } > SRAM
    .data : { *(.data*) *(.sdata*) } > SRAM
    .bss (NOLOAD) : { *(.bss*) *(.sbss*) *(COMMON) } > SRAM
}
