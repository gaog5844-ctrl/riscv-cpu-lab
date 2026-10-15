// 32 步恢复余数除法。启动时锁存操作数；运算期间由 EX 阶段背压。
// RISC-V 除零/INT_MIN 除 -1 均返回规范规定值，不产生算术异常。
module rv32_div (
    input  logic clk, reset, start, cancel,
    input  logic is_signed, want_remainder,
    input  logic [31:0] dividend, divisor,
    output logic busy, done,
    output logic [31:0] result
);
    logic [31:0] quotient, denominator;
    logic [31:0] remainder;
    logic [5:0] count;
    logic negate_q, negate_r, select_r;
    logic [32:0] shifted, reduced;
    // 恢复除法的不变式保证减法后余数小于 32 位除数。
    wire unused_reduced_carry = reduced[32];
    logic [31:0] next_q;
    always_comb begin
        shifted = {remainder, quotient[31]};
        reduced = shifted;
        next_q = {quotient[30:0], 1'b0};
        if (shifted >= {1'b0, denominator}) begin
            reduced = shifted - {1'b0, denominator};
            next_q[0] = 1'b1;
        end
    end
    always_ff @(posedge clk) begin
        if (reset || cancel) begin
            busy <= 0;
            done <= 0;
            result <= 0;
            quotient <= 0;
            denominator <= 0;
            remainder <= 0;
            count <= 0;
            negate_q <= 0;
            negate_r <= 0;
            select_r <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                if (divisor == 0) begin
                    result <= want_remainder ? dividend : 32'hffffffff;
                    done <= 1;
                end else if (is_signed && dividend == 32'h80000000 && divisor == 32'hffffffff) begin
                    result <= want_remainder ? 0 : 32'h80000000;
                    done <= 1;
                end else begin
                    quotient <= (is_signed && dividend[31]) ? -dividend : dividend;
                    denominator <= (is_signed && divisor[31]) ? -divisor : divisor;
                    remainder <= 0;
                    negate_q <= is_signed && (dividend[31] ^ divisor[31]);
                    negate_r <= is_signed && dividend[31];
                    select_r <= want_remainder;
                    count <= 0;
                    busy <= 1;
                end
            end else if (busy) begin
                remainder <= reduced[31:0];
                quotient <= next_q;
                count <= count + 1;
                if (count == 31) begin
                    result <= select_r ? (negate_r ? -reduced[31:0] : reduced[31:0])
                                       : (negate_q ? -next_q : next_q);
                    busy <= 0;
                    done <= 1;
                end
            end
        end
    end
endmodule
