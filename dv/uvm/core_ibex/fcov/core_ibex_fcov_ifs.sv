interface core_ibex_fcov_if_stage_if (
  input logic if_instr_valid
);
  initial begin
    core_ibex_fcov_pkg::fcov_ifs::if_stage = if_stage_i.u_if_stage_if;
  end
endinterface

interface core_ibex_fcov_wb_stage_if (
  input logic fcov_wb_valid,
  input logic outstanding_load_wb_o
);
  initial begin
    core_ibex_fcov_pkg::fcov_ifs::wb_stage = wb_stage_i.u_wb_stage_if;
  end
endinterface

interface core_ibex_fcov_load_store_unit_if (
  input logic fcov_ls_error_exception,
  input logic fcov_ls_pmp_exception
);
  initial begin
    core_ibex_fcov_pkg::fcov_ifs::lsu = load_store_unit_i.u_load_store_unit_if;
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
  input logic        stall_jump,
  input logic        fcov_rf_rd_wb_hz,
  input logic        fcov_branch_taken,
  input logic        fcov_branch_not_taken
);
  initial begin
    core_ibex_fcov_pkg::fcov_ifs::id_stage = id_stage_i.u_id_stage_if;
  end
endinterface

interface core_ibex_fcov_controller_if (
  input logic fcov_interrupt_taken,
  input logic fcov_debug_entry_if,
  input logic fcov_debug_entry_id,
  input logic fcov_pipe_flush
);
  initial begin
    core_ibex_fcov_pkg::fcov_ifs::controller = controller_i.u_controller_if;
  end
endinterface
