module axi_tl_wrapper #(
    parameter ID_WIDTH      = 1,
    parameter SourceWidth   = 1,
    parameter SinkWidth     = 1,
    parameter AddrWidth     = 56,
    parameter DataWidth     = 64,
    parameter SizeWidth     = 3
) (
    input clk,
    input rstn,

    input  [0:0] mem_aw_id,
    input  [AddrWidth-1:0] mem_aw_addr,
    input  [7:0] mem_aw_len,
    input  [2:0] mem_aw_size,
    input  [1:0] mem_aw_burst,
    input  mem_aw_valid,
    output mem_aw_ready,
    input  [DataWidth-1:0] mem_w_data,
    input  [DataWidth/8-1:0] mem_w_strb,
    input  mem_w_last,
    input  mem_w_valid,
    output mem_w_ready,
    output [0:0] mem_b_id,
    output [1:0] mem_b_resp,
    output mem_b_valid,
    input  mem_b_ready,
    input  [0:0] mem_ar_id,
    input  [AddrWidth-1:0] mem_ar_addr,
    input  [7:0] mem_ar_len,
    input  [2:0] mem_ar_size,
    input  [1:0] mem_ar_burst,
    input  mem_ar_valid,
    output mem_ar_ready,
    output [0:0] mem_r_id,
    output [DataWidth-1:0] mem_r_data,
    output [1:0] mem_r_resp,
    output mem_r_last,
    output mem_r_valid,
    input  mem_r_ready,

  input                        cache_a_ready,
  output                       cache_a_valid,
  output                 [2:0] cache_a_opcode,
  output                 [2:0] cache_a_param,
  output       [SizeWidth-1:0] cache_a_size,
  output     [SourceWidth-1:0] cache_a_source,
  output       [AddrWidth-1:0] cache_a_address,
  output     [DataWidth/8-1:0] cache_a_mask,
  output                       cache_a_corrupt,
  output       [DataWidth-1:0] cache_a_data,
  output                       cache_b_ready,
  input                        cache_b_valid,
  input                  [2:0] cache_b_opcode,
  input                  [2:0] cache_b_param,
  input        [SizeWidth-1:0] cache_b_size,
  input      [SourceWidth-1:0] cache_b_source,
  input        [AddrWidth-1:0] cache_b_address,
  input      [DataWidth/8-1:0] cache_b_mask,
  input                        cache_b_corrupt,
  input        [DataWidth-1:0] cache_b_data,
  input                        cache_c_ready,
  output                       cache_c_valid,
  output                 [2:0] cache_c_opcode,
  output                 [2:0] cache_c_param,
  output       [SizeWidth-1:0] cache_c_size,
  output     [SourceWidth-1:0] cache_c_source,
  output       [AddrWidth-1:0] cache_c_address,
  output                       cache_c_corrupt,
  output       [DataWidth-1:0] cache_c_data,
  output                       cache_d_ready,
  input                        cache_d_valid,
  input                  [2:0] cache_d_opcode,
  input                  [1:0] cache_d_param,
  input        [SizeWidth-1:0] cache_d_size,
  input      [SourceWidth-1:0] cache_d_source,
  input        [SinkWidth-1:0] cache_d_sink,
  input                        cache_d_denied,
  input                        cache_d_corrupt,
  input        [DataWidth-1:0] cache_d_data,
  input                        cache_e_ready,
  output                       cache_e_valid,
  output       [SinkWidth-1:0] cache_e_sink
);

    axi_channel #(
        .ID_WIDTH (ID_WIDTH),
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

    assign mem.aw_id        = mem_aw_id;
    assign mem.aw_addr      = mem_aw_addr;
    assign mem.aw_len       = mem_aw_len;
    assign mem.aw_size      = mem_aw_size;
    assign mem.aw_burst     = mem_aw_burst;
    assign mem.aw_lock      = '0;
    assign mem.aw_cache     = '0;
    assign mem.aw_prot      = '0;
    assign mem.aw_qos       = '0;
    assign mem.aw_region    = '0;
    assign mem.aw_user      = '0;
    assign mem.aw_valid     = mem_aw_valid;
    assign mem_aw_ready     = mem.aw_ready;

    assign mem.w_data   = mem_w_data;
    assign mem.w_strb   = mem_w_strb;
    assign mem.w_last   = mem_w_last;
    assign mem.w_user   = '0;
    assign mem.w_valid  = mem_w_valid;
    assign mem_w_ready  = mem.w_ready;

    assign mem_b_id     = mem.b_id;
    assign mem_b_resp   = mem.b_resp;
    assign mem_b_valid  = mem.b_valid;
    assign mem.b_ready  = mem_b_ready;

    assign mem.ar_id        = mem_ar_id;
    assign mem.ar_addr      = mem_ar_addr;
    assign mem.ar_len       = mem_ar_len;
    assign mem.ar_size      = mem_ar_size;
    assign mem.ar_burst     = mem_ar_burst;
    assign mem.ar_lock      = '0;
    assign mem.ar_cache     = '0;
    assign mem.ar_prot      = '0;
    assign mem.ar_qos       = '0;
    assign mem.ar_region    = '0;
    assign mem.ar_user      = '0;
    assign mem.ar_valid     = mem_ar_valid;
    assign mem_ar_ready     = mem.ar_ready;

    assign mem_r_id     = mem.r_id;
    assign mem_r_data   = mem.r_data;
    assign mem_r_resp   = mem.r_resp;
    assign mem_r_last   = mem.r_last;
    assign mem_r_valid  = mem.r_valid;
    assign mem.r_ready  = mem_r_ready;

  assign cache.a_ready = cache_a_ready;
  assign cache_a_valid = cache.a_valid;
  assign cache_a_opcode = cache.a_opcode;
  assign cache_a_param = cache.a_param;
  assign cache_a_size = cache.a_size;
  assign cache_a_source = cache.a_source;
  assign cache_a_address = cache.a_address;
  assign cache_a_mask = cache.a_mask;
  assign cache_a_corrupt = cache.a_corrupt;
  assign cache_a_data = cache.a_data;
  assign cache_b_ready = cache.b_ready;
  assign cache.b_valid = cache_b_valid;
  assign cache.b_opcode = cache_b_opcode;
  assign cache.b_param = cache_b_param;
  assign cache.b_size = cache_b_size;
  assign cache.b_source = cache_b_source;
  assign cache.b_address = cache_b_address;
  assign cache.b_mask = cache_b_mask;
  assign cache.b_corrupt = cache_b_corrupt;
  assign cache.b_data = cache_b_data;
  assign cache.c_ready = cache_c_ready;
  assign cache_c_valid = cache.c_valid;
  assign cache_c_opcode = cache.c_opcode;
  assign cache_c_param = cache.c_param;
  assign cache_c_size = cache.c_size;
  assign cache_c_source = cache.c_source;
  assign cache_c_address = cache.c_address;
  assign cache_c_corrupt = cache.c_corrupt;
  assign cache_c_data = cache.c_data;
  assign cache_d_ready = cache.d_ready;
  assign cache.d_valid = cache_d_valid;
  assign cache.d_opcode = cache_d_opcode;
  assign cache.d_param = cache_d_param;
  assign cache.d_size = cache_d_size;
  assign cache.d_source = cache_d_source;
  assign cache.d_sink = cache_d_sink;
  assign cache.d_denied = cache_d_denied;
  assign cache.d_corrupt = cache_d_corrupt;
  assign cache.d_data = cache_d_data;
  assign cache.e_ready = cache_e_ready;
  assign cache_e_valid = cache.e_valid;
  assign cache_e_sink = cache.e_sink;

    axi_adapter_tl #(
        .ID_WIDTH (ID_WIDTH),
        .SourceWidth (SourceWidth),
        .SinkWidth (SinkWidth),
        .AddrWidth (AddrWidth),
        .DataWidth (DataWidth),
        .SizeWidth (SizeWidth)
    ) inst (clk, rstn, mem, cache);
endmodule
