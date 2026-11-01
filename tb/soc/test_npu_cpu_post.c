#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "npu_frame.h"
#define REQUIRE(x) do{if(!(x)){fprintf(stderr,"CPU_POST_FAIL line=%d\n",__LINE__);exit(1);}}while(0)
static unsigned char heads[B03_HEADS_BYTES],table[B03_POST_TABLE_BYTES];
static uint32_t regs[1024];
static int rd(void *p,uint32_t off,uint32_t *v){(void)p;*v=regs[off/4];return 0;}
static int wr(void *p,uint32_t off,uint32_t v){(void)p;(void)off;(void)v;return 0;}
static int fence(void *p){(void)p;return 0;}
static int shared(void *p,uint32_t address,uint32_t *v,uint32_t words){
    uint32_t offset;(void)p;
    if(address>=B03_OUTPUT_BASES_0&&address-B03_OUTPUT_BASES_0<B03_HEADS_BYTES){
        offset=address-B03_OUTPUT_BASES_0;REQUIRE(offset%4==0&&words*4<=sizeof heads-offset);memcpy(v,heads+offset,words*4);
    }else if(address>=B03_POST_TABLE_BASE&&address-B03_POST_TABLE_BASE<B03_POST_TABLE_BYTES){
        offset=address-B03_POST_TABLE_BASE;REQUIRE(offset%4==0&&words*4<=sizeof table-offset);memcpy(v,table+offset,words*4);
    }else{fprintf(stderr,"out of range read address=%08x words=%u\n",address,words);return -1;}
    return 0;
}
static void load(const char *path,unsigned char *p,size_t n){FILE *f=fopen(path,"rb");REQUIRE(f);REQUIRE(fread(p,1,n,f)==n&&fgetc(f)==EOF);fclose(f);}
int main(int argc,char **argv){
    struct npu_frame_io io={0,rd,wr,shared,fence};struct npu_frame_ticket t={0,9,11,7};struct npu_frame_result r;
    uint32_t *d=regs+NF_COMPLETION_BASE/4;unsigned i;
    REQUIRE(argc==3);load(argv[1],table,sizeof table);load(argv[2],heads,sizeof heads);
    regs[NF_REG_STATUS/4]=NF_STATUS_HELD;regs[NF_REG_SESSION_EPOCH/4]=7;
    d[NF_DONE_CMD_ID]=9;d[NF_DONE_FRAME_ID_LO]=11;d[NF_DONE_EPOCH]=7;
    d[NF_DONE_RESULT_OFFSET]=B03_OUTPUT_BASES_0+B03_HEADS_OFFSET-SOC_DDR_BASE-SOC_WINDOW_BASE;
    d[NF_DONE_RESULT_BYTES]=B03_HEADS_BYTES;d[NF_DONE_LIVE]=1;d[NF_DONE_PUBLISHED]=1;
    memset(&r,0,sizeof r);REQUIRE(npu_frame_collect(&io,&t,&r)==NPU_FRAME_OK&&r.valid);
    printf("CPU_POST_BOXES %u\n",r.display_count);
    for(i=0;i<r.display_count;i++){
        REQUIRE(r.boxes[i].score_bits>=0x3f19999au&&r.boxes[i].score_bits<=0x3f800000u);
        if(i)REQUIRE(r.boxes[i-1].score_bits>=r.boxes[i].score_bits);
        printf("BOX %u %u %u %u %u\n",r.boxes[i].candidate,r.boxes[i].x,r.boxes[i].y,r.boxes[i].width,r.boxes[i].height);
        printf("SCORE %u %u\n",r.boxes[i].candidate,r.boxes[i].score_bits);
    }
    return 0;
}
