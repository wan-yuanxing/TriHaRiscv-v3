/* TriHa test-TCM startup: loaded data, cleared BSS, aligned stack, trap report. */
    .section .init, "ax"
    .option norvc
    .option norelax
    .globl _start
_start:
    la gp, __global_pointer$
    la sp, __stack_top
    la t0, triha_trap_entry
    csrw mtvec, t0
    csrw mstatus, zero
    csrw mie, zero
    la t0, __bss_start
    la t1, __bss_end
1:
    bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:
    call main
    call triha_exit
3:
    j 3b

    .balign 4
triha_trap_entry:
    csrr a0, mcause
    csrr a1, mtval
    call triha_trap
    j 3b

    .section .note.GNU-stack,"",@progbits
