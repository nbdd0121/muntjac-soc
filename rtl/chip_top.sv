`include "tl_util.svh"

module chip_top (
  input  sys_clk_i,
  input  sys_rst_ni,
  // QSPI
  inout  [1:0] qspi_dq,
  output       qspi_csn,
  // UART
  input  uart_rts,
  output uart_cts,
  input  uart_txd,
  output uart_rxd,
  // SD
  input        sd_cd,
  inout        sd_cmd,
  inout  [3:0] sd_dat,
  output       sd_reset,
  output       sd_sck,
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

  logic clk;
  logic io_clk;
  logic rstn;

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

  // #endregion
  ///////////////////////

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
    .uart_rts,
    .uart_cts,
    .uart_txd,
    .uart_rxd,
    `TL_CONNECT_DEVICE_PORT(link, uart_tl),
    .irq_o (irq_uart)
  );

  // #endregion
  ///////////////////////
  
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

  // #endregion
  ///////////////////////

endmodule
