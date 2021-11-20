`include "tl_util.svh"

module chip_top (
  input  sys_clk_i,
  input  sys_rst_ni,
  // QSPI
  inout  [1:0] qspi_dq,
  output       qspi_csn,
  // UART
  output uart_tx,
  input  uart_rx,
  input  uart_cts,
  output uart_rts,
  // SD
  input        sd_cd,
  inout        sd_cmd,
  inout  [3:0] sd_dat,
  output       sd_reset,
  output       sd_sck,
  // Ethernet
  output       mdc,
  inout        mdio,
  output       rmii_ref_clk,
  output [1:0] rmii_txd,
  output       rmii_tx_en,
  input  [1:0] rmii_rxd,
  input        rmii_csr_dv,
  input        rmii_rx_er,
  output       phy_rst_n,
  input        phy_irq_i,
  // DDR
  output [12:0] ddr2_sdram_addr,
  output [2:0]  ddr2_sdram_ba,
  output        ddr2_sdram_cas_n,
  output [0:0]  ddr2_sdram_ck_n,
  output [0:0]  ddr2_sdram_ck_p,
  output [0:0]  ddr2_sdram_cke,
  output [0:0]  ddr2_sdram_cs_n,
  output [1:0]  ddr2_sdram_dm,
  inout  [15:0] ddr2_sdram_dq,
  inout  [1:0]  ddr2_sdram_dqs_n,
  inout  [1:0]  ddr2_sdram_dqs_p,
  output [0:0]  ddr2_sdram_odt,
  output        ddr2_sdram_ras_n,
  output        ddr2_sdram_we_n
);

  localparam NumCores = 2;
  localparam TimerClkFreq = 50;
  localparam AddrWidth = 38;
  localparam DmaSourceWidth = 3;
  localparam HostSourceWidth = 2;
  localparam DeviceSourceWidth = 5;
  localparam SinkWidth = 4;

  logic clk;
  logic io_clk;
  logic rstn;

  `TL_DECLARE(128, AddrWidth, DmaSourceWidth, SinkWidth, dma_tl);
  `TL_DECLARE(128, AddrWidth, DeviceSourceWidth, 1, mem_tl);
  `TL_DECLARE(32, AddrWidth, DeviceSourceWidth, 1, rom_tl);
  `TL_DECLARE(64, AddrWidth, DeviceSourceWidth, 1, io_tl);

  /////////////////
  // #region DMA //

  // #endregion
  /////////////////

  /////////////////
  // #region CCX //

  logic [NumCores-1:0] irq_timer_m;
  logic [NumCores-1:0] irq_software_m;
  logic [NumCores-1:0] irq_external_s;
  logic [NumCores-1:0] irq_external_m;

  ccx #(
    .NumCores (NumCores),
    .DmaSourceWidth (DmaSourceWidth),
    .DeviceSourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .AddrWidth (AddrWidth)
  ) ccx (
    .clk_i (clk),
    .rst_ni (rstn),
    .irq_software_m_i (irq_software_m),
    .irq_timer_m_i (irq_timer_m),
    .irq_external_m_i (irq_external_m),
    .irq_external_s_i (irq_external_s),
    `TL_CONNECT_DEVICE_PORT(dma, dma_tl),
    `TL_CONNECT_HOST_PORT(mem, mem_tl),
    `TL_CONNECT_HOST_PORT(rom, rom_tl),
    `TL_CONNECT_HOST_PORT(io, io_tl)
  );

  // #endregion
  /////////////////

  ///////////////////////////
  // #region DDR and clock //

  `TL_DECLARE(128, 27, 8, 1, ddr_tl);

  ddr #(
    .DataWidth   (128),
    .AddrWidth   (27),
    .SourceWidth (8)
  ) ddr (
    .sys_clk_i,
    .sys_rst_ni,
    .clk_o    (clk),
    .io_clk_o (io_clk),
    .rst_no   (rstn),
    .ddr2_sdram_addr,
    .ddr2_sdram_ba,
    .ddr2_sdram_cas_n,
    .ddr2_sdram_ck_n,
    .ddr2_sdram_ck_p,
    .ddr2_sdram_cke,
    .ddr2_sdram_cs_n,
    .ddr2_sdram_dm,
    .ddr2_sdram_dq,
    .ddr2_sdram_dqs_n,
    .ddr2_sdram_dqs_p,
    .ddr2_sdram_odt,
    .ddr2_sdram_ras_n,
    .ddr2_sdram_we_n,
    `TL_CONNECT_DEVICE_PORT(link, ddr_tl)
  );

  tl_adapter #(
    .HostDataWidth (128),
    .DeviceDataWidth (128),
    .HostAddrWidth (AddrWidth),
    .DeviceAddrWidth (27),
    .HostSourceWidth (DeviceSourceWidth),
    .DeviceSourceWidth (8),
    .HostSinkWidth (1),
    .DeviceSinkWidth (1),
    .HostMaxSize (6),
    .DeviceMaxSize (6),
    .HostFifo (1'b0),
    .DeviceFifo (1'b0)
  ) mem_adapter (
    .clk_i (clk),
    .rst_ni (rstn),
    `TL_CONNECT_DEVICE_PORT(host, mem_tl),
    `TL_CONNECT_HOST_PORT(device, ddr_tl)
  );

  // #endregion
  ///////////////////////////

  ///////////////////////
  // #region SPI flash //

  `TL_DECLARE(32, 24, 1, 1, flash_tl);

  spi #(
    .DataWidth   (32),
    .AddrWidth   (24),
    .SourceWidth (1)
  ) spi_flash (
    .clk_i (clk),
    .rst_ni (rstn),
    .io_clk_i (io_clk),
    .spi_io_io (qspi_dq[1:0]),
    .spi_ss_io (qspi_csn),
    `TL_CONNECT_DEVICE_PORT(link, flash_tl)
  );

  tl_adapter #(
    .HostDataWidth (32),
    .DeviceDataWidth (32),
    .HostAddrWidth (AddrWidth),
    .DeviceAddrWidth (24),
    .HostSourceWidth (DeviceSourceWidth),
    .DeviceSourceWidth (1),
    .HostSinkWidth (1),
    .DeviceSinkWidth (1),
    .HostMaxSize (6),
    .DeviceMaxSize (6),
    .HostFifo (1'b0),
    .DeviceFifo (1'b0)
  ) rom_adapter (
    .clk_i (clk),
    .rst_ni (rstn),
    `TL_CONNECT_DEVICE_PORT(host, rom_tl),
    `TL_CONNECT_HOST_PORT(device, flash_tl)
  );

  // #endregion
  ///////////////////////

  ///////////////////////
  // #region IO Switch //

  `TL_DECLARE_ARR(64, AddrWidth, DeviceSourceWidth, 1, io_ch, [5:0]);

  localparam [AddrWidth-1:0] PlicBaseAddr  = 'h11000000;
  localparam [AddrWidth-1:0] PlicBaseMask  = 'h  3FFFFF;

  localparam [AddrWidth-1:0] ClintBaseAddr = 'h11400000;
  localparam [AddrWidth-1:0] ClintBaseMask = 'h    FFFF;

  localparam [AddrWidth-1:0] UartBaseAddr  = 'h10000000;
  localparam [AddrWidth-1:0] UartBaseMask  = 'h    1FFF;

  localparam [AddrWidth-1:0] SdhciBaseAddr = 'h10010000;
  localparam [AddrWidth-1:0] SdhciBaseMask = 'h     FFF;

  localparam [AddrWidth-1:0] EthMacBaseAddr = 'h10100000;
  localparam [AddrWidth-1:0] EthMacBaseMask = 'h   3FFFF;
  localparam [AddrWidth-1:0] EthDmaBaseAddr = 'h10200000;
  localparam [AddrWidth-1:0] EthDmaBaseMask = 'h     3FF;

  tl_socket_1n #(
    .SourceWidth (DeviceSourceWidth),
    .AddrWidth (AddrWidth),
    .DataWidth (64),
    .NumLinks    (6),
    .NumAddressRange (6),
    .AddressBase ({ClintBaseAddr, PlicBaseAddr, UartBaseAddr, SdhciBaseAddr, EthMacBaseAddr, EthDmaBaseAddr}),
    .AddressMask ({ClintBaseMask, PlicBaseMask, UartBaseMask, SdhciBaseMask, EthMacBaseMask, EthDmaBaseMask}),
    .AddressLink ({3'd         1, 3'd        2, 3'd        3, 3'd         4, 3'd          5, 3'd          5})
  ) io_socket_1n (
    .clk_i (clk),
    .rst_ni (rstn),
    `TL_CONNECT_DEVICE_PORT(host, io_tl),
    `TL_CONNECT_HOST_PORT(device, io_ch)
  );

  tl_error_sink #(
    .DataWidth (64),
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (1),
    .MaxSize (3)
  ) error_sink (
    .clk_i (clk),
    .rst_ni (rstn),
    `TL_CONNECT_DEVICE_PORT_IDX(host, io_ch, [0])
  );

  // #endregion
  ///////////////////////

  ////////////////////////////
  // #region PLIC and CLINT //

  clint_tl #(
    .NumHarts (NumCores),
    .TimerClockFrequency (50),
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth)
  ) clint (
    .clk_i (clk),
    .rst_ni (rstn),
    .timer_clk_i (io_clk),
    .msip_o (irq_software_m),
    .mtip_o (irq_timer_m),
    `TL_CONNECT_DEVICE_PORT_IDX(link, io_ch, [1])
  );

  logic [31:0] interrupts;
  logic [31:0] edge_trigger;

  plic_tl #(
    .NumContexts (NumCores),
    .NumIrqs (32),
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth)
  ) plic (
    .clk_i (clk),
    .rst_ni (rstn),
    .interrupts_i (interrupts),
    .edge_trigger_i (edge_trigger),
    .irq_o (irq_external_s),
    `TL_CONNECT_DEVICE_PORT_IDX(link, io_ch, [2])
  );

  // #endregion
  ////////////////////////////

  //////////////////
  // #region UART //

  `TL_DECLARE(32, 13, 1, 1, uart_tl);

  logic irq_uart;

  uart #(
    .DataWidth   (32),
    .AddrWidth   (13),
    .SourceWidth (1)
  ) uart (
    .clk_i (clk),
    .rst_ni (rstn),
    .io_clk_i (io_clk),
    .uart_tx,
    .uart_rx,
    .uart_cts,
    .uart_rts,
    `TL_CONNECT_DEVICE_PORT(link, uart_tl),
    .irq_o (irq_uart)
  );
  
  tl_adapter #(
    .HostDataWidth (64),
    .DeviceDataWidth (32),
    .HostAddrWidth (AddrWidth),
    .DeviceAddrWidth (13),
    .HostSourceWidth (DeviceSourceWidth),
    .DeviceSourceWidth (1),
    .HostSinkWidth (1),
    .DeviceSinkWidth (1),
    .HostMaxSize (3),
    .DeviceMaxSize (2),
    .HostFifo (1'b0),
    .DeviceFifo (1'b1)
  ) uart_adapter (
    .clk_i (clk),
    .rst_ni (rstn),
    `TL_CONNECT_DEVICE_PORT_IDX(host, io_ch, [3]),
    `TL_CONNECT_HOST_PORT(device, uart_tl)
  );

  // #endregion
  //////////////////
  
  ///////////////////
  // #region SDHCI //

  `TL_DECLARE(32, 12, 1, 1, sdhci_tl);

  logic irq_sd;

  sdhci #(
    .AddrWidth   (12),
    .SourceWidth (1)
  ) sdhci (
    .clk_i (clk),
    .rst_ni (rstn),
    .io_clk_i (io_clk),
    .sd_cd,
    .sd_cmd,
    .sd_dat,
    .sd_reset,
    .sd_sck,
    `TL_CONNECT_DEVICE_PORT(link, sdhci_tl),
    .irq_o (irq_sd)
  );
  
  tl_adapter #(
    .HostDataWidth (64),
    .DeviceDataWidth (32),
    .HostAddrWidth (AddrWidth),
    .DeviceAddrWidth (12),
    .HostSourceWidth (DeviceSourceWidth),
    .DeviceSourceWidth (1),
    .HostSinkWidth (1),
    .DeviceSinkWidth (1),
    .HostMaxSize (3),
    .DeviceMaxSize (2),
    .HostFifo (1'b0),
    .DeviceFifo (1'b1)
  ) sdhci_adapter (
    .clk_i (clk),
    .rst_ni (rstn),
    `TL_CONNECT_DEVICE_PORT_IDX(host, io_ch, [4]),
    `TL_CONNECT_HOST_PORT(device, sdhci_tl)
  );

  // #endregion
  ///////////////////

  //////////////////////
  // #region Ethernet //

  `TL_DECLARE(32, 28, DeviceSourceWidth, 1, eth_io);
  `TL_DECLARE(64, 32, DmaSourceWidth, SinkWidth, eth_dma);

   logic eth_irq;
   logic dma_tx_irq;
   logic dma_rx_irq;
   logic phy_irq;

  eth #(
    .IoDataWidth (32),
    .IoAddrWidth (28),
    .IoSourceWidth (DeviceSourceWidth),
    .DmaSourceWidth (DmaSourceWidth),
    .DmaSinkWidth (SinkWidth)
  ) eth (
    .clk_i (clk),
    .rst_ni (rstn),
    .io_clk_i (io_clk),
    .mdc,
    .mdio,
    .rmii_ref_clk,
    .rmii_txd,
    .rmii_tx_en,
    .rmii_rxd,
    .rmii_csr_dv,
    .rmii_rx_er,
    .phy_rst_n,
    .phy_irq (phy_irq_i),
    `TL_CONNECT_DEVICE_PORT(io, eth_io),
    `TL_CONNECT_HOST_PORT(dma, eth_dma),
    .eth_irq_o (eth_irq),
    .dma_tx_irq_o (dma_tx_irq),
    .dma_rx_irq_o (dma_rx_irq),
    .phy_irq_o (phy_irq)
  );

  tl_adapter #(
    .HostDataWidth (64),
    .DeviceDataWidth (32),
    .HostAddrWidth (AddrWidth),
    .DeviceAddrWidth (28),
    .HostSourceWidth (DeviceSourceWidth),
    .DeviceSourceWidth (DeviceSourceWidth),
    .HostSinkWidth (1),
    .DeviceSinkWidth (1),
    .HostMaxSize (3),
    .DeviceMaxSize (2),
    .HostFifo (1'b0),
    .DeviceFifo (1'b0)
  ) eth_io_adapter (
    .clk_i (clk),
    .rst_ni (rstn),
    `TL_CONNECT_DEVICE_PORT_IDX(host, io_ch, [5]),
    `TL_CONNECT_HOST_PORT(device, eth_io)
  );

  tl_adapter #(
    .HostDataWidth (64),
    .DeviceDataWidth (128),
    .HostAddrWidth (32),
    .DeviceAddrWidth (AddrWidth),
    .HostSourceWidth (DmaSourceWidth),
    .DeviceSourceWidth (DmaSourceWidth),
    .HostSinkWidth (SinkWidth),
    .DeviceSinkWidth (SinkWidth)
  ) eth_dma_adapter (
    .clk_i (clk),
    .rst_ni (rstn),
    `TL_CONNECT_DEVICE_PORT(host, eth_dma),
    `TL_CONNECT_HOST_PORT(device, dma_tl)
  );

  // #endregion
  //////////////////////

  ////////////////////////
  // region IRQ routing //

  always_comb begin
    interrupts = '0;
    edge_trigger = '0;

    // UART IRQ is level-triggered
    interrupts[1] = irq_uart;
    edge_trigger[1] = 1'b0;

    // SD IRQ is level-triggered
    interrupts[2] = irq_sd;
    edge_trigger[1] = 1'b0;

    // Ethernet IRQs are all level-triggered
    interrupts[3] = eth_irq;
    interrupts[4] = dma_tx_irq;
    interrupts[5] = dma_rx_irq;
    interrupts[6] = phy_irq;
    edge_trigger[6:3] = 4'b0;
  end

  // endregion
  ////////////////////////

endmodule
