/* Real native CPU -> adapter -> Video MMIO diagnostic. Test geometry is 30x20;
 * generated video_cfg.h continues to describe the production 800x600 mode. */
#include <stdint.h>
#include "video_regs.h"
#include "video_cfg.h"
#ifndef TEST_CASE
#define TEST_CASE 0
#endif
#define SIG ((volatile uint32_t *)0x00010000u)
static volatile uint32_t expected_cause, expected_pc, expected_value;
extern void test_load_fault(void), test_store_fault(void);
extern char fault_load_pc[], fault_store_pc[];
static uint32_t rd(uint32_t offset) { return *(volatile uint32_t *)(VIDEO_MMIO_BASE + offset); }
static void wr(uint32_t offset, uint32_t value) { *(volatile uint32_t *)(VIDEO_MMIO_BASE + offset) = value; }
__attribute__((noreturn)) static void fail(uint32_t code)
{
    SIG[0] = 0xbad00000u | code;
    for (;;) __asm__ volatile ("nop");
}
static void check(uint32_t condition, uint32_t code) { if (!condition) fail(code); }

uint32_t trap_handle(uint32_t cause, uint32_t pc, uint32_t value)
{
    if (cause == 0x8000000bu) {
        uint32_t pending = rd(VIDEO_REG_IRQ_PENDING);
        SIG[3]++;
        SIG[10] = cause; SIG[11] = pc; SIG[12] = value;
        check(TEST_CASE == 1 && (pending & 3u), 0x10);
        if (pending & 1u) {
            check(rd(VIDEO_REG_ACCEPTED_FRAME_ID_RECORD) == 0x10203040u, 0x11);
            SIG[13]++;
        }
        if (pending & 2u) {
            check(rd(VIDEO_REG_COMPLETED_RESULT) == 1u, 0x12);
            SIG[14]++;
        }
        wr(VIDEO_REG_IRQ_PENDING, pending & 3u);
        /* Read back the endpoint W1C before clearing the CPU pending bit.
         * In this pinned CPU ordinary instruction immediates can also arm its
         * CSR MIP/SIP read buffer. The first clear drains that buffer; allow its
         * pipeline to empty before the second clear. Diagnostic workaround. */
        while (rd(VIDEO_REG_IRQ_PENDING) & (pending & 3u)) { }
        __asm__ volatile ("csrw mip, zero\n.rept 8\nnop\n.endr\ncsrw mip, zero");
        return pc;
    }
    check(cause == expected_cause && pc == expected_pc && value == expected_value, 0x20);
    uint32_t index = cause == 5u ? 4u : 7u;
    SIG[index] = cause; SIG[index+1] = pc; SIG[index+2] = value;
    SIG[2]++;
    expected_cause = 0;
    return pc + 4u;
}

int main(void)
{
    for (uint32_t i=0; i<16; ++i) SIG[i]=0;
    SIG[1]=1;
    check(rd(VIDEO_REG_VERSION) == VIDEO_ABI_VERSION, 1);
    check(rd(VIDEO_REG_CAPABILITIES) == VIDEO_CAPABILITIES, 2);
    /* Explicit fixture dimensions; never confuse them with production config. */
    check(rd(VIDEO_REG_FRAME_WIDTH)==30 && rd(VIDEO_REG_FRAME_HEIGHT)==20, 3);
    check(rd(VIDEO_REG_INPUT_WIDTH)==12 && rd(VIDEO_REG_INPUT_HEIGHT)==11, 4);
    check(rd(VIDEO_REG_RAW_STRIDE)==96 && rd(VIDEO_REG_PREVIEW_STRIDE)==48 && rd(VIDEO_REG_INPUT_STRIDE)==16, 5);
    expected_cause=5; expected_pc=(uint32_t)fault_load_pc; expected_value=0x200103fcu;
    test_load_fault();
    expected_cause=7; expected_pc=(uint32_t)fault_store_pc; expected_value=VIDEO_MMIO_BASE+VIDEO_REG_VERSION;
    test_store_fault();
    check(SIG[2]==2, 6);
    wr(VIDEO_REG_CONTROL, VIDEO_CONTROL_ENABLE_MASK);
    wr(VIDEO_REG_REQUEST_SLOT, 0);
    wr(VIDEO_REG_REQUEST_FRAME_ID, 0x10203040u);
    wr(VIDEO_REG_REQUEST_VERSION, VIDEO_INPUT_PREPROCESS_VERSION);
    wr(VIDEO_REG_IRQ_MASK, 7);
    if (TEST_CASE == 1) {
        __asm__ volatile ("csrw mie, %0" :: "r"(0x800u));
        __asm__ volatile ("csrsi mstatus, 8");
    }
    SIG[1]=2;
    wr(VIDEO_REG_CAPTURE_REQUEST, VIDEO_CAPTURE_REQUEST_SUBMIT_MASK);
    uint32_t budget=200000;
    if (TEST_CASE == 1) {
        while (!SIG[14] && --budget) { __asm__ volatile ("nop"); }
        __asm__ volatile ("csrci mstatus, 8");
        check(budget && SIG[13]==1 && SIG[14]==1 && SIG[3]>=1, 7);
        check(rd(VIDEO_REG_IRQ_PENDING)==0, 8);
    } else {
        while (!(rd(VIDEO_REG_STATUS)&VIDEO_STATUS_COMPLETION_PENDING_MASK) && --budget) { }
        check(budget, 9);
    }
    check(rd(VIDEO_REG_COMPLETED_FRAME_ID_RECORD)==0x10203040u, 0x30);
    check(rd(VIDEO_REG_COMPLETED_RAW_BASE)==VIDEO_FRAME_SLOT_A && rd(VIDEO_REG_COMPLETED_INPUT_BASE)==VIDEO_INPUT_SLOT_A, 0x31);
    if (TEST_CASE == 2) {
        check(rd(VIDEO_REG_COMPLETED_RESULT)==0x300u && rd(VIDEO_REG_ERROR_CODE)==3u, 0x32);
        check(!(rd(VIDEO_REG_STATUS)&VIDEO_STATUS_ACCEPTED_PENDING_MASK), 0x33);
        check(rd(VIDEO_REG_COMPLETED_RAW_PIXELS)==0 && rd(VIDEO_REG_COMPLETED_RAW_BYTES)==0 && rd(VIDEO_REG_COMPLETED_PREVIEW_BYTES)==0, 0x34);
        check(rd(VIDEO_REG_IRQ_PENDING)==6, 0x35);
        wr(VIDEO_REG_IRQ_PENDING, 6);
    } else {
        check(rd(VIDEO_REG_COMPLETED_RESULT)==1u && rd(VIDEO_REG_ERROR_CODE)==0u, 0x36);
        check(rd(VIDEO_REG_COMPLETED_RAW_PIXELS)==600 && rd(VIDEO_REG_COMPLETED_PREVIEW_PIXELS)==150 && rd(VIDEO_REG_COMPLETED_INPUT_PIXELS)==96, 0x37);
        check(rd(VIDEO_REG_COMPLETED_RAW_BYTES)==1800 && rd(VIDEO_REG_COMPLETED_PREVIEW_BYTES)==450 && rd(VIDEO_REG_COMPLETED_INPUT_BYTES)==396, 0x38);
        check(rd(VIDEO_REG_COMPLETED_FIFO_PEAK)==37, 0x39);
        if (TEST_CASE == 0) {
            check(rd(VIDEO_REG_IRQ_PENDING)==3 && (rd(VIDEO_REG_STATUS)&VIDEO_STATUS_ACCEPTED_PENDING_MASK), 0x3a);
            wr(VIDEO_REG_IRQ_PENDING, 1);
            check(rd(VIDEO_REG_IRQ_PENDING)==2, 0x3b);
            wr(VIDEO_REG_IRQ_PENDING, 2);
        }
    }
    check(rd(VIDEO_REG_IRQ_PENDING)==0, 0x3c);
    SIG[15]=rd(VIDEO_REG_STATUS);
    SIG[1]=3;
    SIG[0]=0x43505556u;
    for (;;) __asm__ volatile ("nop");
}
