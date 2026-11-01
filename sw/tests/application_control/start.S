.section .init
.globl _start
_start:
    li sp, 0x18000
    la t0, trap_handler
    csrw mtvec, t0
    li s1, 0x20000000
    li s2, 0x20010000
    li t1, 0x12345678
    sw t1, 0(s1)
    lw t2, 0(s1)
    bne t1, t2, fail
    li t1, 0x89abcdef
    sw t1, 0(s2)
    lw t2, 0(s2)
    bne t1, t2, fail
    li s3, 0x82001000
    li t1, 0xaabbccdd
    sw t1, 0(s3)
    lw t2, 0(s3)
    bne t1, t2, fail
    li t1, 0x11
    sb t1, 1(s3)
    lw t2, 0(s3)
    li t1, 0xaabb11dd
    bne t1, t2, fail
    li s0, 0
    li t0, 0x800
    csrw mie, t0
    li t0, 8
    csrs mstatus, t0
    li t0, 1
    sw t0, 0x20(s1)
irq_wait:
    beqz s0, irq_wait
    li t0, 1
    bne s0, t0, fail
    li t0, 0x600d600d
    sw t0, 0xf0(s2)
park:
    j park
.balign 4
trap_handler:
    csrr t0, mcause
    li t1, 0x8000000b
    bne t0, t1, fail
    sw zero, 0x20(s1)
    lw t0, 0x20(s1)
    bnez t0, fail
    csrw mip, zero
    addi s0, s0, 1
    mret
fail:
    li t0, 0xdeadbad0
    sw t0, 0xf0(s2)
    j park
