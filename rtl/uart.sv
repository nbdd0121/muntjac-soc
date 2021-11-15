`include "axi_lite_util.svh"
`include "tl_util.svh"

module uart #(
  parameter DataWidth   = 32,
  parameter AddrWidth   = 13,
  parameter SourceWidth = 1
) (
  // Clock and reset
  input clk_i,
  input rst_ni,
  input io_clk_i,

  // IO ports
  output uart_tx,
  input  uart_rx,
  input  uart_cts,
  output uart_rts,

  // TileLink port
  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, 1, link),
  output irq_o
);

  `AXI_LITE_DECLARE(DataWidth, AddrWidth, axi);

  // Clock wizard

  wire uart_clk;
  clk_wiz_uart clk_wiz (
    .clk_in1  (io_clk_i),
    .resetn   (rst_ni),
    .clk_out1 (uart_clk),
    .locked   ()
  );

  wire uart_ctsn = ~uart_cts;
  wire uart_rtsn;
  assign uart_rts = ~uart_rtsn;

  axi_uart16550_0 uart (
    .s_axi_aclk    (io_clk_i),
    .s_axi_aresetn (rst_ni),
    .ip2intc_irpt  (irq_o),
    .freeze        (1'b0),
    .s_axi_awready (axi_aw_ready),
    .s_axi_awvalid (axi_aw_valid),
    .s_axi_awaddr  (axi_aw.addr),
    .s_axi_wready  (axi_w_ready),
    .s_axi_wvalid  (axi_w_valid),
    .s_axi_wdata   (axi_w.data),
    .s_axi_wstrb   (axi_w.strb),
    .s_axi_bready  (axi_b_ready),
    .s_axi_bvalid  (axi_b_valid),
    .s_axi_bresp   (axi_b.resp),
    .s_axi_arready (axi_ar_ready),
    .s_axi_arvalid (axi_ar_valid),
    .s_axi_araddr  (axi_ar.addr),
    .s_axi_rready  (axi_r_ready),
    .s_axi_rvalid  (axi_r_valid),
    .s_axi_rdata   (axi_r.data),
    .s_axi_rresp   (axi_r.resp),
    .baudoutn (),
    .ctsn   (uart_ctsn),
    .dcdn   (1'b1),
    .ddis   (),
    .dsrn   (1'b1),
    .dtrn   (),
    .out1n  (),
    .out2n  (),
    .rin    (1'b1),
    .rtsn   (uart_rtsn),
    .rxrdyn (),
    .sin    (uart_rx),
    .sout   (uart_tx),
    .txrdyn (),
    .xin    (uart_clk),
    .xout   ()
    );

  // Clock converter

  `AXI_LITE_DECLARE(DataWidth, AddrWidth, axi_sync);

  axi_clock_converter_uart clock_cvt (
    .s_axi_aclk     (clk_i),
    .s_axi_aresetn  (rst_ni),
    .s_axi_arready  (axi_sync_ar_ready),
    .s_axi_arvalid  (axi_sync_ar_valid),
    .s_axi_araddr   (axi_sync_ar.addr),
    .s_axi_arprot   (axi_sync_ar.prot),
    .s_axi_awready  (axi_sync_aw_ready),
    .s_axi_awvalid  (axi_sync_aw_valid),
    .s_axi_awaddr   (axi_sync_aw.addr),
    .s_axi_awprot   (axi_sync_aw.prot),
    .s_axi_bready   (axi_sync_b_ready),
    .s_axi_bvalid   (axi_sync_b_valid),
    .s_axi_bresp    (axi_sync_b.resp),
    .s_axi_rready   (axi_sync_r_ready),
    .s_axi_rvalid   (axi_sync_r_valid),
    .s_axi_rdata    (axi_sync_r.data),
    .s_axi_rresp    (axi_sync_r.resp),
    .s_axi_wready   (axi_sync_w_ready),
    .s_axi_wvalid   (axi_sync_w_valid),
    .s_axi_wdata    (axi_sync_w.data),
    .s_axi_wstrb    (axi_sync_w.strb),
    .m_axi_aclk     (io_clk_i),
    .m_axi_aresetn  (rst_ni),
    .m_axi_arready  (axi_ar_ready),
    .m_axi_arvalid  (axi_ar_valid),
    .m_axi_araddr   (axi_ar.addr),
    .m_axi_arprot   (axi_ar.prot),
    .m_axi_awready  (axi_aw_ready),
    .m_axi_awvalid  (axi_aw_valid),
    .m_axi_awaddr   (axi_aw.addr),
    .m_axi_awprot   (axi_aw.prot),
    .m_axi_bready   (axi_b_ready),
    .m_axi_bvalid   (axi_b_valid),
    .m_axi_bresp    (axi_b.resp),
    .m_axi_rready   (axi_r_ready),
    .m_axi_rvalid   (axi_r_valid),
    .m_axi_rdata    (axi_r.data),
    .m_axi_rresp    (axi_r.resp),
    .m_axi_wready   (axi_w_ready),
    .m_axi_wvalid   (axi_w_valid),
    .m_axi_wdata    (axi_w.data),
    .m_axi_wstrb    (axi_w.strb)
  );

  // TileLink to AXI-lite bridge

  tl_axi_lite_adapter #(
    .DataWidth   (DataWidth),
    .AddrWidth   (AddrWidth),
    .SourceWidth (SourceWidth)
  ) adapter (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    `TL_FORWARD_DEVICE_PORT(host, link),
    `AXI_CONNECT_HOST_PORT(device, axi_sync)
  );

endmodule
