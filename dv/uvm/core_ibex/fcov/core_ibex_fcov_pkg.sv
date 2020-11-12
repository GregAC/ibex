package core_ibex_fcov_pkg;
  class fcov_ifs;
    static virtual core_ibex_fcov_if_stage_if        if_stage;
    static virtual core_ibex_fcov_id_stage_if        id_stage;
    static virtual core_ibex_fcov_wb_stage_if        wb_stage;
    static virtual core_ibex_fcov_load_store_unit_if lsu;
    static virtual core_ibex_fcov_controller_if      controller;
  endclass
endpackage


