`include "axi_util.svh"
`include "tl_util.svh"

module spi #(
  parameter DataWidth   = 32,
  parameter AddrWidth   = 24,
  parameter SourceWidth = 1
) (
  // Clock and reset
  input clk_i,
  input rst_ni,
  input io_clk_i,

  // IO ports
  inout  [1:0] spi_io_io,
  inout        spi_ss_io,

  // TileLink port
  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, 1, link)
);

  `AXI_DECLARE(DataWidth, AddrWidth, SourceWidth, axi);

  // Disable write ports
  assign axi_aw_ready = 1'b0;
  assign axi_w_ready = 1'b0;
  assign axi_b_valid = 1'b0;
  assign axi_b = 'x;

  // The first three clock cycles on USRCCLKO
  // after End of Startup are used to switch the clock source and will not be output on the
  // external CCLK pin.
  // Source: https://www.xilinx.com/support/documentation/user_guides/ug470_7Series_Config.pdf
  //
  // So what we basically do is to delay the reset signals by 5 cycles, and during that we feed
  // io_clk directly to USRCCLKO during these cycles. By the time we switched to sck, USRCCLKO
  // should already observe needed clock cycles.

  logic [4:0] rstn_ff;
  always @(posedge io_clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rstn_ff <= 0;
    end else begin
      rstn_ff <= {1'b1, rstn_ff[4:1]};
    end
  end

  wire rstn_sync = rstn_ff[0];

  wire sck_o;
  wire sck_t;
  wire cclk_o = rstn_sync ? sck_o : io_clk_i;
  wire cclk_t = rstn_sync ? sck_t : 1'b0;

  (* KEEP = "true" *)
  STARTUPE2 #(
    .PROG_USR      ("FALSE"),
    .SIM_CCLK_FREQ (0.0)
  ) startupe2 (
    .CFGCLK    (),
    .CFGMCLK   (),
    .EOS       (),
    .PREQ      (),
    .CLK       (1'b0),
    .GSR       (1'b0),
    .GTS       (1'b0),
    .KEYCLEARB (1'b0),
    .PACK      (1'b0),
    .USRCCLKO  (cclk_o),
    .USRCCLKTS (cclk_t),
    .USRDONEO  (1'b1),
    .USRDONETS (1'b0)
  );

  // IOBUFs

  logic [1:0] spi_io_i;
  logic [1:0] spi_io_o;
  logic [1:0] spi_io_t;
  logic       spi_ss_o;
  logic       spi_ss_t;

  IOBUF spi_io_0_iobuf (
    .I(spi_io_o[0]),
    .IO(spi_io_io[0]),
    .O(spi_io_i[0]),
    .T(spi_io_t[0])
  );
  IOBUF spi_io_1_iobuf (
    .I(spi_io_o[1]),
    .IO(spi_io_io[1]),
    .O(spi_io_i[1]),
    .T(spi_io_t[1])
  );
  OBUFT spi_ss_obuf (
    .I(spi_ss_o),
    .O(spi_ss_io),
    .T(spi_ss_t)
  );

  wire ar_ready;
  assign axi_ar_ready = ar_ready && rstn_sync;

  // FPGA will read bitstream starting from address 0, so we flip the MSB bit
  // so that firmware located at the upper half is considered as being at address 0.
  wire [AddrWidth-1:0] ar_addr = {~axi_ar.addr[AddrWidth-1], axi_ar.addr[AddrWidth-2:0]};

  axi_quad_spi_0 spi_flash (
    // SPI port
    .ext_spi_clk (io_clk_i),
    .io0_i       (spi_io_i[0]),
    .io0_o       (spi_io_o[0]),
    .io0_t       (spi_io_t[0]),
    .io1_i       (spi_io_i[1]),
    .io1_o       (spi_io_o[1]),
    .io1_t       (spi_io_t[1]),
    .sck_i       (1'b0),
    .sck_o       (sck_o),
    .sck_t       (sck_t),
    .ss_i        (1'b0),
    .ss_o        (spi_ss_o),
    .ss_t        (spi_ss_t),
    // AXI port
    .s_axi4_aclk    (clk_i),
    .s_axi4_aresetn (rstn_sync),
    .s_axi4_arready (ar_ready),
    .s_axi4_arvalid (axi_ar_valid && rstn_sync),
    .s_axi4_araddr  (ar_addr),
    .s_axi4_arid    (axi_ar.id),
    .s_axi4_arburst (axi_ar.burst),
    .s_axi4_arcache (axi_ar.cache),
    .s_axi4_arlen   (axi_ar.len),
    .s_axi4_arlock  (axi_ar.lock),
    .s_axi4_arprot  (axi_ar.prot),
    .s_axi4_arsize  (axi_ar.size),
    .s_axi4_awready (),
    .s_axi4_awvalid (1'b0),
    .s_axi4_awaddr  ('x),
    .s_axi4_awid    ('x),
    .s_axi4_awburst ('x),
    .s_axi4_awcache ('x),
    .s_axi4_awlen   ('x),
    .s_axi4_awlock  ('x),
    .s_axi4_awprot  ('x),
    .s_axi4_awsize  ('x),
    .s_axi4_bready  (1'b0),
    .s_axi4_bvalid  (),
    .s_axi4_bid     (),
    .s_axi4_bresp   (),
    .s_axi4_rready  (axi_r_ready),
    .s_axi4_rvalid  (axi_r_valid),
    .s_axi4_rid     (axi_r.id),
    .s_axi4_rdata   (axi_r.data),
    .s_axi4_rlast   (axi_r.last),
    .s_axi4_rresp   (axi_r.resp),
    .s_axi4_wready  (),
    .s_axi4_wvalid  (1'b0),
    .s_axi4_wdata   ('x),
    .s_axi4_wlast   ('x),
    .s_axi4_wstrb   ('x),
    // AXI-Lite port (unconnected)
    .s_axi_aclk    (clk_i),
    .s_axi_aresetn (rstn_sync),
    .s_axi_arready (),
    .s_axi_arvalid (1'b0),
    .s_axi_araddr  ('0),
    .s_axi_awready (),
    .s_axi_awvalid (1'b0),
    .s_axi_awaddr  ('0),
    .s_axi_bready  (1'b0),
    .s_axi_bvalid  (),
    .s_axi_bresp   (),
    .s_axi_rready  (1'b0),
    .s_axi_rvalid  (),
    .s_axi_rdata   (),
    .s_axi_rresp   (),
    .s_axi_wready  (),
    .s_axi_wvalid  (1'b0),
    .s_axi_wdata   ('0),
    .s_axi_wstrb   ('1),
    .ip2intc_irpt  ()
  );

  // TileLink to AXI bridge

  tl_axi_adapter #(
    .DataWidth   (DataWidth),
    .AddrWidth   (AddrWidth),
    .SourceWidth (SourceWidth),
    .IdWidth     (SourceWidth)
  ) adapter (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    `TL_FORWARD_DEVICE_PORT(host, link),
    `AXI_CONNECT_HOST_PORT(device, axi)
  );

endmodule
