// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`ifndef RV32B
  `define RV32B ibex_pkg::RV32BNone
`endif

/**
 * Ibex simple system
 *
 * This is a basic system consisting of an ibex, a 1 MB sram for instruction/data
 * and a small memory mapped control module for outputting ASCII text and
 * controlling/halting the simulation from the software running on the ibex.
 *
 * It is designed to be used with verilator but should work with other
 * simulators, a small amount of work may be required to support the
 * simulator_ctrl module.
 */

module display_ibex_top #(
  parameter SRAMInitFile = ""
) (
  input clk_sys_i,
  input rst_sys_ni,

  input clk_hdmi_i,
  input rst_hdmi_ni,

  output logic       hdmi_tx_de_o,
  output logic       hdmi_tx_hs_o,
  output logic       hdmi_tx_vs_o,
  output logic [7:0] hdmi_tx_r_o,
  output logic [7:0] hdmi_tx_g_o,
  output logic [7:0] hdmi_tx_b_o
);

  parameter bit               PMPEnable                = 1'b0;
  parameter int unsigned      PMPGranularity           = 0;
  parameter int unsigned      PMPNumRegions            = 4;
  parameter bit               RV32E                    = 1'b0;
  parameter bit               RV32M                    = 1'b1;
  parameter ibex_pkg::rv32b_e RV32B                    = `RV32B;
  parameter bit               BranchTargetALU          = 1'b0;
  parameter bit               WritebackStage           = 1'b0;
  parameter                   MultiplierImplementation = "fast";

  // Real screen: 1080p
  //parameter int HSync            = 44;
  //parameter int HActive          = 1920;
  //parameter int HBack            = 148;
  //parameter int HFront           = 88;
  //parameter int VSync            = 5;
  //parameter int VActive          = 1080;
  //parameter int VBack            = 36;
  //parameter int VFront           = 4;
  //parameter int TextMemAddrWidth = 14;

  // Sim screen: 256 x 128
  parameter int HSync            = 2;
  parameter int HActive          = 256;
  parameter int HBack            = 5;
  parameter int HFront           = 3;
  parameter int VSync            = 1;
  parameter int VActive          = 128;
  parameter int VBack            = 3;
  parameter int VFront           = 5;
  parameter int TextMemAddrWidth = 8;

  parameter int TextMemDepth     = 2 ** TextMemAddrWidth;

  parameter int    FontWidth   = 8;
  parameter int    FontHeight  = 16;

  typedef enum {
    CoreD
  } bus_host_e;

  typedef enum {
    Ram,
    SimCtrl,
    Timer,
    TextRam,
    ColourRam,
    FGPaletteRam,
    BGPaletteRam,
    DisplayCtrl
  } bus_device_e;

  localparam int NrDevices = 8;
  localparam int NrHosts = 1;

  // interrupts
  logic timer_irq;
  logic vcounter_irq;

  // host and device signals
  logic           host_req    [NrHosts];
  logic           host_gnt    [NrHosts];
  logic [31:0]    host_addr   [NrHosts];
  logic           host_we     [NrHosts];
  logic [ 3:0]    host_be     [NrHosts];
  logic [31:0]    host_wdata  [NrHosts];
  logic           host_rvalid [NrHosts];
  logic [31:0]    host_rdata  [NrHosts];
  logic           host_err    [NrHosts];

  // devices (slaves)
  logic           device_req    [NrDevices];
  logic [31:0]    device_addr   [NrDevices];
  logic           device_we     [NrDevices];
  logic [ 3:0]    device_be     [NrDevices];
  logic [31:0]    device_wdata  [NrDevices];
  logic           device_rvalid [NrDevices];
  logic [31:0]    device_rdata  [NrDevices];
  logic           device_err    [NrDevices];

  // Device address mapping
  logic [31:0] cfg_device_addr_base [NrDevices];
  logic [31:0] cfg_device_addr_mask [NrDevices];

  assign cfg_device_addr_base[Ram]          = 32'h100000;
  assign cfg_device_addr_mask[Ram]          = ~32'h1FFFF; // 128 kB
  assign cfg_device_addr_base[SimCtrl]      = 32'h20000;
  assign cfg_device_addr_mask[SimCtrl]      = ~32'h3FF; // 1 kB
  assign cfg_device_addr_base[Timer]        = 32'h30000;
  assign cfg_device_addr_mask[Timer]        = ~32'h3FF; // 1 kB
  assign cfg_device_addr_base[TextRam]      = 32'h40000;
  assign cfg_device_addr_mask[TextRam]      = ~32'h7FFF; // 32 kB
  assign cfg_device_addr_base[ColourRam]    = 32'h50000;
  assign cfg_device_addr_mask[ColourRam]    = ~32'h7FFF; // 32 kB
  assign cfg_device_addr_base[FGPaletteRam] = 32'h60000;
  assign cfg_device_addr_mask[FGPaletteRam] = ~32'h3F;
  assign cfg_device_addr_base[BGPaletteRam] = 32'h60040;
  assign cfg_device_addr_mask[BGPaletteRam] = ~32'h3F;
  assign cfg_device_addr_base[DisplayCtrl]  = 32'h70000;
  assign cfg_device_addr_mask[DisplayCtrl]  = ~32'h3FF; // 1 kB

  // Instruction fetch signals
  logic instr_req;
  logic instr_gnt;
  logic instr_rvalid;
  logic [31:0] instr_addr;
  logic [31:0] instr_rdata;
  logic instr_err;

  assign instr_gnt = instr_req;
  assign instr_err = '0;

  // Tie-off unused error signals
  assign device_err[Ram] = 1'b0;
  assign device_err[SimCtrl] = 1'b0;

  bus #(
    .NrDevices    ( NrDevices ),
    .NrHosts      ( NrHosts   ),
    .DataWidth    ( 32        ),
    .AddressWidth ( 32        )
  ) u_bus (
    .clk_i                 ( clk_sys_i     ),
    .rst_ni                ( rst_sys_ni    ),

    .host_req_i            ( host_req      ),
    .host_gnt_o            ( host_gnt      ),
    .host_addr_i           ( host_addr     ),
    .host_we_i             ( host_we       ),
    .host_be_i             ( host_be       ),
    .host_wdata_i          ( host_wdata    ),
    .host_rvalid_o         ( host_rvalid   ),
    .host_rdata_o          ( host_rdata    ),
    .host_err_o            ( host_err      ),

    .device_req_o          ( device_req    ),
    .device_addr_o         ( device_addr   ),
    .device_we_o           ( device_we     ),
    .device_be_o           ( device_be     ),
    .device_wdata_o        ( device_wdata  ),
    .device_rvalid_i       ( device_rvalid ),
    .device_rdata_i        ( device_rdata  ),
    .device_err_i          ( device_err    ),

    .cfg_device_addr_base,
    .cfg_device_addr_mask
  );

`ifdef VERILATOR
  ibex_core_tracing #(
`else
  ibex_core #(
`endif
    .PMPEnable                ( PMPEnable                ),
    .PMPGranularity           ( PMPGranularity           ),
    .PMPNumRegions            ( PMPNumRegions            ),
    .MHPMCounterNum           ( 29                       ),
    .RV32E                    ( RV32E                    ),
    .RV32M                    ( RV32M                    ),
    .RV32B                    ( RV32B                    ),
    .BranchTargetALU          ( BranchTargetALU          ),
    .WritebackStage           ( WritebackStage           ),
    .MultiplierImplementation ( MultiplierImplementation ),
    .DmHaltAddr               ( 32'h00100000             ),
    .DmExceptionAddr          ( 32'h00100000             )
  ) u_core (
    .clk_i          ( clk_sys_i          ),
    .rst_ni         ( rst_sys_ni         ),

    .test_en_i      ( 'b0                ),

    .hart_id_i      ( 32'b0              ),
     // First instruction executed is at 0x0 + 0x80
    .boot_addr_i    ( 32'h00100000       ),

    .instr_req_o    ( instr_req          ),
    .instr_gnt_i    ( instr_gnt          ),
    .instr_rvalid_i ( instr_rvalid       ),
    .instr_addr_o   ( instr_addr         ),
    .instr_rdata_i  ( instr_rdata        ),
    .instr_err_i    ( instr_err          ),

    .data_req_o     ( host_req[CoreD]    ),
    .data_gnt_i     ( host_gnt[CoreD]    ),
    .data_rvalid_i  ( host_rvalid[CoreD] ),
    .data_we_o      ( host_we[CoreD]     ),
    .data_be_o      ( host_be[CoreD]     ),
    .data_addr_o    ( host_addr[CoreD]   ),
    .data_wdata_o   ( host_wdata[CoreD]  ),
    .data_rdata_i   ( host_rdata[CoreD]  ),
    .data_err_i     ( host_err[CoreD]    ),

    .irq_software_i ( 1'b0               ),
    .irq_timer_i    ( timer_irq          ),
    .irq_external_i ( 1'b0               ),
    .irq_fast_i     ( {14'b0, vcounter_irq} ),
    .irq_nm_i       ( 1'b0               ),

    .debug_req_i    ( 'b0                ),

    .fetch_enable_i ( 'b1                ),
    .core_sleep_o   (                    )
  );

  // SRAM block for instruction and data storage
  ram_2p #(
    .Depth(128*1024/4),
    .MemInitFile(SRAMInitFile)
  ) u_ram (
    .clk_i      ( clk_sys_i          ),
    .rst_ni     ( rst_sys_ni         ),

    .a_req_i    ( device_req[Ram]    ),
    .a_we_i     ( device_we[Ram]     ),
    .a_be_i     ( device_be[Ram]     ),
    .a_addr_i   ( device_addr[Ram]   ),
    .a_wdata_i  ( device_wdata[Ram]  ),
    .a_rvalid_o ( device_rvalid[Ram] ),
    .a_rdata_o  ( device_rdata[Ram]  ),

    .b_req_i    ( instr_req          ),
    .b_we_i     ( 1'b0               ),
    .b_be_i     ( 4'b0               ),
    .b_addr_i   ( instr_addr         ),
    .b_wdata_i  ( 32'b0              ),
    .b_rvalid_o ( instr_rvalid       ),
    .b_rdata_o  ( instr_rdata        )
  );


  timer #(
    .DataWidth    (32),
    .AddressWidth (32)
  ) u_timer (
    .clk_i          ( clk_sys_i            ),
    .rst_ni         ( rst_sys_ni           ),

    .timer_req_i    ( device_req[Timer]    ),
    .timer_we_i     ( device_we[Timer]     ),
    .timer_be_i     ( device_be[Timer]     ),
    .timer_addr_i   ( device_addr[Timer]   ),
    .timer_wdata_i  ( device_wdata[Timer]  ),
    .timer_rvalid_o ( device_rvalid[Timer] ),
    .timer_rdata_o  ( device_rdata[Timer]  ),
    .timer_err_o    ( device_err[Timer]    ),
    .timer_intr_o   ( timer_irq            )
  );

  logic [TextMemAddrWidth-1:0] text_mem_disp_addr;
  logic [7:0]                  text_mem_disp_char;
  logic [7:0]                  text_mem_disp_colour;
  logic [3:0]                  colour_addr_fg;
  logic [3:0]                  colour_addr_bg;
  logic [31:0]                 colour_data_fg;
  logic [31:0]                 colour_data_bg;

  //logic [31:0] text_ram_core_be;

  //assign text_ram_core_be = {{8{device_be[TextRam][3]}},
  //                           {8{device_be[TextRam][2]}},
  //                           {8{device_be[TextRam][1]}},
  //                           {8{device_be[TextRam][0]}}};

  //logic                        text_ram_disp_rvalid;
  //logic [TextMemAddrWidth-1:0] text_ram_disp_addr;
  //logic [1:0]                  text_ram_disp_rdata_sel;
  //logic [31:0]                 text_ram_disp_rdata;
  //logic [7:0]                  text_ram_disp_char;

  //prim_ram_2p #(
  //  .Width(32),
  //  .Depth(TextMemDepth),
  //  .DataBitsPerMask(8)
  //) u_text_ram (
  //  .clk_a_i   ( clk_sys_i                                  ),
  //  .clk_b_i   ( clk_hdmi_i                                 ),

  //  .a_req_i   ( device_req[TextRam]                        ),
  //  .a_write_i ( device_we[TextRam]                         ),
  //  .a_addr_i  ( device_addr[TextRam][TextMemAddrWidth-1:2] ),
  //  .a_wdata_i ( device_wdata[TextRam]                      ),
  //  .a_wmask_i ( text_ram_core_be                           ),
  //  .a_rdata_o ( device_rdata[TextRam]                      ),

  //  .b_req_i   ( 1'b1                                       ),
  //  .b_write_i ( 1'b0                                       ),
  //  .b_wdata_i ( 32'b0                                      ),
  //  .b_wmask_i ( 32'b0                                      ),
  //  .b_addr_i  ( text_ram_disp_addr[TextMemAddrWidth-1:2]   ),
  //  .b_rdata_o ( text_ram_disp_rdata                        )
  //);

  //always_ff @(posedge clk_sys_i or negedge rst_sys_ni) begin
  //  if(~rst_sys_ni) begin
  //    text_ram_disp_rvalid <= 1'b0;
  //  end else begin
  //    text_ram_disp_rvalid <= device_req[TextRam];
  //  end
  //end

  //always_ff @(posedge clk_hdmi_i or negedge rst_hdmi_ni) begin
  //  if(~rst_hdmi_ni) begin
  //    text_ram_disp_rdata_sel <= 2'b00;
  //  end else begin
  //    text_ram_disp_rdata_sel <= text_ram_disp_addr[1:0];
  //  end
  //end

  //assign device_rvalid[TextRam] = text_ram_disp_rvalid;
  //assign device_err[TextRam]    = 1'b0;

  //always_comb begin
  //  text_ram_disp_char = text_ram_disp_rdata[7:0];

  //  unique case(text_ram_disp_rdata_sel)
  //    2'b00: text_ram_disp_char = text_ram_disp_rdata[7:0];
  //    2'b01: text_ram_disp_char = text_ram_disp_rdata[15:8];
  //    2'b10: text_ram_disp_char = text_ram_disp_rdata[23:16];
  //    2'b11: text_ram_disp_char = text_ram_disp_rdata[31:24];
  //  endcase
  //end
  //
  display_ram #(
    .Depth(TextMemDepth),
    .ByteDispWidth(1)
  ) u_text_ram (
    .clk_core_i    ( clk_sys_i              ),
    .rst_core_ni   ( rst_sys_ni             ),

    .core_req_i    ( device_req[TextRam]    ),
    .core_we_i     ( device_we[TextRam]     ),
    .core_addr_i   ( device_addr[TextRam]   ),
    .core_wdata_i  ( device_wdata[TextRam]  ),
    .core_be_i     ( device_be[TextRam]     ),
    .core_rdata_o  ( device_rdata[TextRam]  ),
    .core_rvalid_o ( device_rvalid[TextRam] ),
    .core_err_o    ( device_err[TextRam]    ),

    .clk_disp_i    ( clk_hdmi_i             ),
    .rst_disp_ni   ( rst_hdmi_ni            ),

    .disp_addr_i   ( text_mem_disp_addr     ),
    .disp_rdata_o  ( text_mem_disp_char     )
  );

  display_ram #(
    .Depth(TextMemDepth),
    .ByteDispWidth(1)
  ) u_colour_ram (
    .clk_core_i    ( clk_sys_i                ),
    .rst_core_ni   ( rst_sys_ni               ),

    .core_req_i    ( device_req[ColourRam]    ),
    .core_we_i     ( device_we[ColourRam]     ),
    .core_addr_i   ( device_addr[ColourRam]   ),
    .core_wdata_i  ( device_wdata[ColourRam]  ),
    .core_be_i     ( device_be[ColourRam]     ),
    .core_rdata_o  ( device_rdata[ColourRam]  ),
    .core_rvalid_o ( device_rvalid[ColourRam] ),
    .core_err_o    ( device_err[ColourRam]    ),

    .clk_disp_i    ( clk_hdmi_i               ),
    .rst_disp_ni   ( rst_hdmi_ni              ),

    .disp_addr_i   ( text_mem_disp_addr       ),
    .disp_rdata_o  ( text_mem_disp_colour     )
  );

  display_ram #(
    .Depth(64),
    .ByteDispWidth(0)
  ) u_fg_palette_ram (
    .clk_core_i    ( clk_sys_i                   ),
    .rst_core_ni   ( rst_sys_ni                  ),

    .core_req_i    ( device_req[FGPaletteRam]    ),
    .core_we_i     ( device_we[FGPaletteRam]     ),
    .core_addr_i   ( device_addr[FGPaletteRam]   ),
    .core_wdata_i  ( device_wdata[FGPaletteRam]  ),
    .core_be_i     ( device_be[FGPaletteRam]     ),
    .core_rdata_o  ( device_rdata[FGPaletteRam]  ),
    .core_rvalid_o ( device_rvalid[FGPaletteRam] ),
    .core_err_o    ( device_err[FGPaletteRam]    ),

    .clk_disp_i    ( clk_hdmi_i                  ),
    .rst_disp_ni   ( rst_hdmi_ni                 ),

    .disp_addr_i   ( {colour_addr_fg, 2'b00}     ),
    .disp_rdata_o  ( colour_data_fg              )
  );

  display_ram #(
    .Depth(64),
    .ByteDispWidth(0)
  ) u_bg_palette_ram (
    .clk_core_i    ( clk_sys_i                   ),
    .rst_core_ni   ( rst_sys_ni                  ),

    .core_req_i    ( device_req[BGPaletteRam]    ),
    .core_we_i     ( device_we[BGPaletteRam]     ),
    .core_addr_i   ( device_addr[BGPaletteRam]   ),
    .core_wdata_i  ( device_wdata[BGPaletteRam]  ),
    .core_be_i     ( device_be[BGPaletteRam]     ),
    .core_rdata_o  ( device_rdata[BGPaletteRam]  ),
    .core_rvalid_o ( device_rvalid[BGPaletteRam] ),
    .core_err_o    ( device_err[BGPaletteRam]    ),

    .clk_disp_i    ( clk_hdmi_i                  ),
    .rst_disp_ni   ( rst_hdmi_ni                 ),

    .disp_addr_i   ( {colour_addr_bg, 2'b00}     ),
    .disp_rdata_o  ( colour_data_bg              )
  );

  logic display_en_hdmi;
  logic [13:0] vcounter_hdmi;

  display_ctrl #(
    .VCounterWidth(14)
  ) u_display_ctrl (
    .clk_sys_i         ( clk_sys_i                  ),
    .rst_sys_ni        ( rst_sys_ni                 ),

    .clk_hdmi_i        ( clk_hdmi_i                 ),
    .rst_hdmi_ni       ( rst_hdmi_ni                ),

    .core_req_i        ( device_req[DisplayCtrl]    ),
    .core_we_i         ( device_we[DisplayCtrl]     ),
    .core_addr_i       ( device_addr[DisplayCtrl]   ),
    .core_wdata_i      ( device_wdata[DisplayCtrl]  ),
    .core_be_i         ( device_be[DisplayCtrl]     ),
    .core_rdata_o      ( device_rdata[DisplayCtrl]  ),
    .core_rvalid_o     ( device_rvalid[DisplayCtrl] ),
    .core_err_o        ( device_err[DisplayCtrl]    ),

    .vcounter_hdmi_i   ( vcounter_hdmi              ),
    .vcounter_int_o    ( vcounter_irq               ),
    .display_en_hdmi_o ( display_en_hdmi            )
  );

  logic [7:0] fg_colour_r;
  logic [7:0] fg_colour_g;
  logic [7:0] fg_colour_b;

  logic [7:0] bg_colour_r;
  logic [7:0] bg_colour_g;
  logic [7:0] bg_colour_b;

  assign fg_colour_r = colour_data_fg[7:0];
  assign fg_colour_g = colour_data_fg[15:8];
  assign fg_colour_b = colour_data_fg[23:16];

  assign bg_colour_r = colour_data_bg[7:0];
  assign bg_colour_g = colour_data_bg[15:8];
  assign bg_colour_b = colour_data_bg[23:16];

  text_display #(
    .HSync            ( HSync            ),
    .HActive          ( HActive          ),
    .HBack            ( HBack            ),
    .HFront           ( HFront           ),
    .VSync            ( VSync            ),
    .VActive          ( VActive          ),
    .VBack            ( VBack            ),
    .VFront           ( VFront           ),
    .TextMemAddrWidth ( TextMemAddrWidth ),
    .FontWidth        ( FontWidth        ),
    .FontHeight       ( FontHeight       )
  ) text_display_i (
    .clk_i                ( clk_hdmi_i                ),
    .rst_ni               ( rst_hdmi_ni               ),

    .display_en_i         ( display_en_hdmi           ),
    .vcounter_o           ( vcounter_hdmi             ),

    .hdmi_tx_de_o         ( hdmi_tx_de_o              ),
    .hdmi_tx_hs_o         ( hdmi_tx_hs_o              ),
    .hdmi_tx_vs_o         ( hdmi_tx_vs_o              ),
    .hdmi_tx_r_o          ( hdmi_tx_r_o               ),
    .hdmi_tx_g_o          ( hdmi_tx_g_o               ),
    .hdmi_tx_b_o          ( hdmi_tx_b_o               ),

    .text_mem_addr_o      ( text_mem_disp_addr        ),
    .text_mem_char_i      ( text_mem_disp_char        ),

    .text_mem_bg_colour_i ( text_mem_disp_colour[3:0] ),
    .text_mem_fg_colour_i ( text_mem_disp_colour[7:4] ),

    .colour_addr_fg_o     ( colour_addr_fg            ),
    .colour_addr_bg_o     ( colour_addr_bg            ),

    .fg_colour_r_i        ( fg_colour_r               ),
    .fg_colour_g_i        ( fg_colour_g               ),
    .fg_colour_b_i        ( fg_colour_b               ),

    .bg_colour_r_i        ( bg_colour_r               ),
    .bg_colour_g_i        ( bg_colour_g               ),
    .bg_colour_b_i        ( bg_colour_b               )
  );

`ifdef VERILATOR
  simulator_ctrl #(
    .LogName("ibex_simple_system.log")
  ) u_simulator_ctrl (
    .clk_i    ( clk_sys_i              ),
    .rst_ni   ( rst_sys_ni             ),

    .req_i    ( device_req[SimCtrl]    ),
    .we_i     ( device_we[SimCtrl]     ),
    .be_i     ( device_be[SimCtrl]     ),
    .addr_i   ( device_addr[SimCtrl]   ),
    .wdata_i  ( device_wdata[SimCtrl]  ),
    .rvalid_o ( device_rvalid[SimCtrl] ),
    .rdata_o  ( device_rdata[SimCtrl]  )
  );

  export "DPI-C" function mhpmcounter_get;

  function automatic longint mhpmcounter_get(int index);
    return u_core.u_ibex_core.cs_registers_i.mhpmcounter[index];
  endfunction
`else
  assign device_rvalid[SimCtrl] = 1'b1;
  assign device_rdata[SimCtrl] = 32'hBAADF00D;
`endif
endmodule
