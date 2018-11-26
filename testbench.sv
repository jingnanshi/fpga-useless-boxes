module testbench();
    logic clk, reset;
	 logic [9:0] switch, PWM;
    
    // device under test
    useless_boxes dut(clk, reset, switch, PWM);
    
    // generate clock signals
    initial 
        forever begin
            clk = 1'b0; #5;
            clk = 1'b1; #5;
        end
        
    initial begin
      reset = 1'b1; #10;
		reset = 1'b0; #10;
		switch = 10'b1000000000;
    end 

endmodule
