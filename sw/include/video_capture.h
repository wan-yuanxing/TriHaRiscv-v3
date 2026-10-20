#ifndef TRIHA_VIDEO_CAPTURE_H
#define TRIHA_VIDEO_CAPTURE_H
#include <stdint.h>
#include "video_capture_v2.h"
#include "video_frame_pool.h"
/* One serialized CPU owner. Offsets are relative to VCAP_MMIO_BASE. Successful
 * callback completion means the AXI response has completed. A failed write may
 * already have executed: retain the allocation and use coordinated recovery.
 * fence orders MMIO only; it is not cross-master DDR visibility evidence. */
struct video_capture_io {
    void *context;
    int (*read32)(void *,uint32_t,uint32_t *);
    int (*write32)(void *,uint32_t,uint32_t);
    int (*fence)(void *);
};
struct video_capture_identity {
    struct video_frame_token id;
    uint32_t version,raw_base,preview_base,input_base;
};
struct video_capture_completion {
    struct video_capture_identity identity;
    uint32_t result,raw_pixels,preview_pixels,input_pixels;
    uint32_t raw_bytes,preview_bytes,input_bytes,raw_crc,preview_crc,fifo_peak,drained;
};
struct video_capture_events {
    uint32_t pending,error;
    struct video_capture_identity accepted;
    struct video_capture_completion completed;
};
enum { VIDEO_CAPTURE_OK=0,VIDEO_CAPTURE_INVALID=-1,VIDEO_CAPTURE_BUSY=-2,
       VIDEO_CAPTURE_VERSION=-3,VIDEO_CAPTURE_IO=-4,VIDEO_CAPTURE_PROTOCOL=-5,
       VIDEO_CAPTURE_FAILED=-6 };
int video_capture_enable(const struct video_capture_io *);
int video_capture_submit(const struct video_capture_io *,const struct video_frame_allocation *);
int video_capture_read_events(const struct video_capture_io *,struct video_capture_events *);
int video_capture_validate_completion(const struct video_capture_events *,const struct video_frame_allocation *);
int video_capture_ack(const struct video_capture_io *,uint32_t bits);
int video_capture_rearm(const struct video_capture_io *);
#endif
