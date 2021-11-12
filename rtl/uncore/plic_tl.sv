module plic_tl #(
  parameter NumContexts = 1,
  // Currently can only be 32.
  parameter NumIrqs = 32,

  parameter AddrWidth   = 22,
  parameter SourceWidth = 1
) (
  input logic clk_i,
  input logic rst_ni,

  // Interrupt sources. Bit 0 is ignored.
  input logic [NumIrqs-1:0] interrupts_i,

  // Whether each interrupt should be level triggered or edge triggered
  input logic [NumIrqs-1:0] edge_trigger_i,

  // IRQ output for each context.
  output logic [NumContexts-1:0] irq_o,

  `TL_DECLARE_DEVICE_PORT(64, AddrWidth, SourceWidth, 1, link)
);

  logic bram_en;
  logic bram_we;
  logic [3:0] bram_wmask;
  logic [19:0] bram_addr;
  logic [31:0] bram_wrdata;
  logic [31:0] bram_rddata;

  plic #(
    .NUM_CONTEXTS (NumContexts),
    .NUM_IRQS (NumIrqs)
  ) plic (
    .clk (clk_i),
    .rstn (rst_ni),
    .interrupts (interrupts_i),
    .edge_trigger (edge_trigger_i),
    .bram_addr ({bram_addr, 2'b0}),
    .bram_en (bram_en),
    .bram_we (bram_we ? &bram_wmask : 1'b0),
    .bram_rddata (bram_rddata),
    .bram_wrdata (bram_wrdata),
    .irq (irq_o)
  );

  `TL_DECLARE(32, AddrWidth, SourceWidth, 1, narrow);

  tl_adapter_bram #(
    .DataWidth (32),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .BramAddrWidth (20)
  ) bram_bridge (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, narrow),
    .bram_en_o    (bram_en),
    .bram_we_o    (bram_we),
    .bram_wmask_o (bram_wmask),
    .bram_addr_o  (bram_addr),
    .bram_wdata_o (bram_wrdata),
    .bram_rdata_i (bram_rddata)
  );

  tl_adapter #(
    .HostDataWidth (64),
    .DeviceDataWidth (32),
    .HostAddrWidth (AddrWidth),
    .DeviceAddrWidth (AddrWidth),
    .HostSourceWidth (SourceWidth),
    .DeviceSourceWidth (SourceWidth),
    .HostMaxSize (3),
    .DeviceMaxSize (2),
    .HostFifo (1'b0),
    .DeviceFifo (1'b1)
  ) narrower (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, link),
    `TL_CONNECT_HOST_PORT(device, narrow)
  );

endmodule
