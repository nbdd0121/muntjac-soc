set workroot [pwd]

# Ensure that rgb2dvi IP is extracted
if {!([file exists "${workroot}/ip/rgb2dvi"])} {
    exec mkdir -p "${workroot}/ip"
    exec tar -xvzf "${workroot}/rgb2dvi.tar" -C "${workroot}/ip"
}

# Ensure that axi_ps2 IP is extracted
if {!([file exists "${workroot}/ip/axi_ps2_1.0"])} {
    exec mkdir -p "${workroot}/ip"
    exec tar -xvzf "${workroot}/axi_ps2_1.0.tar.gz" -C "${workroot}/ip"
}

set_property ip_repo_paths [file normalize "${workroot}/ip"] [current_project]
update_ip_catalog

set_property used_in_synthesis false [get_files clocks.xdc]

# Enable Retiming in synthesis
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

# Create DDR Memory Controller
create_ip -name mig_7series -vendor xilinx.com -library ip -module_name mig_7series_0
set_property CONFIG.XML_INPUT_FILE [file normalize "${workroot}/mig.prj"] [get_ips mig_7series_0]

# Create AXI Quad SPI
create_ip -name axi_quad_spi -vendor xilinx.com -library ip -version 3.2 -module_name axi_quad_spi_0
set_property -dict [list \
    CONFIG.C_SPI_MEMORY {3} \
    CONFIG.C_SPI_MEM_ADDR_BITS {32} \
    CONFIG.C_USE_STARTUP {0} \
    CONFIG.C_USE_STARTUP_INT {0} \
    CONFIG.C_SPI_MODE {1} \
    CONFIG.C_SCK_RATIO {2} \
    CONFIG.C_XIP_MODE {1} \
    CONFIG.C_XIP_PERF_MODE {0} \
    CONFIG.C_TYPE_OF_AXI4_INTERFACE {1} \
    CONFIG.C_S_AXI4_ID_WIDTH {1} \
    CONFIG.Async_Clk {1} \
] [get_ips axi_quad_spi_0]

# Create AXI UART16550
# This IP has a requirement for its input clock so we use io_clk instead of bus clk
# and need an extra clock converter.
# We also need a clock wizard for a 18.432MHz clock which works better for most baud rates.
create_ip -name axi_uart16550 -vendor xilinx.com -library ip -version 2.0 -module_name axi_uart16550_0
set_property -dict [list \
    CONFIG.C_S_AXI_ACLK_FREQ_HZ_d {50} \
    CONFIG.C_HAS_EXTERNAL_XIN {1} \
    CONFIG.C_EXTERNAL_XIN_CLK_HZ_d {18.432} \
    CONFIG.C_S_AXI_ACLK_FREQ_HZ {50000000} \
    CONFIG.C_EXTERNAL_XIN_CLK_HZ {18432000} \
] [get_ips axi_uart16550_0]

create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name axi_clock_converter_uart
set_property -dict [list \
    CONFIG.PROTOCOL {AXI4LITE} \
    CONFIG.ADDR_WIDTH {13} \
    CONFIG.DATA_WIDTH {32} \
    CONFIG.ID_WIDTH {0} \
    CONFIG.AWUSER_WIDTH {0} \
    CONFIG.ARUSER_WIDTH {0} \
    CONFIG.RUSER_WIDTH {0} \
    CONFIG.WUSER_WIDTH {0} \
    CONFIG.BUSER_WIDTH {0} \
] [get_ips axi_clock_converter_uart]

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_uart
set_property -dict [list \
    CONFIG.PRIMITIVE {PLL} \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.PRIM_IN_FREQ {50} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {18.432} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.CLKIN1_JITTER_PS {200.0} \
    CONFIG.CLKOUT1_DRIVES {BUFG} \
    CONFIG.CLKOUT2_DRIVES {BUFG} \
    CONFIG.CLKOUT3_DRIVES {BUFG} \
    CONFIG.CLKOUT4_DRIVES {BUFG} \
    CONFIG.CLKOUT5_DRIVES {BUFG} \
    CONFIG.CLKOUT6_DRIVES {BUFG} \
    CONFIG.CLKOUT7_DRIVES {BUFG} \
    CONFIG.MMCM_DIVCLK_DIVIDE {2} \
    CONFIG.MMCM_BANDWIDTH {OPTIMIZED} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {59} \
    CONFIG.MMCM_CLKIN1_PERIOD {20.000} \
    CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
    CONFIG.MMCM_COMPENSATION {ZHOLD} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {80} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.CLKOUT1_JITTER {180.940} \
    CONFIG.CLKOUT1_PHASE_ERROR {220.889} \
] [get_ips clk_wiz_uart]

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_dvi
set_property -dict [list \
    CONFIG.PRIMITIVE {PLL} \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.PRIM_IN_FREQ {50} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {74.25} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {371.25} \
    CONFIG.USE_LOCKED {false} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.CLKIN1_JITTER_PS {200.0} \
    CONFIG.CLKOUT1_DRIVES {BUFG} \
    CONFIG.CLKOUT2_DRIVES {BUFG} \
    CONFIG.CLKOUT3_DRIVES {BUFG} \
    CONFIG.CLKOUT4_DRIVES {BUFG} \
    CONFIG.CLKOUT5_DRIVES {BUFG} \
    CONFIG.CLKOUT6_DRIVES {BUFG} \
    CONFIG.CLKOUT7_DRIVES {BUFG} \
    CONFIG.MMCM_DIVCLK_DIVIDE {2} \
    CONFIG.MMCM_BANDWIDTH {OPTIMIZED} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {37} \
    CONFIG.MMCM_CLKIN1_PERIOD {20.000} \
    CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
    CONFIG.MMCM_COMPENSATION {ZHOLD} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {25} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {5} \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.CLKOUT1_JITTER {95.261} \
    CONFIG.CLKOUT1_PHASE_ERROR {107.074} \
    CONFIG.CLKOUT2_JITTER {76.746} \
    CONFIG.CLKOUT2_PHASE_ERROR {107.074} \
] [get_ips clk_wiz_dvi]

create_ip -name rgb2dvi -vendor digilentinc.com -library ip -version 1.4 -module_name rgb2dvi_0
set_property -dict [list \
    CONFIG.kRstActiveHigh {false} \
    CONFIG.kGenerateSerialClk {false} \
] [get_ips rgb2dvi_0]

create_ip -name axi_ps2 -vendor digilentinc.com -library IP -version 1.0 -module_name axi_ps2_0
