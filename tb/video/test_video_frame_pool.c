#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "video_frame_pool.h"

static unsigned checks, callback_failures, stress_frames;
static int trace_enabled;
#define CHECK(c, label) do { ++checks; if (!(c)) { \
    fprintf(stderr,"FRAME_POOL_ASSERT %s line=%d\n",label,__LINE__); exit(1); } } while (0)

struct bus {
    uint32_t reg[1024];
    struct video_frame_pool *pool;
    struct video_frame_pool ack_before;
    unsigned calls, fail_at, writes, submits, fences, guard_ack, ambiguous;
    int last_fence;
};
static int same(struct video_frame_token a, struct video_frame_token b) {
    return a.slot==b.slot && a.frame==b.frame && a.generation==b.generation;
}
static void status(struct bus *b) {
    uint32_t e=b->reg[0x14/4];
    b->reg[8/4]=(b->reg[0x30/4]?128u:0u) | ((e&1u)?12u:0u) |
        ((e&2u)?16u:0u) | ((e&4u)?32u:0u) | ((e&8u)?68u:0u);
}
static int read32(void *context,uint32_t off,uint32_t *value) {
    struct bus *b=context;
    CHECK(off<4096 && !(off&3),"MMIO_READ_OFFSET");
    ++b->calls;
    if (b->calls==b->fail_at) return -1;
    *value=b->reg[off/4]; b->last_fence=0;
    if (trace_enabled) printf("R %08x %08x\n",(unsigned)off,(unsigned)*value);
    return 0;
}
static int write32(void *context,uint32_t off,uint32_t value) {
    struct bus *b=context;
    int failed;
    CHECK(off<4096 && !(off&3),"MMIO_WRITE_OFFSET");
    ++b->calls; failed=b->calls==b->fail_at;
    if (off==0x18 && b->guard_ack)
        CHECK(memcmp(b->pool,&b->ack_before,sizeof b->ack_before)==0,"ACK_GUARD_POOL_BEFORE_WRITE");
    if (failed && !b->ambiguous) return -1;
    if (off==0x20 || off==0x18) CHECK(b->last_fence,"FENCE_BEFORE_PUBLICATION");
    if (off==0x20) ++b->submits;
    if (off==0x18) { b->reg[0x14/4]&=~value; status(b); }
    else b->reg[off/4]=value;
    ++b->writes; b->last_fence=0;
    if (trace_enabled) printf("W %08x %08x\n",(unsigned)off,(unsigned)value);
    return failed?-1:0;
}
static int fence(void *context) {
    struct bus *b=context;
    ++b->calls;
    if (b->calls==b->fail_at) return -1;
    ++b->fences; b->last_fence=1;
    if (trace_enabled) puts("F");
    return 0;
}
static struct video_display_io setup(struct bus *b,struct video_frame_pool *p) {
    struct video_display_io io;
    memset(b,0,sizeof *b); b->pool=p;
    b->reg[0]=0x10000; b->reg[1]=15; b->reg[0x2c/4]=640;
    io.context=b; io.read32=read32; io.write32=write32; io.fence=fence;
    return io;
}
static void commit(struct bus *b,struct video_frame_token id,uint32_t mode,uint32_t seq,uint32_t only) {
    if (trace_enabled) printf("Q %u %u %u %u %u %u\n",(unsigned)id.slot,(unsigned)id.frame,
        (unsigned)id.generation,(unsigned)mode,(unsigned)seq,(unsigned)only);
    b->reg[0x30/4]=id.frame; b->reg[0x34/4]=id.generation; b->reg[0x38/4]=id.slot;
    b->reg[0x3c/4]=mode; b->reg[0x40/4]=seq;
    b->reg[0x44/4]=id.frame; b->reg[0x48/4]=id.generation; b->reg[0x4c/4]=id.slot;
    b->reg[0x50/4]=mode; b->reg[0x54/4]=seq; b->reg[0x58/4]=only;
    b->reg[0x14/4]|=1; status(b);
}
static void release(struct bus *b,struct video_frame_token id) {
    if (trace_enabled) printf("T %u %u %u\n",(unsigned)id.slot,(unsigned)id.frame,(unsigned)id.generation);
    b->reg[0x5c/4]=id.frame; b->reg[0x60/4]=id.generation; b->reg[0x64/4]=id.slot;
    b->reg[0x14/4]|=2; status(b);
}
static void rejected(struct bus *b,uint32_t seq,uint32_t code) {
    if (trace_enabled) printf("J %u %u\n",(unsigned)seq,(unsigned)code);
    b->reg[0x68/4]=seq; b->reg[0x6c/4]=code;
    b->reg[0x14/4]|=4; status(b);
}
static int poll(struct video_frame_pool *p,struct bus *b,const struct video_display_io *io) {
    int rc;
    b->ack_before=*p; b->guard_ack=1;
    rc=video_frame_pool_poll_display(p,io);
    b->guard_ack=0;
    return rc;
}
static struct video_frame_token ready_frame(struct video_frame_pool *p) {
    struct video_frame_allocation a;
    struct video_frame_token graph;
    CHECK(video_frame_pool_allocate(p,&a)==0,"ALLOCATE_READY_HELPER");
    CHECK(video_frame_pool_capture_done(p,&a.id,1)==0,"CAPTURE_READY_HELPER");
    CHECK(video_frame_pool_graph_begin(p,1,&graph)==0 && same(graph,a.id),"GRAPH_READY_HELPER");
    CHECK(video_frame_pool_operator_begin(p,&graph,9)==0,"OP_READY_HELPER");
    CHECK(video_frame_pool_operator_done(p,&graph,9,1,1)==0,"OP_DONE_READY_HELPER");
    CHECK(video_frame_pool_result_ready(p,&graph,1)==0,"RESULT_READY_HELPER");
    return a.id;
}
static struct video_display_record record_for(struct video_frame_token id) {
    struct video_display_record r;
    CHECK(video_display_init_record(&r,id.slot,id.frame,id.generation)==0,"INIT_DISPLAY_RECORD");
    return r;
}
static void show(struct video_frame_pool *p,struct bus *b,const struct video_display_io *io,
                 struct video_frame_token id,uint32_t seq) {
    struct video_display_record r=record_for(id);
    CHECK(video_frame_pool_present(p,io,&r,0,seq,0)==0,"PRESENT_HELPER");
    commit(b,id,0,seq,0);
    CHECK(poll(p,b,io)==0,"POLL_HELPER");
}
static void allocation_case(void) {
    struct video_frame_pool p;
    struct video_frame_allocation a[3],out,before;
    struct video_frame_token graph;
    uint32_t raw[3]={0x82000000u,0x82200000u,0x82400000u};
    uint32_t input[3]={0x82800000u,0x82850000u,0x828a0000u};
    unsigned i;
    video_frame_pool_init(&p,7);
    CHECK(video_frame_pool_free_mask(&p)==7,"INIT_THREE_FREE");
    for (i=0;i<3;++i) {
        memset(&a[i],0xa5,sizeof a[i]);
        CHECK(video_frame_pool_allocate(&p,&a[i])==0,"ALLOCATE_SUCCESS");
        CHECK(a[i].id.slot==i && a[i].id.frame==i+1 && a[i].id.generation==7,"ALLOCATE_TOKEN");
        CHECK(a[i].raw_base==raw[i] && a[i].raw_stride==2400 && a[i].preview_base==raw[i]+0x160000u &&
            a[i].preview_stride==1200 && a[i].input_base==input[i] && a[i].input_bytes==307200 &&
            a[i].preprocess_version==1,"ALLOCATE_ADDRESSES");
        memset(&out,0xa5,sizeof out); before=out;
        CHECK(video_frame_pool_allocate(&p,&out)==VIDEO_FRAME_BUSY && !memcmp(&out,&before,sizeof out),"ONE_CAPTURE_ONLY");
        CHECK(video_frame_pool_capture_done(&p,&a[i].id,1)==0,"CAPTURE_TO_READY");
    }
    CHECK(video_frame_pool_free_mask(&p)==0,"THREE_OCCUPIED");
    CHECK(video_frame_pool_allocate(&p,&out)==VIDEO_FRAME_NO_FREE && !memcmp(&out,&before,sizeof out),"NO_FREE_NO_OVERWRITE");
    CHECK(p.stats.no_free==1,"NO_FREE_ACCOUNTED");
    CHECK(video_frame_pool_graph_begin(&p,1,&graph)==0 && same(graph,a[0].id),"OLDEST_READY_SELECTED");
    CHECK(video_frame_pool_drop(&p,&graph,1)==VIDEO_FRAME_STATE,"PROCESSING_NOT_DROPPED");
    CHECK(video_frame_pool_drop(&p,&a[1].id,99)==0,"UNREFERENCED_READY_DROP");
    CHECK(p.stats.dropped==1 && same(p.last_drop,a[1].id) && p.last_drop_reason==99,"DROP_REASON_RECORDED");
    CHECK(video_frame_pool_allocate(&p,&out)==0 && out.id.slot==1 && out.id.frame==4,"ROUND_ROBIN_SAFE_REUSE");
    CHECK(p.slots[0].state==VIDEO_FRAME_PROCESSING && same(p.graph.id,a[0].id),"REUSE_PRESERVES_GRAPH_OWNER");
}
static void graph_case(void) {
    struct video_frame_pool p; struct video_frame_allocation a,b; struct video_frame_token g,out;
    video_frame_pool_init(&p,7);
    CHECK(video_frame_pool_allocate(&p,&a)==0 && video_frame_pool_capture_done(&p,&a.id,1)==0,"GRAPH_A_READY");
    CHECK(video_frame_pool_graph_begin(&p,0,&g)==VIDEO_FRAME_BUSY,"NPU_BUSY_BLOCKS_GRAPH");
    CHECK(video_frame_pool_graph_begin(&p,1,&g)==0 && same(g,a.id),"GRAPH_A_LOCKED");
    CHECK(video_frame_pool_operator_begin(&p,&g,0xffffffffu)==0,"FIRST_OPERATOR");
    CHECK(video_frame_pool_operator_begin(&p,&g,0)==VIDEO_FRAME_BUSY,"ONE_OPERATOR_IN_FLIGHT");
    CHECK(video_frame_pool_allocate(&p,&b)==0 && video_frame_pool_capture_done(&p,&b.id,1)==0,"CAPTURE_OVERLAPS_GRAPH");
    CHECK(video_frame_pool_graph_begin(&p,1,&out)==VIDEO_FRAME_BUSY,"GRAPH_LOCK_WHILE_OP_BUSY");
    CHECK(video_frame_pool_operator_done(&p,&g,0xffffffffu,0,1)==0,"NONFINAL_OPERATOR_DONE");
    CHECK(video_frame_pool_graph_begin(&p,1,&out)==VIDEO_FRAME_BUSY && same(p.graph.id,a.id),"GRAPH_LOCK_ACROSS_IDLE_GAP");
    CHECK(video_frame_pool_operator_begin(&p,&g,0xffffffffu)==VIDEO_FRAME_INVALID,"OP_TAG_REUSE_REJECTED");
    CHECK(video_frame_pool_operator_begin(&p,&g,1)==VIDEO_FRAME_INVALID,"OP_TAG_STEP_REQUIRED");
    CHECK(video_frame_pool_result_ready(&p,&g,1)==VIDEO_FRAME_BUSY,"NO_RESULT_BEFORE_LAST_OP");
    CHECK(video_frame_pool_operator_begin(&p,&g,0)==0 && video_frame_pool_operator_done(&p,&g,0,1,1)==0,"LAST_OPERATOR_DONE");
    CHECK(video_frame_pool_graph_begin(&p,1,&out)==VIDEO_FRAME_BUSY,"GRAPH_LOCK_THROUGH_POSTPROCESS");
    CHECK(video_frame_pool_result_ready(&p,&g,0)==VIDEO_FRAME_BUSY && p.graph.active,"WORKSPACE_STILL_REFERENCED");
    CHECK(video_frame_pool_result_ready(&p,&g,1)==0 && !p.graph.active,"RESULT_RELEASES_GRAPH");
    CHECK(video_frame_pool_graph_begin(&p,1,&out)==0 && same(out,b.id),"NEXT_GRAPH_AFTER_RESULT");
}
static void display_case(void) {
    struct video_frame_pool p; struct bus b; struct video_display_io io;
    struct video_frame_token a,c,d; struct video_display_record r;
    struct video_frame_allocation out; unsigned mode;
    video_frame_pool_init(&p,7); io=setup(&b,&p);
    a=ready_frame(&p); show(&p,&b,&io,a,10);
    CHECK(p.active.valid && same(p.active.id,a) && p.stats.display_commits==1,"FIRST_COMMIT");
    r=record_for(a);
    for (mode=1;mode<=3;++mode) {
        CHECK(video_frame_pool_present(&p,&io,&r,mode%3,10+mode,1)==0,"MODE_PRESENT");
        commit(&b,a,mode%3,10+mode,1);
        CHECK(poll(&p,&b,&io)==0,"MODE_POLL");
        CHECK(p.slots[a.slot].state==VIDEO_FRAME_DISPLAYING && video_frame_pool_free_mask(&p)==6,"MODE_PRESERVES_SLOT");
        CHECK(p.stats.display_commits==1 && p.stats.mode_commits==mode,"MODE_NOT_NEW_FRAME");
    }
    c=ready_frame(&p); r=record_for(c); r.words[0]=2;
    CHECK(video_frame_pool_present(&p,&io,&r,1,14,0)==0,"INVALID_RECORD_ENQUEUED_TO_GUARD");
    rejected(&b,14,0x10);
    CHECK(poll(&p,&b,&io)==VIDEO_FRAME_REJECTED,"REJECTION_REPORTED");
    CHECK(p.slots[c.slot].state==VIDEO_FRAME_READY_DISPLAY && !p.pending.valid && !p.recovering,"REJECT_PRESERVES_RESULT");
    r=record_for(c);
    CHECK(video_frame_pool_present(&p,&io,&r,1,15,0)==0,"RETRY_REJECTED_RESULT");
    commit(&b,c,1,15,0); release(&b,a);
    CHECK(p.slots[a.slot].state==VIDEO_FRAME_DISPLAYING && p.slots[c.slot].state==VIDEO_FRAME_DISPLAY_PENDING,"NO_CHANGE_BEFORE_EVENT_ACK");
    CHECK(poll(&p,&b,&io)==0,"MERGED_COMMIT_RELEASE");
    CHECK(p.slots[a.slot].state==VIDEO_FRAME_FREE && same(p.active.id,c) && p.stats.releases==1,"RELEASE_AFTER_ACK");
    d=ready_frame(&p); show(&p,&b,&io,d,16);
    CHECK(p.slots[c.slot].state==VIDEO_FRAME_RETIRING && !(video_frame_pool_free_mask(&p)&(1u<<c.slot)),"COMMIT_DOES_NOT_FREE_OLD");
    CHECK(video_frame_pool_allocate(&p,&out)==0 && out.id.slot==a.slot && out.id.frame==4,"ONLY_ACKED_SLOT_REUSED");
    CHECK(video_frame_pool_capture_done(&p,&out.id,1)==0,"REUSED_CAPTURE_DONE");
    CHECK(video_frame_pool_allocate(&p,&out)==VIDEO_FRAME_NO_FREE,"RETIRING_COUNTS_AS_OCCUPIED");
    release(&b,c); CHECK(poll(&p,&b,&io)==0,"DELAYED_RETIRE_ACK");
    CHECK(video_frame_pool_allocate(&p,&out)==0 && out.id.slot==c.slot && out.id.frame==5,"DELAYED_ACK_REUSE");
    CHECK(p.stats.display_commits==3 && p.stats.mode_commits==3 && p.stats.rejected==1,"DISPLAY_COUNTS");
}
static void epoch_case(void) {
    struct video_frame_pool p,before; struct video_frame_allocation a,new_a;
    video_frame_pool_init(&p,7);
    CHECK(video_frame_pool_allocate(&p,&a)==0,"EPOCH_FIRST_CAPTURE");
    CHECK(video_frame_pool_fail(&p,&a.id,29)==VIDEO_FRAME_FAULT,"EXTERNAL_FAILURE");
    CHECK(video_frame_pool_slot_state(&p,a.id.slot)==VIDEO_FRAME_INVALIDATED && p.slots[a.id.slot].state==VIDEO_FRAME_CAPTURING,"INVALID_RETAINS_CAPTURE_LEASE");
    CHECK(video_frame_pool_free_mask(&p)==0,"RECOVERY_BLOCKS_ALL_ALLOCATION");
    before=p;
    CHECK(video_frame_pool_recover(&p,8,7)==VIDEO_FRAME_INVALID && !memcmp(&p,&before,sizeof p),"PARTIAL_QUIESCE_REJECTED");
    CHECK(video_frame_pool_recover(&p,7,15)==VIDEO_FRAME_INVALID && !memcmp(&p,&before,sizeof p),"SAME_EPOCH_REJECTED");
    CHECK(video_frame_pool_recover(&p,8,15)==0 && video_frame_pool_free_mask(&p)==7,"COORDINATED_NEW_EPOCH");
    CHECK(video_frame_pool_allocate(&p,&new_a)==0 && new_a.id.frame==1 && new_a.id.generation==8,"NEW_EPOCH_TOKEN");
    CHECK(video_frame_pool_capture_done(&p,&a.id,1)==VIDEO_FRAME_STALE,"OLD_EPOCH_REJECTED");
    CHECK(p.slots[0].state==VIDEO_FRAME_CAPTURING && p.recovering && video_frame_pool_free_mask(&p)==0,"STALE_EVENT_NEVER_ADVANCES_NEW_CAPTURE");
}
static void bad_operator_case(void) {
    struct video_frame_pool p; struct video_frame_allocation a; struct video_frame_token g; unsigned i;
    for (i=0;i<3;++i) {
        video_frame_pool_init(&p,7);
        CHECK(video_frame_pool_allocate(&p,&a)==0 && video_frame_pool_capture_done(&p,&a.id,1)==0,"BAD_OP_CAPTURE");
        CHECK(video_frame_pool_graph_begin(&p,1,&g)==0 && video_frame_pool_operator_begin(&p,&g,31)==0,"BAD_OP_LOCK");
        if (i==0) CHECK(video_frame_pool_operator_done(&p,&g,32,1,1)==VIDEO_FRAME_STALE,"WRONG_OP_TAG_REJECTED");
        if (i==1) { ++g.frame; CHECK(video_frame_pool_operator_done(&p,&g,31,1,1)==VIDEO_FRAME_STALE,"WRONG_OP_FRAME_REJECTED"); }
        if (i==2) CHECK(video_frame_pool_operator_done(&p,&g,31,1,0)==VIDEO_FRAME_FAULT,"FAILED_OPERATOR_RECOVERY");
        CHECK(p.graph.active && p.recovering && video_frame_pool_free_mask(&p)==0,"FAULT_RETAINS_GRAPH_LEASE");
        CHECK(video_frame_pool_graph_begin(&p,1,&g)==VIDEO_FRAME_FAULT,"NPU_IDLE_CANNOT_CLEAR_FAULT");
    }
}
static void submit_failure_case(void) {
    struct video_frame_pool p; struct bus b; struct video_display_io io;
    struct video_frame_token id; struct video_display_record r;
    struct video_frame_allocation a; unsigned calls,i;
    video_frame_pool_init(&p,7); io=setup(&b,&p); id=ready_frame(&p); r=record_for(id);
    CHECK(video_frame_pool_present(&p,&io,&r,0,1,0)==0,"SUBMIT_BASELINE"); calls=b.calls;
    for (i=1;i<=calls;++i) {
        video_frame_pool_init(&p,7); io=setup(&b,&p); id=ready_frame(&p); r=record_for(id); b.fail_at=i;
        CHECK(video_frame_pool_present(&p,&io,&r,0,1,0)==VIDEO_FRAME_IO,"SUBMIT_CALLBACK_FAILURE");
        ++callback_failures;
        CHECK(p.recovering && p.pending.valid && p.slots[id.slot].state==VIDEO_FRAME_DISPLAY_PENDING,"SUBMIT_ERROR_RETAINS_LEASE");
        CHECK(video_frame_pool_allocate(&p,&a)==VIDEO_FRAME_FAULT,"SUBMIT_ERROR_BLOCKS_REUSE");
        CHECK(b.submits==0 && b.calls==i,"NO_PUBLISH_AFTER_CALLBACK_FAILURE");
    }
    video_frame_pool_init(&p,7); io=setup(&b,&p); id=ready_frame(&p); r=record_for(id); b.fail_at=calls; b.ambiguous=1;
    CHECK(video_frame_pool_present(&p,&io,&r,0,1,0)==VIDEO_FRAME_IO && b.submits==1,"AMBIGUOUS_SUBMIT_ERROR");
    CHECK(p.pending.valid && p.recovering,"PUBLISHED_ERROR_NEVER_ROLLED_BACK");
}
static void two_frame_event(struct video_frame_pool *p,struct bus *b,struct video_display_io *io,
                            struct video_frame_token *a,struct video_frame_token *c) {
    struct video_display_record r;
    video_frame_pool_init(p,7); *io=setup(b,p); *a=ready_frame(p); show(p,b,io,*a,1);
    *c=ready_frame(p); r=record_for(*c);
    CHECK(video_frame_pool_present(p,io,&r,1,2,0)==0,"TWO_FRAME_PENDING");
    commit(b,*c,1,2,0); release(b,*a); b->calls=0; b->writes=0;
}
static void event_failure_case(void) {
    struct video_frame_pool p; struct bus b; struct video_display_io io;
    struct video_frame_token a,c; unsigned calls,i;
    two_frame_event(&p,&b,&io,&a,&c); CHECK(poll(&p,&b,&io)==0,"EVENT_BASELINE"); calls=b.calls;
    for (i=1;i<=calls;++i) {
        two_frame_event(&p,&b,&io,&a,&c); b.fail_at=i;
        CHECK(poll(&p,&b,&io)==VIDEO_FRAME_IO,"EVENT_CALLBACK_FAILURE"); ++callback_failures;
        CHECK(p.recovering && p.pending.valid && same(p.active.id,a) &&
            p.slots[a.slot].state==VIDEO_FRAME_DISPLAYING && p.slots[c.slot].state==VIDEO_FRAME_DISPLAY_PENDING,"FAILED_ACK_RETAINS_BOTH_LEASES");
        CHECK(video_frame_pool_free_mask(&p)==0 && b.writes==0 && b.calls==i,"EVENT_FAILURE_NO_FREE");
    }
    two_frame_event(&p,&b,&io,&a,&c); b.fail_at=calls; b.ambiguous=1;
    CHECK(poll(&p,&b,&io)==VIDEO_FRAME_IO && b.reg[0x14/4]==0,"AMBIGUOUS_ACK_FAILURE");
    CHECK(p.pending.valid && same(p.active.id,a) && p.recovering,"LOST_ACK_CONSERVATIVE_REFERENCES");
    b.fail_at=0; CHECK(video_frame_pool_poll_display(&p,&io)==VIDEO_FRAME_FAULT && p.pending.valid,"NO_EVENT_DOES_NOT_INFER_COMPLETION");
}
static void bad_event_case(void) {
    struct video_frame_pool p; struct bus b; struct video_display_io io;
    struct video_frame_token a,c; unsigned i;
    for (i=0;i<11;++i) {
        two_frame_event(&p,&b,&io,&a,&c);
        switch(i) {
            case 0:++b.reg[0x44/4];break; case 1:++b.reg[0x48/4];break;
            case 2:b.reg[0x4c/4]=3;break; case 3:b.reg[0x50/4]=2;break;
            case 4:++b.reg[0x54/4];break; case 5:b.reg[0x58/4]=1;break;
            case 6:++b.reg[0x60/4];break; case 7:b.reg[0x14/4]|=16;break;
            case 8:b.reg[0x14/4]|=4;b.reg[0x68/4]=2;b.reg[0x6c/4]=0x10;break;
            case 9:b.reg[0x14/4]=4;b.reg[0x68/4]=99;b.reg[0x6c/4]=0x10;break;
            case 10:b.reg[0x14/4]=2;b.reg[0x5c/4]=c.frame;b.reg[0x60/4]=c.generation;b.reg[0x64/4]=c.slot;break;
        }
        CHECK(video_frame_pool_poll_display(&p,&io)==VIDEO_FRAME_PROTOCOL,"BAD_DISPLAY_EVENT_REJECTED");
        CHECK(p.recovering && p.pending.valid && same(p.active.id,a) && b.writes==0,"BAD_EVENT_NO_ACK_OR_FREE");
    }
    two_frame_event(&p,&b,&io,&a,&c); b.reg[0xc/4]=0xe2;b.reg[0x14/4]|=8;status(&b);
    CHECK(video_frame_pool_poll_display(&p,&io)==VIDEO_FRAME_FAULT && p.recovering && same(p.active.id,c) &&
        p.slots[a.slot].state==VIDEO_FRAME_FREE && b.reg[0x14/4]==8,"HARDWARE_FAULT_DRAINS_LEGAL_EVENTS");
}
static void invalid_case(void) {
    struct video_frame_pool p; struct bus b; struct video_display_io io; struct video_frame_allocation a;
    struct video_frame_token id; struct video_display_record r;
    video_frame_pool_init(&p,7);io=setup(&b,&p);
    CHECK(video_frame_pool_allocate(0,&a)==VIDEO_FRAME_INVALID && video_frame_pool_allocate(&p,0)==VIDEO_FRAME_INVALID,"NULL_ALLOCATE");
    CHECK(video_frame_pool_graph_begin(&p,2,&id)==VIDEO_FRAME_INVALID,"INVALID_IDLE");
    CHECK(video_frame_pool_allocate(&p,&a)==0,"UNQUALIFIED_ALLOCATE");r=record_for(a.id);
    CHECK(video_frame_pool_present(&p,&io,&r,0,1,0)==VIDEO_FRAME_STATE && !b.calls,"NO_RAW_BYPASS_PROCESSING");
    CHECK(video_frame_pool_capture_done(&p,&a.id,1)==0,"UNQUALIFIED_READY");
    CHECK(video_frame_pool_present(&p,&io,&r,0,1,0)==VIDEO_FRAME_STATE && !b.calls,"NO_READY_BYPASS_PROCESSING");
    CHECK(video_frame_pool_drop(&p,&a.id,0)==VIDEO_FRAME_INVALID,"DROP_REQUIRES_REASON");
    CHECK(video_frame_pool_graph_begin(&p,1,&id)==0 && video_frame_pool_operator_begin(&p,&id,0)==0 &&
        video_frame_pool_operator_done(&p,&id,0,1,1)==0 && video_frame_pool_result_ready(&p,&id,1)==0,"QUALIFIED_RESULT");
    CHECK(video_frame_pool_present(&p,&io,&r,3,1,0)==VIDEO_FRAME_INVALID && !p.pending.valid,"BAD_MODE_NO_LEASE");
    CHECK(video_frame_pool_present(&p,&io,&r,0,1,2)==VIDEO_FRAME_INVALID,"BAD_MODE_ONLY");
    ++r.words[11]; /* Record identity is unchanged; the existing RTL guards result generation. */
    ++r.words[4];
    CHECK(video_frame_pool_present(&p,&io,&r,0,1,0)==VIDEO_FRAME_STALE && !p.recovering,"FOREIGN_RECORD_NO_LEASE");
}
static void boundary_case(void) {
    struct video_frame_pool p; struct video_frame_allocation a,b,before; struct video_frame_token old;
    video_frame_pool_init(&p,0);p.next_frame=0xffffffffu;p.stats.allocated=0xffffffffu;p.stats.captured=0xffffffffu;
    CHECK(video_frame_pool_allocate(&p,&a)==0 && a.id.frame==0xffffffffu && a.id.generation==0,"LAST_FRAME_ID_VALID");
    CHECK(video_frame_pool_capture_done(&p,&a.id,1)==0 && video_frame_pool_drop(&p,&a.id,1)==0,"LAST_FRAME_COMPLETE");
    CHECK(p.stats.allocated==0xffffffffu && p.stats.captured==0xffffffffu,"COUNTERS_SATURATE");
    memset(&b,0xa5,sizeof b);before=b;
    CHECK(video_frame_pool_allocate(&p,&b)==VIDEO_FRAME_EXHAUSTED && !memcmp(&b,&before,sizeof b),"FRAME_ID_NEVER_SILENTLY_WRAPS");
    CHECK(p.recovering && video_frame_pool_free_mask(&p)==0,"EXHAUSTED_REQUIRES_COORDINATED_EPOCH");
    video_frame_pool_init(&p,7);CHECK(video_frame_pool_allocate(&p,&a)==0 && video_frame_pool_capture_done(&p,&a.id,1)==0,"DUPLICATE_SETUP");
    old=a.id;
    CHECK(video_frame_pool_capture_done(&p,&old,1)==VIDEO_FRAME_STATE && p.recovering && p.slots[old.slot].state==VIDEO_FRAME_READY,"DUPLICATE_CAPTURE_NOT_REAPPLIED");
    video_frame_pool_init(&p,8);
    CHECK(video_frame_pool_allocate(&p,&a)==0 && video_frame_pool_capture_done(&p,&a.id,1)==0 &&
        video_frame_pool_graph_begin(&p,1,&old)==0,"OP_COUNTER_LIMIT_SETUP");
    p.graph.issued=0xffffffffu;p.graph.op_tag=99;
    CHECK(video_frame_pool_operator_begin(&p,&old,100)==VIDEO_FRAME_EXHAUSTED && p.recovering && p.graph.active,
        "OP_TAG_SPACE_NEVER_RECYCLED_WITHIN_GRAPH");
}
static void stress_case(void) {
    struct video_frame_pool p; struct bus b; struct video_display_io io; struct video_frame_allocation a;
    struct video_frame_token current={0,0,0},retiring[3],g; struct video_display_record r;
    uint32_t held=0,retire_mask=0,rng=0x9e3779b9u,last=0;unsigned n,k;
    video_frame_pool_init(&p,19);io=setup(&b,&p);
    for (n=0;n<1000;++n) {
        int rc=video_frame_pool_allocate(&p,&a);
        if (rc==VIDEO_FRAME_NO_FREE) {
            CHECK(retire_mask!=0,"STRESS_NO_FREE_HAS_REAL_REFERENCE");
            for (k=0;k<3;++k) if (retire_mask&(1u<<k)) break;
            release(&b,retiring[k]); CHECK(poll(&p,&b,&io)==0,"STRESS_DELAYED_RELEASE");
            held&=~(1u<<k);retire_mask&=~(1u<<k);
            rc=video_frame_pool_allocate(&p,&a);
        }
        CHECK(rc==0 && !(held&(1u<<a.id.slot)) && a.id.frame==last+1,"STRESS_NO_LIVE_SLOT_OVERWRITE");
        held|=1u<<a.id.slot;last=a.id.frame;
        CHECK(video_frame_pool_capture_done(&p,&a.id,1)==0 && video_frame_pool_graph_begin(&p,1,&g)==0 && same(g,a.id),"STRESS_CAPTURE_GRAPH");
        rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;
        for (k=0;k<(rng%5)+1;++k) {
            CHECK(video_frame_pool_operator_begin(&p,&g,(uint32_t)n*8+k)==0,"STRESS_OP_BEGIN");
            CHECK(video_frame_pool_operator_done(&p,&g,(uint32_t)n*8+k,k==rng%5,1)==0,"STRESS_OP_DONE");
            CHECK(p.graph.active && same(p.graph.id,g),"STRESS_OWNER_THROUGH_GAPS");
        }
        CHECK(video_frame_pool_result_ready(&p,&g,1)==0,"STRESS_RESULT_READY");
        r=record_for(g); CHECK(video_frame_pool_present(&p,&io,&r,0,n,0)==0,"STRESS_PRESENT");
        commit(&b,g,0,n,0); CHECK(poll(&p,&b,&io)==0,"STRESS_COMMIT");
        if (n) { retire_mask|=1u<<current.slot;retiring[current.slot]=current; }
        current=g;
        for (k=0;k<3;++k) CHECK((p.slots[k].state!=VIDEO_FRAME_FREE)==!!(held&(1u<<k)),"STRESS_INDEPENDENT_REFERENCE_MASK");
        if ((rng&3)==0 && retire_mask) {
            for (k=0;k<3;++k) if (retire_mask&(1u<<k)) break;
            release(&b,retiring[k]);CHECK(poll(&p,&b,&io)==0,"STRESS_EARLY_RETIRE");
            retire_mask&=~(1u<<k);held&=~(1u<<k);
        }
        ++stress_frames;
    }
    CHECK(p.stats.display_commits==1000 && !p.recovering,"STRESS_ACTUAL_COMMIT_COUNT");
}
int main(int argc,char **argv) {
    void (*cases[])(void)={allocation_case,graph_case,display_case,epoch_case,bad_operator_case,
        submit_failure_case,event_failure_case,bad_event_case,invalid_case,boundary_case,stress_case};
    unsigned i,count=sizeof cases/sizeof cases[0];
    if (argc==2 && !strcmp(argv[1],"--trace")) {
        trace_enabled=1;display_case();puts("END");return 0;
    }
    if (argc==2 && !strncmp(argv[1],"--case=",7)) {
        i=(unsigned)strtoul(argv[1]+7,0,10);CHECK(i<count,"CASE_RANGE");cases[i]();count=1;
    } else for (i=0;i<count;++i) cases[i]();
    printf("FRAME_POOL_NATIVE_PASS cases=%u checks=%u callback_failures=%u stress_frames=%u\n",count,checks,callback_failures,stress_frames);
    return 0;
}
