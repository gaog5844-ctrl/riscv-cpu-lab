// 五个有状态阶段：IF 请求/响应、ID、EX、MEM、WB。
// 所有副作用由 valid + 握手限定；后级等待向前传播，重定向丢弃旧取指响应。
module rv32_core #(
    parameter logic [31:0] RESET_PC=32'h80000000,
    parameter bit ENABLE_SIMD=1
) (
    input logic clk, reset, predictor_enable,
    output logic i_req_valid,
    input logic i_req_ready,
    output logic [31:0] i_req_addr,
    input logic i_rsp_valid,
    output logic i_rsp_ready,
    input logic [31:0] i_rsp_data,
    input logic i_rsp_error,
    output logic d_req_valid,
    input logic d_req_ready,
    output logic [31:0] d_req_addr, d_req_wdata,
    output logic [3:0] d_req_wstrb,
    input logic d_rsp_valid,
    output logic d_rsp_ready,
    input logic [31:0] d_rsp_data,
    input logic d_rsp_error,
    output logic fence_valid,
    input logic fence_ready,
    input logic fence_error,
    input logic [31:0] fence_error_addr,
    output logic commit_valid, commit_trap,
    output logic [31:0] commit_pc, commit_insn, commit_next_pc,
    output logic [4:0] commit_rd,
    output logic [31:0] commit_data, commit_cause, commit_tval,
    output logic [31:0] commit_mem_addr, commit_mem_data,
    output logic [3:0] commit_mem_wstrb,
    output logic halted,
    output logic [63:0] cycles, retired, stalls, load_stalls, mispredictions
);
    logic [31:0] regs[0:31];
    logic [31:0] fetch_pc, fetch_prediction, pending_pc, pending_prediction;
    logic pending, pending_killed, stop_fetch;
    logic id_valid, id_fault;
    logic [31:0] id_pc, id_insn, id_prediction;
    logic [4:0] dec_rs1,dec_rs2,dec_rd;
    logic dec_use1,dec_use2,dec_we,dec_bimm,dec_load,dec_store,dec_m,dec_simd,dec_fence;
    logic dec_illegal,dec_ecall,dec_ebreak;
    logic [31:0] dec_imm,id_a,id_b;
    logic [3:0] dec_alu,dec_branch;
    logic [1:0] dec_asel;
    logic [2:0] dec_mem;
    rv32_decode #(.ENABLE_SIMD(ENABLE_SIMD)) decoder(
        id_insn,dec_rs1,dec_rs2,dec_rd,dec_use1,dec_use2,dec_we,dec_imm,
        dec_alu,dec_asel,dec_bimm,dec_branch,dec_load,dec_store,dec_mem,
        dec_m,dec_simd,dec_fence,dec_illegal,dec_ecall,dec_ebreak
    );
    typedef struct packed {
        logic [31:0] pc, insn, pred, a, b, imm;
        logic [4:0] rs1,rs2,rd;
        logic use1,use2,we,bimm,load,store,m,simd,fence,trap;
        logic [31:0] cause,tval;
        logic [3:0] alu,branch;
        logic [1:0] asel;
        logic [2:0] mem;
    } ex_t;
    typedef struct packed {
        logic [31:0] pc,insn,npc,value,store_data,mem_addr,cause,tval;
        logic [4:0] rd;
        logic we,load,store,fence,trap;
        logic [2:0] mem;
    } mem_t;
    typedef struct packed {
        logic [31:0] pc,insn,npc,value,addr,store_data,cause,tval;
        logic [4:0] rd;
        logic [3:0] strb;
        logic we,trap;
    } wb_t;
    ex_t e;
    mem_t m;
    wb_t w;
    logic e_valid,m_valid,w_valid,m_sent;
    logic [31:0] ea,eb,alu_a,alu_b,alu_result,simd_result,ex_value;
    logic [31:0] ex_target,ex_npc,ex_cause,ex_tval,load_value,shifted_load;
    logic ex_taken,ex_trap,ex_is_div,ex_complete,ex_fire,ex_allow,id_fire,load_hazard;
    logic m_done,m_fire,mem_error,redirect,flush_front,wb_trap;
    logic [3:0] m_strb;
    logic [31:0] m_write_data,m_value;
    logic div_busy,div_done,div_start,div_started,div_saved,div_operands_ready;
    logic [31:0] div_result,div_saved_result;
    logic signed [32:0] mul_a,mul_b;
    logic signed [65:0] mul_result;
    wire [1:0] unused_mul_top=mul_result[65:64];
    wire [1:0] unused_id_low=id_pc[1:0];
    rv32_alu alu(e.alu,alu_a,alu_b,alu_result);
    rv32_simd simd(e.insn[13:12],ea,eb,simd_result);
    rv32_div divider(
        clk,reset,div_start,mem_error || wb_trap,
        !e.insn[12],e.insn[13],ea,eb,div_busy,div_done,div_result
    );
    rv32_bpu bpu(
        clk,reset,predictor_enable,fetch_pc,fetch_prediction,
        ex_fire && e.branch!=0 && !ex_trap && !mem_error,
        e.pc,ex_target,ex_taken,e.branch>=7
    );
    assign wb_trap=w_valid && w.trap;
    assign commit_valid=w_valid && !halted;
    assign commit_trap=w.trap;
    assign commit_pc=w.pc;
    assign commit_insn=w.insn;
    assign commit_next_pc=w.npc;
    assign commit_rd=(w.we && !w.trap) ? w.rd : 0;
    assign commit_data=(w.we && w.rd!=0 && !w.trap) ? w.value : 0;
    assign commit_cause=w.cause;
    assign commit_tval=w.tval;
    assign commit_mem_addr=w.addr;
    assign commit_mem_data=w.store_data;
    assign commit_mem_wstrb=w.strb;

    // WB -> ID 旁路，避免同一时钟沿读到旧寄存器值。
    always_comb begin
        id_a=dec_rs1==0 ? 0 : regs[dec_rs1];
        id_b=dec_rs2==0 ? 0 : regs[dec_rs2];
        if(w_valid && w.we && !w.trap && w.rd!=0) begin
            if(w.rd==dec_rs1) id_a=w.value;
            if(w.rd==dec_rs2) id_b=w.value;
        end
    end
    // MEM 优先于 WB：选择程序顺序中最近的生产者。
    always_comb begin
        ea=e.a; eb=e.b;
        if(w_valid && w.we && !w.trap && w.rd!=0) begin
            if(e.use1 && e.rs1==w.rd) ea=w.value;
            if(e.use2 && e.rs2==w.rd) eb=w.value;
        end
        if(m_valid && m.we && !m.trap && m.rd!=0 && m_done && !mem_error) begin
            if(e.use1 && e.rs1==m.rd) ea=m_value;
            if(e.use2 && e.rs2==m.rd) eb=m_value;
        end
        alu_a=e.asel==1 ? e.pc : e.asel==2 ? 0 : ea;
        alu_b=e.bimm ? e.imm : eb;
        mul_a=$signed({(e.insn[14:12]==1 || e.insn[14:12]==2) && ea[31],ea});
        mul_b=$signed({e.insn[14:12]==1 && eb[31],eb});
        mul_result=mul_a*mul_b;
    end
    always_comb begin
        ex_value=alu_result;
        if(e.m) begin
            case(e.insn[14:12])
                0: ex_value=mul_result[31:0];
                1,2,3: ex_value=mul_result[63:32];
                default: ex_value=div_saved ? div_saved_result : div_result;
            endcase
        end
        if(e.simd) ex_value=simd_result;
        if(e.branch>=7) ex_value=e.pc+4;
        ex_taken=0;
        case(e.branch)
            1: ex_taken=ea==eb;
            2: ex_taken=ea!=eb;
            3: ex_taken=$signed(ea)<$signed(eb);
            4: ex_taken=$signed(ea)>=$signed(eb);
            5: ex_taken=ea<eb;
            6: ex_taken=ea>=eb;
            7,8: ex_taken=1;
            default: ex_taken=0;
        endcase
        ex_target=e.branch==8 ? ((ea+e.imm)&32'hfffffffe) : e.pc+e.imm;
        ex_npc=ex_taken ? ex_target : e.pc+4;
        ex_trap=e.trap; ex_cause=e.cause; ex_tval=e.tval;
        if(!e.trap && ex_taken && ex_target[1:0]!=0) begin
            ex_trap=1; ex_cause=0; ex_tval=ex_target;
        end
        if(!e.trap && (e.load || e.store) &&
           ((e.mem[1:0]==1 && alu_result[0]) || (e.mem[1:0]==2 && alu_result[1:0]!=0))) begin
            ex_trap=1; ex_cause=e.store ? 6 : 4; ex_tval=alu_result;
        end
    end
    assign ex_is_div=e_valid && e.m && e.insn[14];
    // 除法器在 start 沿锁存操作数，不同于每周期重算的组合 ALU。
    // load-use 的 ID 气泡不足以覆盖任意长缓存等待：必须等 MEM 的生产者可前递。
    assign div_operands_ready=!(m_valid && m.load && !m_done && m.rd!=0 &&
                               ((e.use1 && e.rs1==m.rd) || (e.use2 && e.rs2==m.rd)));
    assign div_start=ex_is_div && div_operands_ready && !div_started && !div_busy && !wb_trap && !mem_error;
    assign ex_complete=!ex_is_div || div_saved || div_done;
    assign m_done=m.trap || (!(m.load || m.store || m.fence)) ||
                  ((m.load || m.store) && m_sent && d_rsp_valid) ||
                  (m.fence && fence_ready);
    assign m_fire=m_valid && m_done && !halted && !wb_trap;
    assign mem_error=m_fire && !m.trap &&
                     (((m.load || m.store) && d_rsp_error) || (m.fence && fence_error));
    assign ex_fire=e_valid && ex_complete && (!m_valid || m_done) && !halted && !wb_trap && !mem_error;
    assign ex_allow=!e_valid || ex_fire;
    assign load_hazard=e_valid && e.load && e.rd!=0 &&
        ((dec_use1 && dec_rs1==e.rd) || (dec_use2 && dec_rs2==e.rd));
    assign redirect=ex_fire && !ex_trap && ex_npc!=e.pred;
    assign flush_front=redirect || (ex_fire && ex_trap) || mem_error || wb_trap;
    assign id_fire=id_valid && ex_allow && !load_hazard && !flush_front && !stop_fetch && !halted;
    assign i_rsp_ready=pending && (pending_killed || !id_valid || id_fire || flush_front || stop_fetch || halted);
    assign i_req_valid=!halted && !stop_fetch && !flush_front &&
        (!pending || (i_rsp_valid && i_rsp_ready)) && (!id_valid || id_fire);
    assign i_req_addr=fetch_pc;
    assign d_req_valid=m_valid && (m.load || m.store) && !m_sent && !m.trap && !halted && !wb_trap;
    assign d_req_addr={m.mem_addr[31:2],2'b0};
    assign d_rsp_ready=m_valid && m_sent && !halted;
    assign fence_valid=m_valid && m.fence && !m.trap && !halted && !wb_trap;
    always_comb begin
        case(m.mem[1:0])
            0: m_strb=4'b0001 << m.mem_addr[1:0];
            1: m_strb=4'b0011 << m.mem_addr[1:0];
            default: m_strb=4'b1111;
        endcase
        m_write_data=m.store_data << {m.mem_addr[1:0],3'b0};
        shifted_load=d_rsp_data >> {m.mem_addr[1:0],3'b0};
        case(m.mem)
            0: load_value={{24{shifted_load[7]}},shifted_load[7:0]};
            1: load_value={{16{shifted_load[15]}},shifted_load[15:0]};
            4: load_value={24'b0,shifted_load[7:0]};
            5: load_value={16'b0,shifted_load[15:0]};
            default: load_value=shifted_load;
        endcase
        m_value=m.load ? load_value : m.value;
        d_req_wstrb=m.store ? m_strb : 0;
        d_req_wdata=m_write_data;
    end
`ifndef SYNTHESIS
    always_ff @(posedge clk) if(!reset) begin
        assert(regs[0]==0) else $fatal(1,"x0 changed");
        assert(!(m_valid && m.load && m.store)) else $fatal(1,"MEM is both load and store");
        assert(!(commit_valid && commit_trap && (commit_rd!=0 || commit_mem_wstrb!=0)))
            else $fatal(1,"faulting retirement has architectural write");
        assert(!(div_start && !div_operands_ready)) else $fatal(1,"division captured stale load operand");
        assert(!(id_fire && load_hazard)) else $fatal(1,"load-use dependency entered EX");
    end
`endif
    always_ff @(posedge clk) begin
        if(reset) begin
            for(integer r=0;r<32;r++) regs[r]<=0;
            fetch_pc<=RESET_PC; pending<=0; pending_killed<=0; pending_pc<=0; pending_prediction<=0;
            id_valid<=0; id_fault<=0; id_pc<=0; id_insn<=0; id_prediction<=0;
            e<='0; m<='0; w<='0; e_valid<=0; m_valid<=0; w_valid<=0; m_sent<=0;
            stop_fetch<=0; halted<=0; div_started<=0; div_saved<=0; div_saved_result<=0;
            cycles<=0; retired<=0; stalls<=0; load_stalls<=0; mispredictions<=0;
        end else if(!halted) begin
            cycles<=cycles+1;
            if(id_valid && !id_fire && !flush_front) stalls<=stalls+1;
            if(id_valid && load_hazard && !flush_front) load_stalls<=load_stalls+1;
            if(redirect) mispredictions<=mispredictions+1;
            if(commit_valid && !w.trap) retired<=retired+1;
            if(w_valid && w.we && !w.trap && w.rd!=0) regs[w.rd]<=w.value;
            regs[0]<=0;
            if(wb_trap) begin
                halted<=1; w_valid<=0; m_valid<=0; e_valid<=0; id_valid<=0; stop_fetch<=1;
            end else begin
                w_valid<=m_fire;
                if(m_fire) begin
                    w.pc<=m.pc; w.insn<=m.insn; w.npc<=m.npc; w.rd<=m.rd; w.we<=m.we;
                    w.value<=m_value; w.trap<=m.trap || mem_error;
                    w.cause<=mem_error ? (m.load ? 5 : 7) : m.cause;
                    w.tval<=mem_error ? (m.fence ? fence_error_addr : m.mem_addr) : m.tval;
                    w.addr<=(m.load || m.store) ? m.mem_addr : 0;
                    w.store_data<=m.store ? m_write_data : 0;
                    w.strb<=(m.store && !m.trap && !mem_error) ? m_strb : 0;
                end
                if(d_req_valid && d_req_ready) m_sent<=1;
                if(m_fire) begin m_valid<=0; m_sent<=0; end
                if(ex_fire) begin
                    m_valid<=1; m_sent<=0;
                    m.pc<=e.pc; m.insn<=e.insn; m.npc<=ex_npc; m.rd<=e.rd; m.we<=e.we;
                    m.value<=ex_value; m.store_data<=eb; m.mem_addr<=alu_result;
                    m.load<=e.load; m.store<=e.store; m.mem<=e.mem; m.fence<=e.fence;
                    m.trap<=ex_trap; m.cause<=ex_cause; m.tval<=ex_tval;
                end
                if(div_start) div_started<=1;
                if(div_done) begin div_saved<=1; div_saved_result<=div_result; end
                if(e_valid) begin e.a<=ea; e.b<=eb; end
                if(ex_fire) begin e_valid<=0; div_started<=0; div_saved<=0; end
                if(id_fire) begin
                    e_valid<=1;
                    e.pc<=id_pc; e.insn<=id_insn; e.pred<=id_prediction; e.a<=id_a; e.b<=id_b;
                    e.rs1<=dec_rs1; e.rs2<=dec_rs2; e.rd<=dec_rd; e.use1<=dec_use1; e.use2<=dec_use2;
                    e.imm<=dec_imm; e.we<=dec_we; e.alu<=dec_alu; e.asel<=dec_asel; e.bimm<=dec_bimm;
                    e.branch<=dec_branch; e.load<=dec_load; e.store<=dec_store; e.mem<=dec_mem;
                    e.m<=dec_m; e.simd<=dec_simd; e.fence<=dec_fence;
                    e.trap<=id_fault || dec_illegal || dec_ecall || dec_ebreak;
                    e.cause<=id_fault ? 1 : dec_illegal ? 2 : dec_ebreak ? 3 : dec_ecall ? 8 : 0;
                    e.tval<=id_fault ? id_pc : dec_illegal ? id_insn : 0;
                    div_started<=0; div_saved<=0;
                end
                if(id_fire) id_valid<=0;
                if(i_rsp_valid && i_rsp_ready) begin
                    pending<=0; pending_killed<=0;
                    if(!pending_killed && !flush_front && !stop_fetch) begin
                        id_valid<=1; id_pc<=pending_pc; id_prediction<=pending_prediction;
                        id_insn<=i_rsp_data; id_fault<=i_rsp_error;
                    end
                end
                if(i_req_valid && i_req_ready) begin
                    pending<=1; pending_killed<=0; pending_pc<=fetch_pc; pending_prediction<=fetch_prediction;
                    fetch_pc<=fetch_prediction;
                end
                if(flush_front) begin
                    id_valid<=0;
                    if(pending && !(i_rsp_valid && i_rsp_ready)) pending_killed<=1;
                end
                if(redirect) fetch_pc<=ex_npc;
                if((ex_fire && ex_trap) || mem_error) stop_fetch<=1;
                if(mem_error) begin e_valid<=0; div_started<=0; div_saved<=0; end
            end
        end
    end
endmodule
