.section .init
.globl _start
_start:
    li sp, 0x18000
    la t0, application_trap
    csrw mtvec, t0
    csrw mie, zero
    la t0, __bss_start
    la t1, __bss_end
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:  call main
3:  j 3b
.balign 4
application_trap:
    csrr t0, mcause
    la t1, face_avatar_trap_cause
    sw t0, 0(t1)
    csrr t0, mepc
    la t1, face_avatar_trap_pc
    sw t0, 0(t1)
    csrr t0, mtval
    la t1, face_avatar_trap_value
    sw t0, 0(t1)
    li t0, 3
    la t1, face_avatar_run_status
    sw t0, 0(t1)
4:  j 4b
