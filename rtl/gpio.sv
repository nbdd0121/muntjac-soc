`include "tl_util.svh"

module gpio # (
  parameter AddrWidth   = 12,
  parameter SourceWidth = 1,
  parameter NumGpios    = 32
) (
  // Clock and reset
  input clk_i,
  input rst_ni,

  // IO ports. They are expected to be presynchronized to clk_i.
  input  logic [NumGpios-1:0] gpio_i,
  output logic [NumGpios-1:0] gpio_o,
  output logic [NumGpios-1:0] gpio_t,

  // TileLink port
  `TL_DECLARE_DEVICE_PORT(32, AddrWidth, SourceWidth, 1, link)
);

  logic bram_en;
  logic bram_we;
  logic [3:0] bram_wmask;
  logic [0:0] bram_addr;
  logic [31:0] bram_wrdata;
  logic [31:0] bram_rddata;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gpio_o <= '0;
      gpio_t <= '1;
    end else begin
      if (bram_en) begin
        bram_rddata <= '0;
        unique case (bram_addr)
          1'b0: begin
            // Select gpio_i or gpio_o based on gpio_t
            bram_rddata <= (gpio_t & gpio_i) | (~gpio_t & gpio_o);
            if (bram_we && |bram_wmask) begin
              gpio_o <= bram_wrdata;
            end
          end
          1'b1: begin
            bram_rddata <= ~gpio_t;
            if (bram_we && |bram_wmask) begin
              gpio_t <= ~bram_wrdata;
            end
          end
        endcase
      end
    end
  end

  // Terminate TileLink and convert to BRAM access.

  tl_adapter_bram #(
    .DataWidth (32),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .BramAddrWidth (1)
  ) bridge (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, link),
    .bram_en_o    (bram_en),
    .bram_we_o    (bram_we),
    .bram_wmask_o (bram_wmask),
    .bram_addr_o  (bram_addr),
    .bram_wdata_o (bram_wrdata),
    .bram_rdata_i (bram_rddata)
  );

endmodule
