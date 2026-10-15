// 阻塞式 1KB D-cache：16 组 x 2 路 x 8 个 32 位字。
// 一次接受一个 CPU 请求；下游一次传输一个字，响应必须晚于请求接受沿。
module rv32_dcache (
    input logic clk,reset,enable,
    input logic cpu_req_valid,
    output logic cpu_req_ready,
    input logic [31:0] cpu_req_addr,cpu_req_wdata,
    input logic [3:0] cpu_req_wstrb,
    output logic cpu_rsp_valid,
    input logic cpu_rsp_ready,
    output logic [31:0] cpu_rsp_data,
    output logic cpu_rsp_error,
    output logic mem_req_valid,
    input logic mem_req_ready,
    output logic [31:0] mem_req_addr,mem_req_wdata,
    output logic [3:0] mem_req_wstrb,
    input logic mem_rsp_valid,
    output logic mem_rsp_ready,
    input logic [31:0] mem_rsp_data,
    input logic mem_rsp_error,
    input logic flush_valid,
    output logic flush_ready,flush_error,
    output logic [31:0] flush_error_addr,
    output logic [63:0] hits,misses,writebacks
);
    typedef enum logic [3:0] {
        IDLE,LOOKUP,WB_REQ,WB_WAIT,REFILL_REQ,REFILL_WAIT,
        BYPASS_REQ,BYPASS_WAIT,RESPONSE,SCAN,FLUSH_DONE
    } state_t;
    state_t state;
    logic [31:0] data[0:1][0:15][0:7];
    logic [22:0] tags[0:1][0:15];
    logic valid[0:1][0:15],dirty[0:1][0:15],lru[0:15];
    logic [31:0] address,write_data,response_data;
    logic [3:0] strobe;
    logic response_error,victim,refilled,flushing;
    logic [3:0] victim_set;
    logic [2:0] word_index;
    logic [5:0] scan_index;
    wire [3:0] set_index=address[8:5];
    wire [2:0] offset=address[4:2];
    wire [22:0] request_tag=address[31:9];
    wire hit0=valid[0][set_index] && tags[0][set_index]==request_tag;
    wire hit1=valid[1][set_index] && tags[1][set_index]==request_tag;
    wire hit_way=!hit0;
    wire replace_way=!valid[0][set_index] ? 1'b0 : !valid[1][set_index] ? 1'b1 : lru[set_index];
    wire [1:0] unused_address_low=address[1:0];
    assign cpu_req_ready=state==IDLE && !flush_valid;
    assign cpu_rsp_valid=state==RESPONSE;
    assign cpu_rsp_data=response_data;
    assign cpu_rsp_error=response_error;
    assign flush_ready=state==FLUSH_DONE;
    assign mem_req_valid=state==WB_REQ || state==REFILL_REQ || state==BYPASS_REQ;
    assign mem_rsp_ready=state==WB_WAIT || state==REFILL_WAIT || state==BYPASS_WAIT;
    always_comb begin
        mem_req_addr=address;
        mem_req_wdata=write_data;
        mem_req_wstrb=strobe;
        if(state==WB_REQ || state==WB_WAIT) begin
            mem_req_addr={tags[victim][victim_set],victim_set,word_index,2'b0};
            mem_req_wdata=data[victim][victim_set][word_index];
            mem_req_wstrb=4'hf;
        end else if(state==REFILL_REQ || state==REFILL_WAIT) begin
            mem_req_addr={address[31:5],word_index,2'b0};
            mem_req_wdata=0; mem_req_wstrb=0;
        end
    end
`ifndef SYNTHESIS
    always_ff @(posedge clk) if(!reset) begin
        if(state==LOOKUP) assert(!(hit0 && hit1)) else $fatal(1,"duplicate cache tags");
        for(integer s=0;s<16;s++)
            for(integer w=0;w<2;w++)
                assert(!dirty[w][s] || valid[w][s]) else $fatal(1,"invalid dirty cache line");
        if(mem_req_valid) assert(mem_req_addr[1:0]==0) else $fatal(1,"unaligned cache backend address");
    end
`endif
    always_ff @(posedge clk) begin
        if(reset) begin
            state<=IDLE; address<=0; write_data<=0; strobe<=0;
            response_data<=0; response_error<=0; victim<=0; victim_set<=0;
            word_index<=0; refilled<=0; flushing<=0; scan_index<=0;
            hits<=0; misses<=0; writebacks<=0; flush_error<=0; flush_error_addr<=0;
            for(integer s=0;s<16;s++) begin
                lru[s]<=0;
                for(integer w=0;w<2;w++) begin
                    valid[w][s]<=0; dirty[w][s]<=0; tags[w][s]<=0;
                    // 无效行的数据不读取；不复位数据阵列，便于后续映射 RAM。
                end
            end
        end else begin
            case(state)
                IDLE: begin
                    if(flush_valid) begin
                        scan_index<=0; flushing<=1; flush_error<=0; flush_error_addr<=0;
                        state<=SCAN;
                    end else if(cpu_req_valid && cpu_req_ready) begin
                        address<=cpu_req_addr; write_data<=cpu_req_wdata; strobe<=cpu_req_wstrb;
                        refilled<=0; response_error<=0; response_data<=0; flushing<=0;
                        // RAM 区域可缓存；MMIO 和越界访问永远旁路。
                        state<=(enable && cpu_req_addr[31:20]==12'h800) ? LOOKUP : BYPASS_REQ;
                    end
                end
                LOOKUP: begin
                    if(hit0 || hit1) begin
                        response_data<=data[hit_way][set_index][offset];
                        if(strobe!=0) begin
                            for(integer b=0;b<4;b++)
                                if(strobe[b]) data[hit_way][set_index][offset][b*8+:8]<=write_data[b*8+:8];
                            dirty[hit_way][set_index]<=1;
                        end
                        lru[set_index]<=!hit_way;
                        if(!refilled) hits<=hits+1;
                        state<=RESPONSE;
                    end else begin
                        misses<=misses+1; refilled<=1;
                        victim<=replace_way; victim_set<=set_index; word_index<=0;
                        if(valid[replace_way][set_index] && dirty[replace_way][set_index]) begin
                            writebacks<=writebacks+1; state<=WB_REQ;
                        end else begin
                            valid[replace_way][set_index]<=0;
                            state<=REFILL_REQ;
                        end
                    end
                end
                WB_REQ: if(mem_req_ready) state<=WB_WAIT;
                WB_WAIT: if(mem_rsp_valid) begin
                    if(mem_rsp_error) begin
                        if(flushing) begin
                            flush_error<=1; flush_error_addr<=mem_req_addr; state<=FLUSH_DONE;
                        end else begin response_error<=1; state<=RESPONSE; end
                    end else if(word_index==7) begin
                        dirty[victim][victim_set]<=0; word_index<=0;
                        if(flushing) begin scan_index<=scan_index+1; state<=SCAN; end
                        else begin valid[victim][victim_set]<=0; state<=REFILL_REQ; end
                    end else begin word_index<=word_index+1'b1; state<=WB_REQ; end
                end
                REFILL_REQ: if(mem_req_ready) state<=REFILL_WAIT;
                REFILL_WAIT: if(mem_rsp_valid) begin
                    if(mem_rsp_error) begin response_error<=1; state<=RESPONSE; end
                    else begin
                        data[victim][victim_set][word_index]<=mem_rsp_data;
                        if(word_index==7) begin
                            valid[victim][victim_set]<=1; dirty[victim][victim_set]<=0;
                            tags[victim][victim_set]<=request_tag; state<=LOOKUP;
                        end else begin word_index<=word_index+1'b1; state<=REFILL_REQ; end
                    end
                end
                BYPASS_REQ: if(mem_req_ready) state<=BYPASS_WAIT;
                BYPASS_WAIT: if(mem_rsp_valid) begin
                    response_data<=mem_rsp_data; response_error<=mem_rsp_error; state<=RESPONSE;
                end
                RESPONSE: if(cpu_rsp_ready) state<=IDLE;
                SCAN: begin
                    if(scan_index==32) state<=FLUSH_DONE;
                    else if(valid[scan_index[4]][scan_index[3:0]] && dirty[scan_index[4]][scan_index[3:0]]) begin
                        victim<=scan_index[4]; victim_set<=scan_index[3:0]; word_index<=0;
                        writebacks<=writebacks+1; state<=WB_REQ;
                    end else scan_index<=scan_index+1'b1;
                end
                FLUSH_DONE: begin flushing<=0; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
