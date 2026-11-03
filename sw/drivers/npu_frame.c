#include "npu_frame.h"

static int io_valid(const struct npu_frame_io *io) {
    return io&&io->read32&&io->write32&&io->read_shared&&io->fence;
}
static int identity(uint32_t x) { return x&&x!=UINT32_MAX; }
static int ticket_valid(const struct npu_frame_ticket *t) {
    return t&&t->slot<3&&identity(t->cmd)&&identity(t->frame)&&identity(t->epoch);
}
static uint32_t input_base(uint32_t slot) {
    return slot==0?B03_INPUT_BASES_0:slot==1?B03_INPUT_BASES_1:B03_INPUT_BASES_2;
}
static uint32_t output_base(uint32_t slot) {
    return slot==0?B03_OUTPUT_BASES_0:slot==1?B03_OUTPUT_BASES_1:B03_OUTPUT_BASES_2;
}
static uint32_t crc_words(uint32_t crc,const uint32_t *words,uint32_t count) {
    uint32_t i,j,k,v;
    for(i=0;i<count;++i) {
        v=words[i];
        for(j=0;j<4;++j) {
            crc^=v&255u;v>>=8;
            for(k=0;k<8;++k)crc=(crc>>1)^((0u-(crc&1u))&0xedb88320u);
        }
    }
    return crc;
}

/* CPU-post path.  B03 still writes the quantized heads; this compact integer
 * decoder consumes them without pulling the table/decoder/NMS hardware into
 * the FPGA.  The table is read only for candidates above threshold. */
static int q16_from_fp32(uint32_t encoded,int32_t *q) {
    uint32_t exp=encoded>>23 & 255u, frac=encoded & 0x7fffffu;
    uint32_t mantissa=(1u<<23)|frac, magnitude;
    int shift;
    if ((encoded&0x7fffffffu)==0) { *q=0; return 0; }
    if (!exp || exp==255u) return -1;
    shift=(int)exp-134;
    if (shift>=0) {
        /* Extents beyond the image saturate before clipping, never wrap. */
        magnitude=(shift>7 || mantissa>(0x7fffffffu>>shift))?0x7fffffffu:mantissa<<shift;
    } else magnitude=shift<-23?0u:mantissa>>(-shift);
    *q=(encoded>>31)?-(int32_t)magnitude:(int32_t)magnitude;
    return 0;
}
static int table_q16(const struct npu_frame_io *io,uint32_t scale,uint16_t code,uint32_t axis,int32_t *q) {
    uint32_t raw,offset=(scale<<19)|((uint32_t)code<<3)|(axis>=2u?4u:0u);
    if (code==0x8000u || axis>=4u || offset>=B03_POST_TABLE_BYTES)return -1;
    if (io->read_shared(io->context,B03_POST_TABLE_BASE+offset,&raw,1))return -1;
    return q16_from_fp32(raw,q);
}
static uint32_t roi_endpoint(int64_t endpoint,uint32_t pad,uint32_t limit,int upper) {
    int64_t clipped=endpoint-((int64_t)pad<<16);
    if(clipped<0)clipped=0;
    if(clipped>((int64_t)limit<<16))clipped=(int64_t)limit<<16;
    /* Fixed 800x600 / 320x240 geometry: both scale factors are exactly 5/2.
     * Clip before the multiply; preserve subpixels until floor/ceil. */
    return ((uint32_t)clipped*5u+(upper?131071u:0u))>>17;
}
static uint32_t box_area(const struct npu_frame_box *b) { return b->width*b->height; }
static uint32_t product_score_bits(uint32_t product) {
    /* Above the 0.6 threshold, product/2^32 has exponent -2 or -1.
     * Round it to FP32, then use the B03 digit-by-digit rounded square root.
     * This preserves the public FP32 score ABI without an FPU or libm. */
    uint32_t shift=product>=0x80000000u?8u:7u;
    uint32_t mantissa=product>>shift,rem=product&((1u<<shift)-1u),half=1u<<(shift-1u);
    uint32_t root=0,remainder=0,trial,high,low;int digit;
    if(rem>half||(rem==half&&(mantissa&1u)))++mantissa;
    high=mantissa>>(shift==8u?8:9);low=mantissa<<(shift==8u?24:23);
    for(digit=23;digit>=0;--digit){
        remainder=(remainder<<2)|(high>>14);
        high=((high<<2)|(low>>30))&65535u;low<<=2;
        trial=(root<<2)|1u;
        if(remainder>=trial){remainder-=trial;root=(root<<1)|1u;}else root<<=1;
    }
    if(remainder>root)++root;
    return (126u<<23)+(root-(1u<<23));
}
static int box_iou_gt(const struct npu_frame_box *a,const struct npu_frame_box *b) {
    uint32_t ax2=a->x+a->width,ay2=a->y+a->height,bx2=b->x+b->width,by2=b->y+b->height;
    uint32_t x=a->x> b->x?a->x:b->x,y=a->y>b->y?a->y:b->y;
    uint32_t x2=ax2<bx2?ax2:bx2,y2=ay2<by2?ay2:by2;
    uint32_t iw=x2>x?x2-x:0,ih=y2>y?y2-y:0,inter=iw*ih;
    uint32_t uni=box_area(a)+box_area(b)-inter;
    return uni && inter*10u>uni*3u;
}
static int cpu_post_heads(const struct npu_frame_io *io,const struct npu_frame_ticket *t,struct npu_frame_result *out) {
    uint32_t cls_words[32],obj_words[32],bbox_words[2],i,scale,base,chunk,j,n;
    struct npu_frame_box candidates[64],kept[16]; uint32_t nc=0,nk=0;
    uint32_t cursor_score=UINT32_MAX,cursor_id=0;
    const uint32_t product_threshold=1546188224u; /* B03 sqrt(product/2^32) >= FP32(0.6). */
    /* A bounded buffer is a sorted page, never a top-k semantic limit. Heads
     * remain immutable while the frame is HELD. Resume below the last key
     * until NMS has 16 survivors or all eligible candidates are exhausted. */
    do {
        nc=0;
        for (scale=0;scale<3;scale++) {
            uint32_t count=scale==0?1600u:scale==1?400u:100u,grid=scale==0?40u:scale==1?20u:10u,stride=8u<<scale;
            base=scale==0?0u:scale==1?1600u:2000u;
            for(chunk=0;chunk<count;chunk+=64u) {
                n=(count-chunk)>64u?64u:(count-chunk);
                uint32_t cls_base=scale==0?0u:scale==1?1664u:2176u;
                uint32_t obj_base=scale==0?2304u:scale==1?3968u:4480u;
                uint32_t bb_base=scale==0?4608u:scale==1?11008u:12672u;
                if(io->read_shared(io->context,output_base(t->slot)+B03_HEADS_OFFSET+2u*(cls_base+chunk),cls_words,(n+1u)/2u)||
                   io->read_shared(io->context,output_base(t->slot)+B03_HEADS_OFFSET+2u*(obj_base+chunk),obj_words,(n+1u)/2u))return NPU_FRAME_IO;
                for(j=0;j<n;j++) {
                    i=chunk+j;
                    uint32_t shift=(j&1u)*16u;
                    uint32_t product=((cls_words[j/2u]>>shift)&65535u)*((obj_words[j/2u]>>shift)&65535u);
                    uint32_t score;
                    if(product<product_threshold)continue;
                    score=product_score_bits(product);
                    if(score>cursor_score||(score==cursor_score&&base+i<=cursor_id))continue;
                    /* Ascending head traversal already breaks equal-score ties
                     * by candidate id, matching the hardware key sort. */
                    if(nc==64u&&score<=candidates[63].score_bits)continue;
                    int32_t dx,dy,w,h;int64_t cx,cy;uint32_t x,y,x2,y2; uint16_t code;
                    if(io->read_shared(io->context,output_base(t->slot)+B03_HEADS_OFFSET+2u*(bb_base+4u*i),bbox_words,2))return NPU_FRAME_IO;
                    code=(uint16_t)bbox_words[0]; if(table_q16(io,scale,code,0,&dx))return NPU_FRAME_IO;
                    code=(uint16_t)(bbox_words[0]>>16); if(table_q16(io,scale,code,1,&dy))return NPU_FRAME_IO;
                    code=(uint16_t)bbox_words[1]; if(table_q16(io,scale,code,2,&w))return NPU_FRAME_IO;
                    code=(uint16_t)(bbox_words[1]>>16); if(table_q16(io,scale,code,3,&h))return NPU_FRAME_IO;
                    /* Table extent is exp(raw*scale)*stride, already in model pixels. */
                    cx=(((int64_t)(i%grid)<<16)+dx)*stride;
                    cy=(((int64_t)(i/grid)<<16)+dy)*stride;
                    if(w<=0||h<=0)continue;
                    x=roi_endpoint(cx-w/2,0,320,0);x2=roi_endpoint(cx+(w+1LL)/2,0,320,1);
                    y=roi_endpoint(cy-h/2,40,240,0);y2=roi_endpoint(cy+(h+1LL)/2,40,240,1);
                    if(x2<=x||y2<=y)continue;
                    /* Keep the next 64 rounded-score keys, including later heads. */
                    uint32_t pos=nc<64u?nc++:63u;
                    while(pos&&candidates[pos-1].score_bits<score){candidates[pos]=candidates[pos-1];--pos;}
                    candidates[pos].x=x;candidates[pos].y=y;candidates[pos].width=x2-x;candidates[pos].height=y2-y;
                    candidates[pos].score_bits=score;candidates[pos].candidate=base+i;candidates[pos].stride=stride;
                }
            }
        }
        /* Greedy NMS keeps its survivors across consecutive sorted pages. */
        for(i=0;i<nc&&nk<16u;i++){uint32_t j;int suppressed=0;for(j=0;j<nk;j++)if(box_iou_gt(&candidates[i],&kept[j])){suppressed=1;break;}if(!suppressed)kept[nk++]=candidates[i];}
        if(nc){cursor_score=candidates[nc-1].score_bits;cursor_id=candidates[nc-1].candidate;}
    } while(nc==64u&&nk<16u);
    out->face_count=nk;out->display_count=nk;out->crc=0;
    for(i=0;i<nk;i++)out->boxes[i]=kept[i];
    out->valid=1;return NPU_FRAME_OK;
}

int npu_frame_submit(const struct npu_frame_io *io,const struct npu_frame_ticket *t) {
    uint32_t w[32],i,id,status,epoch,base=SOC_DDR_BASE+SOC_WINDOW_BASE;
    if(!io_valid(io)||!ticket_valid(t))return NPU_FRAME_INVALID;
    if(io->read32(io->context,NF_REG_ID_VERSION,&id)||io->read32(io->context,NF_REG_STATUS,&status)||
       io->read32(io->context,NF_REG_SESSION_EPOCH,&epoch))return NPU_FRAME_IO;
    if(id!=NF_ID_VERSION)return NPU_FRAME_VERSION;
    if(status&NF_STATUS_FAULT||epoch!=t->epoch)return NPU_FRAME_FAULT;
    if(status!=NF_STATUS_IDLE)return NPU_FRAME_BUSY;
    for(i=0;i<32;++i)w[i]=0;
    w[0]=0x33444d42;w[1]=1;w[2]=128;w[3]=1;
    w[4]=B03_PROGRAM_BASE-base;w[5]=B03_PROGRAM_BYTES;
    w[6]=B03_WORKSPACE_BASE-base;w[7]=B03_WORKSPACE_BYTES;
    w[8]=input_base(t->slot)-base;w[9]=B03_INPUT_BYTES;
    w[10]=output_base(t->slot)+B03_RESULT_OFFSET-base;w[11]=B03_RESULT_BYTES;
    w[12]=B03_POST_TABLE_BASE-base;w[13]=B03_POST_TABLE_BYTES;
    w[14]=t->cmd;w[15]=t->frame;w[17]=t->epoch;w[18]=1;
    w[19]=B03_SOURCE_WIDTH;w[20]=B03_SOURCE_HEIGHT;w[21]=B03_RESIZED_WIDTH;w[22]=B03_RESIZED_HEIGHT;
    w[23]=B03_PAD_LEFT;w[24]=B03_PAD_TOP;w[25]=B03_CAPACITY;
    w[26]=B03_PROGRAM_CRC32;w[27]=B03_PARAMETER_CRC32;
    w[28]=output_base(t->slot)+B03_HEADS_OFFSET-base;w[29]=1;w[30]=B03_WATCHDOG_CYCLES;
    for(i=0;i<32;++i)if(io->write32(io->context,NF_TASK_BASE+4*i,w[i]))return NPU_FRAME_IO;
    if(io->fence(io->context)||io->write32(io->context,NF_REG_CONTROL,NF_START))return NPU_FRAME_IO;
    return NPU_FRAME_OK;
}

int npu_frame_collect(const struct npu_frame_io *io,const struct npu_frame_ticket *t,struct npu_frame_result *out) {
    uint32_t d[20],h[32],b[8],i,status,epoch,base,offset,crc=UINT32_MAX,last_score=0x3f800000;
    if(out)out->valid=0;
    if(!io_valid(io)||!ticket_valid(t)||!out)return NPU_FRAME_INVALID;
    if(io->read32(io->context,NF_REG_STATUS,&status))return NPU_FRAME_IO;
    if(status&NF_STATUS_FAULT)return NPU_FRAME_FAULT;
    if(!(status&NF_STATUS_HELD))return NPU_FRAME_PENDING;
    for(i=0;i<20;++i)if(io->read32(io->context,NF_COMPLETION_BASE+4*i,&d[i]))return NPU_FRAME_IO;
    if(d[NF_DONE_STATUS]||d[NF_DONE_FRAME_ID_HI]||d[NF_DONE_CMD_ID]!=t->cmd||
       d[NF_DONE_FRAME_ID_LO]!=t->frame||d[NF_DONE_EPOCH]!=t->epoch||d[NF_DONE_LIVE]!=1)return NPU_FRAME_PROTOCOL;
    if(d[NF_DONE_PUBLISHED]!=1)return NPU_FRAME_UNPUBLISHED;
    base=output_base(t->slot)+B03_RESULT_OFFSET;offset=base-(SOC_DDR_BASE+SOC_WINDOW_BASE);
    if(d[NF_DONE_RESULT_BYTES]==B03_HEADS_BYTES && d[NF_DONE_FACES]==0) {
        if (d[NF_DONE_RESULT_OFFSET] != (output_base(t->slot)+B03_HEADS_OFFSET-(SOC_DDR_BASE+SOC_WINDOW_BASE)))return NPU_FRAME_PROTOCOL;
        if(io->fence(io->context))return NPU_FRAME_IO;
        if(cpu_post_heads(io,t,out)!=NPU_FRAME_OK)return NPU_FRAME_IO;
        if(io->read32(io->context,NF_REG_STATUS,&status)||io->read32(io->context,NF_REG_SESSION_EPOCH,&epoch))return NPU_FRAME_IO;
        if(status!=NF_STATUS_HELD||epoch!=t->epoch)return NPU_FRAME_FAULT;
        return NPU_FRAME_OK;
    }
    if(d[NF_DONE_FACES]>B03_CAPACITY||d[NF_DONE_RESULT_OFFSET]!=offset||
       d[NF_DONE_RESULT_BYTES]!=128+32*d[NF_DONE_FACES])return NPU_FRAME_PROTOCOL;
    if(io->fence(io->context)||io->read_shared(io->context,base,h,32))return NPU_FRAME_IO;
    if(h[0]!=0x3352504e||h[1]!=1||h[2]!=128||h[3]!=1||h[4]||h[5]||h[6]!=t->cmd||h[7]!=t->epoch||
       h[8]!=t->frame||h[9]||h[10]!=d[NF_DONE_FACES]||h[11]!=32*h[10]||h[12]!=d[NF_DONE_CRC]||
       h[13]!=offset+128||h[14]!=B03_MODEL_TAG||h[15]||h[22]!=B03_SOURCE_WIDTH||h[23]!=B03_SOURCE_HEIGHT||
       h[24]!=B03_RESIZED_WIDTH||h[25]!=B03_RESIZED_HEIGHT||h[26]!=B03_PAD_LEFT||h[27]!=B03_PAD_TOP||
       h[28]!=1||h[29]||h[30]||~crc_words(UINT32_MAX,h,31)!=h[31])return NPU_FRAME_PROTOCOL;
    out->face_count=h[10];out->display_count=h[10]>16?16:h[10];out->crc=h[12];
    for(i=0;i<h[10];++i) {
        if(io->read_shared(io->context,base+128+32*i,b,8))return NPU_FRAME_IO;
        crc=crc_words(crc,b,8);
        if(b[0]>=800||b[1]>=600||!b[2]||!b[3]||b[2]>800-b[0]||b[3]>600-b[1]||
           b[4]>last_score||b[5]>=2100||(b[6]!=8&&b[6]!=16&&b[6]!=32)||b[7])return NPU_FRAME_PROTOCOL;
        last_score=b[4];
        if(i<16) {
            out->boxes[i].x=b[0];out->boxes[i].y=b[1];out->boxes[i].width=b[2];out->boxes[i].height=b[3];
            out->boxes[i].score_bits=b[4];out->boxes[i].candidate=b[5];out->boxes[i].stride=b[6];
        }
    }
    if(~crc!=h[12])return NPU_FRAME_PROTOCOL;
    if(io->read32(io->context,NF_REG_STATUS,&status)||io->read32(io->context,NF_REG_SESSION_EPOCH,&epoch))return NPU_FRAME_IO;
    if(status!=NF_STATUS_HELD||epoch!=t->epoch)return NPU_FRAME_FAULT;
    out->valid=1;return NPU_FRAME_OK;
}

int npu_frame_ack(const struct npu_frame_io *io,const struct npu_frame_ticket *t) {
    uint32_t status;
    if(!io_valid(io)||!ticket_valid(t))return NPU_FRAME_INVALID;
    if(io->write32(io->context,NF_REG_ACK_CMD,t->cmd)||io->write32(io->context,NF_REG_ACK_FRAME,t->frame)||
       io->write32(io->context,NF_REG_ACK_EPOCH,t->epoch)||io->fence(io->context)||
       io->write32(io->context,NF_REG_IRQ_STATUS,NF_IRQ_DONE|NF_IRQ_ERROR)||
       io->write32(io->context,NF_REG_ACK,1)||io->read32(io->context,NF_REG_STATUS,&status))return NPU_FRAME_IO;
    /* Caller owns CPU interrupt pending acknowledgement after this readback. */
    return status==NF_STATUS_IDLE?NPU_FRAME_OK:NPU_FRAME_FAULT;
}
