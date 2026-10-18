/* TriHa test-platform runtime. Board/MMIO integration is a separate target. */
#ifndef TRIHA_RUNTIME_H
#define TRIHA_RUNTIME_H

#include <stdint.h>

void uart_send_char(char value);
void triha_puts(const char *text);
void triha_put_hex32(uint32_t value);
void triha_exit(uint32_t status) __attribute__((noreturn));
void triha_trap(uint32_t cause, uint32_t value) __attribute__((noreturn));

#endif
