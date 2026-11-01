/* Port-driven wrong-path side-effect and delayed fault-completion exercise. */
#ifndef LEAK_BRANCH
#define LEAK_BRANCH 0
#endif
    .option norvc
    .option norelax
    .section .init, "ax"
    .globl _start
_start:
    la sp, __stack_top
    la t0, trap_entry
    csrw mtvec, t0
    csrw mie, zero
    csrw mstatus, zero
    li t0, 0x12345678
    csrw mscratch, t0
    li s0, 0x8001f000
    li s1, 0x10000000
    li s2, 0x8001f080
    li s3, 0x8001f004
    li s9, 0
    li s10, 0xbad00bad
    li s11, 0
    li t0, 0x13579bdf
    sw t0, 0(s0)
    li t0, 0x42
    sw t0, 0(s1)

    .macro branch_case number, kind
    lw s7, 0(s3)
    .balign 8
    .globl branch_\number, bad_b_\number, end_b_\number, resume_b_\number
branch_\number:
    .if \number == LEAK_BRANCH
    beq s7, zero, resume_b_\number
    .else
    bne s7, zero, resume_b_\number
    .endif
bad_b_\number:
    .if \kind == 1
    sw s10, 0(s0)
    .elseif \kind == 2
    sw s10, 0(s1)
    .else
    csrw mscratch, s10
    .endif
end_b_\number:
    nop
    nop
resume_b_\number:
    addi s11, s11, 1
    .endm
    branch_case 1, 1
    branch_case 2, 2
    branch_case 3, 3

    .macro fault_case number, kind
    li s4, 0x22446688
    la s8, resume_f_\number
    .balign 8
    .globl fault_\number, bad_f_\number, end_f_\number, resume_f_\number, after_f_\number
fault_\number:
    lw s4, 0(s2)
bad_f_\number:
    .if \kind == 1
    sw s10, 0(s0)
    .elseif \kind == 2
    sw s10, 0(s1)
    .elseif \kind == 3
    csrw mscratch, s10
    .else
    lw s4, 4(s2)
    .endif
end_f_\number:
    nop
    nop
resume_f_\number:
    lw s4, 0(s3)
after_f_\number:
    addi s11, s11, 1
    li t0, 0x11223344
    bne s4, t0, fail
    li t0, \number
    bne s9, t0, fail
    .endm
    fault_case 1, 1
    fault_case 2, 2
    fault_case 3, 3
    fault_case 4, 4

    lw t0, 0(s0)
    li t1, 0x13579bdf
    bne t0, t1, fail
    csrr t0, mscratch
    li t1, 0x12345678
    bne t0, t1, fail
    li t0, 4
    bne s9, t0, fail
    li t0, 7
    bne s11, t0, fail
    csrw 0x8b2, zero
1:
    j 1b
fail:
    li t0, 91
    csrw 0x8b2, t0
    j 1b

    .balign 64
    .globl trap_entry, trap_mret
trap_entry:
    addi sp, sp, -16
    sw t0, 0(sp)
    sw t1, 4(sp)
    csrr t0, mcause
    li t1, 5
    bne t0, t1, fail
    csrr t0, mtval
    bne t0, s2, fail
    li t0, 0x22446688
    bne s4, t0, fail
    addi s9, s9, 1
    csrw mepc, s8
    lw t0, 0(sp)
    lw t1, 4(sp)
    addi sp, sp, 16
trap_mret:
    mret
    .section .note.GNU-stack,"",@progbits
