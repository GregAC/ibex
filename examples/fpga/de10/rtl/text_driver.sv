module text_driver #(
  parameter int HCounterWidth    = 12,
  parameter int VCounterWidth    = 12,
  parameter int TextMemAddrWidth = 14,
  parameter int MaxLineLength    = 240,
  parameter int FontWidth        = 8,
  parameter int FontHeight       = 16,
  parameter int FontMemAddrWidth = $clog2(FontHeight * 256)
) (
  input                                    clk_i,
  input                                    rst_ni,
  input                                    display_en_i,

  input logic [HCounterWidth-1:0]          hcounter_i,
  input logic [VCounterWidth-1:0]          vcounter_i,

  input logic [HCounterWidth-1:0]          hstart_text_i,
  input logic [HCounterWidth-1:0]          hend_text_i,
  input logic [VCounterWidth-1:0]          vstart_text_i,
  input logic [VCounterWidth-1:0]          vend_text_i,

  output logic [TextMemAddrWidth-1:0]      text_mem_addr_o,
  input  logic [7:0]                       text_mem_char_i,
  input  logic [3:0]                       text_mem_bg_colour_i,
  input  logic [3:0]                       text_mem_fg_colour_i,

  output logic [FontMemAddrWidth-1:0]      font_mem_addr_o,
  input  logic [FontWidth-1:0]             font_mem_line_i,

  output logic [3:0]                       colour_addr_fg_o,
  output logic [3:0]                       colour_addr_bg_o,

  input  logic [$clog2(MaxLineLength)-1:0] text_width_i,

  output logic                             pix_o
);
  localparam int FontXWidth = $clog2(FontWidth);
  localparam int FontYWidth = $clog2(FontHeight);

  logic [TextMemAddrWidth-1:0] text_mem_addr_q;
  logic [FontWidth-1:0]        font_x_mask_q;
  logic [FontXWidth-1:0]       font_x_q;
  logic [FontYWidth-1:0]       font_y_q;

  logic [TextMemAddrWidth-1:0] text_mem_addr_d;
  logic [FontMemAddrWidth-1:0] font_mem_addr_d;
  logic [31:0]                 font_mem_addr_wide_d;
  logic [FontWidth-1:0]        font_x_mask_d;
  logic [FontXWidth-1:0]       font_x_d;
  logic [FontYWidth-1:0]       font_y_d;

  logic                        hactive_q;
  logic                        vactive_q;

  logic                        hactive_d;
  logic                        vactive_d;

  logic                        pix_d;

  // Can use small multiplier for calculating font addr
  // font_mem_addr = (text_mem_char_i * FontHeight) + font_y
  // or round up to nearest power of two
  // font_mem_addr = {text_mem_char_i, font_y}
  // font_y / font_x just increment when in active region
  // font_x not explicit, use font_x_mask, implement as shift register and AND
  // with output from font RAM.

  always @(posedge clk_i or negedge rst_ni) begin
    if(~rst_ni) begin
      hactive_q <= 1'b0;
      vactive_q <= 1'b0;
    end else if (display_en_i) begin
      hactive_q <= hactive_d;
      vactive_q <= vactive_d;
    end
  end

  always @(posedge clk_i) begin
    if(display_en_i) begin
      text_mem_addr_q <= text_mem_addr_d;
      font_x_mask_q   <= font_x_mask_d;
      font_x_q        <= font_x_d;
      font_y_q        <= font_y_d;
    end
  end

  always_comb begin
    text_mem_addr_d = text_mem_addr_q;
    font_x_mask_d   = font_x_mask_q;
    font_x_d        = font_x_q;
    font_y_d        = font_y_q;
    hactive_d       = hactive_q;
    vactive_d       = vactive_q;

    font_mem_addr_wide_d = (text_mem_char_i * FontHeight) + font_y_q;
    font_mem_addr_d      = font_mem_addr_wide_d[FontMemAddrWidth-1:0];
    pix_d                = |(font_mem_line_i & font_x_mask_q);

    if(hcounter_i == '0) begin
      if(vcounter_i == vstart_text_i) begin
        vactive_d       = 1'b1;
        font_y_d        = '0;
        text_mem_addr_d = '0;
      end else if (vcounter_i == vend_text_i) begin
        vactive_d = 1'b0;
      end else if(vactive_q) begin
        if(font_y_q == (FontHeight - 1)) begin
          font_y_d = '0;
        end else begin
          font_y_d = font_y_d + 1'b1;
          text_mem_addr_d = text_mem_addr_q - text_width_i;
        end
      end
    end else if(hcounter_i == hstart_text_i) begin
      hactive_d     = 1'b1;
      font_x_mask_d = {1'b0, 1'b1, {(FontWidth-2){1'b0}}};
      font_x_d      = '0;
    end else if (hcounter_i == hend_text_i) begin
      hactive_d = 1'b0;
    end else if(hactive_q) begin
      if(font_x_q == (FontWidth - 1)) begin
        text_mem_addr_d = text_mem_addr_q + 1'b1;
        font_x_d = '0;
      end else begin
        font_x_d = font_x_q + 1'b1;
      end

      if(font_x_mask_q[FontWidth - 1]) begin
        font_x_mask_d = {{(FontWidth-1){1'b0}}, 1'b1};
      end else begin
        font_x_mask_d = {font_x_mask_q[FontWidth-2:0], 1'b0};
      end
    end
  end

  assign text_mem_addr_o  = text_mem_addr_q;
  assign font_mem_addr_o  = font_mem_addr_d;

  assign colour_addr_fg_o = text_mem_fg_colour_i;
  assign colour_addr_bg_o = text_mem_bg_colour_i;

  assign pix_o            = pix_d;

  logic [31:FontMemAddrWidth]  unused_font_mem_addr_wide_d;

  assign unused_font_mem_addr_wide_d = font_mem_addr_wide_d[31:FontMemAddrWidth];
endmodule
