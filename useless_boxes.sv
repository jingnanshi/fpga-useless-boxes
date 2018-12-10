// useless_boxes.sv
//   Jingnan Shi | Nov. 17, 2018

/////////////////////////////////////////////  
// useless_boxes
//  Top-level module for the USELESS boxes control. Controls a servo to
//  rotate a flipper when then switch to pulled high and flip the switch
//  back low. Pseudo-randomly chooses between three different motion
//  sequences. Applies the controller to all ten USELESS boxes  
///////////////////////////////////////////// 
module useless_boxes(input logic clk,
						   input logic reset,
						   input logic [9:0] switch, 
						   output logic [9:0] PWM);
	genvar i;
	generate
		for (i = 0; i < 10; i = i+1) begin: box_gen_loop
			useless_box box(clk, reset, switch[i], PWM[i]);
		end
	endgenerate

endmodule

/////////////////////////////////////////////  
// useless_box
//   Controller for one useless box. When switch is high, the box needs to
//   push it back to low
///////////////////////////////////////////// 
module useless_box(input logic clk,
						 input logic reset,
                   input logic switch,
						 output logic PWM);
						 
	// level to pulse converter
	logic switch_pulse;
	level2pulse l2p(clk, reset, switch, switch_pulse);
	
	// LFSR RNG
	logic [2:0] behavior_select;
	lfsr_rng rng(clk, reset, switch_pulse, behavior_select);
	
	// Behaviors
	logic [19:0] behavior_1, behavior_2, behavior_3;
	quickpush behav1(clk, switch_pulse, behavior_1);
	slowpush behav2(clk, switch_pulse, behavior_2);
	slow_then_fast_push behav3(clk, switch_pulse, behavior_3);
		
	// Behavior selection mux
	logic [19:0] behavior_duty_cycle;
	always_comb
		case(behavior_select[1:0])
			2'b01: behavior_duty_cycle = behavior_1;
			2'b10: behavior_duty_cycle = behavior_2;
			2'b11: behavior_duty_cycle = behavior_3;
			default: behavior_duty_cycle = behavior_1;
		endcase
	
	// mux for switch between default / behavior
	logic [19:0] duty_cycle;
	always_comb
		if (switch) duty_cycle = behavior_duty_cycle;
		else duty_cycle = 20'd128000;  // default value: 3.2 ms
			
	// A counter to generate a refresh rate of 20 ms
	logic [19:0] count;
	always_ff @ (posedge clk) begin
		if (reset || count == 20'd800000) count <= 20'b0;
		else count <= count + 1'b1;
	end	
	
	// Duty cycle comparator
	// This converts the duty cycle generated by different
	// behaviors to actual PWM signals.
	always_ff @ (posedge clk) begin
		if (count < duty_cycle) PWM <= 1'b1;
		else PWM <= 1'b0;
	end
			 
endmodule 


/////////////////////////////////////////////  
// quickpush
//   Generates the quick push control sequence  
///////////////////////////////////////////// 
module quickpush(input logic clk,
					 input logic reset,
					 output logic [19:0] duty_cycle);
	 
	// ~10 Hz update rate of output duty_cycle
	logic [21:0] q;
	logic sclk;
	assign sclk = q[21];
	always_ff @(posedge clk, posedge reset) begin
		if (reset) q <= 22'b0;
		else q <= q + 22'b1;
	end
	
	// sweep the angle
	always @(posedge sclk, posedge reset) begin
		if (reset) begin
			duty_cycle <= 20'd128000;
		end else begin
			if (duty_cycle > 20'd100000) duty_cycle <= duty_cycle - 20'd1400; //20 steps
			else duty_cycle <= 20'd60000;
		end 
	end
	
endmodule


/////////////////////////////////////////////  
// slowpush
//   Generates the slow push control sequence  
///////////////////////////////////////////// 
module slowpush(input logic clk,
					 input logic reset,
					 output logic [19:0] duty_cycle);
	 
	// A counter to count from 3.2 ms (128000) to 0.45 ms (18000)
	// ~10 Hz update rate of output duty_cycle
	logic [21:0] q;
	logic sclk;
	assign sclk = q[21];
	always_ff @(posedge clk, posedge reset) begin
		if (reset) q <= 22'b0;
		else q <= q + 22'b1;
	end
	
	// sweep the angle
	always @(posedge sclk, posedge reset) begin
		if (reset) begin
			duty_cycle <= 20'd128000;
		end else begin
			if (duty_cycle > 20'd70000) duty_cycle <= duty_cycle - 20'd1160; //50 steps
			else duty_cycle <= 20'd60000;
		end 
	end
	
endmodule


/////////////////////////////////////////////  
// slow_then_fast_push
//   Generates the slow to fast push control sequence  
///////////////////////////////////////////// 
module slow_then_fast_push(input logic clk,
					            input logic reset,
					            output logic [19:0] duty_cycle);
	 
	// A counter to count from 3.2 ms (128000) to 2 ms (80000)
	// then jump to 0.45 ms (18000)
	// ~10 Hz update rate of output duty_cycle [21:0]
	logic [21:0] q;
	logic sclk;
	assign sclk = q[21];
	always_ff @(posedge clk, posedge reset) begin
		if (reset) q <= 22'b0;
		else q <= q + 22'b1;
	end
	
	// sweep the angle
	always_ff @(posedge sclk, posedge reset) begin
		if (reset) duty_cycle <= 20'd128000;
		else begin
			if (duty_cycle > 20'd80000) duty_cycle <= duty_cycle - 20'd2400;  //20 steps 
		   else duty_cycle <= 20'd60000;
		end
	end
	
endmodule


/////////////////////////////////////////////  
// lfsr_rng
//   A 3-bit LFSR pesdo-number generator. Holds the number if not enabled
///////////////////////////////////////////// 
module lfsr_rng(input logic clk, 
				    input logic reset,
				    input logic en,
				    output logic [2:0] q);
	always_ff @(posedge clk, posedge reset) begin
    if (reset)
      q <= 3'd1; // initial seed, anything except zero
    else if (en)
      q <= {q[1:0], q[2] ^ q[1]}; // polynomial for maximal LFSR
	 else
	   q <= q;
	end
endmodule

/////////////////////////////////////////////  
// level2pulse
//   Generate a pulse when level changes from low to high
/////////////////////////////////////////////
module level2pulse(input clk,
				       input reset,
						 input level,
						 output pulse);
	typedef enum logic [1:0] {Low, Write, High} statetype;
	statetype state, nextstate;
	
	// State register
	always_ff @(posedge clk, posedge reset) 
		if (reset) state <= Low;
		else       state <= nextstate; 
	
	// next state logic 
   always_comb
		case(state)
			Low:if (level) nextstate=Write;
				 else nextstate=Low;
			Write:nextstate=High;
			High:if (level) nextstate=High;
				  else nextstate=Low;
			default:nextstate=Low;
		endcase 
	
	assign pulse=(state==Write);
	
endmodule 

