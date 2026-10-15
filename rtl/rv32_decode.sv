module rv32_decode #(
    parameter bit ENABLE_SIMD = 1
) (
    input  logic [31:0] insn,
    output logic [4:0] rs1, rs2, rd,
    output logic uses_rs1, uses_rs2, rd_we,
    output logic [31:0] imm,
    output logic [3:0] alu_op,
    output logic [1:0] a_sel,
    output logic b_imm,
    output logic [3:0] branch,
    output logic mem_read, mem_write,
    output logic [2:0] mem_funct,
    output logic is_m, is_simd, fence,
    output logic illegal, ecall, ebreak
);
    logic [6:0] opcode, f7;
    logic [2:0] f3;
    assign opcode = insn[6:0];
    assign f7 = insn[31:25];
    assign f3 = insn[14:12];
    assign rs1 = insn[19:15];
    assign rs2 = insn[24:20];
    assign rd = insn[11:7];
    always_comb begin
        uses_rs1=0; uses_rs2=0; rd_we=0; imm=0; alu_op=0;
        a_sel=0; b_imm=0; branch=0; mem_read=0; mem_write=0;
        mem_funct=f3; is_m=0; is_simd=0; fence=0; illegal=0; ecall=0; ebreak=0;
        case (opcode)
            7'h37: begin // LUI
                rd_we=1; a_sel=2; b_imm=1; imm={insn[31:12],12'b0};
            end
            7'h17: begin // AUIPC
                rd_we=1; a_sel=1; b_imm=1; imm={insn[31:12],12'b0};
            end
            7'h6f: begin // JAL
                rd_we=1; branch=7;
                imm={{11{insn[31]}},insn[31],insn[19:12],insn[20],insn[30:21],1'b0};
            end
            7'h67: begin // JALR
                uses_rs1=1; rd_we=1; branch=8;
                imm={{20{insn[31]}},insn[31:20]};
                illegal=(f3!=0);
            end
            7'h63: begin
                uses_rs1=1; uses_rs2=1;
                imm={{19{insn[31]}},insn[31],insn[7],insn[30:25],insn[11:8],1'b0};
                case (f3)
                    0: branch=1;
                    1: branch=2;
                    4: branch=3;
                    5: branch=4;
                    6: branch=5;
                    7: branch=6;
                    default: illegal=1;
                endcase
            end
            7'h03: begin
                uses_rs1=1; rd_we=1; b_imm=1; mem_read=1;
                imm={{20{insn[31]}},insn[31:20]};
                illegal=!(f3==0 || f3==1 || f3==2 || f3==4 || f3==5);
            end
            7'h23: begin
                uses_rs1=1; uses_rs2=1; b_imm=1; mem_write=1;
                imm={{20{insn[31]}},insn[31:25],insn[11:7]};
                illegal=!(f3==0 || f3==1 || f3==2);
            end
            7'h13: begin
                uses_rs1=1; rd_we=1; b_imm=1;
                imm={{20{insn[31]}},insn[31:20]};
                case (f3)
                    0: alu_op=0;
                    1: begin alu_op=2; illegal=(f7!=0); end
                    2: alu_op=3;
                    3: alu_op=4;
                    4: alu_op=5;
                    5: begin alu_op=insn[30] ? 7 : 6; illegal=!(f7==0 || f7==7'h20); end
                    6: alu_op=8;
                    7: alu_op=9;
                    default: illegal=1;
                endcase
            end
            7'h33: begin
                uses_rs1=1; uses_rs2=1; rd_we=1;
                if (f7==1) is_m=1;
                else begin
                    case (f3)
                        0: begin alu_op=insn[30] ? 1 : 0; illegal=!(f7==0 || f7==7'h20); end
                        1: begin alu_op=2; illegal=(f7!=0); end
                        2: begin alu_op=3; illegal=(f7!=0); end
                        3: begin alu_op=4; illegal=(f7!=0); end
                        4: begin alu_op=5; illegal=(f7!=0); end
                        5: begin alu_op=insn[30] ? 7 : 6; illegal=!(f7==0 || f7==7'h20); end
                        6: begin alu_op=8; illegal=(f7!=0); end
                        7: begin alu_op=9; illegal=(f7!=0); end
                        default: illegal=1;
                    endcase
                end
            end
            7'h0f: begin fence=1; illegal=(f3!=0); end
            7'h73: begin
                ecall=(insn==32'h00000073);
                ebreak=(insn==32'h00100073);
                illegal=!(ecall || ebreak);
            end
            7'h0b: begin
                uses_rs1=1; uses_rs2=1; rd_we=1; is_simd=1;
                illegal=!(ENABLE_SIMD && f7==0 && f3<=2);
            end
            default: illegal=1;
        endcase
        if (illegal || ecall || ebreak) begin
            rd_we=0; mem_read=0; mem_write=0; branch=0; fence=0; is_m=0; is_simd=0;
        end
    end
endmodule
