/* TriHa simulation transport. A board port will replace this CSR transport. */
#include "triha_runtime.h"
#include <stddef.h>

void uart_send_char(char value)
{
    uint32_t command = 0x01000000u | (uint8_t)value;
    __asm__ volatile ("csrw 0x8b2, %0" : : "r" (command) : "memory");
}

void triha_puts(const char *text)
{
    while (*text != '\0')
        uart_send_char(*text++);
}

void triha_put_hex32(uint32_t value)
{
    static const char digits[] = "0123456789abcdef";
    for (int shift = 28; shift >= 0; shift -= 4)
        uart_send_char(digits[(value >> shift) & 15u]);
}

void triha_exit(uint32_t status)
{
    status &= 255u;
    __asm__ volatile ("csrw 0x8b2, %0" : : "r" (status) : "memory");
    for (;;) {}
}

void triha_trap(uint32_t cause, uint32_t value)
{
    triha_puts("CPU_TRAP cause=");
    triha_put_hex32(cause);
    triha_puts(" value=");
    triha_put_hex32(value);
    uart_send_char('\n');
    triha_exit(1u);
}

void *memcpy(void *destination, const void *source, size_t size)
{
    unsigned char *out = destination;
    const unsigned char *in = source;
    for (size_t index = 0; index < size; ++index)
        out[index] = in[index];
    return destination;
}

void *memset(void *destination, int value, size_t size)
{
    unsigned char *out = destination;
    for (size_t index = 0; index < size; ++index)
        out[index] = (unsigned char)value;
    return destination;
}
