#include "video_frame_pool.h"
#include "video_cfg.h"

enum { E_CAPTURE=1, E_OPERATOR, E_PUBLISH, E_EVENT_READ, E_ACK, E_PROTOCOL, E_ID_EXHAUSTED };

static void increment(uint32_t *value) {
    if (*value!=UINT32_MAX) ++*value;
}
static int same_id(const struct video_frame_token *a,const struct video_frame_token *b) {
    return a->slot==b->slot && a->frame==b->frame && a->generation==b->generation;
}
static int valid_id(const struct video_frame_token *id) {
    return id && id->slot<3 && id->frame!=0;
}
static int matches(const struct video_frame_pool *p,const struct video_frame_token *id) {
    return valid_id(id) && same_id(id,&p->slots[id->slot].id);
}
static void fault(struct video_frame_pool *p,uint32_t code,const struct video_frame_token *id) {
    if (!p->recovering) {
        p->recovering=1; p->error=code; increment(&p->stats.faults);
    }
    if (id && matches(p,id) && p->slots[id->slot].state!=VIDEO_FRAME_FREE)
        p->slots[id->slot].invalid=1;
}
static int io_valid(const struct video_display_io *io) {
    return io && io->read32 && io->write32 && io->fence;
}

void video_frame_pool_init(struct video_frame_pool *p,uint32_t generation) {
    uint32_t i;
    volatile unsigned char *bytes;
    if (!p) return;
    /* Startup-only byte clearing has no hidden libc dependency on bare RV32. */
    bytes=(volatile unsigned char *)p;
    for (i=0;i<sizeof *p;++i) bytes[i]=0;
    p->generation=generation; p->next_frame=1;
    for (i=0;i<3;++i) { p->slots[i].id.slot=i; p->slots[i].id.generation=generation; }
}
uint32_t video_frame_pool_free_mask(const struct video_frame_pool *p) {
    uint32_t i,mask=0;
    if (!p || p->recovering) return 0;
    for (i=0;i<3;++i)
        if (p->slots[i].state==VIDEO_FRAME_FREE && !p->slots[i].invalid) mask|=1u<<i;
    return mask;
}
uint32_t video_frame_pool_slot_state(const struct video_frame_pool *p,uint32_t slot) {
    if (!p || slot>=3 || p->slots[slot].invalid) return VIDEO_FRAME_INVALIDATED;
    return p->slots[slot].state;
}
int video_frame_pool_allocate(struct video_frame_pool *p,struct video_frame_allocation *out) {
    static const uint32_t raw[3]={VIDEO_FRAME_SLOT_A,VIDEO_FRAME_SLOT_B,VIDEO_FRAME_SLOT_C};
    static const uint32_t input[3]={VIDEO_INPUT_SLOT_A,VIDEO_INPUT_SLOT_B,VIDEO_INPUT_SLOT_C};
    struct video_frame_allocation a;
    uint32_t i,slot=3;
    if (!p || !out) return VIDEO_FRAME_INVALID;
    if (p->recovering) return VIDEO_FRAME_FAULT;
    if (p->next_frame==0) { fault(p,E_ID_EXHAUSTED,0); return VIDEO_FRAME_EXHAUSTED; }
    for (i=0;i<3;++i) if (p->slots[i].state==VIDEO_FRAME_CAPTURING) return VIDEO_FRAME_BUSY;
    for (i=0;i<3;++i) {
        uint32_t candidate=(p->cursor+i)%3;
        if (p->slots[candidate].state==VIDEO_FRAME_FREE && !p->slots[candidate].invalid) { slot=candidate; break; }
    }
    if (slot==3) { increment(&p->stats.no_free); return VIDEO_FRAME_NO_FREE; }
    a.id.slot=slot; a.id.frame=p->next_frame; a.id.generation=p->generation;
    a.raw_base=raw[slot]; a.raw_stride=VIDEO_FRAME_RAW_STRIDE;
    a.preview_base=raw[slot]+VIDEO_FRAME_PREVIEW_OFFSET; a.preview_stride=VIDEO_FRAME_PREVIEW_STRIDE;
    a.input_base=input[slot]; a.input_bytes=VIDEO_INPUT_BYTES; a.preprocess_version=VIDEO_INPUT_PREPROCESS_VERSION;
    p->slots[slot].id=a.id; p->slots[slot].state=VIDEO_FRAME_CAPTURING;
    ++p->next_frame; p->cursor=(slot+1)%3; increment(&p->stats.allocated);
    *out=a;
    return VIDEO_FRAME_OK;
}
int video_frame_pool_capture_done(struct video_frame_pool *p,const struct video_frame_token *id,uint32_t success) {
    if (!p || !id || success>1) return VIDEO_FRAME_INVALID;
    if (!matches(p,id)) { fault(p,E_PROTOCOL,0); return VIDEO_FRAME_STALE; }
    if (p->slots[id->slot].state!=VIDEO_FRAME_CAPTURING) { fault(p,E_PROTOCOL,id); return VIDEO_FRAME_STATE; }
    /* The qualified completion, including failures, proves capture writes drained. */
    p->slots[id->slot].state=VIDEO_FRAME_READY;
    if (!success) fault(p,E_CAPTURE,id);
    if (p->recovering) return VIDEO_FRAME_FAULT;
    increment(&p->stats.captured);
    return VIDEO_FRAME_OK;
}
int video_frame_pool_graph_begin(struct video_frame_pool *p,uint32_t npu_idle,struct video_frame_token *out) {
    uint32_t i,slot=3;
    if (!p || !out || npu_idle>1) return VIDEO_FRAME_INVALID;
    if (p->recovering) return VIDEO_FRAME_FAULT;
    if (p->graph.active || !npu_idle) return VIDEO_FRAME_BUSY;
    for (i=0;i<3;++i) if (p->slots[i].state==VIDEO_FRAME_READY && !p->slots[i].invalid &&
        (slot==3 || p->slots[i].id.frame<p->slots[slot].id.frame)) slot=i;
    if (slot==3) return VIDEO_FRAME_BUSY;
    p->graph.id=p->slots[slot].id; p->graph.active=1; p->graph.op_pending=0;
    p->graph.op_tag=0; p->graph.final_done=0; p->graph.issued=0; p->slots[slot].state=VIDEO_FRAME_PROCESSING;
    increment(&p->stats.graph_starts); *out=p->graph.id;
    return VIDEO_FRAME_OK;
}
int video_frame_pool_operator_begin(struct video_frame_pool *p,const struct video_frame_token *id,uint32_t tag) {
    if (!p || !valid_id(id)) return VIDEO_FRAME_INVALID;
    if (p->recovering) return VIDEO_FRAME_FAULT;
    if (!matches(p,id)) return VIDEO_FRAME_STALE;
    if (!p->graph.active || !same_id(id,&p->graph.id) || p->slots[id->slot].state!=VIDEO_FRAME_PROCESSING)
        return VIDEO_FRAME_STATE;
    if (p->graph.op_pending || p->graph.final_done) return VIDEO_FRAME_BUSY;
    if (p->graph.issued==UINT32_MAX) { fault(p,E_ID_EXHAUSTED,id); return VIDEO_FRAME_EXHAUSTED; }
    if (p->graph.issued && tag!=p->graph.op_tag+1u) return VIDEO_FRAME_INVALID;
    ++p->graph.issued; p->graph.op_tag=tag; p->graph.op_pending=1;
    return VIDEO_FRAME_OK;
}
int video_frame_pool_operator_done(struct video_frame_pool *p,const struct video_frame_token *id,uint32_t tag,uint32_t last,uint32_t success) {
    if (!p || !id || last>1 || success>1) return VIDEO_FRAME_INVALID;
    if (!matches(p,id) || !p->graph.active || !same_id(id,&p->graph.id)) {
        fault(p,E_PROTOCOL,0); return VIDEO_FRAME_STALE;
    }
    if (!p->graph.op_pending || p->slots[id->slot].state!=VIDEO_FRAME_PROCESSING) {
        fault(p,E_PROTOCOL,id); return VIDEO_FRAME_STATE;
    }
    if (tag!=p->graph.op_tag) { fault(p,E_PROTOCOL,id); return VIDEO_FRAME_STALE; }
    p->graph.op_pending=0;
    if (!success) fault(p,E_OPERATOR,id);
    else { p->graph.final_done=last; increment(&p->stats.operators_done); }
    return p->recovering?VIDEO_FRAME_FAULT:VIDEO_FRAME_OK;
}
int video_frame_pool_result_ready(struct video_frame_pool *p,const struct video_frame_token *id,uint32_t workspace_released) {
    if (!p || !valid_id(id) || workspace_released>1) return VIDEO_FRAME_INVALID;
    if (p->recovering) return VIDEO_FRAME_FAULT;
    if (!matches(p,id)) return VIDEO_FRAME_STALE;
    if (!p->graph.active || !same_id(id,&p->graph.id) || p->slots[id->slot].state!=VIDEO_FRAME_PROCESSING)
        return VIDEO_FRAME_STATE;
    if (!p->graph.final_done || p->graph.op_pending || !workspace_released) return VIDEO_FRAME_BUSY;
    p->slots[id->slot].state=VIDEO_FRAME_READY_DISPLAY; p->graph.active=0;
    increment(&p->stats.results);
    return VIDEO_FRAME_OK;
}
int video_frame_pool_frame_done(struct video_frame_pool *p,const struct video_frame_token *id,uint32_t result_valid,uint32_t workspace_released) {
    if (!p || !valid_id(id) || result_valid>1 || workspace_released>1) return VIDEO_FRAME_INVALID;
    if (p->recovering) return VIDEO_FRAME_FAULT;
    if (!matches(p,id) || !p->graph.active || !same_id(id,&p->graph.id)) {
        fault(p,E_PROTOCOL,0); return VIDEO_FRAME_STALE;
    }
    if (p->slots[id->slot].state!=VIDEO_FRAME_PROCESSING || p->graph.issued || p->graph.op_pending) {
        fault(p,E_PROTOCOL,id); return VIDEO_FRAME_STATE;
    }
    if (!result_valid || !workspace_released) return VIDEO_FRAME_BUSY;
    p->slots[id->slot].state=VIDEO_FRAME_READY_DISPLAY; p->graph.active=0;
    increment(&p->stats.results);
    return VIDEO_FRAME_OK;
}
int video_frame_pool_drop(struct video_frame_pool *p,const struct video_frame_token *id,uint32_t reason) {
    uint32_t state;
    if (!p || !valid_id(id) || !reason) return VIDEO_FRAME_INVALID;
    if (p->recovering) return VIDEO_FRAME_FAULT;
    if (!matches(p,id)) return VIDEO_FRAME_STALE;
    state=p->slots[id->slot].state;
    if (state!=VIDEO_FRAME_READY && state!=VIDEO_FRAME_READY_DISPLAY) return VIDEO_FRAME_STATE;
    p->slots[id->slot].state=VIDEO_FRAME_FREE; p->last_drop=*id; p->last_drop_reason=reason;
    increment(&p->stats.dropped);
    return VIDEO_FRAME_OK;
}
int video_frame_pool_present(struct video_frame_pool *p,const struct video_display_io *io,const struct video_display_record *r,
                             uint32_t mode,uint32_t seq,uint32_t mode_only) {
    struct video_frame_token id;
    if (!p || !r || !io_valid(io) || mode>2 || mode_only>1) return VIDEO_FRAME_INVALID;
    if (p->recovering) return VIDEO_FRAME_FAULT;
    id.slot=r->words[VDISP_FIELD_SLOT]; id.frame=r->words[VDISP_FIELD_FRAME]; id.generation=r->words[VDISP_FIELD_GENERATION];
    if (!matches(p,&id)) return VIDEO_FRAME_STALE;
    if (p->pending.valid) return VIDEO_FRAME_BUSY;
    if (mode_only) {
        if (!p->active.valid || !same_id(&id,&p->active.id) || p->slots[id.slot].state!=VIDEO_FRAME_DISPLAYING)
            return VIDEO_FRAME_STATE;
    } else {
        if (p->slots[id.slot].state!=VIDEO_FRAME_READY_DISPLAY ||
            (p->active.valid && id.frame<=p->active.id.frame)) return VIDEO_FRAME_STATE;
        p->slots[id.slot].state=VIDEO_FRAME_DISPLAY_PENDING;
    }
    p->pending.id=id; p->pending.valid=1; p->pending.mode=mode; p->pending.seq=seq; p->pending.mode_only=mode_only;
    if (video_display_submit(io,r,mode,seq,mode_only)!=VIDEO_DISPLAY_OK) {
        /* An I/O error may have occurred after a posted SUBMIT reached hardware. */
        fault(p,E_PUBLISH,0); return VIDEO_FRAME_IO;
    }
    increment(&p->stats.display_submits);
    return VIDEO_FRAME_OK;
}

static int commit_matches(const struct video_frame_pool *p,const struct video_display_events *e) {
    const struct video_frame_submission *s=&p->pending;
    if (!s->valid || e->commit_slot!=s->id.slot || e->commit_frame!=s->id.frame ||
        e->commit_generation!=s->id.generation || e->commit_mode!=s->mode || e->commit_seq!=s->seq ||
        e->commit_mode_only!=s->mode_only || !matches(p,&s->id)) return 0;
    if (s->mode_only)
        return p->active.valid && same_id(&s->id,&p->active.id) && p->slots[s->id.slot].state==VIDEO_FRAME_DISPLAYING;
    return p->slots[s->id.slot].state==VIDEO_FRAME_DISPLAY_PENDING &&
        (!p->active.valid || s->id.frame>p->active.id.frame);
}
static int release_matches(const struct video_frame_pool *p,const struct video_display_events *e) {
    struct video_frame_token id;
    id.slot=e->release_slot; id.frame=e->release_frame; id.generation=e->release_generation;
    if (!matches(p,&id)) return 0;
    if (p->slots[id.slot].state==VIDEO_FRAME_RETIRING) return 1;
    return (e->pending&1u) && !p->pending.mode_only && p->active.valid &&
        same_id(&id,&p->active.id) && p->slots[id.slot].state==VIDEO_FRAME_DISPLAYING;
}
static int reject_matches(const struct video_frame_pool *p,const struct video_display_events *e) {
    const struct video_frame_submission *s=&p->pending;
    if ((e->pending&1u) || !s->valid || e->reject_seq!=s->seq || !e->reject_code || e->reject_code>255 || !matches(p,&s->id))
        return 0;
    return p->slots[s->id.slot].state==(s->mode_only?VIDEO_FRAME_DISPLAYING:VIDEO_FRAME_DISPLAY_PENDING);
}
int video_frame_pool_poll_display(struct video_frame_pool *p,const struct video_display_io *io) {
    struct video_display_events e;
    uint32_t bits;
    if (!p || !io_valid(io)) return VIDEO_FRAME_INVALID;
    if (video_display_read_events(io,&e)!=VIDEO_DISPLAY_OK) {
        fault(p,E_EVENT_READ,0); return VIDEO_FRAME_IO;
    }
    if (e.pending&~15u) { fault(p,E_PROTOCOL,0); return VIDEO_FRAME_PROTOCOL; }
    if (e.pending&8u) {
        if (!e.error || e.error>255) { fault(p,E_PROTOCOL,0); return VIDEO_FRAME_PROTOCOL; }
        fault(p,0x100u|e.error,0);
    }
    if (((e.pending&1u) && !commit_matches(p,&e)) || ((e.pending&2u) && !release_matches(p,&e)) ||
        ((e.pending&4u) && !reject_matches(p,&e))) {
        fault(p,E_PROTOCOL,0); return VIDEO_FRAME_PROTOCOL;
    }
    bits=e.pending&7u;
    if (bits && video_display_ack(io,bits)!=VIDEO_DISPLAY_OK) {
        fault(p,E_ACK,0); return VIDEO_FRAME_IO;
    }
    /* Apply the already validated snapshot only after completed fence/ACK. */
    if (bits&1u) {
        if (p->pending.mode_only) increment(&p->stats.mode_commits);
        else {
            if (p->active.valid) p->slots[p->active.id.slot].state=VIDEO_FRAME_RETIRING;
            p->slots[p->pending.id.slot].state=VIDEO_FRAME_DISPLAYING;
            increment(&p->stats.display_commits);
        }
        p->active=p->pending; p->active.mode_only=0; p->pending.valid=0;
    }
    if (bits&2u) {
        p->slots[e.release_slot].state=VIDEO_FRAME_FREE;
        increment(&p->stats.releases);
    }
    if (bits&4u) {
        if (!p->pending.mode_only) p->slots[p->pending.id.slot].state=VIDEO_FRAME_READY_DISPLAY;
        p->pending.valid=0; increment(&p->stats.rejected);
    }
    if (p->recovering) return VIDEO_FRAME_FAULT;
    return (bits&4u)?VIDEO_FRAME_REJECTED:VIDEO_FRAME_OK;
}
int video_frame_pool_fail(struct video_frame_pool *p,const struct video_frame_token *id,uint32_t reason) {
    if (!p || !id || !reason || reason>65535) return VIDEO_FRAME_INVALID;
    if (!matches(p,id)) { fault(p,E_PROTOCOL,0); return VIDEO_FRAME_STALE; }
    if (p->slots[id->slot].state==VIDEO_FRAME_FREE) { fault(p,E_PROTOCOL,0); return VIDEO_FRAME_STATE; }
    fault(p,0x10000u|reason,id);
    return VIDEO_FRAME_FAULT;
}
int video_frame_pool_recover(struct video_frame_pool *p,uint32_t generation,uint32_t quiesced) {
    if (!p || generation==p->generation || quiesced!=VIDEO_FRAME_QUIESCED_ALL) return VIDEO_FRAME_INVALID;
    video_frame_pool_init(p,generation);
    return VIDEO_FRAME_OK;
}
