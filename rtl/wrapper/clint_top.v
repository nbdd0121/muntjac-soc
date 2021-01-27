module clint_top #(
    parameter NUM_HARTS = 1,
    parameter CLK_FREQ = 40
) (
    input wire clk,
    input wire rstn,

    // We expose the control as a 64KiB BRAM.
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME BRAM, MASTER_TYPE BRAM_CTRL, MEM_SIZE 65536, MEM_WIDTH 64, MEM_ECC NONE, READ_WRITE_MODE READ_WRITE, READ_LATENCY 1" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM ADDR" *)
    input  wire [15:0] bram_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM EN" *)
    input  wire        bram_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM WE" *)
    input  wire [7:0]  bram_we,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM DOUT" *)
    output wire [63:0] bram_rddata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM DIN" *)
    input  wire [63:0] bram_wrdata,

    input wire timer_clk,

    // IRQ output for each hart.
    output wire [NUM_HARTS-1:0] msip,
    output wire [NUM_HARTS-1:0] mtip
);

    clint #(NUM_HARTS, CLK_FREQ) clint (clk, rstn, bram_addr, bram_en, bram_we, bram_rddata, bram_wrdata, timer_clk, msip, mtip);

endmodule
