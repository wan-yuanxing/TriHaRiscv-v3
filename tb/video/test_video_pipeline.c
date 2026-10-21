#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "video_capture.h"
/* Live host controller: every callback consumes the actual RTL bus response.
 * Empty detector results are test premises, not an executed NPU graph. */
static unsigned checks,reads,writes,fences,waits;
#define CHECK(c,n) do { ++checks; if(!(c)) { fprintf(stderr,"VIDEO_PIPELINE_C_ASSERT %s\n",n); exit(1); } } while(0)
struct context { char target; struct video_frame_pool *pool; struct video_frame_pool before; int guard_ack; };
static uint32_t rpc(char op,char target,uint32_t a,uint32_t b) {
    char reply[24];unsigned value;
    printf("RPC %c %c %08x %08x\n",op,target,(unsigned)a,(unsigned)b);fflush(stdout);
    CHECK(scanf("%23s %x",reply,&value)==2&&!strcmp(reply,"RPC_REPLY"),"ACTUAL_RTL_REPLY_REQUIRED");
    return (uint32_t)value;
}
static int read32(void *ctx,uint32_t off,uint32_t *value) {
    struct context *c=ctx;*value=rpc('R',c->target,off,0);++reads;return 0;
}
static int write32(void *ctx,uint32_t off,uint32_t value) {
    struct context *c=ctx;
    if(c->target=='D'&&off==0x18&&c->guard_ack)CHECK(!memcmp(c->pool,&c->before,sizeof c->before),"POOL_MUST_NOT_ADVANCE_BEFORE_ACK");
    CHECK(rpc('W',c->target,off,value)==0,"RTL_WRITE_RESPONSE");++writes;
    if(c->target=='D'&&off==0x18&&c->guard_ack)CHECK(!memcmp(c->pool,&c->before,sizeof c->before),"POOL_MUST_WAIT_CALLBACK_RETURN");
    return 0;
}
static int fence(void *ctx) { struct context *c=ctx;CHECK(rpc('F',c->target,0,0)==0,"MMIO_FENCE_MARKER");++fences;return 0; }
static void await(char target,uint32_t mask) { CHECK((rpc('A',target,mask,0)&mask)==mask,"ACTUAL_EVENT_WAIT");++waits; }
static void poll(struct video_frame_pool *p,struct context *c,const struct video_display_io *io) {
    c->before=*p;c->guard_ack=1;CHECK(video_frame_pool_poll_display(p,io)==0,"DISPLAY_EVENT_AND_ACK");c->guard_ack=0;
}
static uint8_t source(unsigned x,unsigned y,unsigned c,unsigned tag) {
    return (uint8_t)(37*x+19*y+83*c+((x*y)>>3)+tag*43+tag*x);
}
static uint32_t image_crc(unsigned tag,unsigned divisor) {
    uint32_t crc=0xffffffffu;unsigned x,y,c,b,v;
    for(y=0;y<600/divisor;++y)for(x=0;x<800/divisor;++x)for(c=0;c<3;++c) {
        v=source(x*divisor,y*divisor,c,tag);
        if(divisor==2)v=(v+source(x*2+1,y*2,c,tag)+source(x*2,y*2+1,c,tag)+source(x*2+1,y*2+1,c,tag)+2)/4;
        crc^=v;for(b=0;b<8;++b)crc=(crc>>1)^((0u-(crc&1u))&0xedb88320u);
    }
    return ~crc;
}
static void empty_result(struct video_frame_pool *p,const struct video_frame_token *id) {
    struct video_frame_token g;
    CHECK(video_frame_pool_graph_begin(p,1,&g)==0&&g.frame==id->frame,"MOCK_GRAPH_START");
    CHECK(video_frame_pool_operator_begin(p,&g,9)==0,"MOCK_OPERATOR_START");
    CHECK(video_frame_pool_operator_done(p,&g,9,1,1)==0,"MOCK_OPERATOR_DONE");
    CHECK(video_frame_pool_result_ready(p,&g,1)==0,"MOCK_EMPTY_RESULT_READY");
}
int main(int argc,char **argv) {
    struct video_frame_pool p;struct video_frame_allocation a,extra;
    struct video_capture_events e;struct video_display_record record;
    struct context c,d;struct video_capture_io ci;struct video_display_io di;
    unsigned i,failure=argc==2&&!strcmp(argv[1],"--failure");
    memset(&c,0,sizeof c);memset(&d,0,sizeof d);video_frame_pool_init(&p,47);
    c.target='C';c.pool=&p;d.target='D';d.pool=&p;
    ci.context=&c;ci.read32=read32;ci.write32=write32;ci.fence=fence;
    di.context=&d;di.read32=read32;di.write32=write32;di.fence=fence;
    CHECK(video_capture_enable(&ci)==0,"CAPTURE_ENABLE");
    for(i=0;i<(failure?1u:4u);++i) {
        CHECK(video_frame_pool_allocate(&p,&a)==0&&a.id.slot==i%3,"THREE_SLOT_ALLOCATE");
        CHECK(video_display_init_record(&record,a.id.slot,a.id.frame,a.id.generation)==0,"DISPLAY_RECORD");
        {
            unsigned old_reads=reads,old_writes=writes,old_fences=fences;
            int rc=video_frame_pool_present(&p,&di,&record,0,100+i*4,0);
            /* The second display submission is deliberately still pending
             * at frame three: the existing API reports BUSY before STATE. */
            CHECK(rc==(i==2?VIDEO_FRAME_BUSY:VIDEO_FRAME_STATE),"NO_PRESENT_BEFORE_CAPTURE");
            CHECK(reads==old_reads&&writes==old_writes&&fences==old_fences,"NO_IO_BEFORE_CAPTURE");
        }
        CHECK(video_capture_submit(&ci,&a)==0,"CAPTURE_SUBMIT");await('C',2);
        CHECK(video_capture_read_events(&ci,&e)==0,"ACTUAL_CAPTURE_RECORD");
        CHECK(e.completed.identity.id.frame==a.id.frame&&e.completed.identity.id.generation==a.id.generation,"CAPTURE_IDENTITY");
        if(failure) {
            CHECK(video_capture_validate_completion(&e,&a)==VIDEO_CAPTURE_FAILED,"REAL_FAILED_COMPLETION");
            CHECK(e.completed.drained==1,"FAILURE_MUST_DRAIN");
            CHECK(video_frame_pool_capture_done(&p,&a.id,0)==VIDEO_FRAME_FAULT,"FAILED_FRAME_RETAINS_REFERENCE");
            CHECK(video_frame_pool_free_mask(&p)==0,"NO_FREE_AFTER_FAULT");
            CHECK(video_capture_rearm(&ci)==VIDEO_CAPTURE_BUSY,"NO_REARM_AFTER_FAULT");
            CHECK(video_frame_pool_allocate(&p,&extra)==VIDEO_FRAME_FAULT,"NO_ALLOCATION_AFTER_FAULT");
            CHECK(rpc('E','X',1,0)==0,"FINAL_RTL_FAILURE_AUDIT");
            printf("VIDEO_PIPELINE_C_PASS failure=1 frames=0 modes=0 releases=0 checks=%u R=%u W=%u F=%u A=%u\n",checks,reads,writes,fences,waits);return 0;
        }
        CHECK(video_capture_validate_completion(&e,&a)==0,"QUALIFIED_THREE_BRANCH_COMPLETION");
        CHECK(e.completed.raw_crc==image_crc(a.id.frame,1)&&e.completed.preview_crc==image_crc(a.id.frame,2),"INDEPENDENT_RAW_PREVIEW_CRC");
        CHECK(rpc('V','X',a.id.frame,0)==0,"ACTUAL_NATIVE_BYTES_AND_B_RETIREMENT");
        CHECK(video_frame_pool_capture_done(&p,&a.id,1)==0,"QUALIFIED_CAPTURE_DONE");
        CHECK(video_capture_ack(&ci,e.pending&3u)==0,"CAPTURE_EVENT_ACK");
        CHECK(rpc('S','C',0x100,0x100)&0x100,"CORE_AND_SOFTWARE_REARM_READY");
        CHECK(video_capture_rearm(&ci)==0,"EXPLICIT_REARM");empty_result(&p,&a.id);
        if(i==2) {
            CHECK(video_frame_pool_free_mask(&p)==0,"NO_FREE_WHILE_RELEASE_UNACKED");
            CHECK(video_frame_pool_allocate(&p,&extra)==VIDEO_FRAME_NO_FREE,"THIRD_SLOT_PRESSURE");
            await('D',3);poll(&p,&d,&di);
            CHECK(video_frame_pool_free_mask(&p)==1,"OLD_SLOT_FREE_ONLY_AFTER_REAL_ACK");
        }
        CHECK(video_frame_pool_present(&p,&di,&record,0,100+i*4,0)==0,"PRESENT_QUALIFIED_FRAME");
        await('D',i?3:1);
        if(i==1)continue; // Capture the third slot while these real events stay held.
        poll(&p,&d,&di);
        if(i==0) {
            unsigned free_before=video_frame_pool_free_mask(&p);
            CHECK(video_frame_pool_present(&p,&di,&record,0,101,1)==0,"SAME_RAW_MODE");
            await('D',1);poll(&p,&d,&di);
            CHECK(video_frame_pool_free_mask(&p)==free_before,"MODE_DOES_NOT_RELEASE");
        }
    }
    CHECK(p.stats.allocated==4&&p.stats.captured==4&&p.stats.display_commits==4&&p.stats.mode_commits==1&&p.stats.releases==3&&!p.error,"FINAL_SOFTWARE_COUNTS");
    CHECK(rpc('E','X',0,0)==0,"FINAL_RTL_SUCCESS_AUDIT");
    printf("VIDEO_PIPELINE_C_PASS failure=0 frames=4 modes=1 releases=3 checks=%u R=%u W=%u F=%u A=%u\n",checks,reads,writes,fences,waits);return 0;
}
