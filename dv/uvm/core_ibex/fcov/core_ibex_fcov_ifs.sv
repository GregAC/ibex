interface core_ibex_fcov_if_stage_if (
  input logic if_instr_valid
);
  initial begin
    core_ibex_fcov_pkg::fcov_ifs::if_stage = if_stage_i.u_if_stage_if;
  end
endinterface

interface core_ibex_fcov_wb_stage_if (
  input logic wb_valid_q
);
  initial begin
    core_ibex_fcov_pkg::fcov_ifs::wb_stage = wb_stage_i.u_wb_stage_if;
  end
endinterface

interface core_ibex_fcov_id_stage_if (
  input logic        clk_i,
  input logic        instr_valid_i,
  input logic [31:0] instr_rdata_i,
  input logic        stall_ld_hz,
  input logic        stall_mem,
  input logic        stall_multdiv,
  input logic        stall_branch,
  input logic        stall_jump
);

  initial begin
    core_ibex_fcov_pkg::fcov_ifs::id_stage = id_stage_i.u_id_stage_if;
  end
endinterface

