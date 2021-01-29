module tl_axi_wrapper #(
    parameter SourceWidth   = 1,
    parameter SinkWidth     = 1,
    parameter AddrWidth     = 56,
    parameter DataWidth     = 64,
    parameter SizeWidth     = 3
) (
    input clk,
    input rstn,

    output [0:0] mem_aw_id,
    output [AddrWidth-1:0] mem_aw_addr,
    output [7:0] mem_aw_len,
    output [2:0] mem_aw_size,
    output [1:0] mem_aw_burst,
    output [0:0] mem_aw_lock,
    output [3:0] mem_aw_cache,
    output [2:0] mem_aw_prot,
    output [3:0] mem_aw_region,
    output [3:0] mem_aw_qos,
    output mem_aw_valid,
    input  mem_aw_ready,
    output [DataWidth-1:0] mem_w_data,
    output [DataWidth/8-1:0] mem_w_strb,
    output mem_w_last,
    output mem_w_valid,
    input  mem_w_ready,
    input  [0:0] mem_b_id,
    input  [1:0] mem_b_resp,
    input  mem_b_valid,
    output mem_b_ready,
    output [0:0] mem_ar_id,
    output [AddrWidth-1:0] mem_ar_addr,
    output [7:0] mem_ar_len,
    output [2:0] mem_ar_size,
    output [1:0] mem_ar_burst,
    output [0:0] mem_ar_lock,
    output [3:0] mem_ar_cache,
    output [2:0] mem_ar_prot,
    output [3:0] mem_ar_region,
    output [3:0] mem_ar_qos,
    output mem_ar_valid,
    input  mem_ar_ready,
    input  [0:0] mem_r_id,
    input  [DataWidth-1:0] mem_r_data,
    input  [1:0] mem_r_resp,
    input  mem_r_last,
    input  mem_r_valid,
    output mem_r_ready,

  output                       cache_a_ready,
  input                        cache_a_valid,
  input                  [2:0] cache_a_opcode,
  input                  [2:0] cache_a_param,
  input        [SizeWidth-1:0] cache_a_size,
  input      [SourceWidth-1:0] cache_a_source,
  input        [AddrWidth-1:0] cache_a_address,
  input      [DataWidth/8-1:0] cache_a_mask,
  input                        cache_a_corrupt,
  input        [DataWidth-1:0] cache_a_data,
  input                        cache_b_ready,
  output                       cache_b_valid,
  output                 [2:0] cache_b_opcode,
  output                 [2:0] cache_b_param,
  output       [SizeWidth-1:0] cache_b_size,
  output     [SourceWidth-1:0] cache_b_source,
  output       [AddrWidth-1:0] cache_b_address,
  output     [DataWidth/8-1:0] cache_b_mask,
  output                       cache_b_corrupt,
  output       [DataWidth-1:0] cache_b_data,
  output                       cache_c_ready,
  input                        cache_c_valid,
  input                  [2:0] cache_c_opcode,
  input                  [2:0] cache_c_param,
  input        [SizeWidth-1:0] cache_c_size,
  input      [SourceWidth-1:0] cache_c_source,
  input        [AddrWidth-1:0] cache_c_address,
  input                        cache_c_corrupt,
  input        [DataWidth-1:0] cache_c_data,
  input                        cache_d_ready,
  output                       cache_d_valid,
  output                 [2:0] cache_d_opcode,
  output                 [1:0] cache_d_param,
  output       [SizeWidth-1:0] cache_d_size,
  output     [SourceWidth-1:0] cache_d_source,
  output       [SinkWidth-1:0] cache_d_sink,
  output                       cache_d_denied,
  output                       cache_d_corrupt,
  output       [DataWidth-1:0] cache_d_data,
  output                       cache_e_ready,
  input                        cache_e_valid,
  input        [SinkWidth-1:0] cache_e_sink
);

    axi_channel #(
        .ID_WIDTH (1),
        .ADDR_WIDTH (AddrWidth),
        .DATA_WIDTH (DataWidth)
    ) mem(clk, rstn);

    tl_channel #(
        .SourceWidth (SourceWidth),
        .SinkWidth (SinkWidth),
        .AddrWidth (AddrWidth),
        .DataWidth (DataWidth),
        .SizeWidth (SizeWidth)
    ) cache();

    assign mem_aw_id        = mem.aw_id;
    assign mem_aw_addr      = mem.aw_addr;
    assign mem_aw_len       = mem.aw_len;
    assign mem_aw_size      = mem.aw_size;
    assign mem_aw_burst     = mem.aw_burst;
    assign mem_aw_lock      = mem.aw_lock;
    assign mem_aw_cache     = mem.aw_cache;
    assign mem_aw_prot      = mem.aw_prot;
    assign mem_aw_qos       = mem.aw_qos;
    assign mem_aw_region    = mem.aw_region;
    assign mem_aw_valid     = mem.aw_valid;
    assign mem.aw_ready     = mem_aw_ready;

    assign mem_w_data   = mem.w_data;
    assign mem_w_strb   = mem.w_strb;
    assign mem_w_last   = mem.w_last;
    assign mem_w_valid  = mem.w_valid;
    assign mem.w_ready  = mem_w_ready;

    assign mem.b_id     = mem_b_id;
    assign mem.b_resp   = mem_b_resp;
    assign mem.b_user   = 'x;
    assign mem.b_valid  = mem_b_valid;
    assign mem_b_ready  = mem.b_ready;

    assign mem_ar_id        = mem.ar_id;
    assign mem_ar_addr      = mem.ar_addr;
    assign mem_ar_len       = mem.ar_len;
    assign mem_ar_size      = mem.ar_size;
    assign mem_ar_burst     = mem.ar_burst;
    assign mem_ar_lock      = mem.ar_lock;
    assign mem_ar_cache     = mem.ar_cache;
    assign mem_ar_prot      = mem.ar_prot;
    assign mem_ar_qos       = mem.ar_qos;
    assign mem_ar_region    = mem.ar_region;
    assign mem_ar_valid     = mem.ar_valid;
    assign mem.ar_ready     = mem_ar_ready;

    assign mem.r_id     = mem_r_id;
    assign mem.r_data   = mem_r_data;
    assign mem.r_resp   = mem_r_resp;
    assign mem.r_last   = mem_r_last;
    assign mem.r_user   = 'x;
    assign mem.r_valid  = mem_r_valid;
    assign mem_r_ready  = mem.r_ready;

  assign cache_a_ready = cache.a_ready;
  assign cache.a_valid = cache_a_valid;
  assign cache.a_opcode = cache_a_opcode;
  assign cache.a_param = cache_a_param;
  assign cache.a_size = cache_a_size;
  assign cache.a_source = cache_a_source;
  assign cache.a_address = cache_a_address;
  assign cache.a_mask = cache_a_mask;
  assign cache.a_corrupt = cache_a_corrupt;
  assign cache.a_data = cache_a_data;
  assign cache.b_ready = cache_b_ready;
  assign cache_b_valid = cache.b_valid;
  assign cache_b_opcode = cache.b_opcode;
  assign cache_b_param = cache.b_param;
  assign cache_b_size = cache.b_size;
  assign cache_b_source = cache.b_source;
  assign cache_b_address = cache.b_address;
  assign cache_b_mask = cache.b_mask;
  assign cache_b_corrupt = cache.b_corrupt;
  assign cache_b_data = cache.b_data;
  assign cache_c_ready = cache.c_ready;
  assign cache.c_valid = cache_c_valid;
  assign cache.c_opcode = cache_c_opcode;
  assign cache.c_param = cache_c_param;
  assign cache.c_size = cache_c_size;
  assign cache.c_source = cache_c_source;
  assign cache.c_address = cache_c_address;
  assign cache.c_corrupt = cache_c_corrupt;
  assign cache.c_data = cache_c_data;
  assign cache.d_ready = cache_d_ready;
  assign cache_d_valid = cache.d_valid;
  assign cache_d_opcode = cache.d_opcode;
  assign cache_d_param = cache.d_param;
  assign cache_d_size = cache.d_size;
  assign cache_d_source = cache.d_source;
  assign cache_d_sink = cache.d_sink;
  assign cache_d_denied = cache.d_denied;
  assign cache_d_corrupt = cache.d_corrupt;
  assign cache_d_data = cache.d_data;
  assign cache_e_ready = cache.e_ready;
  assign cache.e_valid = cache_e_valid;
  assign cache.e_sink = cache_e_sink;

    tl_adapter_axi #(
        .SourceWidth (SourceWidth),
        .SinkWidth (SinkWidth),
        .AddrWidth (AddrWidth),
        .DataWidth (DataWidth),
        .SizeWidth (SizeWidth)
    ) inst (clk, rstn, cache, mem);
endmodule
