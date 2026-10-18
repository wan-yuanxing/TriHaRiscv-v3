/* Deterministic CPU control test; scratch registers t3/t4 reserved for traps. */
    .section .init,"ax"
    .option norvc
    .option norelax
    .globl _start
_start:
    la sp, __stack_top
    la t0, trap_handler
    csrw mtvec, t0
    csrw mstatus, zero
    csrw mie, zero
    li s0, 0
    li s1, 0
    li s2, 0
    li s3, 0
    la t0, scratch
    li t1, 30
    li t2, 7
arith_loop:
    add s2, s2, t2
    addi s3, s3, 1
    sw s2, 0(t0)
    lw a0, 0(t0)
    bne a0, s2, fail
    sb s3, 4(t0)
    lbu a1, 4(t0)
    bne a1, s3, fail
    sh s2, 6(t0)
    lhu a2, 6(t0)
    bne a2, s2, fail
    mul a3, s3, t2
    bne a3, s2, fail
    div a4, a3, t2
    bne a4, s3, fail
    slli a5, s2, 5
    srli a5, a5, 5
    bne a5, s2, fail
    jal ra, subroutine
    addi t1, t1, -1
    bnez t1, arith_loop

    li s4, 2
    la s5, after_illegal
    .word 0xffffffff
after_illegal:
    li s4, 11
    la s5, after_ecall
    ecall
after_ecall:
    li s4, 3
    la s5, after_ebreak
    ebreak
after_ebreak:
    li s4, 4
    la s5, after_load_align
    lw a0, 2(t0)
after_load_align:
    li s4, 6
    la s5, after_store_align
    sw a0, 2(t0)
after_store_align:
    li t2, 0x8001fff0
    li s4, 5
    la s5, after_load_fault
    lw a0, 0(t2)
after_load_fault:
    li s4, 7
    la s5, after_store_fault
    sw a0, 4(t2)
after_store_fault:
    li s4, 1
    la s5, after_fetch_fault
    j fetch_fault_target
    .balign 8
    .globl fetch_fault_target
fetch_fault_target:
    nop
    nop
    j fail
after_fetch_fault:
    li a0, 8
    bne s0, a0, fail
    li t0, 0x800
    csrw mie, t0
    li t0, 8
    csrs mstatus, t0
    li t0, 0x8001ffe0
    li t1, 1
    sw t1, 0(t0)
wait_irq:
    beqz s1, wait_irq
    li a0, 1
    bne s1, a0, fail
    fence.i
    li a0, 0
    csrw 0x8b2, a0
halt:
    j halt

subroutine:
    xor a6, s2, s3
    xor a6, a6, s3
    bne a6, s2, fail
    jalr zero, 0(ra)

    .balign 4
trap_handler:
    csrr t3, mcause
    bltz t3, interrupt_handler
    bne t3, s4, fail
    addi s0, s0, 1
    csrw mepc, s5
    mret
interrupt_handler:
    li t4, 0x8000000b
    bne t3, t4, fail
    csrw mie, zero
    addi s1, s1, 1
    mret
fail:
    li a0, 1
    csrw 0x8b2, a0
    j halt

    .section .data,"aw"
    .balign 8
scratch:
    .word 0,0
    .section .note.GNU-stack,"",@progbits
