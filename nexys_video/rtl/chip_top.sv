`include "tl_util.svh"

module chip_top import prim_util_pkg::*; (
  input  sys_clk_i,
  input  sys_rst_ni,
  // QSPI
  inout  [1:0] qspi_dq,
  output       qspi_csn,
  // UART
  output uart_tx,
  input  uart_rx,
  // SD
  input        sd_cd,
  inout        sd_cmd,
  inout  [3:0] sd_dat,
  output       sd_reset,
  output       sd_sck,
  // Ethernet
  // output       mdc,
  // inout        mdio,
  // output       rmii_ref_clk,
  // output [1:0] rmii_txd,
  // output       rmii_tx_en,
  // input  [1:0] rmii_rxd,
  // input        rmii_csr_dv,
  // input        rmii_rx_er,
  // output       phy_rst_n,
  // input        phy_irq_i,

  // HDMI
  output       hdmi_tx_clk_p,
  output       hdmi_tx_clk_n,
  output [2:0] hdmi_tx_p,
  output [2:0] hdmi_tx_n,

  // DDR
  output [14:0] ddr3_sdram_addr,
  output [2:0]  ddr3_sdram_ba,
  output        ddr3_sdram_cas_n,
  output [0:0]  ddr3_sdram_ck_n,
  output [0:0]  ddr3_sdram_ck_p,
  output [0:0]  ddr3_sdram_cke,
  output [1:0]  ddr3_sdram_dm,
  inout  [15:0] ddr3_sdram_dq,
  inout  [1:0]  ddr3_sdram_dqs_n,
  inout  [1:0]  ddr3_sdram_dqs_p,
  output [0:0]  ddr3_sdram_odt,
  output        ddr3_sdram_ras_n,
  output        ddr3_sdram_reset_n,
  output        ddr3_sdram_we_n
);

  localparam NumCores = 2;
  localparam TimerClkFreq = 50;

  // Whether Ethernet controller should be enabled.
  localparam EnableEth = 1'b0;
  localparam EnableDvi = 1'b1;

  localparam DviDmaSourceWidth = 2;

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

  localparam NumDmaDevice = 0 + EnableEth + EnableDvi;

  localparam logic [vbits(NumDmaDevice)-1:0] EthDmaIdx = 0;
  localparam logic [vbits(NumDmaDevice)-1:0] DviDmaIdx = EnableEth ? EthDmaIdx + 1 : EthDmaIdx;

  localparam logic [DmaSourceWidth-1:0] EthDmaSourceMask = 3;
  localparam logic [DmaSourceWidth-1:0] EthDmaSourceBase = 0;

  localparam logic [DmaSourceWidth-1:0] DviDmaSourceMask = (1 << DviDmaSourceWidth) - 1;
  localparam logic [DmaSourceWidth-1:0] DviDmaSourceBase =
    ((EnableEth ? EthDmaSourceBase + EthDmaSourceMask + 1 : EthDmaSourceBase) + DviDmaSourceMask) &~ DviDmaSourceMask;

  if (DviDmaSourceBase + DviDmaSourceMask >= (1 << DmaSourceWidth)) begin
    $error("Not enough DMA source IDs");
  end

  `TL_DECLARE(128, AddrWidth, 2, SinkWidth, dma_eth);
  `TL_DECLARE(128, AddrWidth, DviDmaSourceWidth, SinkWidth, dma_dvi);

  if (NumDmaDevice == 0) begin: dummy_dma

    assign dma_tl_a_valid = 1'b0;
    assign dma_tl_a = 'x;
    assign dma_tl_b_ready = 1'b0;
    assign dma_tl_c_valid = 1'b0;
    assign dma_tl_c = 'x;
    assign dma_tl_d_ready = 1'b0;
    assign dma_tl_e_valid = 1'b0;
    assign dma_tl_e = 'x;

  end else begin: dma_shifter

    `TL_DECLARE_ARR(128, AddrWidth, DmaSourceWidth, SinkWidth, dma_ch_shifted, [NumDmaDevice-1:0]);

    if (EnableEth) begin: eth
      tl_source_shifter #(
        .DataWidth (128),
        .AddrWidth (AddrWidth),
        .SinkWidth (SinkWidth),
        .HostSourceWidth (2),
        .DeviceSourceWidth (DmaSourceWidth),
        .SourceBase (EthDmaSourceBase),
        .SourceMask (EthDmaSourceMask)
      ) eth_dma_shifter (
        .clk_i (clk),
        .rst_ni (rstn),
        `TL_CONNECT_DEVICE_PORT(host, dma_eth),
        `TL_CONNECT_HOST_PORT_IDX(device, dma_ch_shifted, [EthDmaIdx])
      );
    end

    if (EnableDvi) begin: dvi
      tl_source_shifter #(
        .DataWidth (128),
        .AddrWidth (AddrWidth),
        .SinkWidth (SinkWidth),
        .HostSourceWidth (DviDmaSourceWidth),
        .DeviceSourceWidth (DmaSourceWidth),
        .SourceBase (DviDmaSourceBase),
        .SourceMask (DviDmaSourceMask)
      ) dvi_dma_shifter (
        .clk_i (clk),
        .rst_ni (rstn),
        `TL_CONNECT_DEVICE_PORT(host, dma_dvi),
        `TL_CONNECT_HOST_PORT_IDX(device, dma_ch_shifted, [DviDmaIdx])
      );
    end

    if (NumDmaDevice == 1) begin: connect

      assign dma_ch_shifted_a_ready[0] = dma_tl_a_ready;
      assign dma_tl_a_valid = dma_ch_shifted_a_valid[0];
      assign dma_tl_a = dma_ch_shifted_a[0];
      assign dma_tl_b_ready = dma_ch_shifted_b_ready[0];
      assign dma_ch_shifted_b_valid[0] = dma_tl_b_valid;
      assign dma_ch_shifted_b[0] = dma_tl_b;
      assign dma_ch_shifted_c_ready[0] = dma_tl_c_ready;
      assign dma_tl_c_valid = dma_ch_shifted_c_valid[0];
      assign dma_tl_c = dma_ch_shifted_c[0];
      assign dma_tl_d_ready = dma_ch_shifted_d_ready[0];
      assign dma_ch_shifted_d_valid[0] = dma_tl_d_valid;
      assign dma_ch_shifted_d[0] = dma_tl_d;
      assign dma_ch_shifted_e_ready[0] = dma_tl_e_ready;
      assign dma_tl_e_valid = dma_ch_shifted_e_valid[0];
      assign dma_tl_e = dma_ch_shifted_e[0];

    end else begin: socket

      function automatic logic [NumDmaDevice-2:0][DmaSourceWidth-1:0] generate_socket_source_base();
        if (EnableEth && EthDmaIdx != 0) generate_socket_source_base[EthDmaIdx - 1] = EthDmaSourceBase;
        if (EnableDvi && DviDmaIdx != 0) generate_socket_source_base[DviDmaIdx - 1] = DviDmaSourceBase;
      endfunction

      function automatic logic [NumDmaDevice-2:0][DmaSourceWidth-1:0] generate_socket_source_mask();
        if (EnableEth && EthDmaIdx != 0) generate_socket_source_mask[EthDmaIdx - 1] = EthDmaSourceMask;
        if (EnableDvi && DviDmaIdx != 0) generate_socket_source_mask[DviDmaIdx - 1] = DviDmaSourceMask;
      endfunction

      function automatic logic [NumDmaDevice-2:0][vbits(NumDmaDevice)-1:0] generate_socket_source_link();
        if (EnableEth && EthDmaIdx != 0) generate_socket_source_link[EthDmaIdx - 1] = EthDmaIdx;
        if (EnableDvi && DviDmaIdx != 0) generate_socket_source_link[DviDmaIdx - 1] = DviDmaIdx;
      endfunction

      tl_socket_m1 #(
        .DataWidth (128),
        .AddrWidth (AddrWidth),
        .SourceWidth (DmaSourceWidth),
        .SinkWidth (SinkWidth),
        .NumLinks (NumDmaDevice),
        .NumSourceRange (NumDmaDevice-1),
        .SourceBase (generate_socket_source_base()),
        .SourceMask (generate_socket_source_mask()),
        .SourceLink (generate_socket_source_link())
      ) dma_aggreg (
        .clk_i (clk),
        .rst_ni (rstn),
        `TL_CONNECT_DEVICE_PORT(host, dma_ch_shifted),
        `TL_CONNECT_HOST_PORT(device, dma_tl)
      );

    end

  end

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

  `TL_DECLARE(128, 29, 8, 1, ddr_tl);

  ddr #(
    .DataWidth   (128),
    .AddrWidth   (29),
    .SourceWidth (8)
  ) ddr (
    .sys_clk_i,
    .sys_rst_ni,
    .clk_o    (clk),
    .io_clk_o (io_clk),
    .rst_no   (rstn),
    .ddr3_sdram_addr,
    .ddr3_sdram_ba,
    .ddr3_sdram_cas_n,
    .ddr3_sdram_ck_n,
    .ddr3_sdram_ck_p,
    .ddr3_sdram_cke,
    .ddr3_sdram_dm,
    .ddr3_sdram_dq,
    .ddr3_sdram_dqs_n,
    .ddr3_sdram_dqs_p,
    .ddr3_sdram_odt,
    .ddr3_sdram_ras_n,
    .ddr3_sdram_reset_n,
    .ddr3_sdram_we_n,
    `TL_CONNECT_DEVICE_PORT(link, ddr_tl)
  );

  tl_adapter #(
    .HostDataWidth (128),
    .DeviceDataWidth (128),
    .HostAddrWidth (AddrWidth),
    .DeviceAddrWidth (29),
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

  `TL_DECLARE(32, 25, 1, 1, flash_tl);

  spi #(
    .DataWidth   (32),
    .AddrWidth   (25),
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
    .DeviceAddrWidth (25),
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

  // Exclude the fixed error sink located at offset 0.
  localparam NumIoDevice = 4 + EnableEth + EnableDvi;

  // Error sink located at offset 0.
  localparam ClintIoIdx = 1;
  localparam PlicIoIdx = 2;
  localparam UartIoIdx = 3;
  localparam SdhciIoIdx = 4;
  localparam EthIoIdx = 5;
  localparam DviIoIdx = EnableEth ? EthIoIdx + 1 : EthIoIdx;

  localparam [AddrWidth-1:0] ClintBaseAddr = 'h11400000;
  localparam [AddrWidth-1:0] ClintBaseMask = 'h    FFFF;

  localparam [AddrWidth-1:0] PlicBaseAddr  = 'h11000000;
  localparam [AddrWidth-1:0] PlicBaseMask  = 'h  3FFFFF;

  localparam [AddrWidth-1:0] UartBaseAddr  = 'h10000000;
  localparam [AddrWidth-1:0] UartBaseMask  = 'h    1FFF;

  localparam [AddrWidth-1:0] SdhciBaseAddr = 'h10010000;
  localparam [AddrWidth-1:0] SdhciBaseMask = 'h     FFF;

  localparam [AddrWidth-1:0] EthBaseAddr   = 'h10100000;
  localparam [AddrWidth-1:0] EthBaseMask   = 'h   7FFFF;

  localparam [AddrWidth-1:0] DviBaseAddr   = 'h10020000;
  localparam [AddrWidth-1:0] DviBaseMask   = 'h     FFF;

  `TL_DECLARE_ARR(64, AddrWidth, DeviceSourceWidth, 1, io_ch, [NumIoDevice:0]);

  function automatic logic [NumIoDevice-1:0][AddrWidth-1:0] generate_socket_address_base();
    generate_socket_address_base[ClintIoIdx - 1] = ClintBaseAddr;
    generate_socket_address_base[PlicIoIdx - 1] = PlicBaseAddr;
    generate_socket_address_base[UartIoIdx - 1] = UartBaseAddr;
    generate_socket_address_base[SdhciIoIdx - 1] = SdhciBaseAddr;
    if (EnableEth) generate_socket_address_base[EthIoIdx - 1] = EthBaseAddr;
    if (EnableDvi) generate_socket_address_base[DviIoIdx - 1] = DviBaseAddr;
  endfunction

  function automatic logic [NumIoDevice-1:0][AddrWidth-1:0] generate_socket_address_mask();
    generate_socket_address_mask[ClintIoIdx - 1] = ClintBaseMask;
    generate_socket_address_mask[PlicIoIdx - 1] = PlicBaseMask;
    generate_socket_address_mask[UartIoIdx - 1] = UartBaseMask;
    generate_socket_address_mask[SdhciIoIdx - 1] = SdhciBaseMask;
    if (EnableEth) generate_socket_address_mask[EthIoIdx - 1] = EthBaseMask;
    if (EnableDvi) generate_socket_address_mask[DviIoIdx - 1] = DviBaseMask;
  endfunction

  function automatic logic [NumIoDevice-1:0][vbits(NumIoDevice+1)-1:0] generate_socket_address_link();
    generate_socket_address_link[ClintIoIdx - 1] = ClintIoIdx;
    generate_socket_address_link[PlicIoIdx - 1] = PlicIoIdx;
    generate_socket_address_link[UartIoIdx - 1] = UartIoIdx;
    generate_socket_address_link[SdhciIoIdx - 1] = SdhciIoIdx;
    if (EnableEth) generate_socket_address_link[EthIoIdx - 1] = EthIoIdx;
    if (EnableDvi) generate_socket_address_link[DviIoIdx - 1] = DviIoIdx;
  endfunction

  tl_socket_1n #(
    .SourceWidth (DeviceSourceWidth),
    .AddrWidth (AddrWidth),
    .DataWidth (64),
    .NumLinks    (NumIoDevice + 1),
    .NumAddressRange (NumIoDevice),
    .AddressBase (generate_socket_address_base()),
    .AddressMask (generate_socket_address_mask()),
    .AddressLink (generate_socket_address_link())
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
    `TL_CONNECT_DEVICE_PORT_IDX(link, io_ch, [ClintIoIdx])
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
    `TL_CONNECT_DEVICE_PORT_IDX(link, io_ch, [PlicIoIdx])
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
    .uart_cts (1'b0),
    .uart_rts (),
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
    `TL_CONNECT_DEVICE_PORT_IDX(host, io_ch, [UartIoIdx]),
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
    `TL_CONNECT_DEVICE_PORT_IDX(host, io_ch, [SdhciIoIdx]),
    `TL_CONNECT_HOST_PORT(device, sdhci_tl)
  );

  // #endregion
  ///////////////////

  //////////////////////
  // #region Ethernet //

  logic eth_irq;
  logic dma_tx_irq;
  logic dma_rx_irq;
  logic phy_irq;

  // if (EnableEth) begin: eth

  //   `TL_DECLARE(32, 19, DeviceSourceWidth, 1, eth_io);
  //   `TL_DECLARE(64, 32, 2, SinkWidth, eth_dma);

  //   eth #(
  //     .IoDataWidth (32),
  //     .IoAddrWidth (19),
  //     .IoSourceWidth (DeviceSourceWidth),
  //     .DmaSourceWidth (2),
  //     .DmaSinkWidth (SinkWidth)
  //   ) eth (
  //     .clk_i (clk),
  //     .rst_ni (rstn),
  //     .io_clk_i (io_clk),
  //     .mdc,
  //     .mdio,
  //     .rmii_ref_clk,
  //     .rmii_txd,
  //     .rmii_tx_en,
  //     .rmii_rxd,
  //     .rmii_csr_dv,
  //     .rmii_rx_er,
  //     .phy_rst_n,
  //     .phy_irq (phy_irq_i),
  //     `TL_CONNECT_DEVICE_PORT(io, eth_io),
  //     `TL_CONNECT_HOST_PORT(dma, eth_dma),
  //     .eth_irq_o (eth_irq),
  //     .dma_tx_irq_o (dma_tx_irq),
  //     .dma_rx_irq_o (dma_rx_irq),
  //     .phy_irq_o (phy_irq)
  //   );

  //   tl_adapter #(
  //     .HostDataWidth (64),
  //     .DeviceDataWidth (32),
  //     .HostAddrWidth (AddrWidth),
  //     .DeviceAddrWidth (19),
  //     .HostSourceWidth (DeviceSourceWidth),
  //     .DeviceSourceWidth (DeviceSourceWidth),
  //     .HostSinkWidth (1),
  //     .DeviceSinkWidth (1),
  //     .HostMaxSize (3),
  //     .DeviceMaxSize (2),
  //     .HostFifo (1'b0),
  //     .DeviceFifo (1'b0)
  //   ) eth_io_adapter (
  //     .clk_i (clk),
  //     .rst_ni (rstn),
  //     `TL_CONNECT_DEVICE_PORT_IDX(host, io_ch, [EthIoIdx]),
  //     `TL_CONNECT_HOST_PORT(device, eth_io)
  //   );

  //   tl_adapter #(
  //     .HostDataWidth (64),
  //     .DeviceDataWidth (128),
  //     .HostAddrWidth (32),
  //     .DeviceAddrWidth (AddrWidth),
  //     .HostSourceWidth (2),
  //     .DeviceSourceWidth (2),
  //     .HostSinkWidth (SinkWidth),
  //     .DeviceSinkWidth (SinkWidth)
  //   ) eth_dma_adapter (
  //     .clk_i (clk),
  //     .rst_ni (rstn),
  //     `TL_CONNECT_DEVICE_PORT(host, eth_dma),
  //     `TL_CONNECT_HOST_PORT(device, dma_eth)
  //   );
  
  // end else begin: dummy_eth

  //   assign mdc = 1'bz;
  //   assign mdio = 1'bz;
  //   assign rmii_ref_clk = 1'bz;
  //   assign rmii_txd = 2'bzz;
  //   assign rmii_tx_en = 1'bz;
  //   assign phy_rst_n = 1'bz;

  // end

  // #endregion
  //////////////////////

  /////////////////////
  // #region Display //

  if (EnableDvi) begin: dvi

    `TL_DECLARE(32, 12, DeviceSourceWidth, 1, dvi_io);

    dvi #(
      .IoAddrWidth (12),
      .IoSourceWidth (DeviceSourceWidth),
      .DmaDataWidth (128),
      .DmaAddrWidth (AddrWidth),
      .DmaSourceWidth (DviDmaSourceWidth),
      .DmaSinkWidth (SinkWidth)
    ) dvi (
      .clk_i (clk),
      .rst_ni (rstn),
      .io_clk_i (io_clk),
      .hdmi_tx_clk_p,
      .hdmi_tx_clk_n,
      .hdmi_tx_p,
      .hdmi_tx_n,
      `TL_CONNECT_DEVICE_PORT(io, dvi_io),
      `TL_CONNECT_HOST_PORT(dma, dma_dvi)
    );

    tl_adapter #(
      .HostDataWidth (64),
      .DeviceDataWidth (32),
      .HostAddrWidth (AddrWidth),
      .DeviceAddrWidth (12),
      .HostSourceWidth (DeviceSourceWidth),
      .DeviceSourceWidth (DeviceSourceWidth),
      .HostSinkWidth (1),
      .DeviceSinkWidth (1),
      .HostMaxSize (3),
      .DeviceMaxSize (2),
      .HostFifo (1'b0),
      .DeviceFifo (1'b1)
    ) dvi_io_adapter (
      .clk_i (clk),
      .rst_ni (rstn),
      `TL_CONNECT_DEVICE_PORT_IDX(host, io_ch, [DviIoIdx]),
      `TL_CONNECT_HOST_PORT(device, dvi_io)
    );

  end else begin: dummy_dvi

    OBUFTDS #(
      .IOSTANDARD ("TMDS_33")
    ) clk_buf (
      .I (1'b0),
      .T (1'b1),
      .O (hdmi_tx_clk_p),
      .OB (hdmi_tx_clk_n)
    );

    for (genvar i = 0; i < 3; i++) begin
      OBUFTDS #(
        .IOSTANDARD ("TMDS_33")
      ) data_buf (
        .I (1'b0),
        .T (1'b1),
        .O (hdmi_tx_p[i]),
        .OB (hdmi_tx_n[i])
      );
    end

  end

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
    if (EnableEth) begin
      interrupts[3] = eth_irq;
      interrupts[4] = dma_tx_irq;
      interrupts[5] = dma_rx_irq;
      interrupts[6] = phy_irq;
      edge_trigger[6:3] = 4'b0;
    end
  end

  // endregion
  ////////////////////////

endmodule
