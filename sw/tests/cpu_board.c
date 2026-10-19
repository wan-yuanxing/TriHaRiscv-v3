/* Board SRAM self-test; the code and stack are outside this owned 8KiB buffer. */
#include "triha_runtime.h"
#include "soc_map.h"

static const volatile uint32_t initialized = 0x13579bdfu;
static volatile uint32_t buffer[2048];

static void fail(unsigned code)
{
    triha_puts("CPU_BOARD_FAIL code=");
    triha_put_hex32(code);
    uart_send_char('\n');
    triha_exit(code);
}

static uint32_t cycle(void)
{
    uint32_t result;
    __asm__ volatile ("csrr %0, cycle" : "=r" (result));
    return result;
}

int main(void)
{
    if (initialized != 0x13579bdfu)
        fail(1);
    for (unsigned i = 0; i < 2048; ++i)
        if (buffer[i] != 0)
            fail(2);
    for (unsigned pass = 0; pass < 4; ++pass) {
        uint32_t mask = 0x55555555u * pass;
        for (unsigned i = 0; i < 2048; ++i)
            buffer[i] = (0x9e3779b9u * i) ^ mask;
        for (unsigned i = 0; i < 2048; ++i)
            if (buffer[i] != ((0x9e3779b9u * i) ^ mask))
                fail(3 + pass);
    }
    volatile uint8_t *bytes = (volatile uint8_t *)buffer;
    for (unsigned i = 0; i < sizeof(buffer); ++i)
        bytes[i] = (uint8_t)(i ^ (i >> 8));
    for (unsigned i = 0; i < 2048; ++i) {
        uint32_t expected = 0;
        for (unsigned lane = 0; lane < 4; ++lane) {
            unsigned index = 4 * i + lane;
            expected |= (uint32_t)(uint8_t)(index ^ (index >> 8)) << (8 * lane);
        }
        if (buffer[i] != expected)
            fail(7);
    }
    if (*(volatile uint32_t *)TRIHA_SYSTEM_BASE != TRIHA_SYSTEM_ID)
        fail(8);
    triha_puts("CPU_BOARD_PASS checked_bytes=8192\n");
    *(volatile uint32_t *)(TRIHA_SYSTEM_BASE + 4u) = 0;
    unsigned sequence = 0;
    for (;;) {
        triha_puts("CPU_ALIVE seq=");
        triha_put_hex32(sequence++);
        triha_puts(" cycle=");
        triha_put_hex32(cycle());
        uart_send_char('\n');
        uint32_t start = cycle();
        while ((uint32_t)(cycle() - start) < TRIHA_CLOCK_HZ) {}
    }
}
