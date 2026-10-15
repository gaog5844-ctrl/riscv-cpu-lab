// 自定义 Xsimd：使用整数寄存器，每个 lane 的边界由位位置定义。
// xdot8 为 signed INT8 点积，结果是 INT32，不读取旧 rd。
module rv32_simd (
    input  logic [1:0] op,
    input  logic [31:0] a, b,
    output logic [31:0] result
);
    logic signed [15:0] product [0:3];
    integer lane;
    always_comb begin
        for (integer j=0; j<4; j=j+1)
            product[j] = $signed(a[j*8 +: 8]) * $signed(b[j*8 +: 8]);
        result = 0;
        case (op)
            2'd0:
                for (lane=0; lane<4; lane=lane+1)
                    result[lane*8 +: 8] = a[lane*8 +: 8] + b[lane*8 +: 8];
            2'd1:
                for (lane=0; lane<2; lane=lane+1)
                    result[lane*16 +: 16] = a[lane*16 +: 16] + b[lane*16 +: 16];
            2'd2:
                for (lane=0; lane<4; lane=lane+1)
                    result = result + {{16{product[lane][15]}}, product[lane]};
            default: result = 0;
        endcase
    end
endmodule
