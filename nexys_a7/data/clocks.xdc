# Rename generated clocks
create_generated_clock -name mig_clk -source [get_pins ddr/ddr_ctrl/u_mig_7series_0_mig/u_ddr2_infrastructure/gen_ui_extra_clocks.mmcm_i/CLKIN1] -master_clock [get_clocks pll_clk3_out] [get_pins ddr/ddr_ctrl/u_mig_7series_0_mig/u_ddr2_infrastructure/gen_ui_extra_clocks.mmcm_i/CLKFBOUT]
create_generated_clock -name bus_clk -source [get_pins ddr/ddr_ctrl/u_mig_7series_0_mig/u_ddr2_infrastructure/gen_ui_extra_clocks.mmcm_i/CLKIN1] -master_clock [get_clocks pll_clk3_out] [get_pins ddr/ddr_ctrl/u_mig_7series_0_mig/u_ddr2_infrastructure/gen_ui_extra_clocks.mmcm_i/CLKOUT0]
create_generated_clock -name io_clk -source [get_pins ddr/ddr_ctrl/u_mig_7series_0_mig/u_ddr2_infrastructure/gen_ui_extra_clocks.mmcm_i/CLKIN1] -master_clock [get_clocks pll_clk3_out] [get_pins ddr/ddr_ctrl/u_mig_7series_0_mig/u_ddr2_infrastructure/gen_ui_extra_clocks.mmcm_i/CLKOUT1]

####################
# region SD Timing #

# From SD base clock to the generated SDCLK
create_generated_clock -name sdclk -source [get_pins sdhci/sdhci/clock_div/io_clk_o] -divide_by 2 [get_pins sdhci/sdhci/clock_div/sdclk_o_reg/Q]

# From SDCLK to the actual SD_SCK output pin
create_generated_clock -name sd_sck -source [get_pins sdhci/sdhci/clock_div/sdclk_o_reg/Q] -multiply_by 1 [get_ports sd_sck]

# All paths between SDCLK and CLK are properly synchronised.
set_false_path -from [get_clocks bus_clk] -to [get_clocks sdclk]
set_false_path -from [get_clocks sdclk] -to [get_clocks bus_clk]
set_false_path -from [get_clocks sd_sck] -to [get_clocks bus_clk]

# All paths between SD base clock and CLK are also properly synchronised.
set_false_path -from [get_clocks bus_clk] -to [get_clocks io_clk]
set_false_path -from [get_clocks io_clk] -to [get_clocks bus_clk]

# This ought to be 14ns. But that fails timing, and I'm too lazy to tweak it.
set_input_delay -clock sd_sck -clock_fall -max 12.000 [get_ports sd_dat]
set_input_delay -clock sd_sck -clock_fall -min 0.000 [get_ports sd_dat]
set_input_delay -clock sd_sck -clock_fall -max 12.000 [get_ports sd_cmd]
set_input_delay -clock sd_sck -clock_fall -min 0.000 [get_ports sd_cmd]
set_output_delay -clock sd_sck -max 5.000 [get_ports sd_dat]
set_output_delay -clock sd_sck -min -5.000 [get_ports sd_dat]
set_output_delay -clock sd_sck -max 5.000 [get_ports sd_cmd]
set_output_delay -clock sd_sck -min -5.000 [get_ports sd_cmd]

# endregion
####################

#######################
# region Flash timing #

# You must provide all the delay numbers
# CCLK delay is 0.5, 6.7 ns min/max for K7-2; refer Data sheet
# Consider the max delay for worst case analysis

set cclk_delay 7.5
# Following are the SPI device parameters
# Max Tco
set tco_max 8
# Min Tco
set tco_min 2

# Setup time requirement
set tsu 1.5
set tcss 3

# Hold time requirement
set th 2
set tcsh 3

# Following are the board/trace delay numbers
# Assumption is that all Data lines are matched
set tdata_trace_delay_max 0.25
set tdata_trace_delay_min 0.25
set tclk_trace_delay_max 0.2
set tclk_trace_delay_min 0.2

### End of user provided delay numbers


# this is to ensure min routing delay from SCK generation to STARTUP input
# User should change this value based on the results
# having more delay on this net reduces the Fmax

#set_max_delay 1.5 -from [get_pins -hier *SCK_O_*FDRE*/C] -to [get_pins -hier *USRCCLKO] -datapath_only
#set_min_delay 0.1 -from [get_pins -hier *SCK_O_*FDRE*/C] -to [get_pins -hier *USRCCLKO]

# Following command creates a divide by 2 clock
# It also takes into account the delay added by STARTUP block to route the CCLK

create_generated_clock -name clk_sck -source [get_pins -hierarchical *spi_flash/ext_spi_clk] [get_pins -hierarchical *USRCCLKO] -edges {3 5 7} -edge_shift [list $cclk_delay $cclk_delay $cclk_delay]

# Data is captured into FPGA on the second rising edge of ext_spi_clk after the SCK falling edge
# Data is driven by the FPGA on every alternate rising_edge of ext_spi_clk

# 8.1, 0.450
set_input_delay -clock clk_sck -max [expr $tco_max + $tdata_trace_delay_max + $tclk_trace_delay_max] [get_ports qspi_dq] -clock_fall
set_input_delay -clock clk_sck -min [expr $tco_min + $tdata_trace_delay_min + $tclk_trace_delay_min] [get_ports qspi_dq] -clock_fall

set_multicycle_path 2 -setup -from [get_clocks clk_sck] -to [get_clocks -of_objects [get_pins -hierarchical *spi_flash/ext_spi_clk]]
set_multicycle_path 1 -hold -end -from [get_clocks clk_sck] -to [get_clocks -of_objects [get_pins -hierarchical *spi_flash/ext_spi_clk]]

# Data is captured into SPI on the following rising edge of SCK
# Data is driven by the IP on alternate rising_edge of the ext_spi_clk
# 1.550, -1.950, 3.050, -2.950
set_output_delay -clock clk_sck -max [expr $tsu + $tdata_trace_delay_max - $tclk_trace_delay_min] [get_ports qspi_dq]
set_output_delay -clock clk_sck -min [expr $tdata_trace_delay_min -$th - $tclk_trace_delay_max] [get_ports qspi_dq]
set_output_delay -clock clk_sck -max [expr $tcss + $tdata_trace_delay_max - $tclk_trace_delay_min] [get_ports qspi_csn]
set_output_delay -clock clk_sck -min [expr $tdata_trace_delay_min -$tcsh - $tclk_trace_delay_max] [get_ports qspi_csn]

set_multicycle_path 2 -setup -start -from [get_clocks -of_objects [get_pins -hierarchical *spi_flash/ext_spi_clk]] -to [get_clocks clk_sck]
set_multicycle_path 1 -hold -from [get_clocks -of_objects [get_pins -hierarchical *spi_flash/ext_spi_clk]] -to [get_clocks clk_sck]

# endregion
#######################
