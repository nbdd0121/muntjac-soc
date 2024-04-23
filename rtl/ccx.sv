`include "tl_util.svh"

module ccx import muntjac_pkg::*; #(
  parameter NumCores = 2,
  parameter DmaSourceWidth = 2,
  parameter DeviceSourceWidth = 5,
  parameter SinkWidth = 1,
  parameter AddrWidth = 56,
  parameter bit EnableHpm = 1'b0
) (
  input clk_i,
  input rst_ni,

  input [NumCores-1:0] irq_software_m_i,
  input [NumCores-1:0] irq_timer_m_i,
  input [NumCores-1:0] irq_external_m_i,
  input [NumCores-1:0] irq_external_s_i,

  `TL_DECLARE_DEVICE_PORT(128, AddrWidth, DmaSourceWidth, SinkWidth, dma),
  `TL_DECLARE_HOST_PORT(128, AddrWidth, DeviceSourceWidth, 1, mem),
  `TL_DECLARE_HOST_PORT(32, AddrWidth, DeviceSourceWidth, 1, rom),
  `TL_DECLARE_HOST_PORT(64, AddrWidth, DeviceSourceWidth, 1, io)
);

  localparam DataWidth = 128;
  localparam HostSourceWidth = 2;

  ///////////////////
  // Connect Ports //
  ///////////////////

  `TL_DECLARE(128, AddrWidth, DmaSourceWidth, SinkWidth, dma);
  `TL_DECLARE(128, AddrWidth, DeviceSourceWidth, 1, mem);
  `TL_DECLARE(32, AddrWidth, DeviceSourceWidth, 1, rom);
  `TL_DECLARE(64, AddrWidth, DeviceSourceWidth, 1, io);
  `TL_BIND_DEVICE_PORT(dma, dma);
  `TL_BIND_HOST_PORT(mem, mem);
  `TL_BIND_HOST_PORT(rom, rom);
  `TL_BIND_HOST_PORT(io, io);

  ///////////////////
  // ID Allocation //
  ///////////////////
  
  localparam logic [DeviceSourceWidth-1:0] SourceMaskS = 0;
  localparam logic [DeviceSourceWidth-1:0] SourceMaskL = 3;
  localparam logic [DeviceSourceWidth-1:0] SourceMaskDma = 2 ** DmaSourceWidth - 1;

  localparam logic [DeviceSourceWidth-1:0] SourceBaseCore = 0;
  // Ensure this is aligned
  localparam logic [DeviceSourceWidth-1:0] SourceBaseDma = (NumCores * 4 + SourceMaskDma) &~ SourceMaskDma;

  localparam logic [HostSourceWidth-1:0] HostSourceMask = 3;
  localparam logic [DmaSourceWidth-1:0] DmaSourceMask = SourceMaskDma;

  localparam [SinkWidth-1:0] MemSinkBase = 0;
  localparam [SinkWidth-1:0] MemSinkMask = 3;

  localparam [SinkWidth-1:0] RomSinkBase = 4;
  localparam [SinkWidth-1:0] RomSinkMask = 0;
  
  localparam [SinkWidth-1:0] IoSinkBase = 5;
  localparam [SinkWidth-1:0] IoSinkMask = 0;

  localparam [AddrWidth-1:0] MemBase = 'h40000000;
  localparam [AddrWidth-1:0] MemMask = 'h3FFFFFFF;
  
  localparam [AddrWidth-1:0] RomBase = 'h00000000;
  localparam [AddrWidth-1:0] RomMask = 'h 1FFFFFF;

  if (SourceBaseDma + SourceMaskDma >= 2 ** DeviceSourceWidth) $fatal(1, "Not enough source width");
  
  /////////
  // CPU //
  /////////

  `TL_DECLARE_ARR(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, cache_unshifted, [NumCores-1:0]);
  `TL_DECLARE_ARR(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, cache_ch, [NumCores:0]);
  logic [NumCores-1:0][63:0] dbg_core;
  logic [63:0] dbg_llc;

  logic hpm_acq_count;
  logic hpm_rel_count;
  logic hpm_miss;

  for (genvar i = 0; i < NumCores; i++) begin: core
    
    logic [HPM_EVENT_NUM-1:0] hpm_event;
    always_comb begin
      hpm_event = '0;

      // Ensure that these HPM counter are only counted on one core.
      if (i == 0) begin
        hpm_event[HPM_EVENT_L2_ACQ_COUNT] = hpm_acq_count;
        hpm_event[HPM_EVENT_L2_REL_COUNT] = hpm_rel_count;
        hpm_event[HPM_EVENT_L2_MISS]      = hpm_miss;
      end
    end

    muntjac_core_wrapper #(
      .DataWidth (DataWidth),
      .PhysAddrLen (AddrWidth),
      .SourceWidth (HostSourceWidth),
      .SinkWidth (SinkWidth),
      .RV64F (muntjac_pkg::RV64FMem),
      .DTlbNumWays (32),
      .DTlbSetsWidth (0),
      .ITlbNumWays (32),
      .ITlbSetsWidth (0),
      .MHPMCounterNum (EnableHpm ? 9 : 0),
      .MHPMICacheEnable (EnableHpm),
      .MHPMDCacheEnable (EnableHpm)
    ) cpu (
      .clk_i,
      .rst_ni,
      `TL_CONNECT_HOST_PORT_IDX(mem, cache_unshifted, [i]),
      .irq_software_m_i (irq_software_m_i[i]),
      .irq_timer_m_i (irq_timer_m_i[i]),
      .irq_external_m_i (irq_external_m_i[i]),
      .irq_external_s_i (irq_external_s_i[i]),
      .hart_id_i (i),
      .hpm_event_i (hpm_event),
      .dbg_o ()
    );

    localparam logic [DeviceSourceWidth-1:0] SourceBase = SourceBaseCore + 4 * i;

    tl_source_shifter #(
      .DataWidth (DataWidth),
      .AddrWidth (AddrWidth),
      .SinkWidth (SinkWidth),
      .HostSourceWidth (HostSourceWidth),
      .DeviceSourceWidth (DeviceSourceWidth),
      .SourceBase (SourceBase),
      .SourceMask (HostSourceMask)
    ) shifter (
      .clk_i,
      .rst_ni,
      `TL_CONNECT_DEVICE_PORT_IDX(host, cache_unshifted, [i]),
      `TL_CONNECT_HOST_PORT_IDX(device, cache_ch, [i])
    );
  end

  /////////////////////////
  // DMA port connection //
  /////////////////////////

  tl_source_shifter #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SinkWidth (SinkWidth),
    .HostSourceWidth (DmaSourceWidth),
    .DeviceSourceWidth (DeviceSourceWidth),
    .SourceBase (SourceBaseDma),
    .SourceMask (DmaSourceMask)
  ) shifter_dma (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, dma),
    `TL_CONNECT_HOST_PORT_IDX(device, cache_ch, [NumCores])
  );

  ////////////////////////////
  // Combine all host ports //
  ////////////////////////////

  function automatic logic [NumCores-1:0][DeviceSourceWidth-1:0] generate_socket_source_base();
    for (int i = 0; i < NumCores; i++) begin
      if (i == 0) begin
        generate_socket_source_base[i] = SourceBaseDma;
      end else begin
        generate_socket_source_base[i] = SourceBaseCore + i * 4;
      end
    end
  endfunction

  function automatic logic [NumCores-1:0][DeviceSourceWidth-1:0] generate_socket_source_mask();
    for (int i = 0; i < NumCores; i++) begin
      if (i == 0) begin
        generate_socket_source_mask[i] = SourceMaskDma;
      end else begin
        generate_socket_source_mask[i] = SourceMaskL;
      end
    end
  endfunction

  function automatic logic [NumCores-1:0][$clog2(NumCores+1)-1:0] generate_socket_source_link();
    for (int i = 0; i < NumCores; i++) begin
      if (i == 0) begin
        generate_socket_source_link[i] = NumCores;
      end else begin
        generate_socket_source_link[i] = i;
      end
    end
  endfunction

  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, host_aggreg_unreg);
  tl_socket_m1 #(
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .DataWidth (DataWidth),
    .NumLinks (NumCores + 1),
    .NumSourceRange (NumCores),
    .SourceBase (generate_socket_source_base()),
    .SourceMask (generate_socket_source_mask()),
    .SourceLink (generate_socket_source_link())
  ) host_aggregator (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, cache_ch),
    `TL_CONNECT_HOST_PORT(device, host_aggreg_unreg)
  );

  // Register slice for timing
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, host_aggreg);
  tl_regslice #(
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .DataWidth (DataWidth),
    .RequestMode (7),
    .ProbeMode (7),
    .ReleaseMode (7),
    .GrantMode (7),
    .AckMode (7)
  ) host_aggreg_reg (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, host_aggreg_unreg),
    `TL_CONNECT_HOST_PORT(device, host_aggreg)
  );

  ////////////////////////////////////////////
  // Switch based on address space property //
  ////////////////////////////////////////////

  `TL_DECLARE_ARR(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device_ch, [2:0]);

  tl_socket_1n #(
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .NumLinks    (3),
    .NumAddressRange (2),
    .AddressBase     ({MemBase, RomBase}),
    .AddressMask     ({MemMask, RomMask}),
    .AddressLink     ({2'd   1, 2'd   2}),
    .NumSinkRange (2),
    .SinkBase ({MemSinkBase, RomSinkBase}),
    .SinkMask ({MemSinkMask, RomSinkMask}),
    .SinkLink ({2'd       1, 2'd       2})
  ) socket_1n (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, host_aggreg),
    `TL_CONNECT_HOST_PORT(device, device_ch)
  );

  ////////////////////////
  // Memory termination //
  ////////////////////////

  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, mem_tlc);

  function automatic logic [NumCores-1:0][DeviceSourceWidth-1:0] generate_llc_source_base();
    for (int i = 0; i < NumCores; i++) begin
      generate_llc_source_base[i] = SourceBaseCore + i * 4;
    end
  endfunction

  function automatic logic [NumCores-1:0][DeviceSourceWidth-1:0] generate_llc_source_mask();
    for (int i = 0; i < NumCores; i++) begin
      generate_llc_source_mask[i] = SourceMaskS;
    end
  endfunction

  muntjac_llc # (
    .SetsWidth (8 + $clog2(NumCores)), // (2**8)*4*64B=64KiB L2 per core
    .AcqTrackerNum (NumCores < 4 ? NumCores : 4),
    .RelTrackerNum (NumCores < 4 ? NumCores : 4),
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .SinkBase (MemSinkBase),
    .SinkMask (MemSinkMask),
    .DeviceSourceBase (0),
    .DeviceSourceMask (7),
    .NumCachedHosts (NumCores),
    .SourceBase (generate_llc_source_base()),
    .SourceMask (generate_llc_source_mask()),
    .EnableHpm (EnableHpm)
  ) llc_inst (
    .clk_i,
    .rst_ni,
    .hpm_acq_count_o (hpm_acq_count),
    .hpm_rel_count_o (hpm_rel_count),
    .hpm_miss_o (hpm_miss),
    `TL_CONNECT_DEVICE_PORT_IDX(host, device_ch, [1]),
    `TL_CONNECT_HOST_PORT(device, mem_tlc)
  );

  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth + 2, 1, mem_wide);

  tl_ram_terminator # (
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .HostSourceWidth (DeviceSourceWidth),
    .DeviceSourceWidth (DeviceSourceWidth + 2),
    .HostSinkWidth (SinkWidth),
    .SinkBase (0),
    .SinkMask (2 ** SinkWidth - 1)
  ) mem_term (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, mem_tlc),
    `TL_CONNECT_HOST_PORT(device, mem_wide)
  );

  tl_adapter #(
    .HostDataWidth (DataWidth),
    .DeviceDataWidth (128),
    .HostAddrWidth (AddrWidth),
    .DeviceAddrWidth (AddrWidth),
    .HostSourceWidth (DeviceSourceWidth + 2),
    .DeviceSourceWidth (DeviceSourceWidth),
    .HostSinkWidth (1),
    .DeviceSinkWidth (1),
    .HostMaxSize (6),
    .DeviceMaxSize (6),
    .HostFifo (1'b0),
    .DeviceFifo (1'b0)
  ) mem_adapter (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, mem_wide),
    `TL_CONNECT_HOST_PORT(device, mem)
  );

  /////////////////////
  // ROM termination //
  /////////////////////

  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth+1, 1, rom_tlc);

  tl_rom_terminator # (
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .HostSourceWidth (DeviceSourceWidth),
    .DeviceSourceWidth (DeviceSourceWidth + 1),
    .HostSinkWidth (SinkWidth),
    .SinkBase (RomSinkBase)
  ) rom_term (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT_IDX(host, device_ch, [2]),
    `TL_CONNECT_HOST_PORT(device, rom_tlc)
  );

  tl_adapter #(
    .HostDataWidth (DataWidth),
    .DeviceDataWidth (32),
    .HostAddrWidth (AddrWidth),
    .DeviceAddrWidth (AddrWidth),
    .HostSourceWidth (DeviceSourceWidth + 1),
    .DeviceSourceWidth (DeviceSourceWidth),
    .HostSinkWidth (1),
    .DeviceSinkWidth (1),
    .HostMaxSize (6),
    .DeviceMaxSize (6),
    .HostFifo (1'b0),
    .DeviceFifo (1'b0)
  ) rom_adapter (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, rom_tlc),
    `TL_CONNECT_HOST_PORT(device, rom)
  );

  ////////////////////
  // IO termination //
  ////////////////////

  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, 1, io_tlc);

  tl_io_terminator # (
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth),
    .HostSinkWidth (SinkWidth),
    .SinkBase (IoSinkBase)
  ) io_term (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT_IDX(host, device_ch, [0]),
    `TL_CONNECT_HOST_PORT(device, io_tlc)
  );

  tl_adapter #(
    .HostDataWidth (DataWidth),
    .DeviceDataWidth (64),
    .HostAddrWidth (AddrWidth),
    .DeviceAddrWidth (AddrWidth),
    .HostSourceWidth (DeviceSourceWidth),
    .DeviceSourceWidth (DeviceSourceWidth),
    .HostSinkWidth (1),
    .DeviceSinkWidth (1),
    .HostMaxSize (6),
    .DeviceMaxSize (3),
    .HostFifo (1'b0),
    .DeviceFifo (1'b0)
  ) io_adapter (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, io_tlc),
    `TL_CONNECT_HOST_PORT(device, io)
  );

endmodule
