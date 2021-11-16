# TODO: This requires a license to use. Replace this with an open source one.
create_ip -name axi_ethernet -vendor xilinx.com -library ip -version 7.2 -module_name axi_ethernet_0
set_property -dict [list \
    CONFIG.PHY_TYPE {RGMII} \
    CONFIG.TXCSUM {Full} \
    CONFIG.RXCSUM {Full} \
    CONFIG.Statistics_Counters {false} \
] [get_ips axi_ethernet_0]

# DMA needed for the AXI Ethernet IP
create_ip -name axi_dma -vendor xilinx.com -library ip -version 7.1 -module_name axi_dma_eth
set_property -dict [list \
    CONFIG.Component_Name {axi_dma_eth} \
    CONFIG.c_sg_length_width {16} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_include_mm2s_dre {1} \
    CONFIG.c_mm2s_burst_size {256} \
    CONFIG.c_sg_use_stsapp_length {1} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_include_s2mm_dre {1} \
    CONFIG.c_s2mm_burst_size {256} \
] [get_ips axi_dma_eth]

# Clock wizard for ref/gtx clocks
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_eth
set_property -dict [list \
    CONFIG.Component_Name {clk_wiz_eth} \
    CONFIG.PRIMITIVE {PLL} \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.PRIM_IN_FREQ {50} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125} \
    CONFIG.USE_LOCKED {false} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.CLKIN1_JITTER_PS {200.0} \
    CONFIG.CLKOUT1_DRIVES {BUFG} \
    CONFIG.CLKOUT2_DRIVES {BUFG} \
    CONFIG.CLKOUT3_DRIVES {BUFG} \
    CONFIG.CLKOUT4_DRIVES {BUFG} \
    CONFIG.CLKOUT5_DRIVES {BUFG} \
    CONFIG.CLKOUT6_DRIVES {BUFG} \
    CONFIG.CLKOUT7_DRIVES {BUFG} \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.MMCM_BANDWIDTH {OPTIMIZED} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {20} \
    CONFIG.MMCM_CLKIN1_PERIOD {20.000} \
    CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
    CONFIG.MMCM_COMPENSATION {ZHOLD} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {5} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {8} \
    CONFIG.PLL_CLKIN_PERIOD {20.000} \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.CLKOUT1_JITTER {142.107} \
    CONFIG.CLKOUT1_PHASE_ERROR {164.985} \
    CONFIG.CLKOUT2_JITTER {154.207} \
    CONFIG.CLKOUT2_PHASE_ERROR {164.985} \
] [get_ips clk_wiz_eth]
