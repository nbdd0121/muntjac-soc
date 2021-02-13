// XXX: This is just a functional model, not optimised for performance.
// TL to AXI bridge
//
// Supports: Get, PutFullData, PutPartialData
module tl_adapter_axi import tl_pkg::*; #(
    parameter  int unsigned SourceWidth = 1,
    parameter  int unsigned SinkWidth   = 1,
    parameter  int unsigned AddrWidth   = 56,
    parameter  int unsigned DataWidth   = 64,
    parameter  int unsigned SizeWidth   = 3
) (
    input  logic       clk_i,
    input  logic       rst_ni,

    tl_channel.device  tl,
    axi_channel.master axi
);

  localparam int unsigned MaskWidth = DataWidth / 8;

  initial begin
    if (SourceWidth != tl.SourceWidth) begin
      $fatal(1, "SourceWidth does not match");
    end
  end

  // We don't use channel B.
  assign tl.b_valid = 1'b0;
  assign tl.b_opcode = tl_b_op_e'('x);
  assign tl.b_param = 'x;
  assign tl.b_size = 'x;
  assign tl.b_address = 'x;
  assign tl.b_source = 'x;
  assign tl.b_mask = 'x;
  assign tl.b_corrupt = 'x;
  assign tl.b_data = 'x;

  // We don't use channel C and E
  assign tl.c_ready = 1'b0;
  assign tl.e_ready = 1'b0;

  wire                   req_valid   = tl.a_valid;
  wire tl_a_op_e         req_opcode  = tl.a_opcode;
  wire [2:0]             req_param   = tl.a_param;
  wire [SizeWidth-1:0]   req_size    = tl.a_size;
  wire [SourceWidth-1:0] req_source  = tl.a_source;
  wire [AddrWidth-1:0]   req_address = tl.a_address;
  wire [DataWidth/8-1:0] req_mask    = tl.a_mask;
  wire [DataWidth-1:0]   req_data    = tl.a_data;

  wire                   grant_ready = tl.d_ready;

  wire mem_aw_ready = axi.aw_ready;
  wire mem_w_ready = axi.w_ready;
  wire mem_b_valid = axi.b_valid;
  wire mem_ar_ready = axi.ar_ready;
  wire mem_r_valid = axi.r_valid;
  wire [DataWidth-1:0] mem_r_data = axi.r_data;
  wire mem_r_last = axi.r_last;

  enum logic [3:0] {
    STATE_IDLE,
    STATE_GET,
    STATE_PUT,
    STATE_PUT_2,
    STATE_PUT_3
  } state = STATE_IDLE, state_d;

  logic [SizeWidth-1:0] size_q, size_d;
  tl_a_op_e opcode_q, opcode_d;
  logic [2:0] param_q, param_d;
  logic [SourceWidth-1:0] source_q, source_d;
  logic [AddrWidth-1:0] address, address_d;
  logic [DataWidth-1:0] data, data_d;
  logic [DataWidth/8-1:0] mask, mask_d;
  logic addr_sent, addr_sent_d;
  logic data_sent, data_sent_d;

  logic [7:0] len_q, len_d;
  logic granted_q, granted_d;

  assign axi.aw_id     = '0;
  assign axi.aw_burst  = axi_common::BURST_INCR;
  assign axi.aw_lock   = '0;
  assign axi.aw_cache  = '0;
  assign axi.aw_prot   = '0;
  assign axi.aw_qos    = '0;
  assign axi.aw_region = '0;
  assign axi.aw_user   = 'x;
  assign axi.w_user    = 'x;
  assign axi.ar_id     = '0;
  assign axi.ar_burst  = axi_common::BURST_INCR;
  assign axi.ar_lock   = '0;
  assign axi.ar_cache  = '0;
  assign axi.ar_prot   = '0;
  assign axi.ar_qos    = '0;
  assign axi.ar_region = '0;
  assign axi.ar_user   = 'x;

  function automatic logic [7:0] axi_burst_len(input logic [SizeWidth-1:0] size);
    if (size <= $clog2(DataWidth / 8)) begin
      return 0;
    end else begin
      return (1 << (size - $clog2(DataWidth / 8))) - 1;
    end
  endfunction

  function automatic logic [2:0] axi_burst_size(input logic [SizeWidth-1:0] size);
    if (size <= $clog2(DataWidth / 8)) begin
      return size;
    end else begin
      return 2'b11;
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

  always_comb begin
    tl.a_ready = 1'b0;

    tl.d_valid = 1'b0;
    tl.d_opcode = tl_d_op_e'('x);
    tl.d_param = 'x;
    tl.d_size = 'x;
    tl.d_source = 'x;
    tl.d_sink = 'x;
    tl.d_denied = 'x;
    tl.d_corrupt = 'x;
    tl.d_data = 'x;

    axi.ar_valid = 1'b0;
    axi.ar_addr = 'x;
    axi.ar_len = 'x;
    axi.ar_size = 'x;
    axi.aw_valid = 1'b0;
    axi.aw_addr = 'x;
    axi.aw_len = 'x;
    axi.aw_size = 'x;
    axi.w_valid = 1'b0;
    axi.w_data = 'x;
    axi.w_last = 'x;
    axi.w_strb = 'x;
    axi.r_ready = 1'b0;
    axi.b_ready = 1'b0;

    state_d = state;
    opcode_d = opcode_q;
    param_d = param_q;
    size_d = size_q;
    source_d = source_q;
    address_d = address;
    data_d = data;
    mask_d = mask;
    addr_sent_d = addr_sent;
    data_sent_d = data_sent;
    granted_d = granted_q;
    len_d = len_q;

    unique case (state)
        STATE_IDLE: begin
            tl.a_ready = 1'b1;
            if (req_valid) begin
                opcode_d = req_opcode;
                param_d = req_param;
                size_d = req_size;
                source_d = req_source;
                address_d = req_address;
                data_d = req_data;
                mask_d = req_mask;
                addr_sent_d = 1'b0;
                data_sent_d = 1'b0;
                granted_d = 1'b0;
                len_d = 8'd0;
                unique case (req_opcode)
                    Get: begin
                        state_d = STATE_GET;
                    end
                    PutFullData, PutPartialData: begin
                        len_d = axi_burst_len(req_size);
                        state_d = STATE_PUT;
                    end
                endcase
            end
        end

        STATE_GET: begin
            // Forward AXI response to the requestor
            axi.r_ready = grant_ready;
            tl.d_valid = mem_r_valid;
            tl.d_opcode = AccessAckData;
            tl.d_param = 0;
            tl.d_size = size_q;
            tl.d_source = source_q;
            tl.d_sink = 0;
            tl.d_denied = 1'b0;
            tl.d_corrupt = 1'b0;
            tl.d_data = mem_r_data;

            axi.ar_valid = !addr_sent;
            axi.ar_addr = address;
            axi.ar_len = axi_burst_len(size_q);
            axi.ar_size = axi_burst_size(size_q);

            // There is an handshake on address bus, thus we can lower ar_valid and wait for reply instead.
            if (mem_ar_ready) begin
                addr_sent_d = 1'b1;
            end

            if (tl.e_valid) granted_d = 1'b1;

            if (grant_ready && mem_r_valid && mem_r_last) begin
                // Last handshake
                state_d = STATE_IDLE;
            end
        end

        STATE_PUT: begin
            axi.aw_valid = !addr_sent;
            axi.aw_addr = address;
            axi.aw_len = axi_burst_len(size_q);
            axi.aw_size = axi_burst_size(size_q);
            axi.w_valid = !data_sent;
            axi.w_data = data;
            axi.w_strb = mask;
            axi.w_last = len_q == 0;

            // There is an handshake on address bus, thus we can lower aw_valid and wait for reply instead.
            if (mem_aw_ready) begin
                addr_sent_d = 1'b1;
            end

            if (mem_w_ready) begin
                data_sent_d = 1'b1;
            end

            if (addr_sent_d && data_sent_d) begin
                len_d = len_q - 1;
                state_d = len_q == 0 ? STATE_PUT_3 : STATE_PUT_2;
            end
        end
        STATE_PUT_2: begin
            axi.w_valid = req_valid;
            axi.w_data = req_data;
            axi.w_strb = req_mask;
            axi.w_last = len_q == 0;
            tl.a_ready = mem_w_ready;

            if (req_valid && mem_w_ready) begin
                len_d = len_q - 1;
                if (len_q == 0) state_d = STATE_PUT_3;
            end
        end
        STATE_PUT_3: begin
            axi.b_ready = grant_ready;
            tl.d_valid = mem_b_valid;
            tl.d_opcode = AccessAck;
            tl.d_param = 0;
            tl.d_size = size_q;
            tl.d_source = source_q;
            tl.d_sink = 0;
            tl.d_denied = 1'b0;
            tl.d_corrupt = 1'b0;
            tl.d_data = mem_r_data;

            if (mem_b_valid && grant_ready) begin
                state_d = STATE_IDLE;
            end
        end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) begin
      state <= STATE_IDLE;
      opcode_q <= tl_a_op_e'('x);
      size_q <= 'x;
      param_q <= 'x;
      source_q <= 'x;
      address <= 'x;
      data <= 'x;
      mask <= 'x;
      addr_sent <= 1'b0;
      data_sent <= 1'b0;
      granted_q <= 'x;
      len_q <= 'x;
    end
    else begin
      state <= state_d;
      opcode_q <= opcode_d;
      size_q <= size_d;
      param_q <= param_d;
      source_q <= source_d;
      address <= address_d;
      data <= data_d;
      mask <= mask_d;
      addr_sent <= addr_sent_d;
      data_sent <= data_sent_d;
      granted_q <= granted_d;
      len_q <= len_d;
    end

endmodule
