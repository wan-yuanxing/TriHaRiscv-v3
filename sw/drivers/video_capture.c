#include "video_capture.h"
#include "video_cfg.h"
static int valid_io(const struct video_capture_io *io) {
    return io && io->read32 && io->write32 && io->fence;
}
static int valid_allocation(const struct video_frame_allocation *a) {
    static const uint32_t raw[]={VIDEO_FRAME_SLOT_A,VIDEO_FRAME_SLOT_B,VIDEO_FRAME_SLOT_C};
    static const uint32_t input[]={VIDEO_INPUT_SLOT_A,VIDEO_INPUT_SLOT_B,VIDEO_INPUT_SLOT_C};
    return a && a->id.slot<3 && a->id.frame && a->raw_base==raw[a->id.slot] &&
        a->preview_base==a->raw_base+VIDEO_FRAME_PREVIEW_OFFSET && a->input_base==input[a->id.slot] &&
        a->raw_stride==VIDEO_FRAME_RAW_STRIDE && a->preview_stride==VIDEO_FRAME_PREVIEW_STRIDE &&
        a->input_bytes==VIDEO_INPUT_BYTES && a->preprocess_version==VIDEO_INPUT_PREPROCESS_VERSION;
}
static int version(const struct video_capture_io *io) {
    uint32_t v,c;
    if(io->read32(io->context,VCAP_REG_VERSION,&v)||io->read32(io->context,VCAP_REG_CAPABILITIES,&c))return VIDEO_CAPTURE_IO;
    return v==VCAP_ABI_VERSION && (c&VCAP_CAPABILITIES)==VCAP_CAPABILITIES ? VIDEO_CAPTURE_OK:VIDEO_CAPTURE_VERSION;
}
int video_capture_enable(const struct video_capture_io *io) {
    uint32_t status;int r;
    if(!valid_io(io))return VIDEO_CAPTURE_INVALID;
    r=version(io);if(r)return r;
    if(io->read32(io->context,VCAP_REG_STATUS,&status))return VIDEO_CAPTURE_IO;
    if(status&0x7eu)return VIDEO_CAPTURE_BUSY;
    if(io->write32(io->context,VCAP_REG_CONTROL,1)||io->write32(io->context,VCAP_REG_IRQ_MASK,7)||io->fence(io->context))return VIDEO_CAPTURE_IO;
    return VIDEO_CAPTURE_OK;
}
int video_capture_submit(const struct video_capture_io *io,const struct video_frame_allocation *a) {
    uint32_t status;int r;
    if(!valid_io(io)||!valid_allocation(a))return VIDEO_CAPTURE_INVALID;
    r=version(io);if(r)return r;
    if(io->read32(io->context,VCAP_REG_STATUS,&status))return VIDEO_CAPTURE_IO;
    if((status&0x201u)!=0x201u || (status&0x7eu))return VIDEO_CAPTURE_BUSY;
    if(io->write32(io->context,VCAP_REG_REQUEST_SLOT,a->id.slot)||
       io->write32(io->context,VCAP_REG_REQUEST_FRAME_ID,a->id.frame)||
       io->write32(io->context,VCAP_REG_REQUEST_VERSION,a->preprocess_version)||
       io->write32(io->context,VCAP_REG_REQUEST_GENERATION,a->id.generation)||
       io->fence(io->context)||io->write32(io->context,VCAP_REG_CAPTURE_REQUEST,1))return VIDEO_CAPTURE_IO;
    return VIDEO_CAPTURE_OK;
}
static int identity(const struct video_capture_io *io,struct video_capture_identity *id,uint32_t base,uint32_t gen) {
    if(io->read32(io->context,base,&id->id.slot)||io->read32(io->context,base+4,&id->id.frame)||
       io->read32(io->context,base+8,&id->version)||io->read32(io->context,base+12,&id->raw_base)||
       io->read32(io->context,base+16,&id->preview_base)||io->read32(io->context,base+20,&id->input_base)||
       io->read32(io->context,gen,&id->id.generation))return VIDEO_CAPTURE_IO;
    return VIDEO_CAPTURE_OK;
}
int video_capture_read_events(const struct video_capture_io *io,struct video_capture_events *out) {
    struct video_capture_events e;struct video_capture_completion *c=&e.completed;
    uint32_t status;
    uint32_t i;volatile unsigned char *bytes=(volatile unsigned char *)&e;
    if(!valid_io(io)||!out)return VIDEO_CAPTURE_INVALID;
    /* Keep the RV32I object independent of a C library memset implementation. */
    for(i=0;i<sizeof e;++i)bytes[i]=0;
    if(io->read32(io->context,VCAP_REG_IRQ_PENDING,&e.pending))return VIDEO_CAPTURE_IO;
    if(e.pending&~7u)return VIDEO_CAPTURE_PROTOCOL;
    if((e.pending&1u)&&identity(io,&e.accepted,VCAP_REG_ACCEPTED_SLOT,VCAP_REG_ACCEPTED_GENERATION))return VIDEO_CAPTURE_IO;
    if(e.pending&2u) {
        if(io->read32(io->context,VCAP_REG_CAPABILITIES,&e.capabilities))return VIDEO_CAPTURE_IO;
        /* Completion has RESULT between identity VERSION and RAW_BASE. */
        if(io->read32(io->context,VCAP_REG_COMPLETED_SLOT,&c->identity.id.slot)||
           io->read32(io->context,VCAP_REG_COMPLETED_FRAME_ID_RECORD,&c->identity.id.frame)||
           io->read32(io->context,VCAP_REG_COMPLETED_VERSION,&c->identity.version)||
           io->read32(io->context,VCAP_REG_COMPLETED_RAW_BASE,&c->identity.raw_base)||
           io->read32(io->context,VCAP_REG_COMPLETED_PREVIEW_BASE,&c->identity.preview_base)||
           io->read32(io->context,VCAP_REG_COMPLETED_INPUT_BASE,&c->identity.input_base)||
           io->read32(io->context,VCAP_REG_COMPLETED_GENERATION,&c->identity.id.generation)||
           io->read32(io->context,VCAP_REG_COMPLETED_RESULT,&c->result)||
           io->read32(io->context,VCAP_REG_COMPLETED_RAW_PIXELS,&c->raw_pixels)||
           io->read32(io->context,VCAP_REG_COMPLETED_PREVIEW_PIXELS,&c->preview_pixels)||
           io->read32(io->context,VCAP_REG_COMPLETED_INPUT_PIXELS,&c->input_pixels)||
           io->read32(io->context,VCAP_REG_COMPLETED_RAW_BYTES,&c->raw_bytes)||
           io->read32(io->context,VCAP_REG_COMPLETED_PREVIEW_BYTES,&c->preview_bytes)||
           io->read32(io->context,VCAP_REG_COMPLETED_INPUT_BYTES,&c->input_bytes)||
           io->read32(io->context,VCAP_REG_COMPLETED_RAW_CRC,&c->raw_crc)||
           io->read32(io->context,VCAP_REG_COMPLETED_PREVIEW_CRC,&c->preview_crc)||
           io->read32(io->context,VCAP_REG_COMPLETED_FIFO_PEAK,&c->fifo_peak)||
           io->read32(io->context,VCAP_REG_COMPLETED_DRAINED,&c->drained))return VIDEO_CAPTURE_IO;
    }
    /* IRQ W1C may mute the notification without clearing the terminal fault.
     * Sample sticky STATUS after the held records; never turn a muted fault
     * into a qualified success. This does not prove physical DDR visibility. */
    if(io->read32(io->context,VCAP_REG_STATUS,&status))return VIDEO_CAPTURE_IO;
    if(status&VCAP_STATUS_STICKY_FAULT_MASK)e.pending|=4u;
    if((e.pending&4u)&&io->read32(io->context,VCAP_REG_ERROR_CODE,&e.error))return VIDEO_CAPTURE_IO;
    *out=e;return VIDEO_CAPTURE_OK;
}
static int same_identity(const struct video_capture_identity *id,const struct video_frame_allocation *a) {
    return id->id.slot==a->id.slot && id->id.frame==a->id.frame && id->id.generation==a->id.generation &&
        id->version==a->preprocess_version && id->raw_base==a->raw_base &&
        id->preview_base==a->preview_base && id->input_base==a->input_base;
}
int video_capture_validate_completion(const struct video_capture_events *e,const struct video_frame_allocation *a) {
    const struct video_capture_completion *c;
    if(!e||!valid_allocation(a))return VIDEO_CAPTURE_INVALID;
    if(!(e->pending&2u))return VIDEO_CAPTURE_BUSY;
    c=&e->completed;
    if((e->pending&~7u)||!same_identity(&c->identity,a)||c->drained!=1||
       (c->result&~0xff01u)||((e->pending&1u)&&!same_identity(&e->accepted,a)))return VIDEO_CAPTURE_PROTOCOL;
    if(c->result!=1u) {
        return !(c->result&1u)&&(c->result&0xff00u) ? VIDEO_CAPTURE_FAILED:VIDEO_CAPTURE_PROTOCOL;
    }
    if(c->raw_pixels!=VIDEO_H_ACTIVE*VIDEO_V_ACTIVE || c->preview_pixels!=((e->capabilities&VCAP_CAP_PREVIEW_OMITTED)?0u:VIDEO_H_ACTIVE*VIDEO_V_ACTIVE/4) ||
       c->input_pixels!=VIDEO_INPUT_WIDTH*(VIDEO_V_ACTIVE*2/5) ||
       c->raw_bytes!=VIDEO_H_ACTIVE*VIDEO_V_ACTIVE*3 || c->preview_bytes!=((e->capabilities&VCAP_CAP_PREVIEW_OMITTED)?0u:VIDEO_H_ACTIVE*VIDEO_V_ACTIVE/4*3) ||
       ((e->capabilities&VCAP_CAP_PREVIEW_OMITTED)&&c->preview_crc!=0) ||
       c->input_bytes!=VIDEO_INPUT_BYTES || !c->fifo_peak || c->fifo_peak>2048)return VIDEO_CAPTURE_PROTOCOL;
    return (e->pending&4u)?VIDEO_CAPTURE_FAILED:VIDEO_CAPTURE_OK;
}
int video_capture_ack(const struct video_capture_io *io,uint32_t bits) {
    uint32_t pending;
    if(!valid_io(io)||!bits||(bits&~3u))return VIDEO_CAPTURE_INVALID;
    if(io->read32(io->context,VCAP_REG_IRQ_PENDING,&pending))return VIDEO_CAPTURE_IO;
    if(bits&~pending)return VIDEO_CAPTURE_INVALID;
    if(io->fence(io->context)||io->write32(io->context,VCAP_REG_IRQ_PENDING,bits))return VIDEO_CAPTURE_IO;
    return VIDEO_CAPTURE_OK;
}
int video_capture_rearm(const struct video_capture_io *io) {
    uint32_t status;int r;
    if(!valid_io(io))return VIDEO_CAPTURE_INVALID;
    r=version(io);if(r)return r;
    if(io->read32(io->context,VCAP_REG_STATUS,&status))return VIDEO_CAPTURE_IO;
    if(!(status&0x100u)||(status&0x70u))return VIDEO_CAPTURE_BUSY;
    if(io->fence(io->context)||io->write32(io->context,VCAP_REG_REARM,1))return VIDEO_CAPTURE_IO;
    return VIDEO_CAPTURE_OK;
}
