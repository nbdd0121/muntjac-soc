`include "axi_util.svh"
`include "tl_util.svh"

module ddr #(
  parameter DataWidth   = 128,
  parameter AddrWidth   = 27,
  parameter SourceWidth = 8
) (
  // Clock and reset
  input  sys_clk_i,
  input  sys_rst_ni,

  output clk_o,
  output io_clk_o,
  output rst_no,

  // IO port
  output [12:0] ddr2_sdram_addr,
  output [2:0]  ddr2_sdram_ba,
  output        ddr2_sdram_cas_n,
  output [0:0]  ddr2_sdram_ck_n,
  output [0:0]  ddr2_sdram_ck_p,
  output [0:0]  ddr2_sdram_cke,
  output [0:0]  ddr2_sdram_cs_n,
  output [1:0]  ddr2_sdram_dm,
  inout  [15:0] ddr2_sdram_dq,
  inout  [1:0]  ddr2_sdram_dqs_n,
  inout  [1:0]  ddr2_sdram_dqs_p,
  output [0:0]  ddr2_sdram_odt,
  output        ddr2_sdram_ras_n,
  output        ddr2_sdram_we_n,

  // TileLink port
  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, 1, link)
);

  `AXI_DECLARE(DataWidth, AddrWidth, SourceWidth, axi);

  // Clock wizard

  wire mig_input_clk;

  clk_wiz_ddr clk_wiz (
    .clk_in1  (sys_clk_i),
    .resetn   (sys_rst_ni),
    .clk_out1 (mig_input_clk),
    .clk_out2 (clk_o),
    .clk_out3 (io_clk_o),
    .locked   (rst_no)
  );

  wire mig_clk;
  wire mig_clk_rstn;

  mig_7series_0 ddr_ctrl (
    // Clock
    .sys_clk_i       (mig_input_clk),
    .sys_rst         (rst_no),
    .ui_clk          (mig_clk),
    .ui_clk_sync_rst (),
    .ui_addn_clk_0   (),
    .ui_addn_clk_1   (),
    .ui_addn_clk_2   (),
    .ui_addn_clk_3   (),
    .ui_addn_clk_4   (),
    .mmcm_locked     (mig_clk_rstn),
    // DDR interface
    .ddr2_addr  (ddr2_sdram_addr),
    .ddr2_ba    (ddr2_sdram_ba),
    .ddr2_cas_n (ddr2_sdram_cas_n),
    .ddr2_ck_n  (ddr2_sdram_ck_n),
    .ddr2_ck_p  (ddr2_sdram_ck_p),
    .ddr2_cke   (ddr2_sdram_cke),
    .ddr2_cs_n  (ddr2_sdram_cs_n),
    .ddr2_dm    (ddr2_sdram_dm),
    .ddr2_dq    (ddr2_sdram_dq),
    .ddr2_dqs_n (ddr2_sdram_dqs_n),
    .ddr2_dqs_p (ddr2_sdram_dqs_p),
    .ddr2_odt   (ddr2_sdram_odt),
    .ddr2_ras_n (ddr2_sdram_ras_n),
    .ddr2_we_n  (ddr2_sdram_we_n),
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
    .device_temp_i       ('0),
    .app_sr_req          ('0),
    .app_sr_active       (  ),
    .app_ref_req         ('0),
    .app_ref_ack         (  ),
    .app_zq_req          ('0),
    .app_zq_ack          (  ),
    .init_calib_complete (  )
  );

  // Clock converter

  `AXI_DECLARE(DataWidth, AddrWidth, SourceWidth, axi_sync);

  axi_clock_converter_ddr clock_cvt (
    .s_axi_aclk     (clk_o),
    .s_axi_aresetn  (rst_no),
    .s_axi_arready  (axi_sync_ar_ready),
    .s_axi_arvalid  (axi_sync_ar_valid),
    .s_axi_araddr   (axi_sync_ar.addr),
    .s_axi_arburst  (axi_sync_ar.burst),
    .s_axi_arcache  (axi_sync_ar.cache),
    .s_axi_arid     (axi_sync_ar.id),
    .s_axi_arlen    (axi_sync_ar.len),
    .s_axi_arlock   (axi_sync_ar.lock),
    .s_axi_arprot   (axi_sync_ar.prot),
    .s_axi_arqos    (axi_sync_ar.qos),
    .s_axi_arregion (axi_sync_ar.region),
    .s_axi_arsize   (axi_sync_ar.size),
    .s_axi_awready  (axi_sync_aw_ready),
    .s_axi_awvalid  (axi_sync_aw_valid),
    .s_axi_awaddr   (axi_sync_aw.addr),
    .s_axi_awburst  (axi_sync_aw.burst),
    .s_axi_awcache  (axi_sync_aw.cache),
    .s_axi_awid     (axi_sync_aw.id),
    .s_axi_awlen    (axi_sync_aw.len),
    .s_axi_awlock   (axi_sync_aw.lock),
    .s_axi_awprot   (axi_sync_aw.prot),
    .s_axi_awqos    (axi_sync_aw.qos),
    .s_axi_awregion (axi_sync_aw.region),
    .s_axi_awsize   (axi_sync_aw.size),
    .s_axi_bready   (axi_sync_b_ready),
    .s_axi_bvalid   (axi_sync_b_valid),
    .s_axi_bid      (axi_sync_b.id),
    .s_axi_bresp    (axi_sync_b.resp),
    .s_axi_rready   (axi_sync_r_ready),
    .s_axi_rvalid   (axi_sync_r_valid),
    .s_axi_rdata    (axi_sync_r.data),
    .s_axi_rid      (axi_sync_r.id),
    .s_axi_rlast    (axi_sync_r.last),
    .s_axi_rresp    (axi_sync_r.resp),
    .s_axi_wready   (axi_sync_w_ready),
    .s_axi_wvalid   (axi_sync_w_valid),
    .s_axi_wdata    (axi_sync_w.data),
    .s_axi_wlast    (axi_sync_w.last),
    .s_axi_wstrb    (axi_sync_w.strb),
    .m_axi_aclk     (mig_clk),
    .m_axi_aresetn  (mig_clk_rstn),
    .m_axi_arready  (axi_ar_ready),
    .m_axi_arvalid  (axi_ar_valid),
    .m_axi_araddr   (axi_ar.addr),
    .m_axi_arburst  (axi_ar.burst),
    .m_axi_arcache  (axi_ar.cache),
    .m_axi_arid     (axi_ar.id),
    .m_axi_arlen    (axi_ar.len),
    .m_axi_arlock   (axi_ar.lock),
    .m_axi_arprot   (axi_ar.prot),
    .m_axi_arqos    (axi_ar.qos),
    .m_axi_arregion (axi_ar.region),
    .m_axi_arsize   (axi_ar.size),
    .m_axi_awready  (axi_aw_ready),
    .m_axi_awvalid  (axi_aw_valid),
    .m_axi_awaddr   (axi_aw.addr),
    .m_axi_awburst  (axi_aw.burst),
    .m_axi_awcache  (axi_aw.cache),
    .m_axi_awid     (axi_aw.id),
    .m_axi_awlen    (axi_aw.len),
    .m_axi_awlock   (axi_aw.lock),
    .m_axi_awprot   (axi_aw.prot),
    .m_axi_awqos    (axi_aw.qos),
    .m_axi_awregion (axi_aw.region),
    .m_axi_awsize   (axi_aw.size),
    .m_axi_bready   (axi_b_ready),
    .m_axi_bvalid   (axi_b_valid),
    .m_axi_bid      (axi_b.id),
    .m_axi_bresp    (axi_b.resp),
    .m_axi_rready   (axi_r_ready),
    .m_axi_rvalid   (axi_r_valid),
    .m_axi_rdata    (axi_r.data),
    .m_axi_rid      (axi_r.id),
    .m_axi_rlast    (axi_r.last),
    .m_axi_rresp    (axi_r.resp),
    .m_axi_wready   (axi_w_ready),
    .m_axi_wvalid   (axi_w_valid),
    .m_axi_wdata    (axi_w.data),
    .m_axi_wlast    (axi_w.last),
    .m_axi_wstrb    (axi_w.strb)
  );

  // TileLink to AXI bridge

  tl_axi_adapter #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .IdWidth (SourceWidth)
  ) adapter (
    .clk_i (clk_o),
    .rst_ni (rst_no),
    `TL_FORWARD_DEVICE_PORT(host, link),
    `AXI_CONNECT_HOST_PORT(device, axi_sync)
  );

endmodule
