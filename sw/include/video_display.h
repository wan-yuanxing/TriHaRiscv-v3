#ifndef TRIHA_VIDEO_DISPLAY_H
#define TRIHA_VIDEO_DISPLAY_H
#include <stdint.h>
#include "video_display_abi.h"
/* Callbacks address offsets within VDISP_BASE, return 0 on completed success.
 * Platform owns uncached mapping, bus errors and real I/O ordering. One caller
 * owns submit and ACK. Successful submit is enqueue only, never pixel commit. */
struct video_display_io {
    void *context;
    int (*read32)(void *, uint32_t, uint32_t *);
    int (*write32)(void *, uint32_t, uint32_t);
    int (*fence)(void *);
};
struct video_display_record { uint32_t words[VDISP_RECORD_WORDS]; };
struct video_display_events {
    uint32_t pending, error;
    uint32_t commit_frame, commit_generation, commit_slot, commit_mode, commit_seq, commit_mode_only;
    uint32_t release_frame, release_generation, release_slot;
    uint32_t reject_seq, reject_code;
};
enum { VIDEO_DISPLAY_OK=0, VIDEO_DISPLAY_INVALID=-1, VIDEO_DISPLAY_BUSY=-2,
       VIDEO_DISPLAY_VERSION=-3, VIDEO_DISPLAY_IO_ERROR=-4 };
int video_display_init_record(struct video_display_record *, uint32_t slot, uint32_t frame, uint32_t generation);
int video_display_submit(const struct video_display_io *, const struct video_display_record *, uint32_t mode, uint32_t seq, uint32_t mode_only);
int video_display_read_events(const struct video_display_io *, struct video_display_events *);
int video_display_ack(const struct video_display_io *, uint32_t bits);
#endif
