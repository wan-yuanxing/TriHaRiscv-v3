/* RV32I/Zicsr startup and full caller-save trap entry; no test exit CSR/MMIO. */
    .section .init, "ax"
    .option norvc
    .option norelax
    .globl _start
_start:
    la gp, __global_pointer$
    la sp, __stack_top
    la t0, trap_entry
    csrw mtvec, t0
    csrw mstatus, zero
    csrw mie, zero
    la t0, __data_load
    la t1, __data_start
    la t2, __data_end
1:  bgeu t1, t2, 2f
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j 1b
2:  la t0, __bss_start
    la t1, __bss_end
3:  bgeu t0, t1, 4f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 3b
4:  call main
5:  j 5b

    .balign 4
trap_entry:
    addi sp, sp, -64
    sw ra, 0(sp)
    sw t0, 4(sp)
    sw t1, 8(sp)
    sw t2, 12(sp)
    sw t3, 16(sp)
    sw t4, 20(sp)
    sw t5, 24(sp)
    sw t6, 28(sp)
    sw a0, 32(sp)
    sw a1, 36(sp)
    sw a2, 40(sp)
    sw a3, 44(sp)
    sw a4, 48(sp)
    sw a5, 52(sp)
    sw a6, 56(sp)
    sw a7, 60(sp)
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    call trap_handle
    csrw mepc, a0
    lw ra, 0(sp)
    lw t0, 4(sp)
    lw t1, 8(sp)
    lw t2, 12(sp)
    lw t3, 16(sp)
    lw t4, 20(sp)
    lw t5, 24(sp)
    lw t6, 28(sp)
    lw a0, 32(sp)
    lw a1, 36(sp)
    lw a2, 40(sp)
    lw a3, 44(sp)
    lw a4, 48(sp)
    lw a5, 52(sp)
    lw a6, 56(sp)
    lw a7, 60(sp)
    addi sp, sp, 64
    mret

    .globl test_load_fault, fault_load_pc, test_store_fault, fault_store_pc
test_load_fault:
    mv t0, a0
fault_load_pc:
    lw a0, 0(t0)
    ret
test_store_fault:
    li t0, 0x20011000
fault_store_pc:
    sw zero, 0(t0)
    ret
    .section .note.GNU-stack,"",@progbits
