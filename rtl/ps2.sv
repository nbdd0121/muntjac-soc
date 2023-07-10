`include "tl_util.svh"
`include "axi_util.svh"
`include "axi_lite_util.svh"

module ps2 # (
  parameter SourceWidth = 1
) (
  // Clock and reset
  input clk_i,
  input rst_ni,

  // IO ports
  inout ps2_clk,
  inout ps2_dat,

  // TileLink port
  `TL_DECLARE_DEVICE_PORT(32, 5, SourceWidth, 1, link),
 
  // Interrupt
  output irq_o
);

  logic ps2_clk_i;
  logic ps2_clk_o;
  logic ps2_clk_t;
  logic ps2_dat_i;
  logic ps2_dat_o;
  logic ps2_dat_t;

  IOBUF ps2_clk_iobuf (
    .I  (ps2_clk_o),
    .IO (ps2_clk),
    .O  (ps2_clk_i),
    .T  (ps2_clk_t)
  );

  IOBUF ps2_dat_iobuf (
    .I  (ps2_dat_o),
    .IO (ps2_dat),
    .O  (ps2_dat_i),
    .T  (ps2_dat_t)
  );

  `AXI_LITE_DECLARE(32, 5, axi);

  axi_ps2_0 (
    .PS2_Data_I (ps2_dat_i),
    .PS2_Data_O (ps2_dat_o),
    .PS2_Data_T (ps2_dat_t),
    .PS2_Clk_I  (ps2_clk_i),
    .PS2_Clk_O  (ps2_clk_o),
    .PS2_Clk_T  (ps2_clk_t),
    .PS2_interrupt (irq_o),
    .S_AXI_awaddr (axi_aw.addr),
    .S_AXI_awprot (axi_aw.prot),
    .S_AXI_awvalid (axi_aw_valid),
    .S_AXI_awready (axi_aw_ready),
    .S_AXI_wdata (axi_w.data),
    .S_AXI_wstrb (axi_w.strb),
    .S_AXI_wvalid (axi_w_valid),
    .S_AXI_wready (axi_w_ready),
    .S_AXI_bresp (axi_b.resp),
    .S_AXI_bvalid (axi_b_valid),
    .S_AXI_bready (axi_b_ready),
    .S_AXI_araddr (axi_ar.addr),
    .S_AXI_arprot (axi_ar.prot),
    .S_AXI_arvalid (axi_ar_valid),
    .S_AXI_arready (axi_ar_ready),
    .S_AXI_rdata (axi_r.data),
    .S_AXI_rresp (axi_r.resp),
    .S_AXI_rvalid (axi_r_valid),
    .S_AXI_rready (axi_r_ready),
    .S_AXI_aclk (clk_i),
    .S_AXI_aresetn (rst_ni)
  );

  tl_axi_lite_adapter #(
    .DataWidth   (32),
    .AddrWidth   (5),
    .SourceWidth (SourceWidth)
  ) adapter (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, link),
    `AXI_CONNECT_HOST_PORT(device, axi)
  );

endmodule
