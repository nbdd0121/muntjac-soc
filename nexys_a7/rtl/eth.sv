`include "axi_util.svh"
`include "axi_lite_util.svh"
`include "tl_util.svh"

module eth #(
  parameter IoDataWidth   = 128,
  parameter IoAddrWidth   = 30,
  parameter IoSourceWidth = 5,
  parameter DmaSourceWidth = 2,
  parameter DmaSinkWidth = 1
) (
  // Clock and reset
  input clk_i,
  input rst_ni,
  input io_clk_i,

  // IO port
  output       mdc,
  inout        mdio,
  (* clock_buffer_type = "none" *)
  output       rmii_ref_clk,
  output [1:0] rmii_txd,
  output       rmii_tx_en,
  input  [1:0] rmii_rxd,
  input        rmii_csr_dv,
  input        rmii_rx_er,
  output       phy_rst_n,
  input        phy_irq,

  // TileLink port
  `TL_DECLARE_DEVICE_PORT(IoDataWidth, IoAddrWidth, IoSourceWidth, 1, io),
  `TL_DECLARE_HOST_PORT(64, 32, DmaSourceWidth, DmaSinkWidth, dma),

  output eth_irq_o,
  output dma_tx_irq_o,
  output dma_rx_irq_o,
  output phy_irq_o
);

  // PHY IRQ only needs to be synchronised
  prim_flop_2sync #(
    .Width(1)
  ) phy_irq_sync (
    .clk_i,
    .rst_ni,
    .d_i (~phy_irq),
    .q_o (phy_irq_o)
  );

  logic gtx_clk;
  logic rmii_ref_clk_shifted;

  clk_wiz_eth gtx_clk_wiz (
    .clk_in1  (io_clk_i),
    .resetn   (rst_ni),
    .clk_out1 (gtx_clk),
    .clk_out2 (rmii_ref_clk_shifted)
  );

  assign rmii_ref_clk = io_clk_i;

  logic       mii_rx_clk;
  logic [3:0] mii_rxd;
  logic       mii_rx_dv;
  logic       mii_rx_err;
  logic       mii_tx_clk;
  logic [3:0] mii_txd;
  logic       mii_tx_en;
  logic       mii_tx_er;

  mii_to_rmii_0 rmii_adapter (
    .rst_n           (rst_ni),
    .ref_clk         (io_clk_i),
    .mac2rmii_tx_en  (mii_tx_en),
    .mac2rmii_txd    (mii_txd),
    .mac2rmii_tx_er  (mii_tx_er),
    .rmii2mac_tx_clk (mii_tx_clk),
    .rmii2mac_rx_clk (mii_rx_clk),
    .rmii2mac_col    (),
    .rmii2mac_crs    (),
    .rmii2mac_rx_dv  (mii_rx_dv),
    .rmii2mac_rx_er  (mii_rx_er),
    .rmii2mac_rxd    (mii_rxd),
    .phy2rmii_crs_dv (rmii_csr_dv),
    .phy2rmii_rx_er  (rmii_rx_er),
    .phy2rmii_rxd    (rmii_rxd),
    .rmii2phy_txd    (rmii_txd),
    .rmii2phy_tx_en  (rmii_tx_en)
  );

  `AXI_LITE_DECLARE(32, 18, axi_lite);

  logic        txc_rstn;
  logic        txc_tready;
  logic        txc_tvalid;
  logic [31:0] txc_tdata;
  logic [3:0]  txc_tkeep;
  logic        txc_tlast;

  logic        txd_rstn;
  logic        txd_tready;
  logic        txd_tvalid;
  logic [31:0] txd_tdata;
  logic [3:0]  txd_tkeep;
  logic        txd_tlast;

  logic        rxs_rstn;
  logic        rxs_tready;
  logic        rxs_tvalid;
  logic [31:0] rxs_tdata;
  logic [3:0]  rxs_tkeep;
  logic        rxs_tlast;

  logic        rxd_rstn;
  logic        rxd_tready;
  logic        rxd_tvalid;
  logic [31:0] rxd_tdata;
  logic [3:0]  rxd_tkeep;
  logic        rxd_tlast;

  logic mdio_i;
  logic mdio_o;
  logic mdio_t;

  IOBUF mdio_buf (
    .I  (mdio_o),
    .IO (mdio),
    .O  (mdio_i),
    .T  (mdio_t)
  );

  axi_ethernet_0 eth (
    // AXI-lite port
    .s_axi_lite_clk    (clk_i),
    .s_axi_lite_resetn (rst_ni),
    .s_axi_arready     (axi_lite_ar_ready),
    .s_axi_arvalid     (axi_lite_ar_valid),
    .s_axi_araddr      (axi_lite_ar.addr),
    .s_axi_awready     (axi_lite_aw_ready),
    .s_axi_awvalid     (axi_lite_aw_valid),
    .s_axi_awaddr      (axi_lite_aw.addr),
    .s_axi_bready      (axi_lite_b_ready),
    .s_axi_bvalid      (axi_lite_b_valid),
    .s_axi_bresp       (axi_lite_b.resp),
    .s_axi_rready      (axi_lite_r_ready),
    .s_axi_rvalid      (axi_lite_r_valid),
    .s_axi_rdata       (axi_lite_r.data),
    .s_axi_rresp       (axi_lite_r.resp),
    .s_axi_wready      (axi_lite_w_ready),
    .s_axi_wvalid      (axi_lite_w_valid),
    .s_axi_wdata       (axi_lite_w.data),
    .s_axi_wstrb       (axi_lite_w.strb),
    // Streaming ports from/to DMA
    .axis_clk          (clk_i),
    .axi_txc_arstn     (txc_rstn),
    .s_axis_txc_tready (txc_tready),
    .s_axis_txc_tvalid (txc_tvalid),
    .s_axis_txc_tdata  (txc_tdata),
    .s_axis_txc_tkeep  (txc_tkeep),
    .s_axis_txc_tlast  (txc_tlast),
    .axi_txd_arstn     (txd_rstn),
    .s_axis_txd_tready (txd_tready),
    .s_axis_txd_tvalid (txd_tvalid),
    .s_axis_txd_tdata  (txd_tdata),
    .s_axis_txd_tkeep  (txd_tkeep),
    .s_axis_txd_tlast  (txd_tlast),
    .axi_rxs_arstn     (rxs_rstn),
    .m_axis_rxs_tready (rxs_tready),
    .m_axis_rxs_tvalid (rxs_tvalid),
    .m_axis_rxs_tdata  (rxs_tdata),
    .m_axis_rxs_tkeep  (rxs_tkeep),
    .m_axis_rxs_tlast  (rxs_tlast),
    .axi_rxd_arstn     (rxd_rstn),
    .m_axis_rxd_tready (rxd_tready),
    .m_axis_rxd_tvalid (rxd_tvalid),
    .m_axis_rxd_tdata  (rxd_tdata),
    .m_axis_rxd_tkeep  (rxd_tkeep),
    .m_axis_rxd_tlast  (rxd_tlast),
    // Clock, reset and interrupts
    .mac_irq           (),
    .interrupt         (eth_irq_o),
    .gtx_clk           (gtx_clk),
    .phy_rst_n         (phy_rst_n),
    // IO ports
    .mii_rx_clk        (mii_rx_clk),
    .mii_rxd           (mii_rxd),
    .mii_rx_dv         (mii_rx_dv),
    .mii_rx_er         (mii_rx_er),
    .mii_tx_clk        (mii_tx_clk),
    .mii_txd           (mii_txd),
    .mii_tx_en         (mii_tx_en),
    .mii_tx_er         (mii_tx_er),
    .mdio_mdc          (mdc),
    .mdio_mdio_i       (mdio_i),
    .mdio_mdio_o       (mdio_o),
    .mdio_mdio_t       (mdio_t)
  );

  ////////////////
  // region DMA //

  `AXI_LITE_DECLARE(32, 10, dma_ctrl);
  `AXI_DECLARE(32, 32, 1, dma_sg);
  `AXI_DECLARE(64, 32, 1, dma_axi);

  // IDs are not used by Xilinx AXI DMA.
  assign dma_sg_aw.id = 1'b0;
  assign dma_sg_ar.id = 1'b0;
  assign dma_axi_aw.id = 1'b0;
  assign dma_axi_ar.id = 1'b0;

  axi_dma_eth dma (
    // AXI-lite port
    .s_axi_lite_aclk          (clk_i),
    .axi_resetn               (rst_ni),
    .s_axi_lite_awready       (dma_ctrl_aw_ready),
    .s_axi_lite_awvalid       (dma_ctrl_aw_valid),
    .s_axi_lite_awaddr        (dma_ctrl_aw.addr),
    .s_axi_lite_wready        (dma_ctrl_w_ready),
    .s_axi_lite_wvalid        (dma_ctrl_w_valid),
    .s_axi_lite_wdata         (dma_ctrl_w.data),
    .s_axi_lite_bready        (dma_ctrl_b_ready),
    .s_axi_lite_bvalid        (dma_ctrl_b_valid),
    .s_axi_lite_bresp         (dma_ctrl_b.resp),
    .s_axi_lite_arready       (dma_ctrl_ar_ready),
    .s_axi_lite_arvalid       (dma_ctrl_ar_valid),
    .s_axi_lite_araddr        (dma_ctrl_ar.addr),
    .s_axi_lite_rready        (dma_ctrl_r_ready),
    .s_axi_lite_rvalid        (dma_ctrl_r_valid),
    .s_axi_lite_rdata         (dma_ctrl_r.data),
    .s_axi_lite_rresp         (dma_ctrl_r.resp),
    // AXI ports
    .m_axi_sg_aclk            (clk_i),
    .m_axi_sg_awready         (dma_sg_aw_ready),
    .m_axi_sg_awvalid         (dma_sg_aw_valid),
    .m_axi_sg_awaddr          (dma_sg_aw.addr),
    .m_axi_sg_awlen           (dma_sg_aw.len),
    .m_axi_sg_awsize          (dma_sg_aw.size),
    .m_axi_sg_awburst         (dma_sg_aw.burst),
    .m_axi_sg_awprot          (dma_sg_aw.prot),
    .m_axi_sg_awcache         (dma_sg_aw.cache),
    .m_axi_sg_wready          (dma_sg_w_ready),
    .m_axi_sg_wvalid          (dma_sg_w_valid),
    .m_axi_sg_wdata           (dma_sg_w.data),
    .m_axi_sg_wstrb           (dma_sg_w.strb),
    .m_axi_sg_wlast           (dma_sg_w.last),
    .m_axi_sg_bready          (dma_sg_b_ready),
    .m_axi_sg_bvalid          (dma_sg_b_valid),
    .m_axi_sg_bresp           (dma_sg_b.resp),
    .m_axi_sg_arready         (dma_sg_ar_ready),
    .m_axi_sg_arvalid         (dma_sg_ar_valid),
    .m_axi_sg_araddr          (dma_sg_ar.addr),
    .m_axi_sg_arlen           (dma_sg_ar.len),
    .m_axi_sg_arsize          (dma_sg_ar.size),
    .m_axi_sg_arburst         (dma_sg_ar.burst),
    .m_axi_sg_arprot          (dma_sg_ar.prot),
    .m_axi_sg_arcache         (dma_sg_ar.cache),
    .m_axi_sg_rready          (dma_sg_r_ready),
    .m_axi_sg_rvalid          (dma_sg_r_valid),
    .m_axi_sg_rdata           (dma_sg_r.data),
    .m_axi_sg_rresp           (dma_sg_r.resp),
    .m_axi_sg_rlast           (dma_sg_r.last),
    .m_axi_mm2s_aclk          (clk_i),
    .m_axi_mm2s_arready       (dma_axi_ar_ready),
    .m_axi_mm2s_arvalid       (dma_axi_ar_valid),
    .m_axi_mm2s_araddr        (dma_axi_ar.addr),
    .m_axi_mm2s_arlen         (dma_axi_ar.len),
    .m_axi_mm2s_arsize        (dma_axi_ar.size),
    .m_axi_mm2s_arburst       (dma_axi_ar.burst),
    .m_axi_mm2s_arprot        (dma_axi_ar.prot),
    .m_axi_mm2s_arcache       (dma_axi_ar.cache),
    .m_axi_mm2s_rready        (dma_axi_r_ready),
    .m_axi_mm2s_rvalid        (dma_axi_r_valid),
    .m_axi_mm2s_rdata         (dma_axi_r.data),
    .m_axi_mm2s_rresp         (dma_axi_r.resp),
    .m_axi_mm2s_rlast         (dma_axi_r.last),
    .m_axi_s2mm_aclk          (clk_i),
    .m_axi_s2mm_awready       (dma_axi_aw_ready),
    .m_axi_s2mm_awvalid       (dma_axi_aw_valid),
    .m_axi_s2mm_awaddr        (dma_axi_aw.addr),
    .m_axi_s2mm_awlen         (dma_axi_aw.len),
    .m_axi_s2mm_awsize        (dma_axi_aw.size),
    .m_axi_s2mm_awburst       (dma_axi_aw.burst),
    .m_axi_s2mm_awprot        (dma_axi_aw.prot),
    .m_axi_s2mm_awcache       (dma_axi_aw.cache),
    .m_axi_s2mm_wready        (dma_axi_w_ready),
    .m_axi_s2mm_wvalid        (dma_axi_w_valid),
    .m_axi_s2mm_wdata         (dma_axi_w.data),
    .m_axi_s2mm_wstrb         (dma_axi_w.strb),
    .m_axi_s2mm_wlast         (dma_axi_w.last),
    .m_axi_s2mm_bready        (dma_axi_b_ready),
    .m_axi_s2mm_bvalid        (dma_axi_b_valid),
    .m_axi_s2mm_bresp         (dma_axi_b.resp),
    // Streaming ports
    .mm2s_cntrl_reset_out_n   (txc_rstn),
    .m_axis_mm2s_cntrl_tready (txc_tready),
    .m_axis_mm2s_cntrl_tvalid (txc_tvalid),
    .m_axis_mm2s_cntrl_tdata  (txc_tdata),
    .m_axis_mm2s_cntrl_tkeep  (txc_tkeep),
    .m_axis_mm2s_cntrl_tlast  (txc_tlast),
    .mm2s_prmry_reset_out_n   (txd_rstn),
    .m_axis_mm2s_tready       (txd_tready),
    .m_axis_mm2s_tvalid       (txd_tvalid),
    .m_axis_mm2s_tdata        (txd_tdata),
    .m_axis_mm2s_tkeep        (txd_tkeep),
    .m_axis_mm2s_tlast        (txd_tlast),
    .s2mm_sts_reset_out_n     (rxs_rstn),
    .s_axis_s2mm_sts_tready   (rxs_tready),
    .s_axis_s2mm_sts_tvalid   (rxs_tvalid),
    .s_axis_s2mm_sts_tdata    (rxs_tdata),
    .s_axis_s2mm_sts_tkeep    (rxs_tkeep),
    .s_axis_s2mm_sts_tlast    (rxs_tlast),
    .s2mm_prmry_reset_out_n   (rxd_rstn),
    .s_axis_s2mm_tready       (rxd_tready),
    .s_axis_s2mm_tvalid       (rxd_tvalid),
    .s_axis_s2mm_tdata        (rxd_tdata),
    .s_axis_s2mm_tkeep        (rxd_tkeep),
    .s_axis_s2mm_tlast        (rxd_tlast),
    // Interrupts
    .mm2s_introut             (dma_tx_irq_o),
    .s2mm_introut             (dma_rx_irq_o),
    .axi_dma_tstvec           ()
  );

  // endregion
  ////////////////

  //////////////////////////////////////
  // region IO Crossbar and adapaters //

  `TL_DECLARE(32, 18, IoSourceWidth, 1, mac_io);
  `TL_DECLARE(32, 10, IoSourceWidth, 1, dma_io);

  tl_axi_lite_adapter #(
    .DataWidth (32),
    .AddrWidth (18),
    .SourceWidth (IoSourceWidth)
  ) mac_adapter (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, mac_io),
    `AXI_CONNECT_HOST_PORT(device, axi_lite)
  );

  tl_axi_lite_adapter #(
    .DataWidth (32),
    .AddrWidth (10),
    .SourceWidth (IoSourceWidth)
  ) dma_io_bridge (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, dma_io),
    `AXI_CONNECT_HOST_PORT(device, dma_ctrl)
  );

  localparam [IoAddrWidth-1:0] MacBaseAddr = 'h100000;
  localparam [IoAddrWidth-1:0] MacBaseMask = 'h 3FFFF;

  localparam [IoAddrWidth-1:0] DmaBaseAddr = 'h200000;
  localparam [IoAddrWidth-1:0] DmaBaseMask = 'h   3FF;

  `TL_DECLARE_ARR(IoDataWidth, IoAddrWidth, IoSourceWidth, 1, io_split, [1:0]);

  tl_socket_1n #(
    .DataWidth (IoDataWidth),
    .AddrWidth (IoAddrWidth),
    .SourceWidth (IoSourceWidth),
    .NumLinks    (2),
    .NumAddressRange (1),
    .AddressBase ({DmaBaseAddr}),
    .AddressMask ({DmaBaseMask}),
    .AddressLink ({1'd       1})
  ) io_socket_1n (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, io),
    `TL_CONNECT_HOST_PORT(device, io_split)
  );

  tl_adapter #(
    .HostDataWidth (IoDataWidth),
    .DeviceDataWidth (32),
    .HostAddrWidth (IoAddrWidth),
    .DeviceAddrWidth (18),
    .HostSourceWidth (IoSourceWidth),
    .DeviceSourceWidth (IoSourceWidth),
    .HostSinkWidth (1),
    .DeviceSinkWidth (1),
    .HostMaxSize ($clog2(IoDataWidth) - 3),
    .DeviceMaxSize (2),
    .HostFifo (1'b0),
    .DeviceFifo (1'b1)
  ) mac_io_adapter (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT_IDX(host, io_split, [0]),
    `TL_CONNECT_HOST_PORT(device, mac_io)
  );

  tl_adapter #(
    .HostDataWidth (IoDataWidth),
    .DeviceDataWidth (32),
    .HostAddrWidth (IoAddrWidth),
    .DeviceAddrWidth (10),
    .HostSourceWidth (IoSourceWidth),
    .DeviceSourceWidth (IoSourceWidth),
    .HostSinkWidth (1),
    .DeviceSinkWidth (1),
    .HostMaxSize ($clog2(IoDataWidth) - 3),
    .DeviceMaxSize (2),
    .HostFifo (1'b0),
    .DeviceFifo (1'b1)
  ) dma_io_adapter (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT_IDX(host, io_split, [1]),
    `TL_CONNECT_HOST_PORT(device, dma_io)
  );

  // endregion
  //////////////////////////////////////

  ///////////////////////////////////////
  // region DMA Crossbar and adapaters //

  `TL_DECLARE(64, 32, DmaSourceWidth - 1, DmaSinkWidth, dma_tl);
  `TL_DECLARE(32, 32, DmaSourceWidth - 1, DmaSinkWidth, sg_tl);

  axi_tl_adapter #(
    .DataWidth (64),
    .AddrWidth (32),
    .SourceWidth (DmaSourceWidth - 1),
    .SinkWidth (DmaSinkWidth),
    .IdWidth (1)
  ) dma_bridge (
    .clk_i,
    .rst_ni,
    `AXI_CONNECT_DEVICE_PORT(host, dma_axi),
    `TL_CONNECT_HOST_PORT(device, dma_tl)
  );

  axi_tl_adapter #(
    .DataWidth (32),
    .AddrWidth (32),
    .SourceWidth (DmaSourceWidth - 1),
    .SinkWidth (DmaSinkWidth),
    .IdWidth (1)
  ) sg_bridge (
    .clk_i,
    .rst_ni,
    `AXI_CONNECT_DEVICE_PORT(host, dma_sg),
    `TL_CONNECT_HOST_PORT(device, sg_tl)
  );

  // Widen SG interface from 32-bit to 64-bit.
  `TL_DECLARE(64, 32, DmaSourceWidth - 1, DmaSinkWidth, sg_wide);

  tl_adapter #(
    .HostDataWidth (32),
    .DeviceDataWidth (64),
    .HostAddrWidth (32),
    .DeviceAddrWidth (32),
    .HostSourceWidth (DmaSourceWidth - 1),
    .DeviceSourceWidth (DmaSourceWidth - 1),
    .HostSinkWidth (DmaSinkWidth),
    .DeviceSinkWidth (DmaSinkWidth)
  ) sg_widener (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, sg_tl),
    `TL_CONNECT_HOST_PORT(device, sg_wide)
  );

  // Shift source IDs.
  `TL_DECLARE_ARR(64, 32, DmaSourceWidth, DmaSinkWidth, dma_split, [1:0]);

  localparam [DmaSourceWidth-1:0] DmaSourceBase = 0;
  localparam [DmaSourceWidth-1:0] DmaSourceMask = 2 ** (DmaSourceWidth - 1) - 1;
  localparam [DmaSinkWidth-1:0]   SgSourceBase = 2 ** (DmaSourceWidth - 1);
  localparam [DmaSinkWidth-1:0]   SgSourceMask = 2 ** (DmaSourceWidth - 1) - 1;

  tl_source_shifter #(
    .DataWidth (64),
    .AddrWidth (32),
    .HostSourceWidth (DmaSourceWidth - 1),
    .DeviceSourceWidth (DmaSourceWidth),
    .SinkWidth (DmaSinkWidth),
    .SourceBase (DmaSourceBase),
    .SourceMask (DmaSourceMask)
  ) dma_source_shifter (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, dma_tl),
    `TL_CONNECT_HOST_PORT_IDX(device, dma_split, [0])
  );

  tl_source_shifter #(
    .DataWidth (64),
    .AddrWidth (32),
    .HostSourceWidth (DmaSourceWidth - 1),
    .DeviceSourceWidth (DmaSourceWidth),
    .SinkWidth (DmaSinkWidth),
    .SourceBase (SgSourceBase),
    .SourceMask (SgSourceMask)
  ) sg_source_shifter (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, sg_wide),
    `TL_CONNECT_HOST_PORT_IDX(device, dma_split, [1])
  );

  tl_socket_m1 #(
    .DataWidth   (64),
    .AddrWidth   (32),
    .SourceWidth (DmaSourceWidth),
    .SinkWidth   (DmaSinkWidth),
    .NumLinks       (2),
    .NumCachedLinks (0),
    .NumSourceRange (1),
    .SourceBase ({SgSourceBase}),
    .SourceMask ({SgSourceMask}),
    .SourceLink ({1'd        1})
  ) dma_socket_m1 (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, dma_split),
    `TL_FORWARD_HOST_PORT(device, dma)
  );

  // endregion
  ///////////////////////////////////////

endmodule
