#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "npu_frame.h"
#define CHECK(x) do {++checks;if(!(x)){fprintf(stderr,"CHECK line %d\n",__LINE__);exit(1);}}while(0)
static unsigned checks;
static uint32_t regs[1024],image[32+17*8];
static unsigned fences,reads;
static int rd(void *p,uint32_t off,uint32_t *v){(void)p;*v=regs[off/4];return 0;}
static int wr(void *p,uint32_t off,uint32_t v){(void)p;regs[off/4]=v;if(off==NF_REG_ACK)regs[NF_REG_STATUS/4]=NF_STATUS_IDLE;return 0;}
static int fence(void *p){(void)p;++fences;return 0;}
static int shared(void *p,uint32_t addr,uint32_t *v,uint32_t words){
    (void)p;CHECK(addr>=0x82908000&&addr+words*4<=0x82908000+sizeof image);
    memcpy(v,(const unsigned char *)image+(addr-0x82908000),words*4);++reads;return 0;
}
static uint32_t crc(const uint32_t *data,unsigned bytes){
    const unsigned char *p=(const unsigned char *)data;uint32_t c=~0u;unsigned i,j;
    for(i=0;i<bytes;++i){c^=p[i];for(j=0;j<8;++j)c=(c>>1)^((0u-(c&1u))&0xedb88320u);}return ~c;
}
int main(void){
    struct npu_frame_io io={0,rd,wr,shared,fence};
    struct npu_frame_ticket ticket={0,9,11,7};
    struct npu_frame_result result;
    unsigned i;uint32_t *d=regs+NF_COMPLETION_BASE/4;
    memset(&result,0,sizeof result);regs[NF_REG_ID_VERSION/4]=NF_ID_VERSION;regs[NF_REG_STATUS/4]=NF_STATUS_IDLE;
    regs[NF_REG_SESSION_EPOCH/4]=7;
    CHECK(npu_frame_submit(&io,&ticket)==NPU_FRAME_OK);
    CHECK(regs[(NF_TASK_BASE+32)/4]==0x800000&&regs[(NF_TASK_BASE+40)/4]==0x908000);
    CHECK(regs[(NF_TASK_BASE+76)/4]==800&&regs[(NF_TASK_BASE+80)/4]==600&&fences==1);
    regs[NF_REG_STATUS/4]=NF_STATUS_HELD;
    d[NF_DONE_CMD_ID]=9;d[NF_DONE_FRAME_ID_LO]=11;d[NF_DONE_EPOCH]=7;d[NF_DONE_FACES]=17;
    d[NF_DONE_RESULT_OFFSET]=0x908000;d[NF_DONE_RESULT_BYTES]=128+17*32;d[NF_DONE_LIVE]=1;
    CHECK(npu_frame_collect(&io,&ticket,&result)==NPU_FRAME_UNPUBLISHED&&reads==0&&!result.valid);
    d[NF_DONE_PUBLISHED]=1;
    image[0]=0x3352504e;image[1]=1;image[2]=128;image[3]=1;image[6]=9;image[7]=7;image[8]=11;
    image[10]=17;image[11]=17*32;image[13]=0x908080;image[14]=B03_MODEL_TAG;
    image[22]=800;image[23]=600;image[24]=320;image[25]=240;image[27]=40;image[28]=1;
    for(i=0;i<17;++i){uint32_t *b=image+32+8*i;b[0]=10+i;b[1]=20;b[2]=30;b[3]=40;b[4]=0x3f000000;b[5]=i;b[6]=8;}
    image[12]=crc(image+32,17*32);image[31]=crc(image,124);d[NF_DONE_CRC]=image[12];
    CHECK(npu_frame_collect(&io,&ticket,&result)==NPU_FRAME_OK);
    CHECK(result.valid&&result.face_count==17&&result.display_count==16&&result.boxes[0].x==10&&result.boxes[15].x==25);
    CHECK(npu_frame_ack(&io,&ticket)==NPU_FRAME_OK&&regs[NF_REG_ACK_CMD/4]==9&&regs[NF_REG_ACK_FRAME/4]==11&&regs[NF_REG_ACK_EPOCH/4]==7);
    regs[NF_REG_STATUS/4]=NF_STATUS_HELD;
    image[32]^=1;CHECK(npu_frame_collect(&io,&ticket,&result)==NPU_FRAME_PROTOCOL&&!result.valid);image[32]^=1;
    d[NF_DONE_FRAME_ID_LO]=12;CHECK(npu_frame_collect(&io,&ticket,&result)==NPU_FRAME_PROTOCOL&&!result.valid);d[NF_DONE_FRAME_ID_LO]=11;
    image[8]=12;image[31]=crc(image,124);CHECK(npu_frame_collect(&io,&ticket,&result)==NPU_FRAME_PROTOCOL&&!result.valid);
    ticket.frame=0xffffffff;CHECK(npu_frame_submit(&io,&ticket)==NPU_FRAME_INVALID);
    printf("PASS NPU_FRAME_DRIVER checks=%u\n",checks);return 0;
}
