#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "video_display.h"
struct model { uint32_t memory[1024]; unsigned calls,writes,fail_at,fences,submit,trace; };
static int fail(struct model *m) { return ++m->calls==m->fail_at; }
static int rd(void *c,uint32_t off,uint32_t *v) {
    struct model *m=c;if(fail(m))return -99;assert(off<4096&&!(off&3));*v=m->memory[off/4];return 0;
}
static int wr(void *c,uint32_t off,uint32_t v) {
    struct model *m=c;if(fail(m))return -99;assert(off<4096&&!(off&3));
    if(m->trace)printf("%08x %08x\n",(unsigned)off,(unsigned)v);
    m->memory[off/4]=v;m->writes++;
    if(off==0x20) { assert(m->fences==1);m->submit++; }
    return 0;
}
static int fence(void *c) { struct model *m=c;if(fail(m))return -99;m->fences++;return 0; }
static void reset(struct model *m) {
    memset(m,0,sizeof *m);m->memory[0]=0x10000;m->memory[1]=15;
}
int main(int argc,char **argv) {
    struct model m;struct video_display_record rec;
    struct video_display_events event,before;
    struct video_display_io io={&m,rd,wr,fence};unsigned i,successful_calls;
    reset(&m);memset(&rec,0xff,sizeof rec);
    assert(video_display_init_record(&rec,2,42,5)==0);
    assert(sizeof rec==640&&rec.words[0]==0x10000&&rec.words[1]==640&&rec.words[2]==2&&rec.words[3]==42&&rec.words[4]==5);
    assert(rec.words[5]==0x82400000&&rec.words[6]==2400&&rec.words[7]==800&&rec.words[8]==600);
    assert(rec.words[9]==3&&rec.words[10]==42&&rec.words[11]==5);
    for(i=12;i<160;i++)assert(rec.words[i]==0);
    if(argc==2&&!strcmp(argv[1],"--trace")) {
        m.trace=1;assert(video_display_submit(&io,&rec,1,123,0)==0);return 0;
    }
    assert(video_display_init_record(&rec,3,1,0)==VIDEO_DISPLAY_INVALID);
    assert(video_display_init_record(&rec,0,0,0)==VIDEO_DISPLAY_INVALID);
    assert(video_display_init_record(0,0,1,0)==VIDEO_DISPLAY_INVALID);
    assert(video_display_init_record(&rec,2,42,5)==0);
    assert(video_display_submit(&io,&rec,1,123,0)==0);successful_calls=m.calls;
    assert(m.submit==1&&m.writes==163&&m.memory[0x24/4]==1&&m.memory[0x28/4]==123);
    for(i=0;i<160;i++)assert(m.memory[0x100/4+i]==rec.words[i]);
    for(i=1;i<=successful_calls;i++) {
        reset(&m);m.fail_at=i;
        assert(video_display_submit(&io,&rec,1,123,0)==VIDEO_DISPLAY_IO_ERROR);
        assert(m.submit==0); // No later publication after any callback failure.
    }
    reset(&m);m.memory[0]=2;assert(video_display_submit(&io,&rec,1,1,0)==VIDEO_DISPLAY_VERSION&&m.writes==0);
    reset(&m);m.memory[1]=0;assert(video_display_submit(&io,&rec,1,1,0)==VIDEO_DISPLAY_VERSION&&m.writes==0);
    for(i=0;i<7;i++)if(i!=4) {
        reset(&m);m.memory[2]=1u<<i;assert(video_display_submit(&io,&rec,1,1,0)==VIDEO_DISPLAY_BUSY&&m.writes==0);
    }
    reset(&m);assert(video_display_submit(&io,&rec,3,1,0)==VIDEO_DISPLAY_INVALID&&m.calls==0);
    assert(video_display_submit(&io,&rec,0,1,2)==VIDEO_DISPLAY_INVALID&&m.calls==0);
    assert(video_display_submit(0,&rec,0,1,0)==VIDEO_DISPLAY_INVALID);
    reset(&m);m.memory[0x14/4]=15;m.memory[0xc/4]=0xe3;
    m.memory[0x44/4]=42;m.memory[0x48/4]=5;m.memory[0x4c/4]=2;m.memory[0x50/4]=1;m.memory[0x54/4]=123;m.memory[0x58/4]=1;
    m.memory[0x5c/4]=41;m.memory[0x60/4]=4;m.memory[0x64/4]=1;m.memory[0x68/4]=99;m.memory[0x6c/4]=0x13;
    assert(video_display_read_events(&io,&event)==0&&m.writes==0);
    assert(event.pending==15&&event.error==0xe3&&event.commit_frame==42&&event.commit_generation==5&&event.commit_slot==2);
    assert(event.commit_mode==1&&event.commit_seq==123&&event.commit_mode_only==1);
    assert(event.release_frame==41&&event.release_generation==4&&event.release_slot==1&&event.reject_seq==99&&event.reject_code==0x13);
    successful_calls=m.calls;
    for(i=1;i<=successful_calls;i++) {
        m.calls=0;m.fail_at=i;memset(&event,0xa5,sizeof event);before=event;
        assert(video_display_read_events(&io,&event)==VIDEO_DISPLAY_IO_ERROR&&memcmp(&event,&before,sizeof event)==0);
    }
    reset(&m);m.memory[0x14/4]=3;
    assert(video_display_ack(&io,4)==VIDEO_DISPLAY_INVALID&&m.writes==0);
    assert(video_display_ack(&io,8)==VIDEO_DISPLAY_INVALID&&m.writes==0);
    assert(video_display_ack(&io,3)==0&&m.memory[0x18/4]==3&&m.fences==1);
    puts("DISPLAY_DRIVER_PASS");return 0;
}
