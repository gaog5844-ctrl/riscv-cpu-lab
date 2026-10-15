#include "Vrv32_core.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include <array>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

constexpr uint32_t BASE = 0x80000000u;
constexpr size_t RAM_SIZE = 1024 * 1024;
struct Transaction {
    bool valid = false;
    uint64_t due = 0;
    uint32_t address = 0, data = 0;
    uint8_t strobe = 0;
};
int main(int argc, char** argv) {
    try {
        std::string image, output="build/trace.csv", wave, summary="build/stats.json";
        unsigned latency=1;
        uint64_t limit=1000000;
        bool prediction=true;
        for(int i=1;i<argc;i++) {
            std::string arg=argv[i];
            auto value=[&]() -> std::string {
                if(++i>=argc) throw std::runtime_error("missing argument for "+arg);
                return argv[i];
            };
            if(arg=="--image") image=value();
            else if(arg=="--trace") output=value();
            else if(arg=="--stats") summary=value();
            else if(arg=="--wave") wave=value();
            else if(arg=="--latency") latency=std::stoul(value());
            else if(arg=="--limit") limit=std::stoull(value());
            else if(arg=="--no-predict") prediction=false;
            else throw std::runtime_error("unknown argument: "+arg);
        }
        if(image.empty() || latency<1) throw std::runtime_error("--image required, latency must be >=1");
        std::vector<uint8_t> mem(RAM_SIZE,0);
        std::ifstream input(image,std::ios::binary|std::ios::ate);
        if(!input || input.tellg()<0 || uint64_t(input.tellg())>RAM_SIZE) throw std::runtime_error("invalid image");
        auto bytes=static_cast<std::streamsize>(input.tellg());
        input.seekg(0); input.read(reinterpret_cast<char*>(mem.data()),bytes);
        std::ofstream trace(output);
        if(!trace) throw std::runtime_error("cannot open trace");
        trace<<"cycle,pc,insn,npc,rd,data,trap,cause,tval,mem_addr,mem_data,mem_wstrb\n";
        auto valid_addr=[](uint32_t addr) {return addr>=BASE && uint64_t(addr-BASE)+4<=RAM_SIZE;};
        auto read=[&](uint32_t addr) -> uint32_t {
            if(addr==0x10000004u) return 0; // 仿真 GPIO 输入
            if(!valid_addr(addr)) return 0;
            size_t n=addr-BASE;
            return uint32_t(mem[n])|(uint32_t(mem[n+1])<<8)|(uint32_t(mem[n+2])<<16)|(uint32_t(mem[n+3])<<24);
        };
        auto write=[&](const Transaction& t) {
            if(t.address==0x10000000u && (t.strobe&1)) {std::cout<<char(t.data&255);return;}
            if(t.address==0x10000004u) return;
            if(!valid_addr(t.address)) return;
            for(unsigned n=0;n<4;n++) if(t.strobe&(1u<<n)) mem[t.address-BASE+n]=(t.data>>(8*n))&255;
        };
        auto context=std::make_unique<VerilatedContext>();
        context->commandArgs(argc,argv);
        if(!wave.empty()) context->traceEverOn(true);
        auto top=std::make_unique<Vrv32_core>(context.get());
        std::unique_ptr<VerilatedFstC> fst;
        if(!wave.empty()) {
            fst=std::make_unique<VerilatedFstC>();
            top->trace(fst.get(),99); fst->open(wave.c_str());
        }
        auto edge=[&](bool high) {
            top->clk=high; top->eval();
            if(fst) fst->dump(context->time());
            context->timeInc(1);
        };
        top->reset=1; top->predictor_enable=prediction;
        top->i_req_ready=0; top->i_rsp_valid=0; top->i_rsp_data=0; top->i_rsp_error=0;
        top->d_req_ready=0; top->d_rsp_valid=0; top->d_rsp_data=0; top->d_rsp_error=0;
        top->fence_ready=1;
        for(int n=0;n<3;n++) {edge(false);edge(true);}
        top->reset=0;
        Transaction it,dt;
        std::array<uint32_t,32> registers{};
        uint64_t commits=0;
        uint32_t last_cause=0,last_tval=0,last_pc=0;
        for(uint64_t cycle=0;cycle<limit && !top->halted;cycle++) {
            top->clk=0;
            top->i_rsp_valid=it.valid && it.due<=cycle;
            top->i_rsp_data=read(it.address);
            top->i_rsp_error=it.valid && !valid_addr(it.address);
            top->d_rsp_valid=dt.valid && dt.due<=cycle;
            top->d_rsp_data=read(dt.address);
            top->d_rsp_error=dt.valid && !valid_addr(dt.address) &&
                dt.address!=0x10000000u && dt.address!=0x10000004u;
            top->i_req_ready=!it.valid;
            top->d_req_ready=!dt.valid;
            top->eval();
            const bool ia=top->i_rsp_valid && top->i_rsp_ready;
            const bool da=top->d_rsp_valid && top->d_rsp_ready;
            // 同周期消耗旧响应并接收新请求，仍保持最多一个在途事务。
            if(ia) top->i_req_ready=1;
            if(da) top->d_req_ready=1;
            top->eval();
            const bool ir=top->i_req_valid && top->i_req_ready;
            const bool dr=top->d_req_valid && top->d_req_ready;
            Transaction next_i{true,cycle+latency,top->i_req_addr,0,0};
            Transaction next_d{true,cycle+latency,top->d_req_addr,top->d_req_wdata,top->d_req_wstrb};
            if(top->commit_valid) {
                trace<<std::dec<<cycle<<','<<std::hex<<top->commit_pc<<','<<top->commit_insn<<','
                     <<top->commit_next_pc<<','<<unsigned(top->commit_rd)<<','<<top->commit_data<<','
                     <<unsigned(top->commit_trap)<<','<<top->commit_cause<<','<<top->commit_tval<<','
                     <<top->commit_mem_addr<<','<<top->commit_mem_data<<','<<unsigned(top->commit_mem_wstrb)<<'\n';
                if(!top->commit_trap) {
                    commits++;
                    if(top->commit_rd) registers[top->commit_rd]=top->commit_data;
                } else {
                    last_cause=top->commit_cause; last_tval=top->commit_tval; last_pc=top->commit_pc;
                }
            }
            edge(false); edge(true);
            if(ia) it.valid=false;
            if(da) {if(!top->reset) write(dt);dt.valid=false;}
            if(ir) it=next_i;
            if(dr) dt=next_d;
        }
        top->final();
        if(fst) fst->close();
        std::ofstream stats(summary);
        if(!stats) throw std::runtime_error("cannot open summary");
        stats<<"{\n\"halted\":"<<(top->halted?"true":"false")
             <<",\"cycles\":"<<top->cycles<<",\"retired\":"<<commits
             <<",\"stalls\":"<<top->stalls<<",\"load_stalls\":"<<top->load_stalls
             <<",\"mispredictions\":"<<top->mispredictions<<",\"memory_latency\":"<<latency
             <<",\"trap_cause\":"<<last_cause<<",\"trap_tval\":"<<last_tval
             <<",\"trap_pc\":"<<last_pc<<",\"a0\":"<<registers[10]<<"\n}\n";
        if(!top->halted) throw std::runtime_error("CPU timeout");
        std::cout<<"HALTED cycles="<<top->cycles<<" retired="<<commits<<" trap="<<last_cause<<"\n";
        return 0;
    } catch(const std::exception& e) {
        std::cerr<<"ERROR: "<<e.what()<<"\n";
        return 1;
    }
}
