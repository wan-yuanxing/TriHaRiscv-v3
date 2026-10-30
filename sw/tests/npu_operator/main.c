/* Host preloads tensors once. The real RV32I CPU configures, starts and reads
 * every output byte from the same digital AXI memory used by the NPU. */
#include "npu_operator.h"
#include "operator_vectors.h"
#ifndef IRQ_MODE
#define IRQ_MODE 0
#endif
#define SIG ((volatile uint32_t *)0x00010000u)
static volatile uint32_t irq_done;
static struct npu_operator_snapshot completion;
__attribute__((noreturn)) static void fail(uint32_t code)
{
    SIG[0] = 0xbad00000u | code;
    for (;;) __asm__ volatile ("nop");
}
static void check(uint32_t condition, uint32_t code)
{
    if (!condition) fail(code);
}
uint32_t trap_handle(uint32_t cause, uint32_t pc, uint32_t value)
{
    SIG[10] = cause; SIG[11] = pc; SIG[12] = value;
    check(IRQ_MODE && cause == 0x8000000bu, 0x10);
    npu_operator_snapshot(&completion);
    check(completion.irq_status == NPU_IRQ_STATUS_DONE_MASK, 0x11);
    SIG[3]++;
    npu_operator_ack(completion.irq_status);
    /* Pinned CPU diagnostic workaround: drain its CSR MIP read buffer before
     * a second clear. This is the already validated CPU revision's behavior. */
    __asm__ volatile ("csrw mip, zero\n.rept 8\nnop\n.endr\ncsrw mip, zero");
    irq_done = 1;
    return pc;
}
int main(void)
{
    for (uint32_t i = 0; i < 16; ++i) SIG[i] = 0;
    SIG[1] = 1;
    check(npu_operator_probe() == 0, 1);
    npu_operator_irq_enable(IRQ_MODE ? 3u : 0u);
    for (uint32_t task = 0; task < 2; ++task) {
        struct npu_operator_config *config = &vector_config;
        config->frame_id = 0x10203040u + task;
        config->generation = 0x50607080u + task;
        config->op_tag = 0x90a0b0c0u + task;
        irq_done = 0;
        check(npu_operator_configure(config) == 0, 2);
        if (IRQ_MODE) {
            __asm__ volatile ("csrw mie, %0" :: "r"(0x800u));
            __asm__ volatile ("csrsi mstatus, 8");
        }
        SIG[1] = 2;
        check(npu_operator_start() == 0, 3);
        uint32_t budget = 200000;
        if (IRQ_MODE) {
            while (!irq_done && --budget) __asm__ volatile ("nop");
            __asm__ volatile ("csrci mstatus, 8");
        } else {
            do { npu_operator_snapshot(&completion); }
            while (!completion.irq_status && --budget);
        }
        check(budget != 0, 4);
        check((completion.status & (NPU_STATUS_DONE_MASK | NPU_STATUS_BUSY_MASK |
            NPU_STATUS_ERROR_MASK | NPU_STATUS_PLATFORM_FAULT_MASK)) == NPU_STATUS_DONE_MASK, 5);
        check(completion.error_code == 0 && completion.irq_status == 1, 6);
        check(completion.frame_id == config->frame_id && completion.generation == config->generation &&
            completion.op_tag == config->op_tag, 7);
        check(completion.total_cycles > 0 && completion.compute_cycles > 0 &&
            completion.dma_wait_cycles > 0 && completion.total_cycles >= completion.compute_cycles &&
            completion.total_cycles >= completion.dma_wait_cycles, 8);
        if (!IRQ_MODE) {
            /* Completion remains frozen until explicit acknowledgement. */
            check(npu_operator_configure(config) == -1 && npu_operator_start() == -1, 9);
        }
        SIG[1] = 3;
        volatile const uint8_t *output = (volatile const uint8_t *)config->output_base;
        for (uint32_t i = 0; i < sizeof(expected_output); ++i) {
            SIG[13] = i;
            SIG[14] = output[i];
            SIG[15] = expected_output[i];
            check(SIG[14] == SIG[15], 0x20);
            SIG[4]++;
        }
        SIG[5] = completion.total_cycles;
        SIG[6] = completion.compute_cycles;
        SIG[7] = completion.dma_wait_cycles;
        SIG[8] = completion.frame_id;
        SIG[9] = completion.generation;
        if (!IRQ_MODE) npu_operator_ack(completion.irq_status);
        npu_operator_snapshot(&completion);
        check(completion.irq_status == 0 && (completion.status & NPU_STATUS_IDLE_MASK), 0x21);
        SIG[2]++;
    }
    check(SIG[3] == (IRQ_MODE ? 2u : 0u), 0x22);
    SIG[1] = 4;
    SIG[0] = 0x4350554eu;
    for (;;) __asm__ volatile ("nop");
}
