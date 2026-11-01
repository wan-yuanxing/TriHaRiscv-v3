#ifndef TRIHA_VIDEO_FRAME_POOL_H
#define TRIHA_VIDEO_FRAME_POOL_H
#include <stdint.h>
#include "video_display.h"

/* One CPU owner serializes all calls. Tokens never authorize a DMA by themselves.
 * Capture/operator/result completions require the platform's real write/drain
 * proof. This library does not implement a fabric, cache fence or NPU graph. */
enum {
    VIDEO_FRAME_OK=0, VIDEO_FRAME_REJECTED=1,
    VIDEO_FRAME_INVALID=-1, VIDEO_FRAME_BUSY=-2, VIDEO_FRAME_NO_FREE=-3,
    VIDEO_FRAME_STALE=-4, VIDEO_FRAME_STATE=-5, VIDEO_FRAME_FAULT=-6,
    VIDEO_FRAME_IO=-7, VIDEO_FRAME_EXHAUSTED=-8, VIDEO_FRAME_PROTOCOL=-9
};
enum {
    VIDEO_FRAME_FREE=0, VIDEO_FRAME_CAPTURING, VIDEO_FRAME_READY,
    VIDEO_FRAME_PROCESSING, VIDEO_FRAME_READY_DISPLAY, VIDEO_FRAME_DISPLAY_PENDING,
    VIDEO_FRAME_DISPLAYING, VIDEO_FRAME_RETIRING, VIDEO_FRAME_INVALIDATED
};
enum {
    VIDEO_FRAME_QUIESCE_CAPTURE=1, VIDEO_FRAME_QUIESCE_COMPUTE=2,
    VIDEO_FRAME_QUIESCE_DISPLAY=4, VIDEO_FRAME_QUIESCE_MAILBOX=8,
    VIDEO_FRAME_QUIESCED_ALL=15
};
struct video_frame_token { uint32_t slot, frame, generation; };
struct video_frame_allocation {
    struct video_frame_token id;
    uint32_t raw_base, raw_stride, preview_base, preview_stride;
    uint32_t input_base, input_bytes, preprocess_version;
};
struct video_frame_slot {
    struct video_frame_token id;
    uint32_t state, invalid;
};
struct video_frame_submission {
    struct video_frame_token id;
    uint32_t valid, mode, seq, mode_only;
};
struct video_frame_graph {
    struct video_frame_token id;
    uint32_t active, op_pending, op_tag, final_done, issued;
};
struct video_frame_stats {
    uint32_t allocated, captured, graph_starts, operators_done, results;
    uint32_t display_submits, display_commits, mode_commits, releases, rejected;
    uint32_t dropped, no_free, faults;
};
struct video_frame_pool {
    struct video_frame_slot slots[3];
    struct video_frame_graph graph;
    struct video_frame_submission active, pending;
    struct video_frame_stats stats;
    struct video_frame_token last_drop;
    uint32_t last_drop_reason, generation, next_frame, cursor, recovering, error;
};

/* init is startup-only. Never use it to forget live references. */
void video_frame_pool_init(struct video_frame_pool *, uint32_t generation);
uint32_t video_frame_pool_free_mask(const struct video_frame_pool *);
uint32_t video_frame_pool_slot_state(const struct video_frame_pool *, uint32_t slot);
int video_frame_pool_allocate(struct video_frame_pool *, struct video_frame_allocation *);
int video_frame_pool_capture_done(struct video_frame_pool *, const struct video_frame_token *, uint32_t success);
int video_frame_pool_graph_begin(struct video_frame_pool *, uint32_t npu_idle, struct video_frame_token *);
/* Software operator ticket: first arbitrary, then +1 modulo32 within one graph;
 * never reuse a ticket in that graph. Hardware tag mapping is an adapter duty. */
int video_frame_pool_operator_begin(struct video_frame_pool *, const struct video_frame_token *, uint32_t op_tag);
int video_frame_pool_operator_done(struct video_frame_pool *, const struct video_frame_token *, uint32_t op_tag, uint32_t last, uint32_t success);
int video_frame_pool_result_ready(struct video_frame_pool *, const struct video_frame_token *, uint32_t workspace_released);
/* Whole-frame NPU path: only after collect validated the published result and
 * hardware ACK proved the shared workspace idle. Never mix with operator tickets. */
int video_frame_pool_frame_done(struct video_frame_pool *, const struct video_frame_token *, uint32_t result_valid, uint32_t workspace_released);
int video_frame_pool_drop(struct video_frame_pool *, const struct video_frame_token *, uint32_t reason);
int video_frame_pool_present(struct video_frame_pool *, const struct video_display_io *, const struct video_display_record *, uint32_t mode, uint32_t seq, uint32_t mode_only);
int video_frame_pool_poll_display(struct video_frame_pool *, const struct video_display_io *);
int video_frame_pool_fail(struct video_frame_pool *, const struct video_frame_token *, uint32_t reason);
/* Only after actual coordinated DMA/compute/display/mailbox quiescence. */
int video_frame_pool_recover(struct video_frame_pool *, uint32_t generation, uint32_t quiesced);
#endif
