#ifndef TRIHA_NPU_FRAME_H
#define TRIHA_NPU_FRAME_H
#include <stdint.h>
#include "frame_config.h"

/* One CPU owner. MMIO callbacks use offsets from NF_BASE; read_shared uses
 * absolute, uncached DDR addresses and returns completed reads. The fence
 * orders CPU I/O; task retirement is proved by hardware, never by this fence. */
struct npu_frame_io {
    void *context;
    int (*read32)(void *,uint32_t,uint32_t *);
    int (*write32)(void *,uint32_t,uint32_t);
    int (*read_shared)(void *,uint32_t,uint32_t *,uint32_t words);
    int (*fence)(void *);
};
struct npu_frame_ticket { uint32_t slot,cmd,frame,epoch; };
struct npu_frame_box { uint32_t x,y,width,height,score_bits,candidate,stride; };
struct npu_frame_result {
    uint32_t valid,face_count,display_count,crc;
    struct npu_frame_box boxes[16];
};
enum { NPU_FRAME_OK=0,NPU_FRAME_PENDING=1,NPU_FRAME_UNPUBLISHED=2,
       NPU_FRAME_INVALID=-1,NPU_FRAME_BUSY=-2,NPU_FRAME_IO=-3,
       NPU_FRAME_PROTOCOL=-4,NPU_FRAME_FAULT=-5,NPU_FRAME_VERSION=-6 };
int npu_frame_submit(const struct npu_frame_io *,const struct npu_frame_ticket *);
/* Collects either the legacy hardware records or CPU-post heads.  The CPU-post
 * path considers all 2100 heads in bounded sorted pages, with rounded FP32
 * score descending / candidate id ascending, then greedy NMS. It retains up
 * to 16 display boxes and never fabricates landmarks. Heads remain immutable
 * under the HELD frame ownership until this call completes. */
int npu_frame_collect(const struct npu_frame_io *,const struct npu_frame_ticket *,struct npu_frame_result *);
int npu_frame_ack(const struct npu_frame_io *,const struct npu_frame_ticket *);
#endif
