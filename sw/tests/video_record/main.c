/* Frozen-CPU digital diagnostic. Fixed detector fixture; no NPU execution. */
#include <stdint.h>
#include <stddef.h>
#include "video_capture.h"
#include "fixture.h"
static volatile uint32_t *const sig=(volatile uint32_t *)0x10000u;
static uint32_t checks,expected_cause,expected_value;
static struct video_frame_pool pool;
static struct video_display_record record;
void *memcpy(void *d,const void *s,size_t n) { unsigned char *a=d;const unsigned char *b=s;while(n--)*a++=*b++;return d; }
void *memset(void *d,int v,size_t n) { unsigned char *a=d;while(n--)*a++=(unsigned char)v;return d; }
static void fail(uint32_t code) { sig[0]=0xbad00000u|code;for(;;)__asm__ volatile("nop"); }
#define CHECK(c,n) do { ++checks;if(!(c))fail(n); } while(0)
extern void test_load_fault(uint32_t),test_store_fault(void);
extern unsigned char fault_load_pc[],fault_store_pc[];
uint32_t trap_handle(uint32_t cause,uint32_t pc,uint32_t value) {
    if(cause!=expected_cause||value!=expected_value||pc!=(uint32_t)(cause==5?fault_load_pc:fault_store_pc))fail(0xe0);
    ++sig[2];expected_cause=0;return pc+4;
}
static int read32(void *ctx,uint32_t off,uint32_t *value) { *value=*(volatile uint32_t *)((uintptr_t)ctx+off);++sig[8];return 0; }
static int write32(void *ctx,uint32_t off,uint32_t value) { *(volatile uint32_t *)((uintptr_t)ctx+off)=value;++sig[9];return 0; }
static int fence(void *ctx) {
    (void)ctx;
    /* The frozen single-outstanding native path acknowledges each MMIO access
       before returning it. This compiler barrier adds no DDR visibility claim. */
    __asm__ volatile("" ::: "memory");++sig[10];return 0;
}
static uint32_t cycle(void) { uint32_t v;__asm__ volatile("rdcycle %0":"=r"(v));return v; }
static void full_raster(void) { uint32_t start=cycle();while((uint32_t)(cycle()-start)<3000000u)__asm__ volatile("nop"); }
static void await(uint32_t base,uint32_t mask) {
    uint32_t budget=1000000u;
    while((*(volatile uint32_t *)(base+0x14u)&mask)!=mask&&--budget) { }
    CHECK(budget,0x10);
}
static void result_ready(const struct video_frame_token *id) {
    struct video_frame_token graph;
    CHECK(video_frame_pool_graph_begin(&pool,1,&graph)==0&&graph.frame==id->frame,0x40);
    CHECK(video_frame_pool_operator_begin(&pool,&graph,9)==0,0x41);
    CHECK(video_frame_pool_operator_done(&pool,&graph,9,1,1)==0,0x42);
    CHECK(video_frame_pool_result_ready(&pool,&graph,1)==0,0x43);
}
int main(void) {
    struct video_capture_io ci={(void *)VCAP_MMIO_BASE,read32,write32,fence};
    struct video_display_io di={(void *)VDISP_BASE,read32,write32,fence};
    struct video_frame_allocation a,extra;struct video_capture_events e;
    unsigned i,j;static const uint32_t modes[3]={1,2,0};
    sig[1]=1;
    expected_cause=5;expected_value=0x20010000;test_load_fault(expected_value);
    expected_cause=5;expected_value=0x20013000;test_load_fault(expected_value);
    expected_cause=7;expected_value=VDISP_BASE;test_store_fault();
    CHECK(sig[2]==3,1);
    CHECK(*(volatile uint32_t *)VDISP_BASE==VDISP_VERSION&&*(volatile uint32_t *)(VDISP_BASE+0x80)==7,2);
    CHECK(video_capture_enable(&ci)==0,3);video_frame_pool_init(&pool,47);
    for(i=0;i<(TEST_CASE?1u:2u);++i) {
        sig[1]=10+i;
        CHECK(video_frame_pool_allocate(&pool,&a)==0&&a.id.slot==i,4);
        CHECK(video_display_init_record(&record,a.id.slot,a.id.frame,a.id.generation)==0,5);
        memcpy(record.words,fixture_words,sizeof record.words);
        record.words[VDISP_FIELD_SLOT]=a.id.slot;record.words[VDISP_FIELD_FRAME]=a.id.frame;record.words[VDISP_FIELD_GENERATION]=a.id.generation;
        record.words[VDISP_FIELD_RAW_BASE]=a.raw_base;record.words[VDISP_FIELD_RESULT_FRAME]=a.id.frame;record.words[VDISP_FIELD_RESULT_GENERATION]=a.id.generation;
        CHECK(video_frame_pool_present(&pool,&di,&record,0,100+4*i,0)==VIDEO_FRAME_STATE,6);
        CHECK(video_capture_submit(&ci,&a)==0,7);await(VCAP_MMIO_BASE,2);
        CHECK(video_capture_read_events(&ci,&e)==0,8);
        CHECK(e.completed.identity.id.frame==a.id.frame&&e.completed.identity.id.generation==47,9);
        if(TEST_CASE) {
            CHECK(video_capture_validate_completion(&e,&a)==VIDEO_CAPTURE_FAILED&&e.completed.drained==1,0x11);
            CHECK(video_frame_pool_capture_done(&pool,&a.id,0)==VIDEO_FRAME_FAULT,0x12);
            CHECK(video_frame_pool_free_mask(&pool)==0&&video_frame_pool_allocate(&pool,&extra)==VIDEO_FRAME_FAULT,0x13);
            CHECK(video_capture_rearm(&ci)==VIDEO_CAPTURE_BUSY,0x14);
            sig[3]=0;sig[4]=0;sig[5]=0;sig[6]=checks;sig[1]=99;sig[0]=0x43505246u;for(;;)__asm__ volatile("nop");
        }
        CHECK(video_capture_validate_completion(&e,&a)==0,0x20);
        CHECK(e.completed.raw_crc==fixture_raw_crc[i]&&e.completed.preview_crc==fixture_preview_crc[i],0x21);
        CHECK(video_frame_pool_capture_done(&pool,&a.id,1)==0,0x22);
        CHECK(video_capture_ack(&ci,e.pending&3u)==0,0x23);
        { uint32_t budget=100000;while(!(*(volatile uint32_t *)(VCAP_MMIO_BASE+0xc)&0x100)&&--budget){}CHECK(budget,0x24); }
        CHECK(video_capture_rearm(&ci)==0,0x25);result_ready(&a.id);
        CHECK(video_frame_pool_present(&pool,&di,&record,0,100+i*4,0)==0,0x26);
        await(VDISP_BASE,i?3:1);CHECK(video_frame_pool_poll_display(&pool,&di)==0,0x27);full_raster();
        if(!i)for(j=0;j<3;++j) {
            uint32_t mask=video_frame_pool_free_mask(&pool);sig[1]=20+j;
            CHECK(video_frame_pool_present(&pool,&di,&record,modes[j],101+j,1)==0,0x30+j);
            await(VDISP_BASE,1);CHECK(video_frame_pool_poll_display(&pool,&di)==0,0x34+j);full_raster();
            CHECK(video_frame_pool_free_mask(&pool)==mask,0x38+j);
        }
    }
    CHECK(pool.stats.allocated==2&&pool.stats.captured==2&&pool.stats.display_commits==2&&pool.stats.mode_commits==3&&pool.stats.releases==1&&!pool.error,0x50);
    sig[3]=pool.stats.captured;sig[4]=pool.stats.mode_commits;sig[5]=pool.stats.releases;sig[6]=checks;sig[1]=99;sig[0]=0x43505246u;
    for(;;)__asm__ volatile("nop");
}
