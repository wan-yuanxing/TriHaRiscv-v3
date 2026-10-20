#include "video_display.h"
#include "video_cfg.h"
static int valid_io(const struct video_display_io *io) {
    return io && io->read32 && io->write32 && io->fence;
}
int video_display_init_record(struct video_display_record *r,uint32_t slot,uint32_t frame,uint32_t generation) {
    uint32_t i;
    static const uint32_t bases[3]={VIDEO_FRAME_SLOT_A,VIDEO_FRAME_SLOT_B,VIDEO_FRAME_SLOT_C};
    if(!r||slot>2||frame==0)return VIDEO_DISPLAY_INVALID;
    for(i=0;i<VDISP_RECORD_WORDS;i++)r->words[i]=0;
    r->words[VDISP_FIELD_VERSION]=VDISP_VERSION;r->words[VDISP_FIELD_BYTES]=VDISP_RECORD_BYTES;
    r->words[VDISP_FIELD_SLOT]=slot;r->words[VDISP_FIELD_FRAME]=frame;r->words[VDISP_FIELD_GENERATION]=generation;
    r->words[VDISP_FIELD_RAW_BASE]=bases[slot];r->words[VDISP_FIELD_RAW_STRIDE]=VIDEO_FRAME_RAW_STRIDE;
    r->words[VDISP_FIELD_WIDTH]=VIDEO_H_ACTIVE;r->words[VDISP_FIELD_HEIGHT]=VIDEO_V_ACTIVE;
    r->words[VDISP_FIELD_FLAGS]=VDISP_FLAG_RESULT_VALID|VDISP_FLAG_RESULT_EMPTY;
    r->words[VDISP_FIELD_RESULT_FRAME]=frame;r->words[VDISP_FIELD_RESULT_GENERATION]=generation;
    return VIDEO_DISPLAY_OK;
}
int video_display_submit(const struct video_display_io *io,const struct video_display_record *r,uint32_t mode,uint32_t seq,uint32_t mode_only) {
    uint32_t value,i;
    if(!valid_io(io)||!r||mode>2||mode_only>1)return VIDEO_DISPLAY_INVALID;
    if(io->read32(io->context,VDISP_REG_VERSION,&value))return VIDEO_DISPLAY_IO_ERROR;
    if(value!=VDISP_VERSION)return VIDEO_DISPLAY_VERSION;
    if(io->read32(io->context,VDISP_REG_CAPABILITIES,&value))return VIDEO_DISPLAY_IO_ERROR;
    if((value&11u)!=11u)return VIDEO_DISPLAY_VERSION;
    if(io->read32(io->context,VDISP_REG_STATUS,&value))return VIDEO_DISPLAY_IO_ERROR;
    if(value&0x6fu)return VIDEO_DISPLAY_BUSY;
    for(i=0;i<VDISP_RECORD_WORDS;i++)
        if(io->write32(io->context,VDISP_SHADOW_OFFSET+i*4,r->words[i]))return VIDEO_DISPLAY_IO_ERROR;
    if(io->write32(io->context,VDISP_REG_MODE,mode)||io->write32(io->context,VDISP_REG_SEQ,seq)||
       io->fence(io->context)||io->write32(io->context,VDISP_REG_SUBMIT,1u|(mode_only<<1)))return VIDEO_DISPLAY_IO_ERROR;
    return VIDEO_DISPLAY_OK;
}
int video_display_read_events(const struct video_display_io *io,struct video_display_events *out) {
    struct video_display_events e={0};
    if(!valid_io(io)||!out)return VIDEO_DISPLAY_INVALID;
    if(io->read32(io->context,VDISP_REG_EVENTS,&e.pending))return VIDEO_DISPLAY_IO_ERROR;
    if(e.pending&1u) {
        if(io->read32(io->context,VDISP_REG_COMMIT_FRAME,&e.commit_frame)||
           io->read32(io->context,VDISP_REG_COMMIT_GENERATION,&e.commit_generation)||
           io->read32(io->context,VDISP_REG_COMMIT_SLOT,&e.commit_slot)||
           io->read32(io->context,VDISP_REG_COMMIT_MODE,&e.commit_mode)||
           io->read32(io->context,VDISP_REG_COMMIT_SEQ,&e.commit_seq)||
           io->read32(io->context,VDISP_REG_COMMIT_MODE_ONLY,&e.commit_mode_only))return VIDEO_DISPLAY_IO_ERROR;
    }
    if(e.pending&2u) {
        if(io->read32(io->context,VDISP_REG_RELEASE_FRAME,&e.release_frame)||
           io->read32(io->context,VDISP_REG_RELEASE_GENERATION,&e.release_generation)||
           io->read32(io->context,VDISP_REG_RELEASE_SLOT,&e.release_slot))return VIDEO_DISPLAY_IO_ERROR;
    }
    if(e.pending&4u) {
        if(io->read32(io->context,VDISP_REG_REJECT_SEQ,&e.reject_seq)||
           io->read32(io->context,VDISP_REG_REJECT_CODE,&e.reject_code))return VIDEO_DISPLAY_IO_ERROR;
    }
    if((e.pending&8u)&&io->read32(io->context,VDISP_REG_ERROR_CODE,&e.error))return VIDEO_DISPLAY_IO_ERROR;
    *out=e;return VIDEO_DISPLAY_OK;
}
int video_display_ack(const struct video_display_io *io,uint32_t bits) {
    uint32_t events;
    if(!valid_io(io)||(bits&~7u))return VIDEO_DISPLAY_INVALID;
    if(io->read32(io->context,VDISP_REG_EVENTS,&events))return VIDEO_DISPLAY_IO_ERROR;
    if(bits&~events)return VIDEO_DISPLAY_INVALID;
    if(io->fence(io->context)||io->write32(io->context,VDISP_REG_ACK,bits))return VIDEO_DISPLAY_IO_ERROR;
    return VIDEO_DISPLAY_OK;
}
