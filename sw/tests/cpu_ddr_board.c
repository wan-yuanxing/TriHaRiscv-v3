/* Standalone destructive DDR self-check; no fabric co-owner may run this image. */
#include "triha_runtime.h"
#include "soc_map.h"
#include "cpu_cache_map.h"
#include "cpu_ddr_board.h"

static uint32_t cycles(void)
{
    uint32_t value;
    __asm__ volatile ("csrr %0, cycle" : "=r"(value));
    return value;
}

static uint32_t pattern(uint32_t index)
{
    return 0x7193acdeu ^ index * 0x139753abu;
}

static int check_region(uint32_t address)
{
    volatile uint32_t *words = (volatile uint32_t *)address;
    for (uint32_t i = 0; i < TRIHA_DDR_BOARD_TEST_WORDS; ++i)
        words[i] = pattern(i);
    for (uint32_t i = 0; i < TRIHA_DDR_BOARD_TEST_WORDS; ++i)
        if (words[i] != pattern(i))
            return 1;
    volatile uint8_t *bytes = (volatile uint8_t *)words;
    bytes[5] = 0x5a;
    if (words[1] != ((pattern(1) & 0xffff00ffu) | 0x00005a00u))
        return 2;
    volatile uint16_t *halves = (volatile uint16_t *)words;
    halves[5] = 0x9573;
    if (words[2] != ((pattern(2) & 0x0000ffffu) | 0x95730000u))
        return 3;
    return 0;
}

int main(void)
{
    triha_puts("CPU_DDR_BOOT\n");
    uint32_t start = cycles();
    while ((*(volatile uint32_t *)TRIHA_CPU_DDR_STATUS_ADDR & TRIHA_CPU_DDR_READY) == 0) {
        if (*(volatile uint32_t *)TRIHA_CPU_DDR_STATUS_ADDR & TRIHA_CPU_DDR_FAULT) {
            triha_puts("CPU_DDR_FAIL init\n");
            return 1;
        }
        if ((uint32_t)(cycles() - start) > 600000000u) {
            triha_puts("CPU_DDR_FAIL timeout\n");
            return 2;
        }
    }
    if (check_region(TRIHA_DDR_BOARD_PRIVATE_TEST_BASE) || check_region(TRIHA_DDR_BOARD_SHARED_TEST_BASE)) {
        triha_puts("CPU_DDR_FAIL data\n");
        return 3;
    }
    volatile uint32_t *code = (volatile uint32_t *)0x80001000u;
    code[0] = 0x00700513u;
    code[1] = 0x00008067u;
    for (uint32_t i = 2; i < 8; ++i)
        code[i] = 0x00000013u;
    __asm__ volatile (".word 0x0000100f" : : : "memory");
    int (*function)(void) = (int (*)(void))0x80001000u;
    if (function() != 7)
        return 4;
    code[0] = 0x00900513u;
    __asm__ volatile (".word 0x0000100f" : : : "memory");
    if (function() != 9)
        return 5;
    if (*(volatile uint32_t *)TRIHA_CPU_DDR_STATUS_ADDR != TRIHA_CPU_DDR_READY)
        return 6;
    triha_puts("CPU_DDR_PASS private=8192 shared=8192 fence_i=1\n");
    return 0;
}
