.option norvc
.option norelax
.section .text.init
.globl _start,test_end,kernel_start,kernel_end
_start:
    li sp,0x800ff000
kernel_start:
    call kernel
    fence rw,rw
kernel_end:
    call verify
    fence rw,rw
test_end:
    ebreak
