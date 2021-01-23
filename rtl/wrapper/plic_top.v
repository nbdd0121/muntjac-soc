module plic_top #(
    // Currently can only be 1.
    parameter NUM_CONTEXTS = 1,
    // Currently can only be 32.
    parameter NUM_IRQS = 32
) (
    input wire clk,
    input wire rstn,

    // Interrupt sources. Bit 0 is ignored.
    input wire [NUM_IRQS-1:0] interrupts,

    // Whether each interrupt should be level triggered or edge triggered
    input wire [NUM_IRQS-1:0] edge_trigger,

    // We expose the control as a 4MiB BRAM.
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME BRAM, MASTER_TYPE BRAM_CTRL, MEM_SIZE 4194304, MEM_WIDTH 32, MEM_ECC NONE, READ_WRITE_MODE READ_WRITE, READ_LATENCY 1" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM ADDR" *)
    input  wire [21:0] bram_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM EN" *)
    input  wire        bram_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM WE" *)
    input  wire [3:0]  bram_we,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM DOUT" *)
    output wire [31:0] bram_rddata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM DIN" *)
    input  wire [31:0] bram_wrdata,

    // IRQ output for each context.
    output wire [NUM_CONTEXTS-1:0] irq
);

    plic #(NUM_CONTEXTS, NUM_IRQS) plic (clk, rstn, interrupts, edge_trigger, bram_addr, bram_en, &bram_we, bram_rddata, bram_wrdata, irq);

endmodule
