#include <stdint.h>
#include "../sw/include/xsimd.h"
#include "bench_inputs.h"

/* GCC may_alias makes 32-bit packed access to aligned byte arrays explicit. */
typedef uint32_t packed_u32 __attribute__((may_alias));
static uint32_t load4(const int8_t *p) { return *(const packed_u32 *)p; }
static void store4(uint8_t *p, uint32_t v) { *(packed_u32 *)p=v; }
__attribute__((aligned(32))) uint8_t output_add[N];
__attribute__((aligned(32))) int32_t output_dot;
__attribute__((aligned(32))) int32_t output_gemv[ROWS];

__attribute__((noinline)) void kernel(void) {
#if KERNEL == 0
    int32_t sum=0;
    unsigned i=0;
#if SIMD
    for(;i+4<=N;i+=4) sum+=xdot8(load4(input_a+i),load4(input_b+i));
#endif
    for(;i<N;i++) sum+=(int32_t)input_a[i]*input_b[i];
    output_dot=sum;
#elif KERNEL == 1
    unsigned i=0;
#if SIMD
    for(;i+4<=N;i+=4) store4(output_add+i,xadd8(load4(input_a+i),load4(input_b+i)));
#endif
    for(;i<N;i++) output_add[i]=(uint8_t)((int)input_a[i]+input_b[i]);
#elif KERNEL == 2
    for(unsigned r=0;r<ROWS;r++) {
        int32_t sum=0;
        unsigned i=0;
#if SIMD
        for(;i+4<=COLS;i+=4) sum+=xdot8(load4(matrix[r]+i),load4(vector+i));
#endif
        for(;i<COLS;i++) sum+=(int32_t)matrix[r][i]*vector[i];
        output_gemv[r]=sum;
    }
#endif
}

/* Golden values generated independently using Python integers, not RTL/Spike. */
__attribute__((noinline)) int verify(void) {
#if KERNEL == 0
    return output_dot!=expected_dot;
#elif KERNEL == 1
    for(unsigned i=0;i<N;i++) if(output_add[i]!=expected_add[i]) return 1;
#elif KERNEL == 2
    for(unsigned r=0;r<ROWS;r++) if(output_gemv[r]!=expected_gemv[r]) return 1;
#endif
    return 0;
}
