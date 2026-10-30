#include "npu_operator.h"

static uint32_t rd(uint32_t offset)
{
    return *(volatile uint32_t *)(NPU_MMIO_BASE + offset);
}
static void wr(uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(NPU_MMIO_BASE + offset) = value;
}
static int available(void)
{
    uint32_t status = rd(NPU_REG_STATUS);
    return (status & NPU_STATUS_IDLE_MASK) &&
        !(status & (NPU_STATUS_BUSY_MASK | NPU_STATUS_PLATFORM_FAULT_MASK)) &&
        rd(NPU_REG_IRQ_STATUS) == 0;
}
int npu_operator_probe(void)
{
    return rd(NPU_REG_ID_VERSION) == NPU_ID_VERSION && rd(NPU_REG_CAPS) == NPU_CAPS ? 0 : -1;
}
int npu_operator_configure(const struct npu_operator_config *c)
{
    if (!available()) return -1;
    wr(NPU_REG_INPUT_BASE, c->input_base);
    wr(NPU_REG_WEIGHT_BASE, c->weight_base);
    wr(NPU_REG_BIAS_BASE, c->bias_base);
    wr(NPU_REG_REQUANT_BASE, c->requant_base);
    wr(NPU_REG_OUTPUT_BASE, c->output_base);
    wr(NPU_REG_INPUT_WH, c->input_wh);
    wr(NPU_REG_CHANNELS, c->channels);
    wr(NPU_REG_OUTPUT_WH, c->output_wh);
    wr(NPU_REG_KSP, c->ksp);
    wr(NPU_REG_FORMAT, c->format);
    wr(NPU_REG_FRAME_ID, c->frame_id);
    wr(NPU_REG_GENERATION, c->generation);
    wr(NPU_REG_OP_TAG, c->op_tag);
    return 0;
}
int npu_operator_start(void)
{
    if (!available()) return -1;
    wr(NPU_REG_CONTROL, NPU_CONTROL_START_MASK);
    return 0;
}
void npu_operator_snapshot(struct npu_operator_snapshot *s)
{
    /* Sample the sticky completion first. Once observed, status/counters and
     * identity are frozen until this single software owner acknowledges it.
     * STATUS first could mix a busy sample with a newly asserted completion. */
    s->irq_status = rd(NPU_REG_IRQ_STATUS);
    s->status = rd(NPU_REG_STATUS);
    s->error_code = rd(NPU_REG_ERROR_CODE);
    s->frame_id = rd(NPU_REG_FRAME_ID);
    s->generation = rd(NPU_REG_GENERATION);
    s->op_tag = rd(NPU_REG_OP_TAG);
    s->total_cycles = rd(NPU_REG_TOTAL_CYCLES);
    s->compute_cycles = rd(NPU_REG_COMPUTE_CYCLES);
    s->dma_wait_cycles = rd(NPU_REG_DMA_WAIT_CYCLES);
}
void npu_operator_irq_enable(uint32_t mask)
{
    wr(NPU_REG_IRQ_ENABLE, mask & NPU_REG_IRQ_ENABLE_VALID_MASK);
}
void npu_operator_ack(uint32_t mask)
{
    wr(NPU_REG_IRQ_STATUS, mask & NPU_REG_IRQ_STATUS_VALID_MASK);
    /* Endpoint acknowledgement must be visible before CPU pending is cleared. */
    (void)rd(NPU_REG_IRQ_STATUS);
}
