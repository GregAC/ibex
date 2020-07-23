module text_display # (
  parameter int    HSync            = 44,
  parameter int    HActive          = 1920,
  parameter int    HBack            = 148,
  parameter int    HFront           = 88,
  parameter int    VSync            = 5,
  parameter int    VActive          = 1080,
  parameter int    VBack            = 36,
  parameter int    VFront           = 4,
  parameter int    TextMemAddrWidth = 14,
  parameter int    FontWidth        = 8,
  parameter int    FontHeight       = 16,

  localparam HTotal = HSync + HActive + HBack + HFront,
  localparam VTotal = VSync + VActive + VBack + VFront,

  localparam HCounterWidth = $clog2(HTotal),
  localparam VCounterWidth = $clog2(VTotal)
) (
  input clk_i,
  input rst_ni,

  input  logic                     display_en_i,
  output logic [VCounterWidth-1:0] vcounter_o,

  output logic       hdmi_tx_de_o,
  output logic       hdmi_tx_hs_o,
  output logic       hdmi_tx_vs_o,
  output logic [7:0] hdmi_tx_r_o,
  output logic [7:0] hdmi_tx_g_o,
  output logic [7:0] hdmi_tx_b_o,

  output logic [TextMemAddrWidth-1:0] text_mem_addr_o,
  input  logic [7:0]                  text_mem_char_i,
  input  logic [3:0]                  text_mem_bg_colour_i,
  input  logic [3:0]                  text_mem_fg_colour_i,

  output logic [3:0]                  colour_addr_fg_o,
  output logic [3:0]                  colour_addr_bg_o,

  input  logic [7:0]                  fg_colour_r_i,
  input  logic [7:0]                  fg_colour_g_i,
  input  logic [7:0]                  fg_colour_b_i,

  input  logic [7:0]                  bg_colour_r_i,
  input  logic [7:0]                  bg_colour_g_i,
  input  logic [7:0]                  bg_colour_b_i

);
  localparam HStart = HSync + HBack;
  localparam HEnd   = HSync + HBack + HActive;

  localparam VStart = VSync + VBack;
  localparam VEnd   = VSync + VBack + VActive;

  localparam HStartText = HStart - 4;
  localparam HEndText   = HEnd + 1;
  localparam VStartText = VStart;
  localparam VEndText   = VEnd;

  localparam TextWidth = HActive / FontWidth;

  logic [HCounterWidth-1:0] hcounter;
  logic [VCounterWidth-1:0] vcounter;

  logic [7:0] hdmi_tx_r_d, hdmi_tx_r_q;
  logic [7:0] hdmi_tx_g_d, hdmi_tx_g_q;
  logic [7:0] hdmi_tx_b_d, hdmi_tx_b_q;

  display_driver # (
    .HCounterWidth ( HCounterWidth ),
    .VCounterWidth ( VCounterWidth )
  ) display_driver_i (
    .clk_i        ( clk_i  ),
    .rst_ni       ( rst_ni         ),

    .driver_en_i  ( display_en_i   ),
    .driver_rst_i ( 1'b0           ),

    .hsync_i      ( HSync          ),
    .hstart_i     ( HStart         ),
    .hend_i       ( HEnd           ),
    .htotal_i     ( HTotal         ),

    .vsync_i      ( VSync          ),
    .vstart_i     ( VStart         ),
    .vend_i       ( VEnd           ),
    .vtotal_i     ( VTotal         ),

    .hcounter_o   ( hcounter       ),
    .vcounter_o   ( vcounter       ),

    .display_hs_o ( hdmi_tx_hs_o   ),
    .display_vs_o ( hdmi_tx_vs_o   ),
    .display_de_o ( hdmi_tx_de_o   )
  );

  /* verilator lint_off UNUSED */
  logic [11:0]          font_mem_addr;
  /* veriatlor lint_on UNUSED */
  logic [FontWidth-1:0] font_mem_line;
  logic		              pix;

  text_driver #(
    .HCounterWidth    ( HCounterWidth    ),
    .VCounterWidth    ( VCounterWidth    ),
    .TextMemAddrWidth ( TextMemAddrWidth ),
    .FontWidth        ( FontWidth        ),
    .FontHeight       ( FontHeight       )
  ) u_text_driver (
    .clk_i                ( clk_i                ),
    .rst_ni               ( rst_ni               ),
    .display_en_i         ( display_en_i         ),

    .hcounter_i           ( hcounter             ),
    .vcounter_i           ( vcounter             ),

    .hstart_text_i        ( HStartText           ),
    .hend_text_i          ( HEndText             ),
    .vstart_text_i        ( VStartText           ),
    .vend_text_i          ( VEndText             ),

    .text_mem_addr_o      ( text_mem_addr_o      ),
    .text_mem_char_i      ( text_mem_char_i      ),
    .text_mem_bg_colour_i ( text_mem_bg_colour_i ),
    .text_mem_fg_colour_i ( text_mem_fg_colour_i ),

    .font_mem_addr_o      ( font_mem_addr        ),
    .font_mem_line_i      ( font_mem_line        ),

    .colour_addr_fg_o     ( colour_addr_fg_o     ),
    .colour_addr_bg_o     ( colour_addr_bg_o     ),

    .text_width_i         ( TextWidth            ),

    .pix_o                ( pix                  )
  );

  /* verilator lint_off UNUSED */
  reg [FontWidth-1:0] font_rom [(FontHeight * 256)-1:0];
  /* verilator lint_on UNUSED */

  `ifndef FONT_ROM_FILE
    `define FONT_ROM_FILE "test_font.vmem"
  `endif

  initial begin
    $readmemb(`FONT_ROM_FILE, font_rom);
  end

  always_ff @(posedge clk_i) begin
    font_mem_line <= font_rom[font_mem_addr];
  end

  assign hdmi_tx_r_d = pix ? bg_colour_r_i : fg_colour_r_i;
  assign hdmi_tx_g_d = pix ? bg_colour_g_i : fg_colour_g_i;
  assign hdmi_tx_b_d = pix ? bg_colour_b_i : fg_colour_b_i;

  always_ff @(posedge clk_i) begin
    if (display_en_i) begin
      hdmi_tx_r_q <= hdmi_tx_r_d;
      hdmi_tx_g_q <= hdmi_tx_g_d;
      hdmi_tx_b_q <= hdmi_tx_b_d;
    end
  end

  assign hdmi_tx_r_o = hdmi_tx_r_q;
  assign hdmi_tx_g_o = hdmi_tx_g_q;
  assign hdmi_tx_b_o = hdmi_tx_b_q;

  logic [11:0] pix_x;
  logic [11:0] pix_y;

  /* verilator lint_off WIDTH */
  assign pix_x = hdmi_tx_de_o ? hcounter - HStart : '0;
  assign pix_y = hdmi_tx_de_o ? vcounter - VStart : '0;
  /* verilator lint_on WIDTH */

  assign vcounter_o = vcounter;
endmodule
