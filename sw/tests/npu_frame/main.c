#include "npu_frame.h"
static volatile uint32_t *const report=(volatile uint32_t *)0x2001fff0u;
static int read32(void *p,uint32_t off,uint32_t *v){(void)p;*v=*(volatile uint32_t *)(NF_BASE+off);return 0;}
static int write32(void *p,uint32_t off,uint32_t v){(void)p;*(volatile uint32_t *)(NF_BASE+off)=v;return 0;}
static int shared(void *p,uint32_t address,uint32_t *v,uint32_t words){uint32_t i;(void)p;for(i=0;i<words;++i)v[i]=((volatile uint32_t *)address)[i];return 0;}
static int fence(void *p){(void)p;__asm__ volatile("fence iorw,iorw" ::: "memory");return 0;}
void fail(uint32_t code){*report=0xdead0000u|(code&65535u);for(;;){}}
int main(void){
    const struct npu_frame_io io={0,read32,write32,shared,fence};
    struct npu_frame_ticket ticket;struct npu_frame_result result;
    uint32_t frame,status,epoch;int r;
    do {read32(0,NF_REG_STATUS,&status);} while(status!=NF_STATUS_IDLE);
    read32(0,NF_REG_SESSION_EPOCH,&epoch);if(epoch!=7)fail(1);
    for(frame=0;frame<2;++frame){
        ticket.slot=frame;ticket.cmd=101+frame;ticket.frame=1001+frame;ticket.epoch=epoch;
        r=npu_frame_submit(&io,&ticket);if(r)fail(0x100u+(uint32_t)-r);
        do {r=npu_frame_collect(&io,&ticket,&result);}while(r==NPU_FRAME_PENDING||r==NPU_FRAME_UNPUBLISHED);
        if(r||!result.valid||result.face_count||result.display_count||result.crc)fail(0x200u+(uint32_t)-r);
        r=npu_frame_ack(&io,&ticket);if(r)fail(0x300u+(uint32_t)-r);
        *report=0x600d0001u+frame;
        __asm__ volatile("fence iorw,iorw" ::: "memory");
    }
    *report=0x600d600du;for(;;){}
}
