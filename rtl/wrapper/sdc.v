module sdc #(
  // Number of cycles taken between driving cmd_o and sampling cmd_i.
  // If this value is less than 0, conflict detection will be disabled.
  parameter ConflictDetection = -1,

  // Supported voltage of this slot. Currently we only support one voltage.
  // The value corresponds to the 3-bit value in power control register.
  parameter Voltage = 3'b111,

  // Maximum current capability for the Voltage.
  // This value corresponds to the 8-bit value in maximum current capability register.
  parameter Current = 8'd0,

  // Maximum number of cycles in clk_i takes for SDCD to stablise
  // The default value is 100ms when clock is 50MHz
  parameter DebouncePeriod = 5000000,

  // SD Base Clock Frequency in MHz. This must range from 1MHz to 63MHz.
  parameter SdBaseClockFreq = 25
) (
  input wire clk,
  input wire rstn,

  input  sd_base_clock,

  input  cmd_i,
  output cmd_o,
  output cmd_t,

  input  [3:0] dat_i,
  output [3:0] dat_o,
  output [3:0] dat_t,

  input  sdcd_n,
  output sdpower_o,
  output sdclk,

  output led,

  output irq,
  output wakeup,

  // We expose the control as a 4MiB BRAM.
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME BRAM, MASTER_TYPE BRAM_CTRL, MEM_SIZE 4096, MEM_WIDTH 32, MEM_ECC NONE, READ_WRITE_MODE READ_WRITE, READ_LATENCY 1" *)
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM ADDR" *)
  input  wire [11:0] bram_addr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM EN" *)
  input  wire        bram_en,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM WE" *)
  input  wire [3:0]  bram_we,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM DOUT" *)
  output wire [31:0] bram_rddata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM DIN" *)
  input  wire [31:0] bram_wrdata
);

  sd_host_intf #(ConflictDetection, Voltage, Current, DebouncePeriod, SdBaseClockFreq) sdc (
    clk, rstn, sd_base_clock,
    cmd_i, cmd_o, cmd_t,
    dat_i, dat_o, dat_t,
    1'b1, sdcd_n, sdpower_o, sdclk,
    led, irq, wakeup, {7'd0, irq},
    bram_en, bram_we, bram_addr, bram_wrdata, bram_rddata
  );

endmodule
