`include "axi_lite_util.svh"
`include "tl_util.svh"

module sdhci #(
  parameter AddrWidth   = 12,
  parameter SourceWidth = 1
) (
  // Clock and reset
  input clk_i,
  input rst_ni,
  input io_clk_i,

  // IO ports
  input        sd_cd,
  inout        sd_cmd,
  inout  [3:0] sd_dat,
  output       sd_reset,
  output       sd_sck,

  // TileLink port
  `TL_DECLARE_DEVICE_PORT(32, AddrWidth, SourceWidth, 1, link),
  output irq_o
);

  logic sd_cmd_i;
  logic sd_cmd_o;
  logic sd_cmd_t;
  logic [3:0] sd_dat_i;
  logic [3:0] sd_dat_o;
  logic [3:0] sd_dat_t;

  IOBUF sd_cmd_iobuf (
    .I  (sd_cmd_o),
    .IO (sd_cmd),
    .O  (sd_cmd_i),
    .T  (sd_cmd_t)
  );

  IOBUF sd_dat_iobuf0 (
    .I  (sd_dat_o[0]),
    .IO (sd_dat[0]),
    .O  (sd_dat_i[0]),
    .T  (sd_dat_t[0])
  );

  IOBUF sd_dat_iobuf1 (
    .I  (sd_dat_o[1]),
    .IO (sd_dat[1]),
    .O  (sd_dat_i[1]),
    .T  (sd_dat_t[1])
  );

  IOBUF sd_dat_iobuf2 (
    .I  (sd_dat_o[2]),
    .IO (sd_dat[2]),
    .O  (sd_dat_i[2]),
    .T  (sd_dat_t[2])
  );

  IOBUF sd_dat_iobuf3 (
    .I  (sd_dat_o[3]),
    .IO (sd_dat[3]),
    .O  (sd_dat_i[3]),
    .T  (sd_dat_t[3])
  );
  
  logic sdpower;
  assign sd_reset = ~sdpower;

  logic bram_en;
  logic bram_we;
  logic [3:0] bram_wmask;
  logic [5:0] bram_addr;
  logic [31:0] bram_wrdata;
  logic [31:0] bram_rddata;

  sd_host_intf sdhci (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .sd_base_clock (io_clk_i),
    .cmd_i (sd_cmd_i),
    .cmd_o (sd_cmd_o),
    .cmd_t (sd_cmd_t),
    .dat_i (sd_dat_i),
    .dat_o (sd_dat_o),
    .dat_t (sd_dat_t),
    .sdwp_ni (1'b1),
    .sdcd_ni (sd_cd),
    .sdpower_o (sdpower),
    .sdclk_o (sd_sck),
    .led_o (),
    .irq_o (irq_o),
    .wakeup_o (),
    .slot_irq_i ({7'd0, irq_o}),
    .bram_en (bram_en),
    .bram_we (bram_we ? bram_wmask : 4'd0),
    .bram_addr  ({bram_addr, 2'b0}),
    .bram_wrdata (bram_wrdata),
    .bram_rddata (bram_rddata)
  );

  tl_adapter_bram #(
    .DataWidth (32),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .BramAddrWidth (6)
  ) bridge (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    `TL_FORWARD_DEVICE_PORT(host, link),
    .bram_en_o    (bram_en),
    .bram_we_o    (bram_we),
    .bram_wmask_o (bram_wmask),
    .bram_addr_o  (bram_addr),
    .bram_wdata_o (bram_wrdata),
    .bram_rdata_i (bram_rddata)
  );

endmodule
