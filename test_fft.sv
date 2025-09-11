
module test_fft();

  // Testbench signals
  logic [7:0] led;
  logic [9:0] sw;
  logic clock;
  logic reset;

  // Clock generation
  initial begin
    clock = 1;  // Start with clock high
    forever #5 clock = ~clock;
  end

  // Instantiate the FFT module
  fft dut (
    .led(led),
    .sw(sw),
    .clock(clock),
    .reset(reset)
  );

  // Stimulus
  initial begin
    // Initialize signals
    reset = 1;
    sw = 10'b0;

    // Apply reset
    #10 reset = 0;
    #10 reset = 1;
    end

    initial begin
	
    // Test sequence
    #20 sw = 10'b0000000000; // Set Sw9 to 0
    #20 sw = 10'b1000000000; // Set SW9 to start
    #20 sw = 10'b1100000000; // Set SW8 to move to twiddle_factor
    #20 sw = 10'b1000000000; // Clear SW8 to move to wait_twiddle_factor
    #20 sw = 10'b1100000000; // Set SW8 to move to read_Reb
    #20 sw = 10'b1010101010; // Set some values for Reb
    #20 sw = 10'b1000000000; // Clear SW8 to move to wait_read_Reb
    #20 sw = 10'b1100000000; // Set SW8 to move to read_Rea
    #20 sw = 10'b1001100110; // Set some values for Rea
    #20 sw = 10'b1000000000; // Clear SW8 to move to display_Imy
    #20 sw = 10'b1100000000; // Set SW8 to move to display_Rez
    #20 sw = 10'b1000000000; // Clear SW8 to move to display_Imz
    #20 sw = 10'b1100000000; // Set SW8 to move back to twiddle_factor

    // Run for a while and finish simulation
    #100 $finish;
  end

  // Monitor
  initial begin
    $monitor("Time=%0t led=%b sw=%b state=%s", 
             $time, led, sw, dut.present_state.name);
  end

endmodule

