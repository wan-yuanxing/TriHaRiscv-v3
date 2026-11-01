#include "face_avatar.h"
#include <stddef.h>

/* Telemetry only. Hardware IDLE is gated by health, model seal and ownership. */
volatile uint32_t face_avatar_system_epoch;
volatile uint32_t face_avatar_run_status;
volatile uint32_t face_avatar_trap_cause,face_avatar_trap_pc,face_avatar_trap_value;
struct face_avatar face_avatar_application;
static int read_mmio(void *base,uint32_t offset,uint32_t *value) {
    *value=*(volatile uint32_t *)((uintptr_t)base+offset);return 0;
}
static int write_mmio(void *base,uint32_t offset,uint32_t value) {
    *(volatile uint32_t *)((uintptr_t)base+offset)=value;return 0;
}
static int read_shared(void *context,uint32_t address,uint32_t *out,uint32_t words) {
    uint32_t i;(void)context;
    if ((address&3u) || address<SOC_FRAMES_BASE || words>(0x88000000u-address)/4 || address>=0x88000000u)return -1;
    for(i=0;i<words;++i)out[i]=((volatile const uint32_t *)(uintptr_t)address)[i];
    return 0;
}
static int io_fence(void *context) {
    (void)context;__asm__ volatile ("fence iorw,iorw" ::: "memory");return 0;
}
static const struct face_avatar_io platform_io={
    {(void *)(uintptr_t)VCAP_MMIO_BASE,read_mmio,write_mmio,io_fence},
    {(void *)(uintptr_t)VDISP_BASE,read_mmio,write_mmio,io_fence},
    {(void *)(uintptr_t)NF_BASE,read_mmio,write_mmio,read_shared,io_fence}
};
int main(void) {
    uint32_t epoch,status,live_epoch,confirmed_status;
    /* Polling avoids the admitted core's separately latched external mip bit. */
    for (;;) {
        read_mmio((void *)(uintptr_t)NF_BASE,NF_REG_STATUS,&status);
        if (status!=NF_STATUS_IDLE)continue;
        read_mmio((void *)(uintptr_t)NF_BASE,NF_REG_SESSION_EPOCH,&epoch);
        if (!epoch || epoch==UINT32_MAX)continue;
        read_mmio((void *)(uintptr_t)NF_BASE,NF_REG_STATUS,&confirmed_status);
        read_mmio((void *)(uintptr_t)NF_BASE,NF_REG_SESSION_EPOCH,&live_epoch);
        if (confirmed_status==NF_STATUS_IDLE && live_epoch==epoch)break;
    }
    face_avatar_system_epoch=epoch;
    if (face_avatar_init(&face_avatar_application,&platform_io,epoch)) {
        face_avatar_run_status=2;for (;;) {}
    }
    face_avatar_run_status=1;
    for (;;)if (face_avatar_step(&face_avatar_application)!=FACE_AVATAR_OK) {
        face_avatar_run_status=2;for (;;) {}
    }
}
