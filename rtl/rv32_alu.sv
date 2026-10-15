// 组合整数 ALU。移位量固定截取低 5 位，比较显式区分有/无符号。
module rv32_alu (
    input  logic [3:0]  op,
    input  logic [31:0] a, b,
    output logic [31:0] result
);
    always_comb begin
        case (op)
            4'd0: result = a + b;
            4'd1: result = a - b;
            4'd2: result = a << b[4:0];
            4'd3: result = {31'b0, $signed(a) < $signed(b)};
            4'd4: result = {31'b0, a < b};
            4'd5: result = a ^ b;
            4'd6: result = a >> b[4:0];
            4'd7: result = $signed(a) >>> b[4:0];
            4'd8: result = a | b;
            4'd9: result = a & b;
            default: result = 32'b0;
        endcase
    end
endmodule
