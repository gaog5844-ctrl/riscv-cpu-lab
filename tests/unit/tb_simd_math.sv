module tb_simd_math;
    logic [1:0] op;
    logic [31:0] a,b,result,expected;
    rv32_simd dut(.*);
    integer stream,status,count=0;
    initial begin
        stream=$fopen("build/simd-vectors.txt","r");
        if(!stream) $fatal(1,"cannot open SIMD vectors");
        while(!$feof(stream)) begin
            status=$fscanf(stream,"%h %h %h %h\n",op,a,b,expected);
            if(status!=4) $fatal(1,"malformed SIMD vector %0d",count);
            #1;
            if(result!==expected)
                $fatal(1,"SIMD math op=%0d a=%h b=%h got=%h expected=%h",op,a,b,result,expected);
            count++;
        end
        $fclose(stream);
        if(count!=68683) $fatal(1,"incomplete SIMD vectors: %0d",count);
        $display("PASS independent SIMD math: %0d Python-integer vectors",count);
        $finish;
    end
endmodule
