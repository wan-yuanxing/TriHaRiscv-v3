/* Real local boot, cached/private and uncached/shared DDR, FENCE.I and faults. */
    .section .init, "ax"
    .option norvc
    .option norelax
    .globl _start
_start:
    la sp, __stack_top
    la t0, trap_entry
    csrw mtvec, t0
    csrw mie, zero
    csrw mstatus, zero
    li s0, 0x20020000
    li s1, 0x80000000
    li s2, 0x82000000
    li s9, 0
    li s10, 0
    li s11, 0
    li a7, 1
    lw t0, 12(s0)
    bnez t0, fail
    la t0, local_word
    li t1, 0x7153acde
    sw t1, 0(t0)
    lw t2, 0(t0)
    bne t1, t2, fail
    li t0, 0x10000000
    li t1, 0x43
    sw t1, 0(t0)
    li t1, 0x4b
    sw t1, 0(t0)
    // The model observes local status polling before raising DDR ready.
1:
    lw t0, 12(s0)
    andi t0, t0, 1
    beqz t0, 1b
    li a7, 2
    li t1, 0x13579bdf
    sw t1, 0(s1)
    lw t2, 0(s1)
    bne t1, t2, fail
    li t1, 0xa5
    sb t1, 1(s1)
    lw t2, 0(s1)
    li t1, 0x1357a5df
    bne t1, t2, fail
    li t1, 0x2468ace0
    sw t1, 0(s2)
    lw t2, 0(s2)
    bne t1, t2, fail
    li a7, 3
    la t0, function_words
    li t1, 0x80001000
    li t2, 8
2:
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -1
    bnez t2, 2b
    fence.i
    li t0, 0x80001000
    jalr ra, t0, 0
    li t1, 7
    bne a0, t1, fail
    li t0, 0x80001000
    li t1, 0x00900513
    sw t1, 0(t0)
    fence.i
    jalr ra, t0, 0
    li t1, 9
    bne a0, t1, fail
    li a7, 4
    la t0, function_words
    li t1, 0x82001000
    li t2, 8
3:
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -1
    bnez t2, 3b
    fence.i
    li t0, 0x82001000
    jalr ra, t0, 0
    li t1, 7
    bne a0, t1, fail
    li t0, 0x82001000
    li t1, 0x00900513
    sw t1, 0(t0)
    fence.i
    jalr ra, t0, 0
    li t1, 9
    bne a0, t1, fail
    // Read-only status writes must fault without changing ready/fault state.
    li a7, 5
    li s10, 7
    li s11, 0x2002000c
    sw zero, 12(s0)
    li t0, 1
    bne s9, t0, fail
    lw t0, 12(s0)
    li t1, 1
    bne t0, t1, fail
    // Recoverable lower read error; no partially failed line may be published.
    li s10, 5
    li s11, 0x80018000
    lw t1, 0(s11)
    li t0, 2
    bne s9, t0, fail
    li t0, 0x80000000
    lw t1, 0(t0)
    li t2, 0x1357a5df
    bne t1, t2, fail
    // A drained shared store asks the model to assert platform fault.
    li a7, 6
    li t0, 1
    sw t0, 240(s2)
4:
    lw t0, 12(s0)
    andi t0, t0, 2
    beqz t0, 4b
    lw t0, 12(s0)
    li t1, 2
    bne t0, t1, fail
    li s10, 5
    li s11, 0x80000000
    lw t1, 0(s11)
    li t0, 3
    bne s9, t0, fail
    // Local SRAM and system identity remain accessible under platform fault.
    la t0, local_word
    lw t1, 0(t0)
    li t2, 0x7153acde
    bne t1, t2, fail
    lw t1, 0(s0)
    li t2, 0x54524801
    bne t1, t2, fail
    sw zero, 4(s0)
5:
    j 5b
fail:
    sw a7, 4(s0)
    j 5b
    .balign 4
trap_entry:
    csrr t0, mcause
    bne t0, s10, trap_fail
    csrr t0, mtval
    bne t0, s11, trap_fail
    addi s9, s9, 1
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret
trap_fail:
    li a7, 200
    j fail
    .section .rodata, "a"
    .balign 32
function_words:
    .word 0x00700513, 0x00008067
    .rept 6
    .word 0x00000013
    .endr
    .section .bss, "aw", @nobits
    .balign 4
local_word:
    .word 0
    .section .note.GNU-stack,"",@progbits
