module display_ctrl #(
  parameter int VCounterWidth = 11
) (
  input clk_sys_i,
  input rst_sys_ni,

  input clk_hdmi_i,
  input rst_hdmi_ni,

  input  logic        core_req_i,
  input  logic        core_we_i,
  input  logic [31:0] core_addr_i,
  input  logic [31:0] core_wdata_i,
  input  logic [3:0]  core_be_i,
  output logic [31:0] core_rdata_o,
  output logic        core_rvalid_o,
  output logic        core_err_o,

  input  logic [VCounterWidth-1:0] vcounter_hdmi_i,
  output logic                     vcounter_int_o,
  output logic                     display_en_hdmi_o
);
  localparam AddrWidth = 4;
  localparam SyncDepth = 3;

  localparam [AddrWidth-1:2] CtrlAddr = 0;
  localparam [AddrWidth-1:2] StatusAddr = 1;
  localparam [AddrWidth-1:2] TriggerAddr = 2;

  logic [VCounterWidth-1:0] vcounter_sync_q [SyncDepth];
  logic [VCounterWidth-1:0] vcounter_core;
  logic                 display_en_core_q, display_en_core_d;
  logic [SyncDepth-1:0] display_en_sync_q;

  for (genvar i = 0;i < SyncDepth; i++) begin : g_sync
    always @(posedge clk_sys_i or negedge rst_sys_ni) begin
      if (!rst_sys_ni) begin
        vcounter_sync_q[i] <= '0;
      end else begin
        if (i != 0) begin
          vcounter_sync_q[i] <= vcounter_sync_q[i - 1];
        end else begin
          vcounter_sync_q[i] <= bin2gray(vcounter_hdmi_i);
        end
      end
    end

    always @(posedge clk_hdmi_i or negedge rst_hdmi_ni) begin
      if (!rst_hdmi_ni) begin
        display_en_sync_q[i] <= '0;
      end else begin
        display_en_sync_q[i] <= (i == 0) ? display_en_core_q : display_en_sync_q[i - 1];
      end
    end
  end

  assign vcounter_core = gray2bin(vcounter_sync_q[SyncDepth-1]);

  logic core_access_q;
  logic core_access_err_q, core_access_err_d;
  logic vcounter_int_q, vcounter_int_d;
  logic vcounter_int_enable_q, vcounter_int_enable_d;
  logic [VCounterWidth-1:0] vcounter_int_trigger_q, vcounter_int_trigger_d;
  logic [VCounterWidth-1:0] vcounter_core_last;
  logic [31:0] core_rdata_q, core_rdata_d;

  always @(posedge clk_sys_i or negedge rst_sys_ni) begin
    if (!rst_sys_ni) begin
      display_en_core_q      <= 0;
      core_access_q          <= 0;
      core_access_err_q      <= 0;
      vcounter_int_q         <= 0;
      vcounter_int_enable_q  <= 0;
      vcounter_int_trigger_q <= '0;
      vcounter_core_last     <= '0;
      core_rdata_q           <= '0;
    end else begin
      display_en_core_q      <= display_en_core_d;
      core_access_q          <= core_req_i;
      core_access_err_q      <= core_access_err_d;
      vcounter_int_q         <= vcounter_int_d;
      vcounter_int_enable_q  <= vcounter_int_enable_d;
      vcounter_int_trigger_q <= vcounter_int_trigger_d;
      vcounter_core_last     <= vcounter_core;
      core_rdata_q           <= core_rdata_d;
    end
  end

  always_comb begin
    core_rdata_d = '0;

    if (core_req_i && ~core_we_i) begin
      case (core_addr_i[AddrWidth-1:2])
        CtrlAddr: core_rdata_d    = {30'b0,
                                     vcounter_int_enable_q,
                                     display_en_core_q};
        StatusAddr: core_rdata_d  = {{(31 - VCounterWidth){1'b0}},
                                     vcounter_core,
                                     vcounter_int_q};
        TriggerAddr: core_rdata_d = {{(32 - VCounterWidth){1'b0}},
                                     vcounter_int_trigger_q};
        default: ;
      endcase
    end
  end

  always_comb begin
    vcounter_int_d         = vcounter_int_q;
    vcounter_int_enable_d  = vcounter_int_enable_q;
    vcounter_int_trigger_d = vcounter_int_trigger_q;
    display_en_core_d      = display_en_core_q;
    core_access_err_d      = 1'b0;

    if (core_req_i && core_we_i) begin
      case (core_addr_i[AddrWidth-1:2])
        CtrlAddr: begin
          vcounter_int_enable_d = core_wdata_i[1];
          display_en_core_d = core_wdata_i[0];
        end
        StatusAddr: begin
          vcounter_int_d = core_wdata_i[0];
        end
        TriggerAddr: begin
          vcounter_int_trigger_d = core_wdata_i[VCounterWidth-1:0];
        end
        default: begin
          core_access_err_d = 1'b0;
        end
      endcase
    end

    if (vcounter_int_enable_q) begin
      if ((vcounter_core != vcounter_core_last) && (vcounter_core == vcounter_int_trigger_q)) begin
        vcounter_int_d = 1'b1;
      end
    end

    if (core_req_i) begin
      if (core_addr_i[1:0] != 2'b00) begin
        core_access_err_d = 1'b1;
      end

      if (core_we_i && (core_be_i != 4'hf)) begin
        core_access_err_d = 1'b1;
      end
    end
  end

  assign vcounter_int_o = vcounter_int_q;
  assign display_en_hdmi_o = display_en_sync_q[SyncDepth-1];

  assign core_rdata_o = core_rdata_q;
  assign core_rvalid_o = core_access_q;
  assign core_err_o = core_access_err_q;

  function automatic [VCounterWidth-1:0] bin2gray(input logic [VCounterWidth-1:0] decval);
    bin2gray = decval ^ {1'b0, decval[VCounterWidth-1:1]};
  endfunction

  function automatic [VCounterWidth-1:0] gray2bin(input logic [VCounterWidth-1:0] grayval);
    logic [VCounterWidth-1:0] bin_tmp;

    bin_tmp = grayval;
    for (int i = VCounterWidth-2; i >= 0; i--)
      bin_tmp[i] = bin_tmp[i+1]^grayval[i];

    gray2bin = bin_tmp;
  endfunction
endmodule
