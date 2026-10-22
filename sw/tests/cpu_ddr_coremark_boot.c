/* SRAM loader for the exact private-DDR CoreMark payload; outside timing. */
#include "triha_runtime.h"
#include "soc_map.h"
#include "cpu_cache_map.h"
#include "cpu_ddr_payload.h"

int main(void)
{
    triha_puts("CPU_DDR_COREMARK_BOOT\n");
    uint32_t start, now;
    __asm__ volatile ("csrr %0, cycle" : "=r"(start));
    while ((*(volatile uint32_t *)TRIHA_CPU_DDR_STATUS_ADDR & TRIHA_CPU_DDR_READY) == 0) {
        __asm__ volatile ("csrr %0, cycle" : "=r"(now));
        if ((*(volatile uint32_t *)TRIHA_CPU_DDR_STATUS_ADDR & TRIHA_CPU_DDR_FAULT) ||
            (uint32_t)(now - start) > 600000000u) {
            triha_puts("CPU_DDR_COREMARK_FAIL init\n");
            return 1;
        }
    }
    volatile uint32_t *destination = (volatile uint32_t *)TRIHA_PAYLOAD_ENTRY;
    for (uint32_t i = 0; i < TRIHA_PAYLOAD_WORDS; ++i)
        destination[i] = triha_payload[i];
    for (uint32_t i = 0; i < TRIHA_PAYLOAD_WORDS; ++i) {
        if (destination[i] != triha_payload[i]) {
            triha_puts("CPU_DDR_COREMARK_FAIL payload\n");
            return 2;
        }
    }
    __asm__ volatile (".word 0x0000100f" : : : "memory");
    *(volatile uint32_t *)0x00016ff0u = TRIHA_PAYLOAD_CPU_LUTS;
    triha_puts("CPU_DDR_COREMARK_PAYLOAD_PASS\n");
    ((void (*)(void))TRIHA_PAYLOAD_ENTRY)();
    return 3;
}
