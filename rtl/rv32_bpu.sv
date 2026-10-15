// 64 项直接映射 BTB + 两位计数器；比较完整高位 PC 标签。
module rv32_bpu (
    input logic clk, reset, enable,
    input logic [31:0] query_pc,
    output logic [31:0] predicted_pc,
    input logic update,
    input logic [31:0] update_pc, target_pc,
    input logic taken, unconditional
);
    logic valid [0:63];
    logic [23:0] tag [0:63];
    logic [31:0] target [0:63];
    logic [1:0] counter [0:63];
    logic jump [0:63];
    wire [5:0] qi=query_pc[7:2], ui=update_pc[7:2];
    wire [1:0] unused_query_low=query_pc[1:0], unused_update_low=update_pc[1:0];
    always_comb begin
        predicted_pc=query_pc+4;
        if(enable && valid[qi] && tag[qi]==query_pc[31:8] && (jump[qi] || counter[qi][1]))
            predicted_pc=target[qi];
    end
    always_ff @(posedge clk) begin
        if(reset) begin
            for(integer i=0;i<64;i++) begin
                valid[i]<=0; tag[i]<=0; target[i]<=0; counter[i]<=1; jump[i]<=0;
            end
        end else if(update && enable) begin
            valid[ui]<=1; tag[ui]<=update_pc[31:8]; target[ui]<=target_pc; jump[ui]<=unconditional;
            if(!valid[ui] || tag[ui]!=update_pc[31:8]) counter[ui]<=taken ? 2 : 1;
            else if(taken && counter[ui]!=3) counter[ui]<=counter[ui]+1'b1;
            else if(!taken && counter[ui]!=0) counter[ui]<=counter[ui]-1'b1;
        end
    end
endmodule
