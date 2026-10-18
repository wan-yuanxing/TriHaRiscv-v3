/* Verify that the real startup establishes initialized data and clears BSS. */
#include "triha_runtime.h"

static volatile uint32_t initial_value = 0x13579bdfu;
static volatile uint32_t zero_values[32];
static volatile uint32_t input_a = 391u;
static volatile uint32_t input_b = 23u;

int main(void)
{
    if (initial_value != 0x13579bdfu)
        return 1;
    for (unsigned int index = 0; index < 32; ++index) {
        if (zero_values[index] != 0u)
            return 2;
    }
    if (input_a / input_b != 17u || input_b * 17u != input_a)
        return 3;
#if TRIHA_RUNTIME_TRAP
    __asm__ volatile (".word 0xffffffff");
    return 4;
#endif
    triha_puts("CPU_RUNTIME_PASS\n");
    return 0;
}
