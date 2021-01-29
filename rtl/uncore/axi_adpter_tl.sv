`include "tl_util.svh"

// XXX: This is just a functional model, not optimised for performance.
// TL to AXI bridge
//
// Supports: Get, PutFullData, PutPartialData
module axi_adapter_tl import tl_pkg::*; import axi_common::*; #(
    parameter  int unsigned ID_WIDTH    = 1,
    parameter  int unsigned SourceWidth = 1,
    parameter  int unsigned SinkWidth   = 1,
    parameter  int unsigned AddrWidth   = 56,
    parameter  int unsigned DataWidth   = 64,
    parameter  int unsigned SizeWidth   = 3,
    parameter  int unsigned MaxSize     = 6
) (
    input  logic       clk_i,
    input  logic       rst_ni,

    axi_channel.slave  axi,
    tl_channel.host    tl
);

  localparam int unsigned MaskWidth = DataWidth / 8;

  initial begin
    if (SourceWidth != tl.SourceWidth) begin
      $fatal(1, "SourceWidth does not match");
    end
  end

  ////////////
  // Wiring //
  ////////////

  tl_channel #(
    .DataWidth(DataWidth),
    .AddrWidth(AddrWidth),
    .SizeWidth(SizeWidth),
    .SourceWidth(SourceWidth),
    .SinkWidth(SinkWidth)
  ) tl_reg();

  tl_regslice #(
    .DataWidth(DataWidth),
    .AddrWidth(AddrWidth),
    .SizeWidth(SizeWidth),
    .SourceWidth(SourceWidth),
    .SinkWidth(SinkWidth),
    .RequestMode (0),
    .GrantMode (1)
  ) regslice (
    .clk_i,
    .rst_ni,
    .host (tl_reg),
    .device (tl)
  );

  `TL_DECLARE(DataWidth, AddrWidth, SizeWidth, SourceWidth, SinkWidth, tl);
  `TL_DEVICE_INTF(tl, tl_reg);

  // We don't use channel B, C, E.
  assign tl_b_ready = 1'b1;
  assign tl_c_valid = 1'b0;
  assign tl_c       = 'x;
  assign tl_e_valid = 1'b1;
  assign tl_e       = 'x;

  wire                   axi_ar_valid = axi.ar_valid;
  wire [ID_WIDTH-1:0]    axi_ar_id    = axi.ar_id;
  wire [AddrWidth-1:0]   axi_ar_addr  = axi.ar_addr;
  wire [7:0]             axi_ar_len   = axi.ar_len;
  wire [2:0]             axi_ar_size  = axi.ar_size;

  wire                   axi_aw_valid = axi.aw_valid;
  wire [ID_WIDTH-1:0]    axi_aw_id    = axi.aw_id;
  wire [AddrWidth-1:0]   axi_aw_addr  = axi.aw_addr;
  wire [7:0]             axi_aw_len   = axi.aw_len;
  wire [2:0]             axi_aw_size  = axi.aw_size;

  wire                   axi_w_valid  = axi.w_valid;
  wire [DataWidth-1:0]   axi_w_data   = axi.w_data;
  wire [DataWidth/8-1:0] axi_w_strb   = axi.w_strb;
  wire                   axi_w_last   = axi.w_last;

  wire                   axi_r_ready  = axi.r_ready;
  wire                   axi_b_ready  = axi.b_ready;

  logic axi_ar_ready;
  logic axi_aw_ready;
  logic axi_w_ready;
  logic axi_r_valid;
  logic [ID_WIDTH-1:0] axi_r_id;
  logic [DataWidth-1:0] axi_r_data;
  resp_t axi_r_resp;
  logic axi_r_last;
  logic axi_b_valid;
  logic [ID_WIDTH-1:0] axi_b_id;
  resp_t axi_b_resp;

  assign axi.ar_ready = axi_ar_ready;
  assign axi.aw_ready = axi_aw_ready;
  assign axi.w_ready = axi_w_ready;
  assign axi.r_valid = axi_r_valid;
  assign axi.r_id = axi_r_id;
  assign axi.r_data = axi_r_data;
  assign axi.r_resp = axi_r_resp;
  assign axi.r_last = axi_r_last;
  assign axi.b_valid = axi_b_valid;
  assign axi.b_id = axi_b_id;
  assign axi.b_resp = axi_b_resp;

  assign axi.r_user = '0;
  assign axi.b_user = '0;

  ///////////////////
  // Burst Tracker //
  ///////////////////

  logic tl_a_last;
  logic tl_d_last;
  
  tl_burst_tracker #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) tl_burst_tracker (
    .clk_i,
    .rst_ni,
    .link_h2d_i (`TL_H2D_PACK(tl)),
    .link_d2h_i (`TL_D2H_PACK(tl)),
    .req_len_o (),
    .prb_len_o (),
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .prb_idx_o (),
    .rel_idx_o (),
    .gnt_idx_o (),
    .req_left_o (),
    .prb_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (),
    .prb_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (tl_a_last),
    .prb_last_o (),
    .rel_last_o (),
    .gnt_last_o (tl_d_last)
  );

  typedef struct packed {
    logic [AddrWidth-1:0] addr;
    logic [7:0] len;
    logic [2:0] size;
  } axi_req_t;

  typedef struct packed {
    axi_req_t req;
    logic has_remaining;
    axi_req_t remaining;
  } frag_t;

  function automatic frag_t fragment(input axi_req_t req);
    if (req.size < $clog2(DataWidth / 8)) begin
      // No narrow burst support.
      fragment.req.addr = req.addr;
      fragment.req.len = req.len;
      fragment.req.size = req.size;
      fragment.has_remaining = 1'b0;
      fragment.remaining = 'x;
    end else begin
      logic [7:0] len_left;
      logic [7:0] alignment;
      logic [7:0] max_size;

      // First compute the largest burst allowed by looking at the len.
      len_left = (req.len + 1) >> 1;
      len_left |= len_left >> 1;
      len_left |= len_left >> 2;
      len_left |= len_left >> 4;

      // Compute the largest burst allowed by natural alignment of address.
      alignment = ((req.addr & (-req.addr)) - 1) >> $clog2(DataWidth / 8);

      // The max allowed size is the min of two.
      max_size = len_left & alignment & (2 ** (MaxSize - $clog2(DataWidth / 8)) - 1);

      fragment.req.addr = req.addr;
      fragment.req.len = max_size;
      fragment.req.size = req.size;
      fragment.has_remaining = max_size != req.len;
      fragment.remaining.addr = req.addr + ((max_size + 1) << $clog2(DataWidth / 8));
      fragment.remaining.len = req.len - max_size - 1;
      fragment.remaining.size = req.size;
    end
  endfunction

  function automatic logic [7:0] tl_size(input logic [7:0] axi_len, input logic [3:0] axi_size);
    if (axi_size < $clog2(DataWidth / 8)) begin
      return axi_size;
    end else begin
      unique case (axi_len)
        0: return $clog2(DataWidth / 8);
        1: return $clog2(DataWidth / 8) + 1;
        2, 3: return $clog2(DataWidth / 8) + 2;
        4, 5, 6, 7: return $clog2(DataWidth / 8) + 3;
      endcase
    end
  endfunction

  function automatic logic [7:0] get_mask(
      input  logic [2:0] addr,
      input  logic [SizeWidth-1:0] size
  );
    unique case (size)
      0: get_mask = 'b1 << addr;
      1: get_mask = 'b11 << addr;
      2: get_mask = 'b1111 << addr;
      default: get_mask = 'b11111111;
    endcase
  endfunction

  enum logic [2:0] {
    StateIdle,
    StateGet,
    StatePut,
    StatePut2,
    StatePut3
  } state_q, state_d;

  logic [ID_WIDTH-1:0] id_q, id_d;
  logic addr_sent_q, addr_sent_d;
  axi_req_t pending_q, pending_d;
  wire frag_t frag = fragment(pending_q);

  always_comb begin
    tl_a_valid = 1'b0;
    tl_a = 'x;
    tl_d_ready = 1'b0;

    axi_ar_ready = 1'b0;
    axi_aw_ready = 1'b0;
    axi_w_ready = 1'b0;
    axi_r_valid = 1'b0;
    axi_r_id = 'x;
    axi_r_data = 'x;
    axi_r_resp = resp_t'('x);
    axi_r_last = 1'bx;
    axi_b_valid = 1'b0;
    axi_b_id = 'x;
    axi_b_resp = resp_t'('x);

    state_d = state_q;
    id_d = id_q;
    pending_d = pending_q;
    addr_sent_d = addr_sent_q;

    unique case (state_q)
      StateIdle: begin
        if (axi_aw_valid) begin
          axi_aw_ready = 1'b1;
          id_d = axi_aw_id;
          pending_d = '{
            // Force the alignment (AXI doesn't mandate it)
            addr: axi_aw_addr >> axi_aw_size << axi_aw_size,
            len: axi_aw_len,
            size: axi_aw_size
          };
          state_d = StatePut;
        end else if (axi_ar_valid) begin
          addr_sent_d = 1'b0;
          axi_ar_ready = 1'b1;
          id_d = axi_ar_id;
          pending_d = '{
            addr: axi_ar_addr >> axi_ar_size << axi_ar_size,
            len: axi_ar_len,
            size: axi_ar_size
          };
          state_d = StateGet;
        end
      end

      StateGet: begin
        tl_a_valid   = !addr_sent_q;
        tl_a.opcode  = Get;
        tl_a.param   = 0;
        tl_a.size    = tl_size(frag.req.len, frag.req.size);
        tl_a.source  = 0;
        tl_a.address = frag.req.addr;
        tl_a.mask    = get_mask(frag.req.addr, frag.req.size);
        tl_a.corrupt = 1'b0;
        tl_a.data   = 'x;

        if (tl_a_ready) begin
          addr_sent_d = 1'b1;
        end

        // Forward TL response to the requestor
        tl_d_ready = axi_r_ready;
        axi_r_valid = tl_d_valid;
        axi_r_id    = id_q;
        axi_r_data  = tl_d.data;
        axi_r_resp  = tl_d.denied ? RESP_SLVERR : RESP_OKAY;
        axi_r_last  = tl_d_last && !frag.has_remaining;

        if (tl_d_valid && tl_d_ready && tl_d_last) begin
          if (frag.has_remaining) begin
            pending_d = frag.remaining;
            addr_sent_d = 1'b0;
          end else begin
            state_d = StateIdle;
          end
        end
      end

      StatePut: begin
        axi_w_ready  = tl_a_ready;
        tl_a_valid   = axi_w_valid;
        tl_a.opcode  = PutPartialData;
        tl_a.param   = 0;
        tl_a.size    = tl_size(frag.req.len, frag.req.size);
        tl_a.source  = 0;
        tl_a.address = frag.req.addr;
        tl_a.mask    = axi_w_strb;
        tl_a.corrupt = 1'b0;
        tl_a.data    = axi_w_data;

        if (tl_a_valid && tl_a_ready && tl_a_last) begin
          if (frag.has_remaining) begin
            state_d = StatePut2;
            pending_d = frag.remaining;
          end else begin
            state_d = StatePut3;
          end
        end
      end

      StatePut2: begin
        tl_d_ready = 1'b1;
        if (tl_d_valid) begin
          state_d = StatePut;
        end
      end

      StatePut3: begin
        tl_d_ready = axi_b_ready;
        axi_b_valid = tl_d_valid;
        axi_b_id = id_q;
        axi_b_resp = tl_d.denied ? RESP_SLVERR : RESP_OKAY;

        if (tl_d_valid && tl_d_ready) begin
          state_d = StateIdle;
        end
      end

      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) begin
      state_q <= StateIdle;
      id_q <= 'x;
      pending_q <= 'x;
      addr_sent_q <= 1'b0;
    end
    else begin
      state_q <= state_d;
      id_q <= id_d;
      pending_q <= pending_d;
      addr_sent_q <= addr_sent_d;
    end

endmodule
