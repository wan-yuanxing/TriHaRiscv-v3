.section .init
.globl _start
_start:
    li sp,0x18000
    la t0,trap
    csrw mtvec,t0
    csrw mie,zero
    call main
1:  j 1b
.balign 4
trap:
    csrr a0,mcause
    li t0,0x400
    or a0,a0,t0
    call fail
