module tb_bpu;
    logic clk=0,reset=1,enable=1;
    always #5 clk=~clk;
    logic [31:0] query_pc=0,prediction;
    logic update_valid=0;
    logic [31:0] update_pc=0,update_target=0;
    logic update_taken=0,update_jump=0;
    rv32_bpu dut(clk,reset,enable,query_pc,prediction,update_valid,update_pc,update_target,update_taken,update_jump);
    integer checks=0;
    task automatic expect_pc(input logic [31:0] pc,input logic [31:0] target);
        query_pc=pc;#1;
        if(prediction!==target) $fatal(1,"prediction pc=%h actual=%h expected=%h",pc,prediction,target);
        checks++;
    endtask
    task automatic update(input logic [31:0] pc,input logic [31:0] target,input logic taken,input logic jump);
        @(negedge clk);
        update_valid=1;update_pc=pc;update_target=target;update_taken=taken;update_jump=jump;
        @(negedge clk);update_valid=0;
    endtask
    initial begin
        repeat(2) @(negedge clk);reset=0;
        expect_pc('h80000000,'h80000004);
        update('h80000000,'h80000040,1,0);
        expect_pc('h80000000,'h80000040);
        update('h80000000,'h80000040,1,0); // strongly taken
        update('h80000000,'h80000040,1,0); // saturate
        update('h80000000,'h80000040,0,0);
        expect_pc('h80000000,'h80000040);
        update('h80000000,'h80000040,0,0);
        expect_pc('h80000000,'h80000004);
        update('h80000000,'h80000040,0,0);
        update('h80000000,'h80000040,0,0);
        expect_pc('h80000000,'h80000004);
        // Same low index, different tag.
        expect_pc('h80000100,'h80000104);
        update('h80000100,'h80000200,1,1);
        expect_pc('h80000100,'h80000200);
        expect_pc('h80000000,'h80000004);
        // Indirect target changes at the same PC.
        update('h80000100,'h80000300,1,1);
        expect_pc('h80000100,'h80000300);
        enable=0;
        expect_pc('h80000100,'h80000104);
        $display("PASS BPU: %0d checks; saturation, alias tags, indirect target, disable",checks);
        $finish;
    end
endmodule
