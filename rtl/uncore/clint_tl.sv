module clint_tl #(
  parameter NumHarts = 1,
  parameter TimerClockFrequency = 40,

  parameter AddrWidth   = 16,
  parameter SourceWidth = 1
) (
  input logic clk_i,
  input logic rst_ni,
  input logic timer_clk_i,

  // IRQ output for each hart.
  output logic [NumHarts-1:0] msip_o,
  output logic [NumHarts-1:0] mtip_o,

  `TL_DECLARE_DEVICE_PORT(64, AddrWidth, SourceWidth, 1, link)
);

  logic bram_en;
  logic bram_we;
  logic [7:0] bram_wmask;
  logic [12:0] bram_addr;
  logic [63:0] bram_wrdata;
  logic [63:0] bram_rddata;

  clint #(
    .NUM_HARTS (NumHarts),
    .CLK_FREQ  (TimerClockFrequency)
  ) clint (
    .clk (clk_i),
    .rstn (rst_ni),
    .bram_addr ({bram_addr, 3'b0}),
    .bram_en (bram_en),
    .bram_we (bram_we ? bram_wmask : '0),
    .bram_rddata (bram_rddata),
    .bram_wrdata (bram_wrdata),
    .timer_clk (timer_clk_i),
    .msip (msip_o),
    .mtip (mtip_o)
  );

  tl_adapter_bram #(
    .DataWidth (64),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .BramAddrWidth (13)
  ) bridge (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, link),
    .bram_en_o    (bram_en),
    .bram_we_o    (bram_we),
    .bram_wmask_o (bram_wmask),
    .bram_addr_o  (bram_addr),
    .bram_wdata_o (bram_wrdata),
    .bram_rdata_i (bram_rddata)
  );

endmodule
