#ifndef RISCV_CPU_LAB_XSIMD_H
#define RISCV_CPU_LAB_XSIMD_H
#include <stdint.h>
/* Custom-0 packed integer operations. NOT the standard RISC-V V extension. */
static inline uint32_t xadd8(uint32_t a, uint32_t b) {
    uint32_t r;
    __asm__ volatile (".insn r 0x0b, 0, 0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline uint32_t xadd16(uint32_t a, uint32_t b) {
    uint32_t r;
    __asm__ volatile (".insn r 0x0b, 1, 0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline int32_t xdot8(uint32_t a, uint32_t b) {
    int32_t r;
    __asm__ volatile (".insn r 0x0b, 2, 0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
#endif
