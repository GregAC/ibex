module display_driver #(
  parameter int HCounterWidth = 12,
  parameter int VCounterWidth = 12
) (
  input clk_i,
  input rst_ni,

  input  logic driver_en_i,
  input  logic driver_rst_i,

  input  logic [HCounterWidth-1:0] hsync_i,
  input  logic [HCounterWidth-1:0] hstart_i,
  input  logic [HCounterWidth-1:0] hend_i,
  input  logic [HCounterWidth-1:0] htotal_i,

  input  logic [VCounterWidth-1:0] vsync_i,
  input  logic [VCounterWidth-1:0] vstart_i,
  input  logic [VCounterWidth-1:0] vend_i,
  input  logic [VCounterWidth-1:0] vtotal_i,

  output logic [HCounterWidth-1:0] hcounter_o,
  output logic [VCounterWidth-1:0] vcounter_o,
  output logic                     display_hs_o,
  output logic                     display_vs_o,
  output logic                     display_de_o
);

  logic [HCounterWidth-1:0] hcounter_q;
  logic [VCounterWidth-1:0] vcounter_q;

  logic [HCounterWidth-1:0] hcounter_inc;
  logic [VCounterWidth-1:0] vcounter_inc;

  logic [HCounterWidth-1:0] hcounter_d;
  logic [VCounterWidth-1:0] vcounter_d;

  logic display_hs_q;
  logic display_vs_q;
  logic display_v_de_q;
  logic display_h_de_q;
  logic display_de_q;

  logic display_hs_d;
  logic display_vs_d;
  logic display_v_de_d;
  logic display_h_de_d;
  logic display_de_d;

  always @(posedge clk_i or negedge rst_ni) begin
    if(~rst_ni) begin
      hcounter_q     <= '0;
      vcounter_q     <= '0;
      display_hs_q   <= 1'b0;
      display_vs_q   <= 1'b0;
      display_h_de_q <= 1'b0;
      display_v_de_q <= 1'b0;
      display_de_q   <= 1'b0;
    end else if(driver_en_i) begin
      hcounter_q     <= hcounter_d;
      vcounter_q     <= vcounter_d;
      display_hs_q   <= display_hs_d;
      display_vs_q   <= display_vs_d;
      display_v_de_q <= display_v_de_d;
      display_h_de_q <= display_h_de_d;
      display_de_q   <= display_de_d;
    end
  end

  always_comb begin
    hcounter_inc = hcounter_q + 1'b1;
    vcounter_inc = vcounter_q + 1'b1;

    if(driver_rst_i) begin
      hcounter_d     = '0;
      vcounter_d     = '0;
      display_hs_d   = 1'b0;
      display_vs_d   = 1'b0;
      display_h_de_d = 1'b0;
      display_v_de_d = 1'b0;
      display_de_d   = 1'b0;
    end else begin
      hcounter_d     = hcounter_q;
      vcounter_d     = vcounter_q;
      display_hs_d   = display_hs_q;
      display_vs_d   = display_vs_q;
      display_v_de_d = display_v_de_q;
      display_h_de_d = display_h_de_q;

      if(hcounter_inc == htotal_i) begin
        hcounter_d   = '0;
        display_hs_d = 1;

        if(vcounter_inc == vtotal_i) begin
          display_vs_d = 1;
          vcounter_d   = '0;
        end else begin
          vcounter_d = vcounter_inc;
        end

        if(vcounter_inc == vsync_i) begin
          display_vs_d = 0;
        end

        if(vcounter_inc == vstart_i) begin
          display_v_de_d = 1;
        end else if(vcounter_inc == vend_i) begin
          display_v_de_d = 0;
        end
      end else begin
        hcounter_d = hcounter_inc;
      end

      if(hcounter_inc == hsync_i) begin
        display_hs_d = 0;
      end

      if(hcounter_inc == hstart_i) begin
        display_h_de_d = 1;
      end else if(hcounter_inc == hend_i) begin
        display_h_de_d = 0;
      end

      if(display_h_de_d & display_v_de_d) begin
        display_de_d = 1;
      end else begin
        display_de_d = 0;
      end
    end
  end

  assign hcounter_o   = hcounter_q;
  assign vcounter_o   = vcounter_q;
  assign display_hs_o = ~display_hs_q;
  assign display_vs_o = ~display_vs_q;
  assign display_de_o = display_de_q;
endmodule
