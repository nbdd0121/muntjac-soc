`include "axi_util.svh"
`include "tl_util.svh"

module ddr #(
  parameter DataWidth   = 128,
  parameter AddrWidth   = 29,
  parameter SourceWidth = 8
) (
  // Clock and reset
  input  sys_clk_i,
  input  sys_rst_ni,

  output clk_o,
  output io_clk_o,
  output rst_no,

  // IO port
  output [14:0] ddr3_sdram_addr,
  output [2:0]  ddr3_sdram_ba,
  output        ddr3_sdram_cas_n,
  output [0:0]  ddr3_sdram_ck_n,
  output [0:0]  ddr3_sdram_ck_p,
  output [0:0]  ddr3_sdram_cke,
  output [1:0]  ddr3_sdram_dm,
  inout  [15:0] ddr3_sdram_dq,
  inout  [1:0]  ddr3_sdram_dqs_n,
  inout  [1:0]  ddr3_sdram_dqs_p,
  output [0:0]  ddr3_sdram_odt,
  output        ddr3_sdram_ras_n,
  output        ddr3_sdram_reset_n,
  output        ddr3_sdram_we_n,

  // TileLink port
  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, 1, link)
);

  `AXI_DECLARE(DataWidth, AddrWidth, SourceWidth, axi);

  wire ref_clk;
  wire mig_clk;

  mig_7series_0 ddr_ctrl (
    // Clock
    .sys_clk_i       (sys_clk_i),
    .clk_ref_i       (ref_clk),
    .sys_rst         (sys_rst_ni),
    .ui_clk          (mig_clk),
    .ui_clk_sync_rst (),
    .ui_addn_clk_0   (ref_clk),
    .ui_addn_clk_1   (clk_o),
    .ui_addn_clk_2   (io_clk_o),
    .ui_addn_clk_3   (),
    .ui_addn_clk_4   (),
    .mmcm_locked     (rst_no),
    // DDR interface
    .ddr3_addr    (ddr3_sdram_addr),
    .ddr3_ba      (ddr3_sdram_ba),
    .ddr3_cas_n   (ddr3_sdram_cas_n),
    .ddr3_ck_n    (ddr3_sdram_ck_n),
    .ddr3_ck_p    (ddr3_sdram_ck_p),
    .ddr3_cke     (ddr3_sdram_cke),
    .ddr3_dm      (ddr3_sdram_dm),
    .ddr3_dq      (ddr3_sdram_dq),
    .ddr3_dqs_n   (ddr3_sdram_dqs_n),
    .ddr3_dqs_p   (ddr3_sdram_dqs_p),
    .ddr3_odt     (ddr3_sdram_odt),
    .ddr3_ras_n   (ddr3_sdram_ras_n),
    .ddr3_reset_n (ddr3_sdram_reset_n),
    .ddr3_we_n    (ddr3_sdram_we_n),
    // AXI interface
    .aresetn       (rst_no),
    .s_axi_arready (axi_ar_ready),
    .s_axi_arvalid (axi_ar_valid),
    .s_axi_araddr  (axi_ar.addr),
    .s_axi_arburst (axi_ar.burst),
    .s_axi_arcache (axi_ar.cache),
    .s_axi_arid    (axi_ar.id),
    .s_axi_arlen   (axi_ar.len),
    .s_axi_arlock  (axi_ar.lock),
    .s_axi_arprot  (axi_ar.prot),
    .s_axi_arqos   (axi_ar.qos),
    .s_axi_arsize  (axi_ar.size),
    .s_axi_awready (axi_aw_ready),
    .s_axi_awvalid (axi_aw_valid),
    .s_axi_awaddr  (axi_aw.addr),
    .s_axi_awburst (axi_aw.burst),
    .s_axi_awcache (axi_aw.cache),
    .s_axi_awid    (axi_aw.id),
    .s_axi_awlen   (axi_aw.len),
    .s_axi_awlock  (axi_aw.lock),
    .s_axi_awprot  (axi_aw.prot),
    .s_axi_awqos   (axi_aw.qos),
    .s_axi_awsize  (axi_aw.size),
    .s_axi_bready  (axi_b_ready),
    .s_axi_bvalid  (axi_b_valid),
    .s_axi_bid     (axi_b.id),
    .s_axi_bresp   (axi_b.resp),
    .s_axi_rready  (axi_r_ready),
    .s_axi_rvalid  (axi_r_valid),
    .s_axi_rdata   (axi_r.data),
    .s_axi_rid     (axi_r.id),
    .s_axi_rlast   (axi_r.last),
    .s_axi_rresp   (axi_r.resp),
    .s_axi_wready  (axi_w_ready),
    .s_axi_wvalid  (axi_w_valid),
    .s_axi_wdata   (axi_w.data),
    .s_axi_wlast   (axi_w.last),
    .s_axi_wstrb   (axi_w.strb),
    // Other signals
    .device_temp         (  ),
    .app_sr_req          ('0),
    .app_sr_active       (  ),
    .app_ref_req         ('0),
    .app_ref_ack         (  ),
    .app_zq_req          ('0),
    .app_zq_ack          (  ),
    .init_calib_complete (  )
  );

  // TileLink to AXI bridge

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, 1, link_sync);

  tl_axi_adapter #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .IdWidth (SourceWidth)
  ) adapter (
    .clk_i (mig_clk),
    .rst_ni (rst_no),
    `TL_CONNECT_DEVICE_PORT(host, link_sync),
    `AXI_CONNECT_HOST_PORT(device, axi)
  );

  // Clock converter

  tl_fifo_async #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (1),
    .RequestFifoDepth (32),
    .GrantFifoDepth (32)
  ) cdc (
    .clk_host_i (clk_o),
    .rst_host_ni (rst_no),
    `TL_FORWARD_DEVICE_PORT(host, link),
    .clk_device_i (mig_clk),
    .rst_device_ni (rst_no),
    `TL_CONNECT_HOST_PORT(device, link_sync)
  );

endmodule
