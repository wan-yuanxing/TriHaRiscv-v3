/* TriHa CoreMark platform configuration. Algorithm sources remain unchanged. */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>
#include <stdint.h>
#include "core_build_config.h"

#define HAS_FLOAT 0
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 0
#define HAS_PRINTF 0
#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD MEM_STACK
#define MULTITHREAD 1
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0
#define COMPILER_VERSION "GCC " __VERSION__
#define COMPILER_FLAGS TRIHA_COMPILER_FLAGS
#if TRIHA_SOC_MMIO
#define MEM_LOCATION "SRAM stack"
#else
#define MEM_LOCATION "TCM stack"
#endif

typedef int16_t ee_s16;
typedef uint16_t ee_u16;
typedef int32_t ee_s32;
typedef uint32_t ee_u32;
typedef uint8_t ee_u8;
typedef uintptr_t ee_ptr_int;
typedef size_t ee_size_t;
typedef uint32_t CORE_TICKS;
typedef uint32_t CORETIMETYPE;

#define align_mem(x) ((void *)(4u + (((ee_ptr_int)(x) - 1u) & ~3u)))

typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;

extern ee_u32 default_num_contexts;
void portable_init(core_portable *port, int *argc, char *argv[]);
void portable_fini(core_portable *port);
int ee_printf(const char *format, ...);
void triha_coremark_note(const char *format);

#endif
