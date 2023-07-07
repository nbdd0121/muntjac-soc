`include "tl_util.svh"

module muntjac_core_wrapper import muntjac_pkg::*; #(
  parameter DataWidth = 64,
  parameter PhysAddrLen = 56,
  parameter rv64f_e RV64F = RV64FNone,
  parameter int unsigned DCacheWaysWidth = 2,
  parameter int unsigned DCacheSetsWidth = 6,
  parameter int unsigned ICacheWaysWidth = 2,
  parameter int unsigned ICacheSetsWidth = 6,
  parameter int unsigned DTlbNumWays = 4,
  parameter int unsigned DTlbSetsWidth = 3,
  parameter int unsigned ITlbNumWays = 4,
  parameter int unsigned ITlbSetsWidth = 3,
  parameter int unsigned MHPMCounterNum = 0,
  parameter bit          MHPMICacheEnable = 1'b0,
  parameter bit          MHPMDCacheEnable = 1'b0,
  parameter int unsigned SourceWidth = 4,
  parameter int unsigned SinkWidth = 1
) (
  // Clock and reset
  input  logic            clk_i,
  input  logic            rst_ni,

  // Memory interface
  `TL_DECLARE_HOST_PORT(DataWidth, PhysAddrLen, SourceWidth, SinkWidth, mem),

  input  logic irq_software_m_i,
  input  logic irq_timer_m_i,
  input  logic irq_external_m_i,
  input  logic irq_external_s_i,

  input  logic [63:0] hart_id_i,

  input  logic [HPM_EVENT_NUM-1:0] hpm_event_i,

  // Debug connections
  output instr_trace_t dbg_o
);

  if (DataWidth == 128 &&
      PhysAddrLen == 38 &&
      RV64F == RV64FFull &&
      DCacheWaysWidth == 2 &&
      DCacheSetsWidth == 6 &&
      ICacheWaysWidth == 2 &&
      ICacheSetsWidth == 6 &&
      DTlbNumWays == 32 &&
      DTlbSetsWidth == 0 &&
      ITlbNumWays == 32 &&
      ITlbSetsWidth == 0 &&
      MHPMCounterNum == 0 &&
      MHPMICacheEnable == 1'b0 &&
      MHPMDCacheEnable == 1'b0 &&
      SourceWidth == 2 &&
      SinkWidth == 4
  ) begin: preset1

    muntjac_core_preset1 core (
      .clk_i,
      .rst_ni,
      `TL_FORWARD_HOST_PORT(mem, mem),
      .irq_software_m_i,
      .irq_timer_m_i,
      .irq_external_m_i,
      .irq_external_s_i,
      .hart_id_i,
      .hpm_event_i,
      .dbg_o
    );

  end else begin: no_preset

    $warning("Preset is not used due to parameter mismatch");
    
    muntjac_core #(
      .DataWidth        (DataWidth),
      .PhysAddrLen      (PhysAddrLen),
      .RV64F            (RV64F),
      .DCacheWaysWidth  (DCacheWaysWidth),
      .DCacheSetsWidth  (DCacheSetsWidth),
      .ICacheWaysWidth  (ICacheWaysWidth),
      .ICacheSetsWidth  (ICacheSetsWidth),
      .DTlbNumWays      (DTlbNumWays),
      .DTlbSetsWidth    (DTlbSetsWidth),
      .ITlbNumWays      (ITlbNumWays),
      .ITlbSetsWidth    (ITlbSetsWidth),
      .MHPMCounterNum   (MHPMCounterNum),
      .MHPMICacheEnable (MHPMICacheEnable),
      .MHPMDCacheEnable (MHPMDCacheEnable),
      .SourceWidth      (SourceWidth),
      .SinkWidth        (SinkWidth)
    ) core (
      .clk_i,
      .rst_ni,
      `TL_FORWARD_HOST_PORT(mem, mem),
      .irq_software_m_i,
      .irq_timer_m_i,
      .irq_external_m_i,
      .irq_external_s_i,
      .hart_id_i,
      .hpm_event_i,
      .dbg_o
    );

  end

endmodule
