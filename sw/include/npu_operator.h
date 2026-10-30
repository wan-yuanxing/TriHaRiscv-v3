#ifndef TRIHA_NPU_OPERATOR_H
#define TRIHA_NPU_OPERATOR_H
#include <stdint.h>
#include "npu_regs.h"

/* This operator ABI has no implicit cache maintenance or fabric ordering. */
struct npu_operator_config {
    uint32_t input_base, weight_base, bias_base, requant_base, output_base;
    uint32_t input_wh, channels, output_wh, ksp, format;
    uint32_t frame_id, generation, op_tag;
};
struct npu_operator_snapshot {
    uint32_t status, irq_status, error_code;
    uint32_t frame_id, generation, op_tag;
    uint32_t total_cycles, compute_cycles, dma_wait_cycles;
};
int npu_operator_probe(void);
int npu_operator_configure(const struct npu_operator_config *config);
int npu_operator_start(void);
void npu_operator_snapshot(struct npu_operator_snapshot *snapshot);
void npu_operator_irq_enable(uint32_t mask);
void npu_operator_ack(uint32_t mask);
#endif
