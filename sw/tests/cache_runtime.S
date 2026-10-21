/* Real CPU/cache directed program. CSR output is test-only host transport.
 * DDR locations below are private test allocations, not a new SoC map.
 */
    .section .init, "ax"
    .option norvc
    .option norelax
    .globl _start
_start:
    la sp, __stack_top
    la t0, trap_entry
    csrw mtvec, t0
    csrw mstatus, zero
    csrw mie, zero
    li s5, 0
    li s4, 1
    li s0, 0x80010000
    li t0, 0x11223344
    sw t0, 0(s0)
    lw t1, 0(s0)
    bne t0, t1, fail
    lw t1, 0(s0)
    bne t0, t1, fail

    li s4, 2
    li t0, 0x80
    sb t0, 1(s0)
    li t0, 0xa5b6
    sh t0, 2(s0)
    lw t1, 0(s0)
    li t0, 0xa5b68044
    bne t0, t1, fail
    lb t1, 1(s0)
    li t0, -128
    bne t0, t1, fail
    lhu t1, 2(s0)
    li t0, 0xa5b6
    bne t0, t1, fail

    li s4, 3
    li t0, 0x80012000
    li t1, 0x52317684
    sw t1, 0(t0)
    lw t2, 0(t0)
    bne t1, t2, fail
    li t0, 0x80014000
    li t1, 0x963ac721
    sw t1, 0(t0)
    lw t2, 0(t0)
    bne t1, t2, fail
    lw t1, 0(s0)
    li t0, 0xa5b68044
    bne t0, t1, fail

    li s4, 4
    li t0, 0x82000100
    li t1, 0x647391ab
    sw t1, 0(t0)
    lw t2, 0(t0)
    bne t1, t2, fail
    lw t2, 0(t0)
    bne t1, t2, fail

    li s4, 5
    call dynamic_function
    li t0, 1
    bne a0, t0, fail
    la t1, dynamic_function
    li t0, 0x00200513
    sw t0, 0(t1)
    fence rw,rw
    fence.i
    call dynamic_function
    li t0, 2
    bne a0, t0, fail

    li s4, 6
    csrw 0x3a2, s0
    lw t1, 0(s0)
    li t0, 0xa5b68044
    bne t0, t1, fail
    csrw 0x3a0, zero
    csrw 0x3a1, s0
    lw t1, 0(s0)
    bne t0, t1, fail

    li s4, 7
    li t3, 0x80018100
    li t0, 0x55667788
    sw t0, 0(t3)
    li s5, 5
    li s6, 0x80018000
    la s7, after_fault_load
    li t2, 0xdeadbeef
    lw a1, 0(s6)
    sw t2, 0(t3)             /* Must be squashed; trap resumes after it. */
after_fault_load:
    bnez s5, fail
    lw t1, 0(t3)
    li t0, 0x55667788
    bne t0, t1, fail

    li s4, 8
    li s5, 7
    li s6, 0x80018020
    la s7, after_fault_store
    sw t0, 0(s6)
after_fault_store:
    bnez s5, fail

    li s4, 9
    li s5, 1
    li s6, 0x80018200
    la s7, after_fault_fetch
    jr s6
after_fault_fetch:
    bnez s5, fail

    li s4, 10
    li t0, 99
    li t1, 13
    mul t2, t0, t1
    li t3, 1287
    bne t2, t3, fail
    div t2, t0, t1
    li t3, 7
    bne t2, t3, fail
    li a0, 0
    csrw 0x8b2, a0
1:  j 1b
fail:
    mv a0, s4
    csrw 0x8b2, a0
2:  j 2b

    .balign 32
dynamic_function:
    li a0, 1
    ret

    .balign 32
trap_entry:
    csrr t0, mcause
    bne t0, s5, fail
    csrr t0, mtval
    bne t0, s6, fail
    csrw mepc, s7
    li s5, 0
    mret

    .section .note.GNU-stack,"",@progbits
