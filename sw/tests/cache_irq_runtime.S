/* Cache-enabled IRQ exercise: resident load, delayed refill and load return. */
    .option norvc
    .option norelax
    .section .init, "ax"
    .globl _start
_start:
    la sp, __stack_top
    csrw mie, zero
    csrw mstatus, zero
    li s0, 0x20020000
    la t0, __payload_load
    la t1, __payload_start
    la t2, __payload_end
1:
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    bltu t1, t2, 1b
    fence.i
    la t0, payload_entry
    jr t0

    .section .irqtext, "ax"
    .globl payload_entry
payload_entry:
    la t0, trap_entry
    csrw mtvec, t0
    li s1, 0x80002000
    li s2, 0x80002400
    li s3, 0x80002800
    li s5, 0x00017000
    li s6, 0
    li s9, 0
    li t0, 0x13579bdf
    sw t0, 0(s1)
    lw t1, 0(s1)
    bne t0, t1, fail
    li t0, 0x88
    csrw mstatus, t0

    li s8, 1
    sw s8, 0(s5)
    li t0, 0x800
    csrw mie, t0
    .globl phase1_load, phase1_after, phase1_end
phase1_load:
    lw s4, 0(s1)
phase1_after:
    addi s6, s6, 1
    li t1, 1
1:
    bne s9, t1, 1b
    li t0, 0x13579bdf
    bne s4, t0, fail
phase1_end:
    sw s6, 4(s5)

    li s8, 2
    sw s8, 0(s5)
    li t0, 0x800
    csrw mie, t0
    .globl phase2_load, phase2_after, phase2_end
phase2_load:
    lw s4, 0(s2)
phase2_after:
    addi s6, s6, 1
    li t1, 2
2:
    bne s9, t1, 2b
    li t0, 0x2468ace0
    bne s4, t0, fail
phase2_end:
    sw s6, 4(s5)

    li s8, 3
    sw s8, 0(s5)
    li t0, 0x800
    csrw mie, t0
    .globl phase3_load, phase3_after, phase3_end
phase3_load:
    lw s4, 0(s3)
phase3_after:
    addi s6, s6, 1
    li t1, 3
3:
    bne s9, t1, 3b
    li t0, 0x31415926
    bne s4, t0, fail
phase3_end:
    sw s6, 4(s5)
    li t0, 3
    bne s6, t0, fail
    bne s9, t0, fail
    csrr t0, mstatus
    li t1, 0x88
    bne t0, t1, fail
    csrr t0, mie
    bnez t0, fail
    sw zero, 4(s0)
4:
    j 4b
fail:
    li t0, 91
    sw t0, 4(s0)
    j 4b

    .balign 256
    .globl trap_entry, trap_mret
trap_entry:
    addi sp, sp, -16
    sw t0, 0(sp)
    sw t1, 4(sp)
    csrr t0, mcause
    li t1, 0x8000000b
    bne t0, t1, fail
    csrr t0, mtval
    bnez t0, fail
    csrr t0, mstatus
    li t1, 0x1880
    bne t0, t1, fail
    csrr t0, mie
    li t1, 0x800
    bne t0, t1, fail
    csrw mie, zero
    addi s9, s9, 1
#ifdef BROKEN_IRQ_RETURN
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
#endif
    lw t0, 0(sp)
    lw t1, 4(sp)
    addi sp, sp, 16
trap_mret:
    mret
    .balign 4
    .section .note.GNU-stack,"",@progbits
