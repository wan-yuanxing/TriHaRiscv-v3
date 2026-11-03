#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "face_avatar.h"
#include "video_cfg.h"
#define CHECK(x) do { ++checks; if (!(x)) { fprintf(stderr,"FACE_AVATAR_FAIL line=%d: %s\n",__LINE__,#x); exit(1); } } while (0)
static unsigned checks;
struct fixture {
    struct face_avatar app;
    uint32_t cap[256],disp[1024],npu[256],image[32+17*8],image_base;
    unsigned cap_starts,npu_starts,npu_acks,presents,io_count,shared_words;
    int fail_device; uint32_t fail_offset; unsigned fail_write,fail_at;
};
struct endpoint { struct fixture *f; unsigned device; };
static struct fixture f;
static struct endpoint cap_ep,disp_ep,npu_ep;
static int read32(void *context,uint32_t off,uint32_t *value) {
    struct endpoint *e=context; struct fixture *p=e->f;
    ++p->io_count;
    if(p->fail_at==p->io_count)return -1;
    if(p->fail_device==(int)e->device && !p->fail_write && off==p->fail_offset)return -1;
    *value=(e->device==1?p->cap:e->device==2?p->disp:p->npu)[off/4];return 0;
}
static int write32(void *context,uint32_t off,uint32_t value) {
    struct endpoint *e=context;struct fixture *p=e->f;uint32_t *r=e->device==1?p->cap:e->device==2?p->disp:p->npu;
    ++p->io_count;
    if(p->fail_at==p->io_count)return -1;
    if(p->fail_device==(int)e->device && p->fail_write && off==p->fail_offset)return -1;
    if(e->device==1 && off==VCAP_REG_IRQ_PENDING) {
        r[off/4]&=~value;
        if(value&2)r[VCAP_REG_STATUS/4]=0x383;
    } else if(e->device==2 && off==VDISP_REG_ACK)r[VDISP_REG_EVENTS/4]&=~value;
    else r[off/4]=value;
    if(e->device==1 && off==VCAP_REG_CONTROL)r[VCAP_REG_STATUS/4]=0x201;
    if(e->device==1 && off==VCAP_REG_REARM)r[VCAP_REG_STATUS/4]=0x201;
    if(e->device==1 && off==VCAP_REG_CAPTURE_REQUEST){++p->cap_starts;r[VCAP_REG_STATUS/4]=0x20b;}
    if(e->device==2 && off==VDISP_REG_SUBMIT)++p->presents;
    if(e->device==3 && off==NF_REG_CONTROL){++p->npu_starts;r[NF_REG_STATUS/4]=NF_STATUS_BUSY;}
    if(e->device==3 && off==NF_REG_ACK){++p->npu_acks;r[NF_REG_STATUS/4]=NF_STATUS_IDLE;}
    return 0;
}
static int fence(void *context){struct fixture *p=((struct endpoint *)context)->f;++p->io_count;return p->fail_at==p->io_count?-1:0;}
static int shared(void *context,uint32_t address,uint32_t *out,uint32_t words) {
    struct fixture *p=((struct endpoint *)context)->f;
    ++p->io_count;if(p->fail_at==p->io_count)return -1;
    CHECK(address>=p->image_base && address+words*4<=p->image_base+sizeof p->image);
    if(p->fail_device==4)return -1;
    memcpy(out,(unsigned char *)p->image+address-p->image_base,words*4);p->shared_words+=words;return 0;
}
static uint32_t crc(const uint32_t *data,unsigned words) {
    uint32_t c=~0u;unsigned i,j,k;
    for(i=0;i<words;++i)for(j=0;j<4;++j){c^=(data[i]>>(j*8))&255u;for(k=0;k<8;++k)c=(c>>1)^((0u-(c&1u))&0xedb88320u);}
    return ~c;
}
static void setup(void) {
    struct face_avatar_io io;
    memset(&f,0,sizeof f);cap_ep.f=disp_ep.f=npu_ep.f=&f;cap_ep.device=1;disp_ep.device=2;npu_ep.device=3;
    io.capture=(struct video_capture_io){&cap_ep,read32,write32,fence};
    io.display=(struct video_display_io){&disp_ep,read32,write32,fence};
    io.npu=(struct npu_frame_io){&npu_ep,read32,write32,shared,fence};
    f.cap[VCAP_REG_VERSION/4]=VCAP_ABI_VERSION;f.cap[VCAP_REG_CAPABILITIES/4]=VCAP_CAPABILITIES;
    f.disp[VDISP_REG_VERSION/4]=VDISP_VERSION;f.disp[VDISP_REG_CAPABILITIES/4]=VDISP_CAPABILITIES;
    f.npu[NF_REG_ID_VERSION/4]=NF_ID_VERSION;f.npu[NF_REG_STATUS/4]=NF_STATUS_IDLE;f.npu[NF_REG_SESSION_EPOCH/4]=7;
    CHECK(face_avatar_init(&f.app,&io,7)==FACE_AVATAR_OK);
}
static void step(void){CHECK(face_avatar_step(&f.app)==FACE_AVATAR_OK);}
static void capture_done(void) {
    const struct video_frame_allocation *a=&f.app.capture;
    uint32_t *r=f.cap;CHECK(f.app.capture_submitted);
    r[VCAP_REG_IRQ_PENDING/4]=3;r[VCAP_REG_STATUS/4]=0x2b3;
    r[VCAP_REG_ACCEPTED_SLOT/4]=r[VCAP_REG_COMPLETED_SLOT/4]=a->id.slot;
    r[VCAP_REG_ACCEPTED_FRAME_ID_RECORD/4]=r[VCAP_REG_COMPLETED_FRAME_ID_RECORD/4]=a->id.frame;
    r[VCAP_REG_ACCEPTED_VERSION/4]=r[VCAP_REG_COMPLETED_VERSION/4]=a->preprocess_version;
    r[VCAP_REG_ACCEPTED_GENERATION/4]=r[VCAP_REG_COMPLETED_GENERATION/4]=a->id.generation;
    r[VCAP_REG_ACCEPTED_RAW_BASE/4]=r[VCAP_REG_COMPLETED_RAW_BASE/4]=a->raw_base;
    r[VCAP_REG_ACCEPTED_PREVIEW_BASE/4]=r[VCAP_REG_COMPLETED_PREVIEW_BASE/4]=a->preview_base;
    r[VCAP_REG_ACCEPTED_INPUT_BASE/4]=r[VCAP_REG_COMPLETED_INPUT_BASE/4]=a->input_base;
    r[VCAP_REG_COMPLETED_RESULT/4]=1;r[VCAP_REG_COMPLETED_DRAINED/4]=1;
    r[VCAP_REG_COMPLETED_RAW_PIXELS/4]=800*600;r[VCAP_REG_COMPLETED_PREVIEW_PIXELS/4]=400*300;
    r[VCAP_REG_COMPLETED_INPUT_PIXELS/4]=320*240;r[VCAP_REG_COMPLETED_RAW_BYTES/4]=800*600*3;
    r[VCAP_REG_COMPLETED_PREVIEW_BYTES/4]=400*300*3;r[VCAP_REG_COMPLETED_INPUT_BYTES/4]=VIDEO_INPUT_BYTES;
    r[VCAP_REG_COMPLETED_FIFO_PEAK/4]=100;
}
static void npu_done(unsigned faces) {
    const struct npu_frame_ticket *t=&f.app.ticket;uint32_t *d=f.npu+NF_COMPLETION_BASE/4,*h=f.image;unsigned i;
    CHECK(faces<=17 && f.app.npu_submitted);memset(d,0,80);memset(h,0,sizeof f.image);
    f.image_base=(t->slot==0?B03_OUTPUT_BASES_0:t->slot==1?B03_OUTPUT_BASES_1:B03_OUTPUT_BASES_2)+B03_RESULT_OFFSET;
    f.npu[NF_REG_STATUS/4]=NF_STATUS_HELD;
    d[NF_DONE_CMD_ID]=t->cmd;d[NF_DONE_FRAME_ID_LO]=t->frame;d[NF_DONE_EPOCH]=t->epoch;
    d[NF_DONE_FACES]=faces;d[NF_DONE_RESULT_OFFSET]=f.image_base-0x82000000;d[NF_DONE_RESULT_BYTES]=128+32*faces;
    d[NF_DONE_LIVE]=d[NF_DONE_PUBLISHED]=1;
    h[0]=0x3352504e;h[1]=1;h[2]=128;h[3]=1;h[6]=t->cmd;h[7]=t->epoch;h[8]=t->frame;
    h[10]=faces;h[11]=32*faces;h[13]=d[NF_DONE_RESULT_OFFSET]+128;h[14]=B03_MODEL_TAG;
    h[22]=800;h[23]=600;h[24]=320;h[25]=240;h[27]=40;h[28]=1;
    for(i=0;i<faces;++i){uint32_t *b=h+32+i*8;b[0]=10+i;b[1]=20;b[2]=30;b[3]=40;b[4]=0x3f000000-i;b[5]=i;b[6]=8;}
    d[NF_DONE_CRC]=h[12]=crc(h+32,faces*8);h[31]=crc(h,31);
#ifdef FACE_AVATAR_BROKEN
    h[31]^=1;
#endif
}
static void commit(void) {
    const struct video_frame_submission *p=&f.app.pool.pending;uint32_t *r=f.disp;CHECK(p->valid);
    r[VDISP_REG_EVENTS/4]|=1;r[VDISP_REG_COMMIT_FRAME/4]=p->id.frame;r[VDISP_REG_COMMIT_GENERATION/4]=p->id.generation;
    r[VDISP_REG_COMMIT_SLOT/4]=p->id.slot;r[VDISP_REG_COMMIT_MODE/4]=p->mode;r[VDISP_REG_COMMIT_SEQ/4]=p->seq;
    r[VDISP_REG_COMMIT_MODE_ONLY/4]=p->mode_only;
}
static void release(unsigned slot) {
    const struct video_frame_token *id=&f.app.pool.slots[slot].id;uint32_t *r=f.disp;
    r[VDISP_REG_EVENTS/4]|=2;r[VDISP_REG_RELEASE_SLOT/4]=slot;r[VDISP_REG_RELEASE_FRAME/4]=id->frame;
    r[VDISP_REG_RELEASE_GENERATION/4]=id->generation;
}
static void pipeline(void) {
    unsigned i,j;uint32_t *r;
    setup();step();CHECK(f.cap_starts==1 && f.app.capture.id.slot==0);
    for(i=0;i<40;++i)step();CHECK(f.cap_starts==1 && f.app.pool.stats.allocated==1);
    capture_done();step();CHECK(f.npu_starts==1 && f.cap_starts==2 && f.app.ticket.slot==0);
    for(i=0;i<40;++i)step();CHECK(f.npu_starts==1 && f.cap_starts==2);
    capture_done();step();capture_done();step();CHECK(f.cap_starts==3 && video_frame_pool_free_mask(&f.app.pool)==0);
    for(i=0;i<40;++i)step();CHECK(f.cap_starts==3 && f.npu_starts==1);
    npu_done(17);step();CHECK(f.shared_words==32+17*8 && f.npu_acks==1 && f.presents==1);
    CHECK(f.app.pool.pending.id.slot==0 && f.app.pool.slots[0].state==VIDEO_FRAME_DISPLAY_PENDING);
    r=f.disp+VDISP_SHADOW_OFFSET/4;
    CHECK(r[VDISP_FIELD_BOX_MASK]==65535 && r[VDISP_FIELD_PRIMARY_INDEX]==0);
    CHECK(r[VDISP_FIELD_FLAGS]==(VDISP_FLAG_RESULT_VALID|VDISP_FLAG_PRIMARY_VALID));
    CHECK(r[VDISP_FIELD_FRAME]==1 && r[VDISP_FIELD_RESULT_FRAME]==1 && r[VDISP_FIELD_GENERATION]==7 && r[VDISP_FIELD_RESULT_GENERATION]==7);
    for(i=0;i<16;++i){CHECK(r[32+i*8]==((20u<<16)|(10+i)));CHECK(r[33+i*8]==((60u<<16)|(40+i)));for(j=2;j<8;++j)CHECK(r[32+i*8+j]==0);}
    step();CHECK(f.npu_starts==2);npu_done(0);step();CHECK(f.npu_acks==2 && f.presents==1);
    CHECK(f.app.pool.slots[1].state==VIDEO_FRAME_READY_DISPLAY && f.app.records[1].words[VDISP_FIELD_BOX_MASK]==0);
    CHECK(f.app.records[1].words[VDISP_FIELD_FLAGS]==(VDISP_FLAG_RESULT_VALID|VDISP_FLAG_RESULT_EMPTY));
    for(i=0;i<20;++i)step();CHECK(f.cap_starts==3 && f.app.pool.stats.releases==0);
    commit();step();CHECK(f.app.pool.active.id.slot==0 && f.app.pool.pending.id.slot==1);
    commit();step();CHECK(f.app.pool.slots[0].state==VIDEO_FRAME_RETIRING && f.app.pool.active.id.slot==1);
    for(i=0;i<20;++i)step();CHECK(f.cap_starts==3);
    release(0);step();CHECK(f.cap_starts==4 && f.app.capture.id.slot==0 && f.app.capture.id.frame==4);
}
static void failures(void) {
    unsigned before;
    setup();step();f.cap[VCAP_REG_STATUS/4]=0x20b;capture_done();f.cap[VCAP_REG_COMPLETED_GENERATION/4]=6;
    CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && f.app.pool.slots[0].state==VIDEO_FRAME_CAPTURING && !f.npu_starts);
    before=f.io_count;CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && f.io_count==before);
    setup();step();capture_done();f.cap[VCAP_REG_COMPLETED_DRAINED/4]=0;
    CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && f.app.capture_valid && !f.npu_starts);
    setup();step();capture_done();step();npu_done(1);f.npu[(NF_COMPLETION_BASE/4)+NF_DONE_FRAME_ID_LO]++;
    CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && !f.npu_acks && !f.presents && f.app.pool.graph.active);
    setup();step();capture_done();step();npu_done(17);f.image[32+16*8]^=1;
    CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && !f.npu_acks && !f.presents && f.app.pool.graph.active);
    setup();f.fail_device=1;f.fail_write=1;f.fail_offset=VCAP_REG_CAPTURE_REQUEST;
    CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && f.app.capture_valid && f.app.pool.slots[0].state==VIDEO_FRAME_CAPTURING);
    setup();step();capture_done();step();npu_done(1);f.fail_device=3;f.fail_write=1;f.fail_offset=NF_REG_ACK;
    CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && f.app.pool.graph.active && !f.presents);
    setup();step();capture_done();step();npu_done(1);f.fail_device=2;f.fail_write=1;f.fail_offset=VDISP_REG_SUBMIT;
    CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && f.app.pool.pending.valid && f.app.pool.slots[0].state==VIDEO_FRAME_DISPLAY_PENDING);
    setup();step();capture_done();step();npu_done(1);step();commit();f.fail_device=2;f.fail_write=1;f.fail_offset=VDISP_REG_ACK;
    CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && f.app.pool.pending.valid && !f.app.pool.active.valid);
    setup();step();capture_done();step();npu_done(1);f.npu[NF_COMPLETION_BASE/4+NF_DONE_PUBLISHED]=0;
    step();CHECK(!f.npu_acks && !f.presents && f.app.pool.graph.active);
    setup();f.cap[VCAP_REG_STATUS/4]=VCAP_STATUS_STICKY_FAULT_MASK;f.cap[VCAP_REG_ERROR_CODE/4]=1;
    CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && !f.cap_starts);
}
static void busy_and_pool(void) {
    struct video_frame_allocation a;struct video_frame_token id;
    setup();f.app.capture_enabled=1;f.cap[VCAP_REG_STATUS/4]=0x20b;step();
    CHECK(f.app.capture_valid && !f.app.capture_submitted && f.app.pool.stats.allocated==1);
    step();CHECK(f.app.pool.stats.allocated==1 && !f.cap_starts);f.cap[VCAP_REG_STATUS/4]=0x201;step();CHECK(f.cap_starts==1);
    setup();CHECK(video_frame_pool_allocate(&f.app.pool,&a)==VIDEO_FRAME_OK);
    CHECK(video_frame_pool_capture_done(&f.app.pool,&a.id,1)==VIDEO_FRAME_OK);
    CHECK(video_frame_pool_graph_begin(&f.app.pool,1,&id)==VIDEO_FRAME_OK);
    CHECK(video_frame_pool_frame_done(&f.app.pool,&id,0,1)==VIDEO_FRAME_BUSY && f.app.pool.graph.active);
    CHECK(video_frame_pool_frame_done(&f.app.pool,&id,1,0)==VIDEO_FRAME_BUSY && f.app.pool.graph.active);
    CHECK(video_frame_pool_frame_done(&f.app.pool,&id,1,1)==VIDEO_FRAME_OK && !f.app.pool.graph.active);
    CHECK(f.app.pool.slots[id.slot].state==VIDEO_FRAME_READY_DISPLAY);
}
static void prepare_phase(unsigned phase) {
    setup();
    if(phase>=1){step();capture_done();}
    if(phase>=2){step();npu_done(1);}
    if(phase>=3){step();commit();}
}
static void callback_failures(void) {
    unsigned phase,count,n,before,slot,frames[3],allocated[3];
    for(phase=0;phase<4;++phase) {
        prepare_phase(phase);before=f.io_count;step();count=f.io_count-before;
        CHECK(count>0);
        for(n=1;n<=count;++n) {
            prepare_phase(phase);
            for(slot=0;slot<3;++slot){frames[slot]=f.app.pool.slots[slot].id.frame;allocated[slot]=f.app.pool.slots[slot].state!=VIDEO_FRAME_FREE;}
            f.fail_at=f.io_count+n;
            CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && f.app.pool.recovering);
            for(slot=0;slot<3;++slot)if(allocated[slot]) {
                CHECK(f.app.pool.slots[slot].state!=VIDEO_FRAME_FREE);
                CHECK(f.app.pool.slots[slot].id.frame==frames[slot]);
            }
            before=f.io_count;CHECK(face_avatar_step(&f.app)==FACE_AVATAR_FAULT && f.io_count==before);
        }
    }
}
static void primary_selection(void) {
    struct video_display_record r;
    struct video_frame_token id={0,1,7};
    struct npu_frame_result result={0};
    unsigned p,other;
    result.valid=1;result.face_count=result.display_count=3;
    result.boxes[0]=(struct npu_frame_box){10,20,10,10,0x3f700000,10,8};
    result.boxes[1]=(struct npu_frame_box){20,30,40,30,0x3f600000,20,8};
    result.boxes[2]=(struct npu_frame_box){30,40,20,20,0x3f500000,30,8};
    CHECK(face_avatar_build_record(&r,&id,&result)==FACE_AVATAR_OK);
    CHECK(r.words[VDISP_FIELD_PRIMARY_INDEX]==1); /* area beats score */
    CHECK(r.words[VDISP_HEADER_WORDS]==(10u|(20u<<16))); /* keep BOX order */
    result.boxes[2].width=40;result.boxes[2].height=30;
    CHECK(face_avatar_build_record(&r,&id,&result)==FACE_AVATAR_OK);
    CHECK(r.words[VDISP_FIELD_PRIMARY_INDEX]==1); /* score breaks area tie */
    result.boxes[2].score_bits=result.boxes[1].score_bits;
    result.boxes[2].candidate=5;
    CHECK(face_avatar_build_record(&r,&id,&result)==FACE_AVATAR_OK);
    CHECK(r.words[VDISP_FIELD_PRIMARY_INDEX]==2); /* stable candidate key */
    result.boxes[1].candidate=5;
    CHECK(face_avatar_build_record(&r,&id,&result)==FACE_AVATAR_OK);
    CHECK(r.words[VDISP_FIELD_PRIMARY_INDEX]==1); /* exact tie keeps first */
    result.face_count=result.display_count=16;
    for(p=0;p<16;++p) {
        for(other=0;other<16;++other)result.boxes[other]=(struct npu_frame_box){0,0,1,1,0x3f000000,other,8};
        result.boxes[p].width=800;result.boxes[p].height=600;
        CHECK(face_avatar_build_record(&r,&id,&result)==FACE_AVATAR_OK);
        CHECK(r.words[VDISP_FIELD_PRIMARY_INDEX]==p);
    }
    result.face_count=result.display_count=0;
    CHECK(face_avatar_build_record(&r,&id,&result)==FACE_AVATAR_OK);
    CHECK(r.words[VDISP_FIELD_FLAGS]==(VDISP_FLAG_RESULT_VALID|VDISP_FLAG_RESULT_EMPTY));
    CHECK(r.words[VDISP_FIELD_PRIMARY_INDEX]==0);
}
static void avatar_records_and_modes(void) {
    struct video_display_record r;
    struct video_frame_token id={0,1,7};
    struct npu_frame_result result={0};
    struct face_avatar_asset asset={1,7,SOC_AVATAR_BASE,128,128,384},bad;
    unsigned i;
    result.valid=1;result.face_count=result.display_count=1;
    result.boxes[0]=(struct npu_frame_box){0,0,40,20,0x3f000000,0,8};
    CHECK(face_avatar_build_avatar_record(&r,&id,&result,&asset)==FACE_AVATAR_OK);
    CHECK(r.words[VDISP_FIELD_AVATAR_XY0]==(0xfff6u|(0xffecu<<16))); /* (-10,-20), side60 */
    CHECK(r.words[VDISP_FIELD_AVATAR_XY1]==(50u|(40u<<16)));
    CHECK(r.words[VDISP_FIELD_FLAGS]==(VDISP_FLAG_RESULT_VALID|VDISP_FLAG_PRIMARY_VALID|VDISP_FLAG_AVATAR_ENABLE));
    CHECK(r.words[VDISP_FIELD_ASSET_ID]==1 && r.words[VDISP_FIELD_ASSET_GENERATION]==7);
    CHECK(r.words[VDISP_FIELD_ASSET_BASE]==SOC_AVATAR_BASE && r.words[VDISP_FIELD_ASSET_BYTES]==262144);
    CHECK(r.words[VDISP_FIELD_ASSET_WIDTH]==256 && r.words[VDISP_FIELD_ASSET_HEIGHT]==256 && r.words[VDISP_FIELD_ASSET_STRIDE]==1024);
    asset.anchor_x=0;asset.anchor_y=256;asset.coverage_q8=257;
    result.boxes[0]=(struct npu_frame_box){797,597,3,3,0x3f000000,0,8};
    CHECK(face_avatar_build_avatar_record(&r,&id,&result,&asset)==FACE_AVATAR_OK);
    CHECK(r.words[VDISP_FIELD_AVATAR_XY0]==(798u|(594u<<16)));
    CHECK(r.words[VDISP_FIELD_AVATAR_XY1]==(802u|(598u<<16))); /* do not clip source mapping */
    for(i=0;i<8;++i) {
        bad=asset;
        switch(i) {
        case 0:bad.id=0;break;case 1:bad.generation=0;break;
        case 2:bad.base=SOC_AVATAR_BASE-16;break;case 3:bad.base=0x82800000u-262144u+16;break;
        case 4:bad.base++;break;case 5:bad.anchor_x=257;break;
        case 6:bad.coverage_q8=0;break;default:bad.coverage_q8=1025;break;
        }
        CHECK(face_avatar_build_avatar_record(&r,&id,&result,&bad)==FACE_AVATAR_INVALID);
    }
    result.face_count=result.display_count=0;
    CHECK(face_avatar_build_avatar_record(&r,&id,&result,&asset)==FACE_AVATAR_OK);
    CHECK(r.words[VDISP_FIELD_FLAGS]==(VDISP_FLAG_RESULT_VALID|VDISP_FLAG_RESULT_EMPTY));
    for(i=14;i<=22;++i)CHECK(r.words[i]==0);
    setup();CHECK(face_avatar_select_mode(&f.app,2)==FACE_AVATAR_INVALID);
    CHECK(face_avatar_configure_asset(&f.app,&asset)==FACE_AVATAR_OK);
    CHECK(face_avatar_select_mode(&f.app,3)==FACE_AVATAR_INVALID);
    step();CHECK(face_avatar_configure_asset(&f.app,&asset)==FACE_AVATAR_INVALID);
    capture_done();step();npu_done(1);step();
    CHECK(f.app.pool.pending.mode==0 && !f.app.pool.pending.mode_only);
    CHECK(f.app.records[0].words[VDISP_FIELD_FLAGS]&VDISP_FLAG_AVATAR_ENABLE);
    CHECK(face_avatar_select_mode(&f.app,2)==FACE_AVATAR_OK);step();
    CHECK(f.app.pool.pending.mode==0); /* outstanding immutable request */
    commit();step();CHECK(f.app.pool.pending.mode==2 && f.app.pool.pending.mode_only);
    CHECK(f.app.pool.pending.id.frame==f.app.pool.active.id.frame);
    CHECK(face_avatar_select_mode(&f.app,1)==FACE_AVATAR_OK);step();
    CHECK(f.app.pool.pending.mode==2);
    commit();step();CHECK(f.app.pool.pending.mode==1 && f.app.pool.pending.mode_only);
    commit();step();CHECK(f.app.pool.active.mode==1 && !f.app.pool.pending.valid);
    CHECK(f.app.pool.stats.mode_commits==2 && !f.app.pool.stats.releases);
}
int main(void) {
    primary_selection();avatar_records_and_modes();pipeline();failures();busy_and_pool();callback_failures();
    printf("PASS FACE_AVATAR checks=%u\n",checks);return 0;
}
