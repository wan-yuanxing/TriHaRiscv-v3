/* Real ROM->SRAM execution, initialized data, stack/BSS and byte lanes. */
#include "triha_runtime.h"
#include "soc_map.h"

static volatile uint32_t initialized = 0x13579bdfu;
static volatile uint32_t zeros[32];
static volatile uint32_t scratch[8];

int main(void)
{
    if (initialized != 0x13579bdfu)
        return 1;
    for (unsigned int i = 0; i < 32; ++i)
        if (zeros[i] != 0)
            return 2;
    for (unsigned int i = 0; i < 8; ++i)
        scratch[i] = 0x192731u * i;
    volatile uint8_t *bytes = (volatile uint8_t *)scratch;
    bytes[7] = 0x5a;
    if (scratch[1] != 0x5a192731u)
        return 3;
    if (*(volatile uint32_t *)TRIHA_SYSTEM_BASE != TRIHA_SYSTEM_ID)
        return 4;
    /* FENCE.I encoding; preserve the benchmark's RV32IM_Zicsr compiler flags. */
    __asm__ volatile (".word 0x0000100f" : : : "memory");
    triha_puts("SOC_RUNTIME_PASS\n");
    return 0;
}
