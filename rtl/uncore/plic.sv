module plic #(
    parameter NUM_CONTEXTS = 1,
    // Currently can only be 32.
    parameter NUM_IRQS = 32
) (
    input logic clk,
    input logic rstn,

    // Interrupt sources. Bit 0 is ignored.
    input logic [NUM_IRQS-1:0] interrupts,

    // Whether each interrupt should be level triggered or edge triggered
    input logic [NUM_IRQS-1:0] edge_trigger,

    // We expose the control as a 4MiB BRAM.
    input  logic [21:0] bram_addr,
    input  logic        bram_en,
    input  logic        bram_we,
    output logic [31:0] bram_rddata,
    input  logic [31:0] bram_wrdata,

    // IRQ output for each context.
    output logic [NUM_CONTEXTS-1:0] irq
);

    if (NUM_IRQS > 32) begin
        $error("At most 32 IRQs are supported at the moment");
    end

    if (NUM_CONTEXTS > 64) begin
        $error("At most 64 contexts are supported at the moment");
    end

    localparam ADDR_WIDTH = 22;

    logic [NUM_IRQS-1:0] prev_interrupts;

    logic [NUM_IRQS-1:0] pending;
    logic [NUM_IRQS-1:0] claimed;
    logic [NUM_CONTEXTS-1:0][NUM_IRQS-1:0] enable;

    for (genvar ctx_id = 0; ctx_id < NUM_CONTEXTS; ctx_id++) begin
        assign irq[ctx_id] = |(pending & ~claimed & enable[ctx_id]);
    end

    //
    // Matching addresses
    //

    wire priority_match = bram_addr[ADDR_WIDTH-1:12] == 0;

    wire pending_match = bram_addr[ADDR_WIDTH-1:7] == 'b1_00000;
    wire [4:0] pending_irq = bram_addr[6:2];

    // This currently matches 0x2000 to 0x4000, i.e. 64 contexts
    wire enable_match = bram_addr[ADDR_WIDTH-1:13] == 1;
    wire [5:0] enable_ctx = bram_addr[12:7];
    wire [4:0] enable_irq = bram_addr[6:2];

    wire threshold_match = bram_addr[ADDR_WIDTH-1:18] == 'b1_000 && bram_addr[11:2] == 0;
    wire claim_match = bram_addr[ADDR_WIDTH-1:18] == 'b1_000 && bram_addr[11:2] == 1;
    wire [5:0] match_ctx = bram_addr[17:12];

    //
    // BRAM Interfacing logic
    //

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            prev_interrupts <= '1;
            pending <= '0;
            claimed <= '0;
            enable  <= '0;
            bram_rddata <= 'x;
        end
        else begin
            prev_interrupts <= interrupts;
            // Set pending when we receive the interrupt.
            pending <= pending | ((~edge_trigger | ~prev_interrupts) & interrupts);

            if (bram_en) begin
                bram_rddata <= 'x;
                unique case (1'b1)
                    // Priority; we hardwire them to 1
                    priority_match: bram_rddata <= 1;
                    // Pending, IRQ 0-31
                    pending_match: bram_rddata <= pending_irq == 0 ? pending : 0;
                    // Enable, CTX 0, IRQ 0-31
                    enable_match: begin
                        if (enable_irq == 0 && enable_ctx < NUM_CONTEXTS) begin
                            bram_rddata <= enable[enable_ctx];
                            if (bram_we) begin
                                enable[enable_ctx] <= bram_wrdata;
                            end
                        end
                        else begin
                            bram_rddata <= 0;
                        end
                    end
                    // Threshold, CTX 0; we hardwire them to 0
                    threshold_match: bram_rddata <= 0;
                    // Claim, CTX 0
                    claim_match: begin
                        if (match_ctx < NUM_CONTEXTS) begin
                            if (bram_we) begin
                                claimed[bram_wrdata[4:0]] <= 1'b0;
                                bram_rddata <= 'x;
                            end
                            else begin
                                automatic logic [NUM_IRQS-1:0] claimable = pending & ~claimed & enable[match_ctx];
                                automatic logic [4:0] irq = 0;
                                for (int i = NUM_IRQS - 1; i > 0; i--) begin
                                    if (claimable[i]) begin
                                        irq = i;
                                    end
                                end
                                pending[irq] <= 1'b0;
                                claimed[irq] <= 1'b1;
                                bram_rddata <= irq;
                            end
                        end
                        else begin
                            bram_rddata <= 0;
                        end
                    end
                    // Out of bound access
                    default: begin
                        bram_rddata <= 0;
                        $warning("PLIC out-of-bound access at %h", bram_addr);
                    end
                endcase
            end
        end

endmodule
