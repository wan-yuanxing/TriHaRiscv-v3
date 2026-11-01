/* Local boot copies the cacheable code and handler to modeled private DDR. */
ENTRY(_start)
MEMORY {
    RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 32768
    DDR (rwx) : ORIGIN = 0x80004000, LENGTH = 16384
}
__stack_top = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS {
    .init : { KEEP(*(.init)) } > RAM
    .irqtext : ALIGN(32) {
        __payload_start = .;
        *(.irqtext)
        . = ALIGN(4);
        __payload_end = .;
    } > DDR AT> RAM
    __payload_load = LOADADDR(.irqtext);
    /DISCARD/ : { *(.eh_frame*) }
    ASSERT(__payload_load + SIZEOF(.irqtext) < 0x17000, "IRQ image overlaps markers")
}
