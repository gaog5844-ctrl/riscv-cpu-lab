// 独立标量参考语义；不链接 RTL，也不复用硬件实现。
#include <riscv/extension.h>
#include <cstdint>

static reg_t execute_xsimd(processor_t* p, insn_t insn, reg_t pc) {
    auto* state=p->get_state();
    const uint32_t a=uint32_t(state->XPR[insn.rs1()]);
    const uint32_t b=uint32_t(state->XPR[insn.rs2()]);
    uint32_t value=0;
    switch(insn.funct3()) {
        case 0:
            for(unsigned lane=0;lane<4;lane++)
                value |= (((a>>(8*lane))+(b>>(8*lane)))&255u)<<(8*lane);
            break;
        case 1:
            for(unsigned lane=0;lane<2;lane++)
                value |= (((a>>(16*lane))+(b>>(16*lane)))&65535u)<<(16*lane);
            break;
        case 2: {
            int32_t sum=0;
            for(unsigned lane=0;lane<4;lane++) {
                const int32_t x=int8_t((a>>(8*lane))&255u);
                const int32_t y=int8_t((b>>(8*lane))&255u);
                sum+=x*y;
            }
            value=uint32_t(sum);
            break;
        }
        default: throw std::runtime_error("unregistered Xsimd operation");
    }
    const reg_t result=reg_t(int64_t(int32_t(value)));
    state->XPR.write(insn.rd(),result);
    if(p->get_log_commits_enabled() && insn.rd()!=0)
        state->log_reg_write[insn.rd()<<4]={result,0};
    return reg_t(int64_t(int32_t(uint32_t(pc)+4)));
}
class xsimd_t final : public extension_t {
public:
    const char* name() const override {return "xsimd";}
    std::vector<insn_desc_t> get_instructions(const processor_t&) override {
        std::vector<insn_desc_t> out;
        for(unsigned f=0;f<3;f++)
            out.push_back({0x0b|(f<<12),0xfe00707f,
                execute_xsimd,execute_xsimd,execute_xsimd,execute_xsimd,
                execute_xsimd,execute_xsimd,execute_xsimd,execute_xsimd});
        return out;
    }
    std::vector<disasm_insn_t*> get_disasms(const processor_t* =nullptr) override {return {};}
};
REGISTER_EXTENSION(xsimd, [](){return new xsimd_t;})
