#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "video_capture.h"
#include "video_cfg.h"
static uint32_t regs[1024];
static unsigned checks,calls,fail_at,trace_on,fail_after,last_write,io_failures,ambiguous;
#define CHECK(x,label) do {++checks;if(!(x)){fprintf(stderr,"CAPTURE_DRIVER_ASSERT %s line%d\n",label,__LINE__);exit(1);}} while(0)
static int read32(void *p,uint32_t off,uint32_t *value) {
    (void)p;if(++calls==fail_at)return -1;*value=regs[off/4];
    if(trace_on)printf("R %08x %08x\n",off,*value);
    return 0;
}
static int write32(void *p,uint32_t off,uint32_t value) {
    int failed;
    (void)p;failed=++calls==fail_at;last_write=calls;
    if(failed&&!fail_after)return -1;
    if(trace_on)printf("W %08x %08x\n",off,value);
    if(off==VCAP_REG_IRQ_PENDING)regs[off/4]&=~value;
    else if(off==VCAP_REG_REARM)regs[VCAP_REG_STATUS/4]=0x281;
    else {regs[off/4]=value;
        if(off==VCAP_REG_CONTROL)regs[VCAP_REG_STATUS/4]=(regs[VCAP_REG_STATUS/4]&~1u)|(value&1u);
        if(off==VCAP_REG_CAPTURE_REQUEST)regs[VCAP_REG_STATUS/4]=0x28b;
    }
    return failed?-1:0;
}
static int fence(void *p) {(void)p;if(++calls==fail_at)return -1;if(trace_on)puts("F");return 0;}
static const struct video_capture_io io={0,read32,write32,fence};
static struct video_frame_allocation allocation(unsigned slot,unsigned frame) {
    struct video_frame_allocation a;
    static const uint32_t raw[]={VIDEO_FRAME_SLOT_A,VIDEO_FRAME_SLOT_B,VIDEO_FRAME_SLOT_C};
    static const uint32_t input[]={VIDEO_INPUT_SLOT_A,VIDEO_INPUT_SLOT_B,VIDEO_INPUT_SLOT_C};
    a.id.slot=slot;a.id.frame=frame;a.id.generation=7;a.raw_base=raw[slot];a.raw_stride=VIDEO_FRAME_RAW_STRIDE;
    a.preview_base=raw[slot]+VIDEO_FRAME_PREVIEW_OFFSET;a.preview_stride=VIDEO_FRAME_PREVIEW_STRIDE;
    a.input_base=input[slot];a.input_bytes=VIDEO_INPUT_BYTES;a.preprocess_version=VIDEO_INPUT_PREPROCESS_VERSION;return a;
}
static void reset(void) {
    memset(regs,0,sizeof regs);calls=fail_at=fail_after=last_write=0;
    regs[VCAP_REG_VERSION/4]=VCAP_ABI_VERSION;regs[VCAP_REG_CAPABILITIES/4]=63;regs[VCAP_REG_STATUS/4]=0x281;
}
static void event(const struct video_frame_allocation *a) {
    uint32_t *p=regs+VCAP_REG_ACCEPTED_SLOT/4,*q=regs+VCAP_REG_COMPLETED_SLOT/4;
    regs[VCAP_REG_IRQ_PENDING/4]=3;regs[VCAP_REG_STATUS/4]=0x2bb;
    p[0]=q[0]=a->id.slot;p[1]=q[1]=a->id.frame;p[2]=q[2]=1;p[3]=q[4]=a->raw_base;
    p[4]=q[5]=a->preview_base;p[5]=q[6]=a->input_base;p[6]=q[16]=a->id.generation;
    q[3]=1;q[7]=480000;q[8]=120000;q[9]=76800;q[10]=1440000;q[11]=360000;q[12]=307200;
    q[13]=0x12345678;q[14]=0x89abcdef;q[15]=37;q[17]=1;
}
static void run_trace(void) {
    struct video_frame_allocation a;struct video_capture_events e;unsigned j;
    reset();regs[VCAP_REG_STATUS/4]=0x280;CHECK(video_capture_enable(&io)==0,"ENABLE");
    for(j=0;j<4;++j) {
        a=allocation(j%3,j+1);CHECK(video_capture_submit(&io,&a)==0,"SUBMIT");
        if(trace_on)printf("E %u %u %u\n",a.id.slot,a.id.frame,a.id.generation);
        event(&a);CHECK(video_capture_read_events(&io,&e)==0,"READ_EVENTS");
        CHECK(video_capture_validate_completion(&e,&a)==0,"QUALIFIED_COMPLETE");
        CHECK(video_capture_ack(&io,3)==0,"ACK");
        regs[VCAP_REG_STATUS/4]=0x38b;
        CHECK(video_capture_rearm(&io)==0,"REARM");
    }
}
static int operation(unsigned op,const struct video_frame_allocation *a,struct video_capture_events *e) {
    switch(op) {
        case 0:return video_capture_enable(&io);case 1:return video_capture_submit(&io,a);
        case 2:return video_capture_read_events(&io,e);case 3:return video_capture_ack(&io,3);
        default:return video_capture_rearm(&io);
    }
}
static void setup_operation(unsigned op,const struct video_frame_allocation *a) {
    reset();
    if(op==2||op==3)event(a);
    if(op==4)regs[VCAP_REG_STATUS/4]=0x38b;
}
int main(int argc,char **argv) {
    struct video_frame_allocation a=allocation(0,1);struct video_capture_events e,sentinel;
    unsigned i,total,op,target;
    if(argc>1&&!strcmp(argv[1],"--trace")){trace_on=1;run_trace();puts("END");return 0;}
    for(op=0;op<5;++op) {
        setup_operation(op,&a);CHECK(operation(op,&a,&e)==0,"BASELINE_OPERATION");total=calls;target=last_write;
        for(i=1;i<=total;++i) {
            setup_operation(op,&a);fail_at=i;
            CHECK(operation(op,&a,&e)==VIDEO_CAPTURE_IO,"ALL_CALLBACK_FAILURES");
            CHECK(calls==i,"IO_NO_AUTOMATIC_RETRY");++io_failures;
        }
        if(target) {
            setup_operation(op,&a);fail_at=target;fail_after=1;
            CHECK(operation(op,&a,&e)==VIDEO_CAPTURE_IO,"AMBIGUOUS_WRITE");
            CHECK(calls==target,"AMBIGUOUS_WRITE_NO_RETRY");++ambiguous;
        }
    }
    reset();CHECK(video_capture_enable(&io)==0,"ENABLE");
    reset();CHECK(video_capture_submit(&io,&a)==0,"SUBMIT");total=calls;
    for(i=1;i<=total;++i){reset();fail_at=i;CHECK(video_capture_submit(&io,&a)==VIDEO_CAPTURE_IO,"SUBMIT_IO");}
    reset();event(&a);CHECK(video_capture_read_events(&io,&e)==0,"READ_EVENTS");total=calls;
    memset(&sentinel,0xa5,sizeof sentinel);
    for(i=1;i<=total;++i){reset();event(&a);e=sentinel;fail_at=i;
        CHECK(video_capture_read_events(&io,&e)==VIDEO_CAPTURE_IO,"EVENT_IO");CHECK(!memcmp(&e,&sentinel,sizeof e),"EVENT_ATOMIC_OUTPUT");}
    reset();event(&a);CHECK(video_capture_read_events(&io,&e)==0,"READ_EVENTS");
    CHECK(video_capture_validate_completion(&e,&a)==0,"COMPLETE_VALIDATE");
    for(i=0;i<12;++i){struct video_capture_events bad=e;
        switch(i) {
            case 0:bad.completed.result=3;break;
            case 1:bad.completed.raw_pixels--;break;case 2:bad.completed.preview_pixels--;break;
            case 3:bad.completed.input_pixels--;break;case 4:bad.completed.raw_bytes--;break;
            case 5:bad.completed.preview_bytes--;break;case 6:bad.completed.input_bytes--;break;
            case 7:bad.completed.fifo_peak=0;break;case 8:bad.completed.drained=0;break;
            case 9:bad.completed.identity.id.frame++;break;case 10:bad.completed.identity.version++;break;
            default:bad.completed.identity.raw_base++;break;
        }
        CHECK(video_capture_validate_completion(&bad,&a)!=0,"CORRUPT_COMPLETE");}
    e.completed.identity.id.generation^=1;CHECK(video_capture_validate_completion(&e,&a)==VIDEO_CAPTURE_PROTOCOL,"STALE_GENERATION");
    reset();regs[VCAP_REG_VERSION/4]=0x10000;CHECK(video_capture_submit(&io,&a)==VIDEO_CAPTURE_VERSION,"OLD_ABI");
    reset();regs[VCAP_REG_STATUS/4]|=2;CHECK(video_capture_submit(&io,&a)==VIDEO_CAPTURE_BUSY,"SLOT_BUSY");
    reset();a.raw_base++;CHECK(video_capture_submit(&io,&a)==VIDEO_CAPTURE_INVALID,"BAD_BASE");a=allocation(0,1);
    reset();CHECK(video_capture_rearm(&io)==VIDEO_CAPTURE_BUSY,"EARLY_REARM");
    reset();event(&a);CHECK(video_capture_ack(&io,4)==VIDEO_CAPTURE_INVALID,"FAULT_ACK_FORBIDDEN");
    CHECK(video_capture_ack(&io,3)==0,"ACK");CHECK(video_capture_ack(&io,1)==VIDEO_CAPTURE_INVALID,"MISSING_ACK_EVENT");
    reset();event(&a);regs[VCAP_REG_STATUS/4]|=64;regs[VCAP_REG_IRQ_PENDING/4]=3;regs[VCAP_REG_ERROR_CODE/4]=6;
    CHECK(video_capture_read_events(&io,&e)==0,"MUTED_FAULT_READ");
    CHECK(video_capture_validate_completion(&e,&a)==VIDEO_CAPTURE_FAILED,"MUTED_STICKY_FAULT");
    run_trace();printf("CAPTURE_DRIVER_PASS checks=%u callback_failures=%u ambiguous_writes=%u\n",checks,io_failures,ambiguous);return 0;
}
