module fft(
    output logic [7:0] led,
    input logic [8:0] sw,
    input logic clock,
    input logic reset
);

    // Signal declarations
    logic signed [15:0] Rey, Imy, Rez, Imz;
    logic signed [7:0] Rey2, Rey3, Rey4, Imy2, Imy3, Rez2, Rez3, Rez4, Imz2, Imz3;
    logic signed [7:0] Reb, Rea, Rebi, Rebi2;
    logic signed [7:0] Rew, Imw;

    // Twiddle factors
    logic signed [7:0] W [0:7][1:0] = '{
        '{ 8'sb01111111,  8'sb00000000},  // W^0 = 1+0j
        '{ 8'sb01011011,  8'sb10100101},  // W^1 = 0.707106 - 0.707106j 
        '{ 8'sb00000000,  8'sb10000000},  // W^2 = 0 - j
        '{ 8'sb10100101,  8'sb10100101},  // W^3 = -0.707106 - 0.707106j
        '{ 8'sb10000000,  8'sb00000000},  // W^4 = -1 + 0j
        '{ 8'sb10100101,  8'sb01011011},  // W^5 = -0.707106 + 0.707106j
        '{ 8'sb00000000,  8'sb01111111},  // W^6 = 0 + j
        '{ 8'sb01011011,  8'sb01011011}   // W^7 = 0.707106 + 0.707106j
    };

    // Single multiplier and ALU (registered outputs)
    logic signed [7:0] mult_in1, mult_in2;
    logic signed [15:0] mult_result;  // Registered multiplier output
    logic signed [7:0] alu_in1, alu_in2;
    logic signed [7:0] alu_result;    // Registered ALU output
    logic alu_sub;                    // 0 = add, 1 = subtract

    // Debounce parameter for 20ms at 50MHz clock
    parameter DEBOUNCE_LIMIT = 2500000;  // 20ms / (1/50MHz) = 1,000,000 cycles

    logic [21:0] debounce_counter;
    logic stable_sw8;

   typedef enum logic [31:0] {
    master_reset         = 32'b00000000000000000000000000000001,  // bit 0
    twiddle_factor       = 32'b00000000000000000000000000000010,  // bit 1
    wait_twiddle_factor  = 32'b00000000000000000000000000000100,  // bit 2
    read_Reb             = 32'b00000000000000000000000000001000,  // bit 3
    wait_read_Reb        = 32'b00000000000000000000000000010000,  // bit 4
    compute_Rebi2        = 32'b00000000000000000000000000100000,  // bit 5
    compute_Rey_mult     = 32'b00000000000000000000000001000000,  // bit 6
    compute_Rey_trunc    = 32'b00000000000000000000000010000000,  // bit 7
    compute_Rey_twos1    = 32'b00000000000000000000000100000000,  // bit 8
    compute_Rey_twos2    = 32'b00000000000000000000001000000000,  // bit 9
    read_Rea             = 32'b00000000000000000000010000000000,  // bit 10
    assign_Rea           = 32'b00000000000000000000100000000000,  // bit 11
    compute_Rey_add      = 32'b00000000000000000001000000000000,  // bit 12
    display_Rey          = 32'b00000000000000000010000000000000,  // bit 13
    compute_Imy_mult     = 32'b00000000000000000100000000000000,  // bit 14
    compute_Imy_trunc    = 32'b00000000000000001000000000000000,  // bit 15
    compute_Imy_twos     = 32'b00000000000000010000000000000000,  // bit 16
    display_Imy          = 32'b00000000000000100000000000000000,  // bit 17
    compute_Rez_mult     = 32'b00000000000001000000000000000000,  // bit 18
    compute_Rez_trunc    = 32'b00000000000010000000000000000000,  // bit 19
    compute_Rez_twos1    = 32'b00000000000100000000000000000000,  // bit 20
    compute_Rez          = 32'b00000000001000000000000000000000,  // bit 21
    compute_Rez_twos2    = 32'b00000000010000000000000000000000,  // bit 22
    compute_Rez_add      = 32'b00000000100000000000000000000000,  // bit 23
    display_Rez          = 32'b00000001000000000000000000000000,  // bit 24
    compute_Imz_mult     = 32'b00000010000000000000000000000000,  // bit 25
    compute_Imz_mult_wait= 32'b00000100000000000000000000000000,  // bit 26
    compute_Imz_trunc    = 32'b00001000000000000000000000000000,  // bit 27
    compute_Imz_twos     = 32'b00010000000000000000000000000000,  // bit 28
    display_Imz          = 32'b00100000000000000000000000000000,  // bit 29
    Rey_neg_impl         = 32'b01000000000000000000000000000000,  // bit 30
    compute_Imz_negative = 32'b10000000000000000000000000000000   // bit 31
} state;
    

    state present_state;

    // **Debounce Logic**
    always_ff @(posedge clock or negedge reset) begin
        if (~reset) begin
            debounce_counter <= 0;
            stable_sw8 <= 0;
        end else begin
            if (sw[7] != stable_sw8) begin
                if (debounce_counter == DEBOUNCE_LIMIT - 1) begin
                    stable_sw8 <= sw[7];
                    debounce_counter <= 0;
                end else begin
                    debounce_counter <= debounce_counter + 1;
                end
            end else begin
                debounce_counter <= 0;
            end
        end
    end

    // Single sequential block for all logic using only present_state
    always_ff @(posedge clock or negedge reset) begin
        if (~reset) begin
            // Reset all registers
            present_state <= master_reset;
            led <= 8'b00000000;
            Imw <= 8'b0;
            Rew <= 8'b0;
            Reb <= 8'b0;
            Rea <= 8'b0;
            Rebi2 <= 8'b0;
            Rey <= 16'b0;
            Imy <= 16'b0;
            Rez <= 16'b0;
            Imz <= 16'b0;
            Rey2 <= 8'b0;
            Rey3 <= 8'b0;
            Rey4 <= 8'b0;
            Imy2 <= 8'b0;
            Imy3 <= 8'b0;
            Rez2 <= 8'b0;
            Rez3 <= 8'b0;
            Rez4 <= 8'b0;
            Imz2 <= 8'b0;
            Imz3 <= 8'b0;
            mult_in1 <= 8'b0;
            mult_in2 <= 8'b0;
            mult_result <= 16'b0;
            alu_in1 <= 8'b0;
            alu_in2 <= 8'b0;
            alu_result <= 8'b0;
            alu_sub <= 1'b0;
        end else begin
            
            // State transitions and sequential operations
            case (present_state)
                master_reset: begin
                    if (stable_sw8)  // Use debounced sw[8]
                        present_state <= twiddle_factor;
                    else
                        present_state <= master_reset;
                end

                twiddle_factor: begin
                    led <= 8'b00000001;
                    Imw <= W[sw[2:0]][0];
                    Rew <= W[sw[2:0]][1];
                    if (~stable_sw8)  // Use debounced sw[8]
                        present_state <= wait_twiddle_factor;
                    else
                        present_state <= twiddle_factor;
                end

                wait_twiddle_factor: begin
                    //led <= 8'b00000010;
                    if (stable_sw8)  // Use debounced sw[8]
                        present_state <= read_Reb;
                    else
                        present_state <= wait_twiddle_factor;
                end

                read_Reb: begin
                    Reb <= sw[6:0];
                    //led <= 8'b00000100;
                    if (~stable_sw8)  // Use debounced sw[8]
                        present_state <= wait_read_Reb;
                    else
                        present_state <= read_Reb;
                end

                wait_read_Reb: begin
                    //led <= 8'b00001000;
                    present_state <= compute_Rebi2;  // Unconditional transition
                end

                compute_Rebi2: begin
                    alu_in1 <= ~Reb;
                    alu_in2 <= 8'b1;
                    alu_sub <= 1'b0;  // ~Reb + 1
                     // Compute directly
                    mult_in1 <= Reb;
                    mult_in2 <= Rew;
                    present_state <= compute_Rey_mult;  // Unconditional transition
                end

                compute_Rey_mult: begin
                    
            
                    Rebi2 <= alu_in1 + alu_in2; 
					Rey <= mult_in1 * mult_in2;
                    //$display("mult_result %b",mult_result);
                    //$display("Rey1 %b",Rey);
                    present_state <= compute_Rey_trunc;  // Unconditional transition
                end

            

                compute_Rey_trunc: begin
                    Rey2 <= Rey[14:7];  // Truncate
                    present_state <= compute_Rey_twos1;  // Fixed transition to next state
                end

                compute_Rey_twos1: begin
                    if (Rey2[7]) begin
                        alu_in1 <= ~Rey2;
                        alu_in2 <= 8'b1;
                        alu_sub <= 1'b0;  // ~Rey2 + 1
                        present_state <= Rey_neg_impl;
                        
                    end else begin
                        Rey3 <= Rey2;
                        present_state <= compute_Rey_twos2;
                    end
                      // Unconditional transition
                end

                Rey_neg_impl:begin

                Rey3 <= alu_in1 + alu_in2;
                present_state <= compute_Rey_twos2;
                end

                compute_Rey_twos2: begin
							//led <= 8'b00010000;
                            
                            $display("alu_in1:%b",alu_in1);
                            $display("Rey3:%b",Rey3);
                    if (stable_sw8)  // Use debounced sw[8]
                        present_state <= read_Rea;
                    else
                        present_state <= compute_Rey_twos2;  // Wait for stable_sw8
                end

                read_Rea: begin
                    $display("Rey3:%b",Rey3);
                    Rea <= sw[6:0];
                    alu_in1 <= Rey3;
                    
                    present_state <= assign_Rea;  // Unconditional transition
                end

                assign_Rea: begin
                    alu_in2 <=Rea;

                    present_state <= compute_Rey_add;  // Unconditional transition
                end




                compute_Rey_add: begin
                    
                    alu_sub <= 1'b0;  // Rey3 + Rea
                    Rey4 <= alu_in1 + alu_in2;
                    //$display("Rey3 %b",Rey3);
                    //$display("Rea %b",Rea);
                    //$display("alu_in1 %b",alu_in1);
                    //$display("alu_in2 %b",alu_in2);
                    //$display("Rey4 %b",Rey4);
                    present_state <= display_Rey;  // Unconditional transition
                end

                display_Rey: begin
                    //$display("Rey4 %b",Rey4);
                    led <= Rey4;
                    mult_in1 <= Reb;
                    mult_in2 <= Imw;
                    present_state <= compute_Imy_mult;  // Unconditional transition
                end

                compute_Imy_mult: begin
                    //$display("mult_in1 %b",mult_in1);
                    //$display("mult_in2 %b",mult_in2);
					Imy <= mult_in1 * mult_in2;
                    present_state <= compute_Imy_trunc;  // Unconditional transition
                end


                compute_Imy_trunc: begin
                    //$display("Imy %b",Imy);
                    Imy2 <= Imy[14:7];  // Truncate
                    present_state <= compute_Imy_twos;  // Unconditional transition
                end

                compute_Imy_twos: begin
                    if (Imy2[7]) begin
                        alu_in1 <= ~Imy2;
                        alu_in2 <= 8'b1;
                        alu_sub <= 1'b0;  // ~Imy2 + 1
                        Imy3 <= alu_in1 + alu_in2;

                        
                    end else begin
                        Imy3 <= Imy2;
                    end
						  if(~stable_sw8)  // conditional transition
								present_state <= display_Imy;
						   else
                                 present_state <= compute_Imy_twos;
                end

                display_Imy: begin
                    //led <= 8'b00100000;
					led <= Imy3;
                    mult_in1 <= Rebi2;
                    mult_in2 <= Rew;
                    if (stable_sw8)  // Use debounced sw[8]
                        present_state <= compute_Rez_mult;
                    else
                        present_state <= display_Imy;
                end

                compute_Rez_mult: begin
                   
					Rez <= mult_in1 * mult_in2;
                    present_state <= compute_Rez_trunc;  // Unconditional transition
                end

                

                compute_Rez_trunc: begin
                    //$display("Rez %b",Rez);
                    Rez2 <= Rez[14:7];  // Truncate
                    present_state <= compute_Rez_twos1;  // Unconditional transition
                end

                compute_Rez_twos1: begin
                    //$display("Rez2 %b",Rez2);
                    if (Rez2[7]) begin
                        alu_in1 <= ~Rez2;
                        alu_in2 <= 8'b1;
                        alu_sub <= 1'b0;  // ~Rez2 + 1
                        present_state <= compute_Rez;
                    end else begin
                        Rez3 <= Rez2;
                        present_state <= compute_Rez_twos2;
                    end
                      // Unconditional transition
                end

                compute_Rez:begin
                        Rez3 <= alu_in1 + alu_in2;


                    present_state <= compute_Rez_twos2;
                end

                compute_Rez_twos2: begin
                    
                    alu_in1 <= Rez3;
                    alu_in2 <= Rea;
                    //alu_sub <= 1'b0;  // Rez3 + Rea
                    present_state <= compute_Rez_add;  // Unconditional transition
                end

                compute_Rez_add: begin
                    Rez4 <= alu_in1 + alu_in2;
                    present_state <= display_Rez;  // Unconditional transition
                end

                display_Rez: begin
                    //led <= 8'b01000000;
                    
						  led <= Rez4;
                    if (~stable_sw8)  // Use debounced sw[8]
                        present_state <= compute_Imz_mult;
                    else
                        present_state <= display_Rez;
                end

                compute_Imz_mult: begin
                    mult_in1 <= Rebi2;
                    mult_in2 <= Imw;
						  
                    present_state <= compute_Imz_mult_wait;  // Unconditional transition
                end

                compute_Imz_mult_wait: begin
                    Imz <= mult_in1 * mult_in2;
                    present_state <= compute_Imz_trunc;  // Unconditional transition
                end

                compute_Imz_trunc: begin
                    
                    Imz2 <= Imz[14:7];  // Truncate
                    present_state <= compute_Imz_twos;  // Unconditional transition
                end

                compute_Imz_twos: begin
                    
                    if (Imz2[7]) begin
                        alu_in1 <= ~Imz2;
                        alu_in2 <= 8'b1;
                        alu_sub <= 1'b0;  // ~Imz2 + 1
                        present_state <= compute_Imz_negative; 
                       
                    end else begin
                        Imz3 <= Imz2;
                        present_state <= display_Imz;
                    end
                     // Unconditional transition
                end

                compute_Imz_negative:begin
                     Imz3 <= alu_in1 + alu_in2;
                     present_state <= display_Imz;
                end

                display_Imz: begin
                    //led <= 8'b10000000;
						  led <= Imz3;
                    if (stable_sw8)  // Use debounced sw[8]
                        present_state <= twiddle_factor;
                    else
                        present_state <= display_Imz;
                end

                default: begin
                    present_state <= master_reset;
                end
            endcase
        end
    end
endmodule