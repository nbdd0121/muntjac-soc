module axi_tl_top  #(
    parameter ID_WIDTH      = 1,
    parameter SourceWidth   = 1,
    parameter SinkWidth     = 1,
    parameter AddrWidth     = 56,
    parameter DataWidth     = 64,
    parameter SizeWidth     = 3
) (
    input clk,
    input rstn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWID" *)
    (* X_INTERFACE_PARAMETER = "CLK_DOMAIN clk,MAX_BURST_LENGTH 256,SUPPORTS_NARROW_BURST 0,HAS_CACHE 0,HAS_LOCK 0,HAS_PROT 0,HAS_QOS 0,HAS_REGION 0" *)
    input  [0:0] mem_aw_id,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWADDR" *)
    input  [AddrWidth-1:0] mem_aw_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWLEN" *)
    input  [7:0] mem_aw_len,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWSIZE" *)
    input  [2:0] mem_aw_size,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWBURST" *)
    input  [1:0] mem_aw_burst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWVALID" *)
    input  mem_aw_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM AWREADY" *)
    output mem_aw_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM WDATA" *)
    input  [DataWidth-1:0] mem_w_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM WSTRB" *)
    input  [DataWidth/8-1:0] mem_w_strb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM WLAST" *)
    input  mem_w_last,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM WVALID" *)
    input  mem_w_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM WREADY" *)
    output mem_w_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM BID" *)
    output [0:0] mem_b_id,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM BRESP" *)
    output [1:0] mem_b_resp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM BVALID" *)
    output mem_b_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM BREADY" *)
    input  mem_b_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARID" *)
    input  [0:0] mem_ar_id,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARADDR" *)
    input  [AddrWidth-1:0] mem_ar_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARLEN" *)
    input  [7:0] mem_ar_len,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARSIZE" *)
    input  [2:0] mem_ar_size,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARBURST" *)
    input  [1:0] mem_ar_burst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARLOCK" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARVALID" *)
    input  mem_ar_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM ARREADY" *)
    output mem_ar_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RID" *)
    output [0:0] mem_r_id,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RDATA" *)
    output [DataWidth-1:0] mem_r_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RRESP" *)
    output [1:0] mem_r_resp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RLAST" *)
    output mem_r_last,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RVALID" *)
    output mem_r_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM RREADY" *)
    input  mem_r_ready,

  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_ready" *)
  input                        cache_a_ready,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_valid" *)
  output                       cache_a_valid,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_opcode" *)
  output                 [2:0] cache_a_opcode,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_param" *)
  output                 [2:0] cache_a_param,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_size" *)
  output       [SizeWidth-1:0] cache_a_size,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_source" *)
  output     [SourceWidth-1:0] cache_a_source,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_address" *)
  output       [AddrWidth-1:0] cache_a_address,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_mask" *)
  output     [DataWidth/8-1:0] cache_a_mask,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_corrupt" *)
  output                       cache_a_corrupt,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE a_data" *)
  output       [DataWidth-1:0] cache_a_data,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_ready" *)
  output                       cache_b_ready,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_valid" *)
  input                        cache_b_valid,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_opcode" *)
  input                  [2:0] cache_b_opcode,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_param" *)
  input                  [2:0] cache_b_param,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_size" *)
  input        [SizeWidth-1:0] cache_b_size,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_source" *)
  input      [SourceWidth-1:0] cache_b_source,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_address" *)
  input        [AddrWidth-1:0] cache_b_address,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_mask" *)
  input      [DataWidth/8-1:0] cache_b_mask,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_corrupt" *)
  input                        cache_b_corrupt,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE b_data" *)
  input        [DataWidth-1:0] cache_b_data,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_ready" *)
  input                        cache_c_ready,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_valid" *)
  output                       cache_c_valid,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_opcode" *)
  output                 [2:0] cache_c_opcode,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_param" *)
  output                 [2:0] cache_c_param,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_size" *)
  output       [SizeWidth-1:0] cache_c_size,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_source" *)
  output     [SourceWidth-1:0] cache_c_source,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_address" *)
  output       [AddrWidth-1:0] cache_c_address,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_corrupt" *)
  output                       cache_c_corrupt,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE c_data" *)
  output       [DataWidth-1:0] cache_c_data,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_ready" *)
  output                       cache_d_ready,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_valid" *)
  input                        cache_d_valid,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_opcode" *)
  input                  [2:0] cache_d_opcode,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_param" *)
  input                  [1:0] cache_d_param,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_size" *)
  input        [SizeWidth-1:0] cache_d_size,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_source" *)
  input      [SourceWidth-1:0] cache_d_source,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_sink" *)
  input        [SinkWidth-1:0] cache_d_sink,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_denied" *)
  input                        cache_d_denied,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_corrupt" *)
  input                        cache_d_corrupt,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE d_data" *)
  input        [DataWidth-1:0] cache_d_data,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE e_ready" *)
  input                        cache_e_ready,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE e_valid" *)
  output                       cache_e_valid,
  (* X_INTERFACE_INFO = "garyguo.net:uncore:tl:1.0 CACHE e_sink" *)
  output       [SinkWidth-1:0] cache_e_sink
);

    axi_tl_wrapper #(
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
