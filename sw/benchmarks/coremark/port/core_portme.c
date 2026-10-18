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

static ee_u32 started;
static ee_u32 stopped;
static ee_u32 errors;
static ee_u32 short_run;

static ee_u32 read_cycle(void)
{
    ee_u32 value;
    __asm__ volatile ("csrr %0, 0xc00" : "=r" (value) : : "memory");
    return value;
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
}

void portable_fini(core_portable *port)
{
    ee_printf("CPU_COREMARK_STATUS errors=%u short=%u\n", errors, short_run);
    port->portable_id = 0;
    if (errors != 0)
        triha_exit(1);
}
