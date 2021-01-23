module clint #(
    parameter NUM_HARTS = 1,
    parameter CLK_FREQ = 40
) (
    input logic clk,
    input logic rstn,

    // We expose the control as a 64KiB BRAM.
    input  logic [15:0] bram_addr,
    input  logic        bram_en,
    input  logic        bram_we,
    output logic [31:0] bram_rddata,
    input  logic [31:0] bram_wrdata,

    input logic timer_clk,

    // IRQ output for each hart.
    output logic [NUM_HARTS-1:0] msip,
    output logic [NUM_HARTS-1:0] mtip
);

    if (NUM_HARTS > 4094) begin
        $error("CLINT can support at most 4094 harts");
    end


    //
    // Time keeper
    //

    logic [$clog2(CLK_FREQ)-1:0] divider;
    logic pulse;

    // Divide timer_clk to generate a 1MHz pulse
    always_ff @(posedge timer_clk or negedge rstn) begin
        if (!rstn) begin
            pulse <= 1'b0;
            divider <= 0;
        end else begin
            pulse <= 1'b0;
            divider <= divider + 1;
            if (divider == CLK_FREQ - 1) begin
                pulse <= 1'b1;
                divider <= 0;
            end
        end
    end

    logic pulse_o;
    prim_pulse_sync sync (
        .clk_src_i (timer_clk),
        .rst_src_ni (rstn),
        .src_pulse_i (pulse),
        .clk_dst_i (clk),
        .rst_dst_ni (rstn),
        .dst_pulse_o (pulse_o)
    );

    logic [NUM_HARTS-1:0][63:0] mtimecmp;
    logic [63:0] mtime;

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            mtime <= '0;
            mtip <= '0;
        end
        else begin
            if (pulse_o) begin
                mtime <= mtime + 1;
            end

            // Check if any timer has fired
            for (int i = 0; i < NUM_HARTS; i++) begin
                mtip[i] <= (mtimecmp[i] <= mtime);
            end
        end

    //
    // BRAM Interfacing logic
    //

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            bram_rddata <= '0;
            for (int i = 0; i < NUM_HARTS; i++) mtimecmp[i] <= '1;
            msip <= '0;
        end
        else begin
            if (bram_en) begin
                bram_rddata <= 0;
                unique case (bram_addr[15:14])
                    2'b00: begin
                        automatic logic [11:0] hart = bram_addr[13:2];
                        if (hart < NUM_HARTS) begin
                            bram_rddata <= msip[hart];
                            if (bram_we) begin
                                msip[hart] <= bram_wrdata[0];
                            end
                        end
                    end
                    2'b01, 2'b10: begin
                        automatic logic [11:0] hart = {bram_addr[15], bram_addr[13:3]};
                        if (hart == 4095) begin
                            bram_rddata <= bram_addr[2] ? mtime[63:32] : mtime[31:0];
                        end
                        else if (hart < NUM_HARTS) begin
                            bram_rddata <= bram_addr[2] ? mtimecmp[hart][63:32] : mtimecmp[hart][31:0];
                            if (bram_we) begin
                                if (bram_addr[2]) begin
                                    mtimecmp[hart][63:32] <= bram_wrdata;
                                end
                                else begin
                                    mtimecmp[hart][31:0] <= bram_wrdata;
                                end
                            end
                        end
                    end
                    default: begin
                        $warning("CLINT out-of-bound access at %h", bram_addr);
                    end
                endcase
            end
        end

endmodule
