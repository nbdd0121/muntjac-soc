module seg_driver (
    input clk,
    input resetn,

    input [31:0] number,
    output logic [6:0] segments,
    output logic [7:0] nibble_enable
);

    // Cycle an index
    logic [2:0] index;
    logic [16:0] counter;
    always_ff @(posedge clk or negedge resetn)
        if (!resetn) begin
            index <= 3'b0;
            counter <= '0;
        end
        else begin
            counter <= counter + 1;
            // Refresh cycle is 1 to 16ms
            // Each nibble should be enabled every 1/8 refresh cycle
            // i.e. at least 1/8 ms.
            // 100MHz * (1/8 ms) = 12500 cycles
            if (counter == 12499) begin
                index <= index + 1;
                counter <= 0;
            end
        end

    // Convert index to one-hot
    always_comb begin
        nibble_enable = '1;
        nibble_enable[index] = 1'b0;
    end

    // Pick up the nibble to display
    logic [7:0][3:0] nibbles;
    logic [3:0] current_nibble;
    assign nibbles = number;
    assign current_nibble = nibbles[index];

    // Set segments
    always_comb
        unique case (current_nibble)
            4'b0000: segments = 7'b0000001;
            4'b0001: segments = 7'b1001111;
            4'b0010: segments = 7'b0010010;
            4'b0011: segments = 7'b0000110;
            4'b0100: segments = 7'b1001100;
            4'b0101: segments = 7'b0100100;
            4'b0110: segments = 7'b0100000;
            4'b0111: segments = 7'b0001111;
            4'b1000: segments = 7'b0000000;
            4'b1001: segments = 7'b0000100;
            4'b1010: segments = 7'b0001000;
            4'b1011: segments = 7'b1100000;
            4'b1100: segments = 7'b0110001;
            4'b1101: segments = 7'b1000010;
            4'b1110: segments = 7'b0110000;
            4'b1111: segments = 7'b0111000;
        endcase

endmodule
