#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "video_frame_pool.h"
/* Host-only reference register model for expected C I/O. RTL replay waits for
 * real scanout events; it never injects this model's commit/retire information. */
static unsigned checks, tracing;
#define CHECK(c,n) do { ++checks; if(!(c)) { fprintf(stderr,"DISPLAY_SCANOUT_C_ASSERT %s\n",n); exit(1); } } while(0)
struct bus { uint32_t r[1024]; struct video_frame_pool *pool; struct video_frame_pool before; unsigned guard_ack; };
static void status(struct bus *b) {
    uint32_t e=b->r[0x14/4];
    b->r[8/4]=(b->r[0x30/4]?128u:0u)|((e&1u)?12u:0u)|((e&2u)?16u:0u);
}
static int read32(void *ctx,uint32_t off,uint32_t *v) {
    struct bus *b=ctx; CHECK(off<4096 && !(off&3),"READ_ADDRESS"); *v=b->r[off/4];
    if(tracing)printf("R %08x %08x\n",(unsigned)off,(unsigned)*v);
    return 0;
}
static int write32(void *ctx,uint32_t off,uint32_t v) {
    struct bus *b=ctx; CHECK(off<4096 && !(off&3),"WRITE_ADDRESS");
    if(off==0x18) {
        if(b->guard_ack)CHECK(!memcmp(b->pool,&b->before,sizeof b->before),"POOL_CHANGED_BEFORE_ACK");
        b->r[0x14/4]&=~v;status(b);
    } else b->r[off/4]=v;
    if(tracing)printf("W %08x %08x\n",(unsigned)off,(unsigned)v);
    return 0;
}
static int fence(void *ctx) { (void)ctx;if(tracing)puts("F");return 0; }
static struct video_frame_token ready(struct video_frame_pool *p) {
    struct video_frame_allocation a;struct video_frame_token graph;
    CHECK(video_frame_pool_allocate(p,&a)==0,"ALLOCATE");
    CHECK(video_frame_pool_capture_done(p,&a.id,1)==0,"MOCK_CAPTURE");
    CHECK(video_frame_pool_graph_begin(p,1,&graph)==0,"MOCK_GRAPH");
    CHECK(video_frame_pool_operator_begin(p,&graph,9)==0,"MOCK_OPERATOR_START");
    CHECK(video_frame_pool_operator_done(p,&graph,9,1,1)==0,"MOCK_OPERATOR_DONE");
    CHECK(video_frame_pool_result_ready(p,&graph,1)==0,"MOCK_RESULT");return a.id;
}
static void model_event(struct bus *b,const struct video_frame_pool *p,unsigned only) {
    const struct video_frame_submission *s=&p->pending;
    b->r[0x44/4]=s->id.frame;b->r[0x48/4]=s->id.generation;b->r[0x4c/4]=s->id.slot;
    b->r[0x50/4]=s->mode;b->r[0x54/4]=s->seq;b->r[0x58/4]=only;
    b->r[0x30/4]=s->id.frame;b->r[0x34/4]=s->id.generation;b->r[0x38/4]=s->id.slot;
    b->r[0x3c/4]=s->mode;b->r[0x40/4]=s->seq;b->r[0x14/4]=1;
    if(p->active.valid&&!only) {
        b->r[0x5c/4]=p->active.id.frame;b->r[0x60/4]=p->active.id.generation;b->r[0x64/4]=p->active.id.slot;
        b->r[0x14/4]|=2;
    }
    status(b);if(tracing)printf("A %u\n",(unsigned)b->r[0x14/4]);
}
static void poll(struct video_frame_pool *p,struct bus *b,const struct video_display_io *io) {
    b->before=*p;b->guard_ack=1;
    CHECK(video_frame_pool_poll_display(p,io)==0,"POLL_REAL_EVENT_REPLAY");b->guard_ack=0;
}
int main(int argc,char **argv) {
    struct video_frame_pool p;struct bus b;struct video_display_io io;
    struct video_frame_token id;struct video_display_record rec;unsigned i;
    tracing=argc==2&&!strcmp(argv[1],"--trace");memset(&b,0,sizeof b);
    video_frame_pool_init(&p,37);b.pool=&p;b.r[0]=0x10000;b.r[1]=15;b.r[0x2c/4]=640;b.r[0x80/4]=1;
    io.context=&b;io.read32=read32;io.write32=write32;io.fence=fence;
    for(i=0;i<6;++i) {
        id=ready(&p);CHECK(id.slot==i%3,"THREE_SLOT_ROTATION");
        CHECK(video_display_init_record(&rec,id.slot,id.frame,id.generation)==0,"RECORD_INIT");
        CHECK(video_frame_pool_present(&p,&io,&rec,0,100+i*3,0)==0,"PRESENT");
        CHECK(video_frame_pool_slot_state(&p,id.slot)==VIDEO_FRAME_DISPLAY_PENDING,"ENQUEUE_IS_NOT_COMMIT");
        model_event(&b,&p,0);poll(&p,&b,&io);
        CHECK(video_frame_pool_slot_state(&p,id.slot)==VIDEO_FRAME_DISPLAYING,"REAL_COMMIT");
        if(i<2) {
            unsigned before=video_frame_pool_free_mask(&p);
            CHECK(video_frame_pool_present(&p,&io,&rec,0,101+i*3,1)==0,"MODE_PRESENT");
            model_event(&b,&p,1);poll(&p,&b,&io);
            CHECK(video_frame_pool_free_mask(&p)==before,"MODE_NO_RELEASE");
        }
    }
    CHECK(p.stats.display_commits==6&&p.stats.mode_commits==2&&p.stats.releases==5&&!p.error,"COUNTS");
    if(tracing)puts("END");else printf("DISPLAY_SCANOUT_C_PASS frames=6 modes=2 releases=5 checks=%u\n",checks);
    return 0;
}
