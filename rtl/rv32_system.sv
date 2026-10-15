// 与 FPGA 器件无关的核 + D-cache 封装；仿真端提供存储器和 MMIO。
module rv32_system #(
    parameter bit ENABLE_SIMD=1
) (
    input logic clk,reset,predictor_enable,cache_enable,
    output logic i_req_valid,
    input logic i_req_ready,
    output logic [31:0] i_req_addr,
    input logic i_rsp_valid,
    output logic i_rsp_ready,
    input logic [31:0] i_rsp_data,
    input logic i_rsp_error,
    output logic d_req_valid,
    input logic d_req_ready,
    output logic [31:0] d_req_addr,d_req_wdata,
    output logic [3:0] d_req_wstrb,
    input logic d_rsp_valid,
    output logic d_rsp_ready,
    input logic [31:0] d_rsp_data,
    input logic d_rsp_error,
    output logic commit_valid,commit_trap,
    output logic [31:0] commit_pc,commit_insn,commit_next_pc,
    output logic [4:0] commit_rd,
    output logic [31:0] commit_data,commit_cause,commit_tval,
    output logic [31:0] commit_mem_addr,commit_mem_data,
    output logic [3:0] commit_mem_wstrb,
    output logic halted,
    output logic [63:0] cycles,retired,stalls,load_stalls,mispredictions,
    output logic [63:0] cache_hits,cache_misses,cache_writebacks
);
    logic cpu_req_valid,cpu_req_ready,cpu_rsp_valid,cpu_rsp_ready,cpu_rsp_error;
    logic [31:0] cpu_req_addr,cpu_req_wdata,cpu_rsp_data;
    logic [3:0] cpu_req_wstrb;
    logic fence_valid,fence_ready,fence_error;
    logic [31:0] fence_error_addr;
    rv32_core #(.ENABLE_SIMD(ENABLE_SIMD)) core (
        .d_req_valid(cpu_req_valid),.d_req_ready(cpu_req_ready),
        .d_req_addr(cpu_req_addr),.d_req_wdata(cpu_req_wdata),.d_req_wstrb(cpu_req_wstrb),
        .d_rsp_valid(cpu_rsp_valid),.d_rsp_ready(cpu_rsp_ready),
        .d_rsp_data(cpu_rsp_data),.d_rsp_error(cpu_rsp_error),.*
    );
    rv32_dcache cache (
        .enable(cache_enable),
        .mem_req_valid(d_req_valid),.mem_req_ready(d_req_ready),
        .mem_req_addr(d_req_addr),.mem_req_wdata(d_req_wdata),.mem_req_wstrb(d_req_wstrb),
        .mem_rsp_valid(d_rsp_valid),.mem_rsp_ready(d_rsp_ready),
        .mem_rsp_data(d_rsp_data),.mem_rsp_error(d_rsp_error),
        .flush_valid(fence_valid),.flush_ready(fence_ready),.flush_error(fence_error),.flush_error_addr(fence_error_addr),
        .hits(cache_hits),.misses(cache_misses),.writebacks(cache_writebacks),.*
    );
endmodule
