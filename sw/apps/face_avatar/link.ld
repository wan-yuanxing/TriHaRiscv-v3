OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { SRAM (rwx) : ORIGIN = 0x00010000, LENGTH = 32K }
SECTIONS {
    .text : { KEEP(*(.init)) *(.text .text.*) } > SRAM
    .rodata : { *(.rodata .rodata.*) } > SRAM
    .data : { *(.data .data.* .sdata .sdata.*) } > SRAM
    .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.bss .bss.* .sbss .sbss.*) *(COMMON) . = ALIGN(4); __bss_end = .; } > SRAM
    ASSERT(__bss_end <= 0x17000, "application must leave 4KiB for stack")
}
