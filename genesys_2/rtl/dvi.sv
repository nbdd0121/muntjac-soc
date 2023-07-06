`include "axi_util.svh"
`include "tl_util.svh"

module dvi #(
  parameter IoAddrWidth = 30,
  parameter IoSourceWidth = 5,
  parameter DmaDataWidth = 64,
  parameter DmaAddrWidth = 64,
  parameter DmaSourceWidth = 2,
  parameter DmaSinkWidth = 1
) (
  // Clock and reset
  input clk_i,
  input rst_ni,
  input io_clk_i,

  // IO port
  output       hdmi_tx_clk_p,
  output       hdmi_tx_clk_n,
  output [2:0] hdmi_tx_p,
  output [2:0] hdmi_tx_n,

  // TileLink port
  `TL_DECLARE_DEVICE_PORT(32, IoAddrWidth, IoSourceWidth, 1, io),
  `TL_DECLARE_HOST_PORT(DmaDataWidth, DmaAddrWidth, DmaSourceWidth, DmaSinkWidth, dma)
);

  // Clock wizard

  wire pxl_clk;
  wire pxl_clk_5;
  clk_wiz_dvi clk_wiz (
    .clk_in1  (io_clk_i),
    .resetn   (rst_ni),
    .clk_out1 (pxl_clk),
    .clk_out2 (pxl_clk_5)
  );

  logic [7:0] red;
  logic [7:0] green;
  logic [7:0] blue;
  logic pixel;
  logic hsync;
  logic vsync;

  logic bram_en;
  logic bram_we;
  logic [3:0] bram_wmask;
  logic [5:0] bram_addr;
  logic [31:0] bram_wrdata;
  logic [31:0] bram_rddata;

  `TL_DECLARE(DmaDataWidth, DmaAddrWidth, DmaSourceWidth, 1, axi);

  display_controller #(
    .DataWidth (DmaDataWidth),
    .AddrWidth (DmaAddrWidth),
    .SourceWidth (DmaSourceWidth)
  ) display (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .pxl_clk_freq_o (),
    .pxl_clk_i (pxl_clk),
    .pxl_clk_en_i (1'b1),
    .red_o (red),
    .green_o (green),
    .blue_o (blue),
    .pixel_o (pixel),
    .hsync_o (hsync),
    .vsync_o (vsync),
    .ctrl_en_i (bram_en),
    .ctrl_we_i (|bram_we),
    .ctrl_addr_i ({bram_addr, 2'b0}),
    .ctrl_wrdata_i (bram_wrdata),
    .ctrl_rddata_o (bram_rddata),
    `TL_CONNECT_HOST_PORT(dma, axi)
  );

  tl_adapter_bram #(
    .DataWidth (32),
    .AddrWidth (IoAddrWidth),
    .SourceWidth (IoSourceWidth),
    .BramAddrWidth (6)
  ) bridge (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    `TL_FORWARD_DEVICE_PORT(host, io),
    .bram_en_o    (bram_en),
    .bram_we_o    (bram_we),
    .bram_wmask_o (bram_wmask),
    .bram_addr_o  (bram_addr),
    .bram_wdata_o (bram_wrdata),
    .bram_rdata_i (bram_rddata)
  );

  tl_adapter #(
    .DataWidth (DmaDataWidth),
    .AddrWidth (DmaAddrWidth),
    .SourceWidth (DmaSourceWidth),
    .HostSinkWidth (1),
    .DeviceSinkWidth (DmaSinkWidth)
  ) dma_bridge (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, axi),
    `TL_FORWARD_HOST_PORT(device, dma)
  );

  rgb2dvi_0 rgb2dvi (
    .vid_pData ({red, blue, green}),
    .vid_pHSync (hsync),
    .vid_pVSync (vsync),
    .vid_pVDE (pixel),
    .aRst_n (rst_ni),
    .PixelClk (pxl_clk),
    .SerialClk (pxl_clk_5),
    .TMDS_Clk_p (hdmi_tx_clk_p),
    .TMDS_Clk_n (hdmi_tx_clk_n),
    .TMDS_Data_p (hdmi_tx_p),
    .TMDS_Data_n (hdmi_tx_n)
  );

endmodule
