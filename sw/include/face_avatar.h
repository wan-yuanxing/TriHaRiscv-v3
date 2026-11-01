#ifndef TRIHA_FACE_AVATAR_H
#define TRIHA_FACE_AVATAR_H
#include "video_capture.h"
#include "npu_frame.h"

enum { FACE_AVATAR_OK=0, FACE_AVATAR_FAULT=-1, FACE_AVATAR_INVALID=-2 };
enum { FACE_AVATAR_CAPTURE=1, FACE_AVATAR_NPU=2, FACE_AVATAR_DISPLAY=3, FACE_AVATAR_POOL=4 };
struct face_avatar_io {
    struct video_capture_io capture;
    struct video_display_io display;
    struct npu_frame_io npu;
};
struct face_avatar {
    struct face_avatar_io io;
    struct video_frame_pool pool;
    struct video_frame_allocation capture;
    struct npu_frame_ticket ticket;
    struct npu_frame_result result;
    struct video_display_record records[3];
    uint32_t capture_enabled,capture_valid,capture_submitted,capture_rearm,npu_submitted;
    uint32_t next_cmd,next_seq,error_domain;
    int error_code;
};
/* Startup only, after supervisor established a sealed model and a new common
 * capture/display/NPU epoch. Never call init to discard live DMA references. */
int face_avatar_init(struct face_avatar *,const struct face_avatar_io *,uint32_t epoch);
/* One serialized polling owner. BUSY makes no ownership progress; I/O/protocol
 * failure latches recovery, retains references and stops subsequent I/O. */
int face_avatar_step(struct face_avatar *);
/* BOX records use already sorted source-space NPU rectangles, without decode,
 * NMS, coordinate scaling, synthetic landmarks or unverified avatar assets. */
int face_avatar_build_record(struct video_display_record *,const struct video_frame_token *,const struct npu_frame_result *);
#endif
