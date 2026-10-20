/* TriHa CoreMark timing uses the real cycle CSR; short-run warnings are kept. */
#include "coremark.h"
#include "triha_runtime.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
#else
volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
#endif
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

static CORE_TICKS started;
static CORE_TICKS stopped;
static ee_u32 errors;
static ee_u32 short_run;

static CORE_TICKS read_cycle(void)
{
#if TRIHA_COREMARK_BOARD
    /* This core exposes the high half of its cycle counter through timeh.
     * Read high/low/high to avoid tearing across a low-half rollover. */
    ee_u32 high, value, again;
    do {
        __asm__ volatile ("csrr %0, 0xc81" : "=r" (high) : : "memory");
        __asm__ volatile ("csrr %0, 0xc00" : "=r" (value) : : "memory");
        __asm__ volatile ("csrr %0, 0xc81" : "=r" (again) : : "memory");
    } while (high != again);
    return ((uint64_t)high << 32) | value;
#else
    ee_u32 value;
    __asm__ volatile ("csrr %0, 0xc00" : "=r" (value) : : "memory");
    return value;
#endif
}

void start_time(void)
{
    started = read_cycle();
}

void stop_time(void)
{
    stopped = read_cycle();
}

CORE_TICKS get_time(void)
{
    return stopped - started;
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ticks / 100000000u;
}

static int contains(const char *text, const char *needle)
{
    while (*text != '\0') {
        const char *left = text;
        const char *right = needle;
        while (*right != '\0' && *left == *right) {
            ++left;
            ++right;
        }
        if (*right == '\0')
            return 1;
        ++text;
    }
    return 0;
}

void triha_coremark_note(const char *format)
{
    if (contains(format, "ERROR! Must execute for at least 10 secs")) {
        short_run = 1;
    } else if (contains(format, "ERROR!") ||
               contains(format, "Cannot validate operation")) {
        ++errors;
    }
}

void portable_init(core_portable *port, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    errors = 0;
    short_run = 0;
    port->portable_id = 1;
#if TRIHA_COREMARK_BOARD
    ee_printf("CPU_COREMARK_START iterations=%lu clock_hz=100000000\n", (ee_u32)ITERATIONS);
    triha_puts("CoreMark running; precise scores follow the CRC report.\n");
#endif
}

#if TRIHA_COREMARK_BOARD
static void print_fixed(const char *label, uint64_t scaled)
{
    ee_printf("%s%lu.%06lu\n", label, (ee_u32)(scaled / 1000000u),
              (ee_u32)(scaled % 1000000u));
}
#endif

void portable_fini(core_portable *port)
{
    ee_printf("CPU_COREMARK_STATUS errors=%u short=%u\n", errors, short_run);
    port->portable_id = 0;
    if (errors != 0)
        triha_exit(1);
#if TRIHA_COREMARK_BOARD
    uint64_t ticks = get_time();
    if (ticks == 0)
        triha_exit(1);
    /* All divisions and UART output are outside the timed algorithm region. */
    ee_printf("CPU_COREMARK_TIME seconds=%lu.%06lu cycles_hi=%lu cycles_lo=%lu clock_hz=100000000\n",
              (ee_u32)(ticks / 100000000u), (ee_u32)((ticks % 100000000u) / 100u),
              (ee_u32)(ticks >> 32), (ee_u32)ticks);
    print_fixed("CoreMark       : ", (uint64_t)ITERATIONS * 100000000u * 1000000u / ticks);
    print_fixed("CoreMark/MHz   : ", (uint64_t)ITERATIONS * 1000000u * 1000000u / ticks);
    if (short_run || ticks < 1000000000u) {
#if TRIHA_COREMARK_PREFLIGHT
        ee_printf("CPU_COREMARK_PREFLIGHT_PASS iterations=%lu\n", (ee_u32)ITERATIONS);
#else
        triha_puts("CPU_COREMARK_BOARD_FAIL duration_below_10_seconds\n");
        triha_exit(1);
#endif
    } else {
        ee_printf("CPU_COREMARK_BOARD_PASS iterations=%lu\n", (ee_u32)ITERATIONS);
    }
#endif
}
