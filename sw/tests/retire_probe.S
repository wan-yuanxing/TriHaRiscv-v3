/* Fourteen dynamic instructions in [probe_begin, probe_end), including stores. */
    .section .init, "ax"
    .option norvc
    .option norelax
    .globl _start
_start:
    la t0, probe_data
    li t1, 3
    /* Independent pair before the counted range exercises both WB lanes. */
    li t4, 4
    csrr s0, 0xc00
    .globl probe_begin
probe_begin:
    addi t2, zero, 0
1:
    add t2, t2, t1
    addi t1, t1, -1
    bne t1, zero, 1b
    sw t2, 0(t0)
    lw t3, 0(t0)
    addi t3, t3, -6
    bne t3, zero, 3f
    .globl probe_end
probe_end:
    csrr s1, 0xc00
    addi a0, zero, 0
    csrw 0x8b2, a0
2:
    j 2b
3:
    addi a0, zero, 1
    csrw 0x8b2, a0
    j 2b

    .section .data, "aw"
    .balign 4
probe_data:
    .word 0
