module tl_axi_top  #(
    parameter SourceWidth   = 1,
    parameter SinkWidth     = 1,
    parameter AddrWidth     = 56,
    parameter DataWidth     = 64,
    parameter SizeWidth     = 3
) (
    input clk,
    input rstn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWID" *)
    (* X_INTERFACE_PARAMETER = "CLK_DOMAIN clk,HAS_CACHE 0,HAS_LOCK 0,HAS_PROT 0,HAS_QOS 0,HAS_REGION 0" *)
    output [0:0] mem_aw_id,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWADDR" *)
    output [AddrWidth-1:0] mem_aw_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWLEN" *)
    output [7:0] mem_aw_len,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWSIZE" *)
    output [2:0] mem_aw_size,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWBURST" *)
    output [1:0] mem_aw_burst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWVALID" *)
    output mem_aw_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWREADY" *)
    input  mem_aw_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM WDATA" *)
    output [DataWidth-1:0] mem_w_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM WSTRB" *)
    output [DataWidth/8-1:0] mem_w_strb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM WLAST" *)
    output mem_w_last,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM WVALID" *)
    output mem_w_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM WREADY" *)
    input  mem_w_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM BID" *)
    input  [0:0] mem_b_id,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM BRESP" *)
    input  [1:0] mem_b_resp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM BVALID" *)
    input  mem_b_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM BREADY" *)
    output mem_b_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARID" *)
    output [0:0] mem_ar_id,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARADDR" *)
    output [AddrWidth-1:0] mem_ar_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARLEN" *)
    output [7:0] mem_ar_len,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARSIZE" *)
    output [2:0] mem_ar_size,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARBURST" *)
    output [1:0] mem_ar_burst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARLOCK" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARVALID" *)
    output mem_ar_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARREADY" *)
    input  mem_ar_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RID" *)
    input  [0:0] mem_r_id,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RDATA" *)
    input  [DataWidth-1:0] mem_r_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RRESP" *)
    input  [1:0] mem_r_resp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RLAST" *)
    input  mem_r_last,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RVALID" *)
    input  mem_r_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RREADY" *)
    output mem_r_ready,

  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_ready" *)
  output                       cache_a_ready,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_valid" *)
  input                        cache_a_valid,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_opcode" *)
  input                  [2:0] cache_a_opcode,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_param" *)
  input                  [2:0] cache_a_param,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_size" *)
  input        [SizeWidth-1:0] cache_a_size,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_source" *)
  input      [SourceWidth-1:0] cache_a_source,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_address" *)
  input        [AddrWidth-1:0] cache_a_address,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_mask" *)
  input      [DataWidth/8-1:0] cache_a_mask,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_corrupt" *)
  input                        cache_a_corrupt,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_data" *)
  input        [DataWidth-1:0] cache_a_data,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_ready" *)
  input                        cache_b_ready,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_valid" *)
  output                       cache_b_valid,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_opcode" *)
  output                 [2:0] cache_b_opcode,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_param" *)
  output                 [2:0] cache_b_param,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_size" *)
  output       [SizeWidth-1:0] cache_b_size,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_source" *)
  output     [SourceWidth-1:0] cache_b_source,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_address" *)
  output       [AddrWidth-1:0] cache_b_address,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_mask" *)
  output     [DataWidth/8-1:0] cache_b_mask,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_corrupt" *)
  output                       cache_b_corrupt,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_data" *)
  output       [DataWidth-1:0] cache_b_data,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_ready" *)
  output                       cache_c_ready,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_valid" *)
  input                        cache_c_valid,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_opcode" *)
  input                  [2:0] cache_c_opcode,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_param" *)
  input                  [2:0] cache_c_param,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_size" *)
  input        [SizeWidth-1:0] cache_c_size,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_source" *)
  input      [SourceWidth-1:0] cache_c_source,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_address" *)
  input        [AddrWidth-1:0] cache_c_address,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_corrupt" *)
  input                        cache_c_corrupt,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_data" *)
  input        [DataWidth-1:0] cache_c_data,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_ready" *)
  input                        cache_d_ready,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_valid" *)
  output                       cache_d_valid,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_opcode" *)
  output                 [2:0] cache_d_opcode,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_param" *)
  output                 [1:0] cache_d_param,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_size" *)
  output       [SizeWidth-1:0] cache_d_size,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_source" *)
  output     [SourceWidth-1:0] cache_d_source,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_sink" *)
  output       [SinkWidth-1:0] cache_d_sink,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_denied" *)
  output                       cache_d_denied,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_corrupt" *)
  output                       cache_d_corrupt,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_data" *)
  output       [DataWidth-1:0] cache_d_data,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE e_ready" *)
  output                       cache_e_ready,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE e_valid" *)
  input                        cache_e_valid,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE e_sink" *)
  input        [SinkWidth-1:0] cache_e_sink
);

    tl_axi_wrapper #(
        .SourceWidth (SourceWidth),
        .SinkWidth (SinkWidth),
        .AddrWidth (AddrWidth),
        .DataWidth (DataWidth),
        .SizeWidth (SizeWidth)
    ) wrapper (
        .clk    (clk),
        .rstn   (rstn),
        .mem_aw_id      (mem_aw_id),
        .mem_aw_addr    (mem_aw_addr),
        .mem_aw_len (mem_aw_len),
        .mem_aw_size    (mem_aw_size),
        .mem_aw_burst   (mem_aw_burst),
        .mem_aw_lock    (),
        .mem_aw_cache   (),
        .mem_aw_prot    (),
        .mem_aw_region  (),
        .mem_aw_qos (),
        .mem_aw_valid   (mem_aw_valid),
        .mem_aw_ready   (mem_aw_ready),
        .mem_w_data (mem_w_data),
        .mem_w_strb (mem_w_strb),
        .mem_w_last (mem_w_last),
        .mem_w_valid    (mem_w_valid),
        .mem_w_ready    (mem_w_ready),
        .mem_b_id   (mem_b_id),
        .mem_b_resp (mem_b_resp),
        .mem_b_valid    (mem_b_valid),
        .mem_b_ready    (mem_b_ready),
        .mem_ar_id  (mem_ar_id),
        .mem_ar_addr    (mem_ar_addr),
        .mem_ar_len (mem_ar_len),
        .mem_ar_size    (mem_ar_size),
        .mem_ar_burst   (mem_ar_burst),
        .mem_ar_lock    (),
        .mem_ar_cache   (),
        .mem_ar_prot    (),
        .mem_ar_region  (),
        .mem_ar_qos (),
        .mem_ar_valid   (mem_ar_valid),
        .mem_ar_ready   (mem_ar_ready),
        .mem_r_id   (mem_r_id),
        .mem_r_data (mem_r_data),
        .mem_r_resp (mem_r_resp),
        .mem_r_last (mem_r_last),
        .mem_r_valid    (mem_r_valid),
        .mem_r_ready    (mem_r_ready),
        .cache_a_ready (cache_a_ready),
        .cache_a_valid (cache_a_valid),
        .cache_a_opcode (cache_a_opcode),
        .cache_a_param (cache_a_param),
        .cache_a_size (cache_a_size),
        .cache_a_source (cache_a_source),
        .cache_a_address (cache_a_address),
        .cache_a_mask (cache_a_mask),
        .cache_a_corrupt (cache_a_corrupt),
        .cache_a_data (cache_a_data),
        .cache_b_ready (cache_b_ready),
        .cache_b_valid (cache_b_valid),
        .cache_b_opcode (cache_b_opcode),
        .cache_b_param (cache_b_param),
        .cache_b_size (cache_b_size),
        .cache_b_source (cache_b_source),
        .cache_b_address (cache_b_address),
        .cache_b_mask (cache_b_mask),
        .cache_b_corrupt (cache_b_corrupt),
        .cache_b_data (cache_b_data),
        .cache_c_ready (cache_c_ready),
        .cache_c_valid (cache_c_valid),
        .cache_c_opcode (cache_c_opcode),
        .cache_c_param (cache_c_param),
        .cache_c_size (cache_c_size),
        .cache_c_source (cache_c_source),
        .cache_c_address (cache_c_address),
        .cache_c_corrupt (cache_c_corrupt),
        .cache_c_data (cache_c_data),
        .cache_d_ready (cache_d_ready),
        .cache_d_valid (cache_d_valid),
        .cache_d_opcode (cache_d_opcode),
        .cache_d_param (cache_d_param),
        .cache_d_size (cache_d_size),
        .cache_d_source (cache_d_source),
        .cache_d_sink (cache_d_sink),
        .cache_d_denied (cache_d_denied),
        .cache_d_corrupt (cache_d_corrupt),
        .cache_d_data (cache_d_data),
        .cache_e_ready (cache_e_ready),
        .cache_e_valid (cache_e_valid),
        .cache_e_sink (cache_e_sink)
    );

endmodule
