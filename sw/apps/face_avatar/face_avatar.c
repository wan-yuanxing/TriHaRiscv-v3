#include "face_avatar.h"

static int fail(struct face_avatar *a,uint32_t domain,int code) {
    if (!a->error_domain) { a->error_domain=domain; a->error_code=code; }
    if (!a->pool.recovering) {
        a->pool.recovering=1; a->pool.error=domain;
        if (a->pool.stats.faults!=UINT32_MAX) ++a->pool.stats.faults;
    }
    return FACE_AVATAR_FAULT;
}
static int capture_identity(const struct video_capture_identity *id,const struct video_frame_allocation *a) {
    return id->id.slot==a->id.slot && id->id.frame==a->id.frame && id->id.generation==a->id.generation &&
        id->version==a->preprocess_version && id->raw_base==a->raw_base &&
        id->preview_base==a->preview_base && id->input_base==a->input_base;
}
int face_avatar_init(struct face_avatar *a,const struct face_avatar_io *io,uint32_t epoch) {
    uint32_t i;volatile unsigned char *bytes;
    if (!a || !io || !epoch || epoch==UINT32_MAX || !io->capture.read32 || !io->capture.write32 || !io->capture.fence ||
        !io->display.read32 || !io->display.write32 || !io->display.fence || !io->npu.read32 || !io->npu.write32 ||
        !io->npu.read_shared || !io->npu.fence) return FACE_AVATAR_INVALID;
    bytes=(volatile unsigned char *)a;
    for (i=0;i<sizeof *a;++i)bytes[i]=0;
    a->io=*io; a->next_cmd=1; a->next_seq=1;
    video_frame_pool_init(&a->pool,epoch);
    return FACE_AVATAR_OK;
}
int face_avatar_build_record(struct video_display_record *r,const struct video_frame_token *id,const struct npu_frame_result *result) {
    uint32_t i,last=0x3f800000u;
    if (!r || !id || !result || result->valid!=1 || result->face_count>B03_CAPACITY ||
        result->display_count!=(result->face_count>16?16:result->face_count)) return FACE_AVATAR_INVALID;
    if (video_display_init_record(r,id->slot,id->frame,id->generation)!=VIDEO_DISPLAY_OK) return FACE_AVATAR_INVALID;
    for (i=0;i<result->display_count;++i) {
        const struct npu_frame_box *b=&result->boxes[i];
        if (b->x>=800 || b->y>=600 || !b->width || !b->height || b->width>800-b->x || b->height>600-b->y || b->score_bits>last)
            return FACE_AVATAR_INVALID;
        last=b->score_bits;
        r->words[VDISP_HEADER_WORDS+i*VDISP_BOX_WORDS]=b->x|(b->y<<16);
        r->words[VDISP_HEADER_WORDS+i*VDISP_BOX_WORDS+1]=(b->x+b->width)|((b->y+b->height)<<16);
        /* Word 2 point mask and words 3..7 remain zero: this model has no landmarks. */
    }
    if (result->display_count) {
        r->words[VDISP_FIELD_FLAGS]=VDISP_FLAG_RESULT_VALID|VDISP_FLAG_PRIMARY_VALID;
        r->words[VDISP_FIELD_BOX_MASK]=(1u<<result->display_count)-1u;
        r->words[VDISP_FIELD_PRIMARY_INDEX]=0;
    }
    return FACE_AVATAR_OK;
}
static int poll_capture(struct face_avatar *a) {
    struct video_capture_events e;int r;
    r=video_capture_read_events(&a->io.capture,&e);
    if (r!=VIDEO_CAPTURE_OK) return fail(a,FACE_AVATAR_CAPTURE,r);
    if (e.pending&4u) return fail(a,FACE_AVATAR_CAPTURE,VIDEO_CAPTURE_FAILED);
    if (!e.pending) return FACE_AVATAR_OK;
    if (!a->capture_valid || !a->capture_submitted) return fail(a,FACE_AVATAR_CAPTURE,VIDEO_CAPTURE_PROTOCOL);
    if ((e.pending&1u) && !capture_identity(&e.accepted,&a->capture))return fail(a,FACE_AVATAR_CAPTURE,VIDEO_CAPTURE_PROTOCOL);
    if (e.pending&2u) {
        r=video_capture_validate_completion(&e,&a->capture);
        if (r!=VIDEO_CAPTURE_OK)return fail(a,FACE_AVATAR_CAPTURE,r);
    }
    r=video_capture_ack(&a->io.capture,e.pending&3u);
    if (r!=VIDEO_CAPTURE_OK)return fail(a,FACE_AVATAR_CAPTURE,r);
    if (e.pending&2u) {
        r=video_frame_pool_capture_done(&a->pool,&a->capture.id,1);
        if (r!=VIDEO_FRAME_OK)return fail(a,FACE_AVATAR_POOL,r);
        a->capture_valid=0; a->capture_submitted=0; a->capture_rearm=1;
    }
    return FACE_AVATAR_OK;
}
static int capture_next(struct face_avatar *a) {
    int r;
    if (a->capture_rearm) {
        r=video_capture_rearm(&a->io.capture);
        if (r==VIDEO_CAPTURE_BUSY)return FACE_AVATAR_OK;
        if (r!=VIDEO_CAPTURE_OK)return fail(a,FACE_AVATAR_CAPTURE,r);
        a->capture_rearm=0;
    }
    if (!a->capture_valid) {
        if (a->pool.next_frame==UINT32_MAX)return fail(a,FACE_AVATAR_POOL,VIDEO_FRAME_EXHAUSTED);
        r=video_frame_pool_allocate(&a->pool,&a->capture);
        if (r==VIDEO_FRAME_BUSY || r==VIDEO_FRAME_NO_FREE)return FACE_AVATAR_OK;
        if (r!=VIDEO_FRAME_OK)return fail(a,FACE_AVATAR_POOL,r);
        a->capture_valid=1;
    }
    if (!a->capture_submitted) {
        r=video_capture_submit(&a->io.capture,&a->capture);
        if (r==VIDEO_CAPTURE_BUSY)return FACE_AVATAR_OK;
        if (r!=VIDEO_CAPTURE_OK)return fail(a,FACE_AVATAR_CAPTURE,r);
        a->capture_submitted=1;
    }
    return FACE_AVATAR_OK;
}
static int poll_npu(struct face_avatar *a) {
    struct video_frame_token id;uint32_t status;int r;
    if (a->npu_submitted) {
        r=npu_frame_collect(&a->io.npu,&a->ticket,&a->result);
        if (r==NPU_FRAME_PENDING || r==NPU_FRAME_UNPUBLISHED)return FACE_AVATAR_OK;
        if (r!=NPU_FRAME_OK)return fail(a,FACE_AVATAR_NPU,r);
        id=a->pool.graph.id;
        r=face_avatar_build_record(&a->records[id.slot],&id,&a->result);
        if (r!=FACE_AVATAR_OK)return fail(a,FACE_AVATAR_NPU,r);
        r=npu_frame_ack(&a->io.npu,&a->ticket);
        if (r!=NPU_FRAME_OK)return fail(a,FACE_AVATAR_NPU,r);
        r=video_frame_pool_frame_done(&a->pool,&id,a->result.valid,1);
        if (r!=VIDEO_FRAME_OK)return fail(a,FACE_AVATAR_POOL,r);
        a->npu_submitted=0;
        return FACE_AVATAR_OK;
    }
    if (!a->pool.graph.active) {
        if (a->io.npu.read32(a->io.npu.context,NF_REG_STATUS,&status))return fail(a,FACE_AVATAR_NPU,NPU_FRAME_IO);
        if (status&NF_STATUS_FAULT)return fail(a,FACE_AVATAR_NPU,NPU_FRAME_FAULT);
        if (status!=NF_STATUS_IDLE)return FACE_AVATAR_OK;
        r=video_frame_pool_graph_begin(&a->pool,1,&id);
        if (r==VIDEO_FRAME_BUSY)return FACE_AVATAR_OK;
        if (r!=VIDEO_FRAME_OK)return fail(a,FACE_AVATAR_POOL,r);
        if (!a->next_cmd || a->next_cmd==UINT32_MAX)return fail(a,FACE_AVATAR_NPU,NPU_FRAME_INVALID);
        a->ticket.slot=id.slot; a->ticket.frame=id.frame; a->ticket.epoch=id.generation; a->ticket.cmd=a->next_cmd++;
    }
    r=npu_frame_submit(&a->io.npu,&a->ticket);
    if (r==NPU_FRAME_BUSY)return FACE_AVATAR_OK;
    if (r!=NPU_FRAME_OK)return fail(a,FACE_AVATAR_NPU,r);
    a->npu_submitted=1;
    return FACE_AVATAR_OK;
}
static int present_next(struct face_avatar *a) {
    uint32_t i,slot=3,status;int r;
    if (a->pool.pending.valid)return FACE_AVATAR_OK;
    for (i=0;i<3;++i)if (a->pool.slots[i].state==VIDEO_FRAME_READY_DISPLAY &&
        (slot==3 || a->pool.slots[i].id.frame<a->pool.slots[slot].id.frame))slot=i;
    if (slot==3)return FACE_AVATAR_OK;
    if (a->io.display.read32(a->io.display.context,VDISP_REG_STATUS,&status))return fail(a,FACE_AVATAR_DISPLAY,VIDEO_DISPLAY_IO_ERROR);
    if (status&0x6fu)return FACE_AVATAR_OK;
    if (!a->next_seq || a->next_seq==UINT32_MAX)return fail(a,FACE_AVATAR_DISPLAY,VIDEO_FRAME_EXHAUSTED);
    r=video_frame_pool_present(&a->pool,&a->io.display,&a->records[slot],1,a->next_seq++,0);
    if (r!=VIDEO_FRAME_OK)return fail(a,FACE_AVATAR_DISPLAY,r);
    return FACE_AVATAR_OK;
}
int face_avatar_step(struct face_avatar *a) {
    int r;
    if (!a)return FACE_AVATAR_INVALID;
    if (a->error_domain || a->pool.recovering)return FACE_AVATAR_FAULT;
    r=video_frame_pool_poll_display(&a->pool,&a->io.display);
    if (r!=VIDEO_FRAME_OK && r!=VIDEO_FRAME_REJECTED)return fail(a,FACE_AVATAR_DISPLAY,r);
    if (poll_capture(a)!=FACE_AVATAR_OK)return FACE_AVATAR_FAULT;
    if (!a->capture_enabled) {
        r=video_capture_enable(&a->io.capture);
        if (r==VIDEO_CAPTURE_BUSY)return FACE_AVATAR_OK;
        if (r!=VIDEO_CAPTURE_OK)return fail(a,FACE_AVATAR_CAPTURE,r);
        a->capture_enabled=1;
    }
    if (poll_npu(a)!=FACE_AVATAR_OK ||
        present_next(a)!=FACE_AVATAR_OK || capture_next(a)!=FACE_AVATAR_OK)return FACE_AVATAR_FAULT;
    return FACE_AVATAR_OK;
}
