module tb_cache;
    logic clk=0,reset=1,enable=1;
    always #5 clk=~clk;
    logic cpu_req_valid=0,cpu_req_ready,cpu_rsp_valid,cpu_rsp_ready=0,cpu_rsp_error;
    logic [31:0] cpu_req_addr=0,cpu_req_wdata=0,cpu_rsp_data;
    logic [3:0] cpu_req_wstrb=0;
    logic mem_req_valid,mem_req_ready,mem_rsp_valid,mem_rsp_ready,mem_rsp_error;
    logic [31:0] mem_req_addr,mem_req_wdata,mem_rsp_data;
    logic [3:0] mem_req_wstrb;
    logic flush_valid=0,flush_ready,flush_error;
    logic [31:0] flush_error_addr;
    logic [63:0] hits,misses,writebacks;
    rv32_dcache dut(.*);
    logic [31:0] memory[0:2047];
    logic pending=0;
    logic [31:0] saved_addr,saved_data;
    logic [3:0] saved_strb;
    integer remaining=0,cycle=0,transactions=0,checks=0;
    logic fail_read=0,fail_write=0;
    logic [31:0] fail_addr=0;
    assign mem_req_ready=!pending && cycle%5>=2;
    assign mem_rsp_valid=pending && remaining==0;
    assign mem_rsp_data=memory[saved_addr[12:2]];
    assign mem_rsp_error=pending && saved_addr==fail_addr && (saved_strb!=0 ? fail_write : fail_read);
    always @(posedge clk) begin
        cycle<=cycle+1;
        if(pending && remaining>0) remaining<=remaining-1;
        if(mem_rsp_valid && mem_rsp_ready) begin
            if(!mem_rsp_error)
                for(integer b=0;b<4;b++)
                    if(saved_strb[b]) memory[saved_addr[12:2]][8*b+:8]<=saved_data[8*b+:8];
            pending<=0;
        end
        if(mem_req_valid && mem_req_ready) begin
            if(pending) $fatal(1,"multiple outstanding cache transactions");
            pending<=1;remaining<=cycle%4+1;transactions<=transactions+1;
            saved_addr<=mem_req_addr;saved_data<=mem_req_wdata;saved_strb<=mem_req_wstrb;
        end
    end
    task automatic check(input logic condition,input string message);
        if(condition !== 1'b1) $fatal(1,"%s",message);
        checks++;
    endtask
    task automatic access(input logic [31:0] addr,input logic [31:0] value,input logic [3:0] strb,
                          input logic [31:0] expected,input logic error_expected);
        logic [31:0] hold_data;
        integer hold_transactions;
        @(negedge clk);
        cpu_req_valid=1;cpu_req_addr=addr;cpu_req_wdata=value;cpu_req_wstrb=strb;
        do @(posedge clk); while(!cpu_req_ready);
        @(negedge clk);cpu_req_valid=0;
        wait(cpu_rsp_valid);#1;
        check(cpu_rsp_error===error_expected,"cache error mismatch");
        if(strb==0 && !error_expected) check(cpu_rsp_data===expected,
            $sformatf("cache read addr=%h got=%h expected=%h",addr,cpu_rsp_data,expected));
        hold_data=cpu_rsp_data;hold_transactions=transactions;
        repeat(3) begin
            @(negedge clk);
            check(cpu_rsp_valid && cpu_rsp_data===hold_data && cpu_rsp_error===error_expected,
                  "response changed while stalled");
            check(transactions==hold_transactions,"extra backend request while response stalled");
        end
        cpu_rsp_ready=1;
        @(negedge clk);cpu_rsp_ready=0;
    endtask
    task automatic flush(input logic expected_error,input logic [31:0] expected_addr);
        @(negedge clk);flush_valid=1;
        wait(flush_ready);#1;
        check(flush_error===expected_error,"flush error mismatch");
        if(expected_error) check(flush_error_addr===expected_addr,"flush fault address mismatch");
        @(negedge clk);flush_valid=0;
        @(negedge clk);
    endtask
    task automatic restart(input logic enabled);
        @(negedge clk);reset=1;enable=enabled;
        repeat(2) @(negedge clk);
        reset=0;
    endtask
    initial begin
        for(integer i=0;i<2048;i++) memory[i]=32'h10000000+i;
        repeat(2) @(negedge clk);reset=0;
        access('h80000000,0,0,'h10000000,0);
        access('h80000000,0,0,'h10000000,0);
        check(hits==1 && misses==1,"cold miss / hit accounting");
        access('h80000000,'h0000aa00,2,0,0);
        access('h80000000,'hface0000,12,0,0);
        access('h80000000,0,0,'hfaceaa00,0);
        check(memory[0]=='h10000000,"write-back cache wrote RAM before flush");
        flush(0,0);
        check(memory[0]=='hfaceaa00,"byte/halfword writeback mismatch");
        // Dirty victim must remain recoverable after a writeback error.
        restart(1);
        access('h80000000,99,15,0,0);
        access('h80000200,55,15,0,0);
        fail_write=1;fail_addr='h80000000;
        access('h80000400,0,0,0,1);
        fail_write=0;
        access('h80000000,0,0,99,0);
        access('h80000400,0,0,'h10000100,0);
        flush(0,0);
        check(memory[0]==99 && memory[128]==55,"retry after dirty eviction failure");
        // A partially filled line is never made valid.
        fail_read=1;fail_addr='h8000060c;
        access('h80000600,0,0,0,1);
        fail_read=0;
        access('h80000600,0,0,'h10000180,0);
        access('h80000000,77,15,0,0);
        fail_write=1;fail_addr='h80000000;
        flush(1,'h80000000);
        fail_write=0;
        flush(0,0);
        check(memory[0]==77,"retry after fence writeback failure");
        // MMIO bypass never allocates a line. Disabling cache is reset-time only.
        begin
            logic [63:0] saved_misses;
            saved_misses=misses;
            access('h10000004,33,15,0,0);
            access('h10000004,0,0,33,0);
            check(misses==saved_misses,"MMIO allocated cache line");
        end
        restart(0);
        access('h80000008,123,15,0,0);
        access('h80000008,0,0,123,0);
        check(memory[2]==123 && hits==0 && misses==0,"uncached bypass");
        // Fault every beat of both eviction and FENCE writeback. Successful
        // earlier beats stay in RAM; the complete dirty line must stay cached.
        for(integer flushing_case=0;flushing_case<2;flushing_case++) begin
            for(integer failed_word=0;failed_word<8;failed_word++) begin
                restart(1);
                for(integer w=0;w<8;w++) memory[w]=32'h10000000+w;
                for(integer w=0;w<8;w++)
                    access(32'h80000000+4*w,32'hbeef0000+w,15,0,0);
                access('h80000200,0,0,memory[128],0); // other way; A becomes LRU
                fail_write=1;fail_addr=32'h80000000+4*failed_word;
                if(flushing_case) flush(1,fail_addr);
                else access('h80000400,0,0,0,1);
                check(dut.valid[0][0] && dut.dirty[0][0],"failed writeback lost dirty victim");
                for(integer w=0;w<8;w++) begin
                    check(memory[w]==(w<failed_word ? 32'hbeef0000+w : 32'h10000000+w),
                          "partial writeback prefix differs from accepted successful beats");
                    access(32'h80000000+4*w,0,0,32'hbeef0000+w,0);
                end
                fail_write=0;
                flush(0,0);
                for(integer w=0;w<8;w++) check(memory[w]==32'hbeef0000+w,"writeback retry lost data");
            end
        end
        // Exercise the SCAN sentinel after all 32 cache lines, including set 15/way 1.
        restart(1);
        for(integer line=0;line<32;line++)
            access(32'h80000000+32*line,32'hcafe0000+line,15,0,0);
        flush(0,0);
        check(writebacks==32,"FENCE did not visit all dirty lines");
        for(integer line=0;line<32;line++)
            check(memory[8*line]==32'hcafe0000+line,"FENCE skipped a line");
        // Enable is a reset-time configuration, not a live bypass switch.
        // A pin change must not expose stale RAM or resurrect a stale cached line.
        $display("PASS writeback fault sweep: eviction/FENCE x 8 beats; all 32 FENCE lines");
        restart(1);
        access('h80000000,'h12345678,15,0,0);
        @(negedge clk);enable=0;
        access('h80000000,0,0,'h12345678,0);
        flush(0,0);
        restart(0);
        access('h80000000,'h87654321,15,0,0);
        @(negedge clk);enable=1;
        access('h80000000,0,0,'h87654321,0);
        check(hits==0 && misses==0,"reset-time disabled cache changed mode without reset");
        $display("PASS cache: %0d checks; backpressure, byte enables, dirty/refill/flush fault recovery",checks);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1,"cache test timeout");
    end
endmodule
