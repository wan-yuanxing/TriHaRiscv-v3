// Native compiled simulation of the unchanged scalar RTL; no internal access.
#include "Vnpu_scalar_conv.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

struct Segment {
    uint32_t base;
    size_t logical;
    std::vector<uint8_t> bytes;
    Segment(uint32_t address, size_t length, const std::string& file, bool fill = false)
        : base(address), logical(length), bytes((length + 15) & ~size_t(15), 0) {
        require(length > 0 && length <= 8 * 1024 * 1024, "invalid segment length");
        if (fill) {
            std::fill(bytes.begin(), bytes.end(), 0xa5);
            return;
        }
        std::ifstream stream(file, std::ios::binary | std::ios::ate);
        require(bool(stream), "cannot open " + file);
        require(stream.tellg() == std::streamoff(length), "file size mismatch " + file);
        stream.seekg(0);
        stream.read(reinterpret_cast<char*>(bytes.data()), length);
        require(bool(stream), "short read " + file);
    }
    bool line(uint32_t address) const {
        return address >= base && uint64_t(address) + 16 <= uint64_t(base) + bytes.size();
    }
};

struct Request {
    bool valid = false, write = false;
    uint32_t address = 0;
    uint16_t strobes = 0;
    std::array<uint8_t, 16> data{};
};

int main(int argc, char** argv) {
    try {
        require(argc == 5, "usage: npu_layer <case-dir> <max-cycles> <actual.bin> <corrupt-0/1>");
        const std::string directory(argv[1]);
        const uint64_t maximum = std::stoull(argv[2]);
        const bool corrupt = std::string(argv[4]) == "1";
        require(maximum > 0, "invalid cycle limit");
        std::array<uint32_t, 32> cfg{};
        std::ifstream config(directory + "/config.hex");
        for (auto& word : cfg) require(bool(config >> std::hex >> word), "config requires 32 words");
        std::string extra;
        require(!(config >> extra), "extra config words");
        Segment input(cfg[0],cfg[17],directory+"/input.bin");
        Segment weight(cfg[1],cfg[18],directory+"/weight.bin");
        Segment bias(cfg[2],cfg[19],directory+"/bias.bin");
        Segment requant(cfg[3],cfg[20],directory+"/requant.bin");
        Segment expected(cfg[4],cfg[21],directory+"/expected.bin");
        Segment output(cfg[4],cfg[21],"",true);
        std::vector<uint8_t> coverage(cfg[21],0);
        std::array<Segment*,4> readable{{&input,&weight,&bias,&requant}};
        std::unique_ptr<VerilatedContext> context(new VerilatedContext);
        context->randReset(0);
        std::unique_ptr<Vnpu_scalar_conv> dut(new Vnpu_scalar_conv(context.get()));
        dut->clk_i=0;dut->rst_ni=0;dut->start_i=0;
        dut->mem_req_ready_i=0;dut->mem_rsp_valid_i=0;dut->mem_rsp_error_i=0;
        for(int i=0;i<4;++i)dut->mem_rsp_rdata_i[i]=0;
        dut->cfg_input_base_i=cfg[0];dut->cfg_weight_base_i=cfg[1];
        dut->cfg_bias_base_i=cfg[2];dut->cfg_requant_base_i=cfg[3];dut->cfg_output_base_i=cfg[4];
        dut->cfg_input_width_i=cfg[5];dut->cfg_input_height_i=cfg[6];
        dut->cfg_input_channels_i=cfg[7];dut->cfg_output_channels_i=cfg[8];
        dut->cfg_output_width_i=cfg[9];dut->cfg_output_height_i=cfg[10];
        dut->cfg_kernel_i=cfg[11];dut->cfg_stride_i=cfg[12];dut->cfg_padding_i=cfg[13];
        dut->cfg_depthwise_i=cfg[14];dut->cfg_input_signed_i=cfg[15];dut->cfg_output_format_i=cfg[16];
        auto tick = [&]() {
            dut->clk_i=0;dut->eval();context->timeInc(5);
            dut->clk_i=1;dut->eval();context->timeInc(5);
        };
        for(int i=0;i<4;++i)tick();
        dut->rst_ni=1;dut->start_i=1;tick();dut->start_i=0;
        Request pending;
        uint64_t cycles=0,reads=0,writes=0,written=0;
        bool corrupted=false;
        while(!dut->done_o && cycles<maximum) {
            dut->mem_req_ready_i=!pending.valid;
            dut->mem_rsp_valid_i=pending.valid;
            dut->mem_rsp_error_i=0;
            if(pending.valid) {
                require((pending.address&15)==0,"unaligned memory request");
                if(pending.write) {
                    require(output.line(pending.address),"write outside output");
                    require(pending.strobes!=0,"empty output strobes");
                    const unsigned element_bytes=cfg[16]==3?2:1;
                    unsigned first=0;
                    while(!(pending.strobes&(1u<<first)))++first;
                    require(first+element_bytes<=16 && first%element_bytes==0 &&
                            pending.strobes==(((1u<<element_bytes)-1)<<first),
                            "invalid element write strobes");
                    const size_t offset=pending.address-output.base;
                    for(int lane=0;lane<16;++lane)if(pending.strobes&(1u<<lane)) {
                        const size_t index=offset+lane;
                        require(index<output.logical,"write into output padding");
                        require(!coverage[index],"duplicate output byte");
                        uint8_t value=pending.data[lane];
                        if(corrupt&&!corrupted){value^=1;corrupted=true;}
                        require(value==expected.bytes[index],"output mismatch at byte "+std::to_string(index));
                        output.bytes[index]=value;coverage[index]=1;++written;
                    }
                    ++writes;
                } else {
                    Segment* segment=nullptr;
                    for(auto candidate:readable)if(candidate->line(pending.address)) {
                        require(segment==nullptr,"overlapping readable segments");segment=candidate;
                    }
                    require(segment!=nullptr,"read outside source segments");
                    const size_t offset=pending.address-segment->base;
                    for(int word=0;word<4;++word) {
                        uint32_t value=0;
                        for(int byte=0;byte<4;++byte)value|=uint32_t(segment->bytes[offset+word*4+byte])<<(8*byte);
                        dut->mem_rsp_rdata_i[word]=value;
                    }
                    ++reads;
                }
            }
            dut->clk_i=0;dut->eval();context->timeInc(5);
            Request next;
            if(dut->mem_req_valid_o&&dut->mem_req_ready_i) {
                next.valid=true;next.write=dut->mem_req_write_o;next.address=dut->mem_req_addr_o;
                next.strobes=dut->mem_req_wstrb_o;
                for(int lane=0;lane<16;++lane)next.data[lane]=(dut->mem_req_wdata_o[lane/4]>>(8*(lane%4)))&255;
            }
            dut->clk_i=1;dut->eval();context->timeInc(5);
            pending=next;++cycles;
            require(!context->gotFinish(),"RTL ended before layer completion");
        }
        require(dut->done_o,"layer timeout");
        require(!dut->error_o,"RTL error code "+std::to_string(dut->error_code_o));
        require(!dut->busy_o&&!pending.valid,"completion before memory response");
        require(written==output.logical,"missing output bytes");
        std::ofstream actual(argv[3],std::ios::binary);
        actual.write(reinterpret_cast<const char*>(output.bytes.data()),output.logical);
        require(bool(actual),"cannot write actual output");
        actual.close();dut->final();
        std::cout<<"NPU_LAYER_PASS cycles="<<cycles<<" compute="<<dut->compute_cycles_o
                 <<" reads="<<reads<<" writes="<<writes<<" bytes="<<written<<"\n";
        return 0;
    } catch(const std::exception& error) {
        std::cerr<<"NPU_LAYER_FAIL "<<error.what()<<"\n";
        return 2;
    }
}
