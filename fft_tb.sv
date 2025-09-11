module fft_tb;

    // Declare signals
    logic [7:0] led;      // LED output from the FFT module
    logic [8:0] sw;       // Switch inputs to the FFT module
    logic clock;          // Clock signal
    logic reset;          // Reset signal

    // Instantiate the FFT module with DEBOUNCE_LIMIT overridden to 10 cycles
    fft #(.DEBOUNCE_LIMIT(10)) uut (
        .led(led),
        .sw(sw),
        .clock(clock),
        .reset(reset)
    );

    // Clock generation: 50 MHz (20 ns period)
    initial begin
        clock = 0;
        forever #10 clock = ~clock;  // Toggle every 10 ns
    end

    // Reset initialization
    initial begin
        reset = 0;
        #40 reset = 1;  // Assert reset for 40 ns, then deassert
    end

    // Task to wait for debounce period (10 clock cycles)
    task wait_debounce;
        repeat(10) @(posedge clock);
    endtask

    // Test sequence with debug statements
    initial begin
        // Initialize switches
        sw = 9'b0;
        #40;  // Wait for reset to complete

        // Set twiddle factor index to W^1 (sw[2:0] = 001)
        sw[2:0] = 3'b011;

        // Start the process: move from master_reset to twiddle_factor
        sw[7] = 1;  // Set sw[7]=1, stable_sw8=1 after debounce
        wait_debounce;

        // Move from twiddle_factor to wait_twiddle_factor
        sw[7] = 0;  // Set sw[7]=0, stable_sw8=0 after debounce
        wait_debounce;

        // Move from wait_twiddle_factor to read_Reb
        sw[7] = 1;  // Set sw[7]=1, stable_sw8=1 after debounce
        wait_debounce;

        // In read_Reb state: set Reb = 24 (00011000)
        sw[7:0] = 8'b00011000;  // sw[7]=0, moves to wait_read_Reb after debounce
        wait_debounce;

        // Debug: Monitor signals during computation
        repeat(20) @(posedge clock) begin
            $display("Time: %t, State: %s, Reb: %d, Rew: %d, mult_result: %d, Rey: %d",
                     $time, uut.present_state.name, uut.Reb, uut.Rew, uut.mult_result, uut.Rey);
        end

        // Move from compute_Rey_twos2 to read_Rea
        sw[7] = 1;  // Set sw[7]=1, stable_sw8=1 after debounce
        wait_debounce;

        // In read_Rea state: set Rea = 24 (00011000)
        sw[7:0] = 8'b00011000;  // sw[7]=0, moves to compute_Rey_add after debounce
        wait_debounce;

        // Wait and display Rey output
        repeat(10) @(posedge clock);
        $display("LED at display_Rey: %d", led);  // Expected: 32

        // Move from compute_Imy_twos to display_Imy
        sw[7] = 0;  // stable_sw8=0 after debounce
        wait_debounce;

        // Move from display_Imy to compute_Rez_mult and display Imy
        sw[7] = 1;  // stable_sw8=1 after debounce
        wait_debounce;
        $display("LED at display_Imy: %d", led);  // Expected: 9

        // Wait and display Rez output
        repeat(20) @(posedge clock);
        sw[7] = 0;  // stable_sw8=0 after debounce
        wait_debounce;
        $display("LED at display_Rez: %d", led);  // Expected: 33

        // Wait and display Imz output
        repeat(20) @(posedge clock);
        sw[7] = 1;  // stable_sw8=1 after debounce
        wait_debounce;
        $display("LED at display_Imz: %d", led);  // Expected: 8

        // End simulation
        #100;
        $stop;
    end

endmodule