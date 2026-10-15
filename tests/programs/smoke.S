.section .text.init
.globl _start
_start:
    li sp, 0x800ff000
    li t0, 35
    li t1, 7
    add t2, t0, t1
    la t3, scratch
    sw t2, 0(t3)
    lw t4, 0(t3)
    add t5, t4, t1
    li t6, 49
    bne t5, t6, fail
    li t0, 0
    li t1, 10
loop:
    addi t0, t0, 1
    blt t0, t1, loop
    mul t2, t0, t1
    div t4, t2, t1
    bne t4, t0, fail
    li t0, 0x04030201
    li t1, 0x08070605
    .insn r 0x0b, 2, 0, t2, t0, t1
    li t4, 70
    bne t2, t4, fail
    li a0, 0
    ebreak
fail:
    li a0, 1
    ebreak
.section .data
.balign 4
scratch: .word 0
