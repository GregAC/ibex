`define MARK_UNUSED(__var_type, __var_name) \
  `ifdef FCOV_TEST_ONLY \
    __var_type unused_fcov_``__var_name; \
\
    assign unused_fcov_``__var_name = fcov_``__var_name; \
  `endif

`define FCOV_SIGNAL(__var_type, __var_name, __var_definition) \
  `ifdef DV_FCOV \
    __var_type fcov_``__var_name; \
\
    assign fcov_``__var_name = __var_definition; \
\
    `MARK_UNUSED(__var_type, __var_name) \
  `endif

`define FCOV_SIGNAL_GEN_IF(__var_type, __var_name, __var_definition, __generate_test, __default_val = '0) \
  `ifdef DV_FCOV \
    __var_type fcov_``__var_name; \
\
    if (__generate_test) begin : g_fcov_``__var_name \
      assign fcov_``__var_name = __var_definition; \
    end else begin : g_no_fcov_``__var_name \
      assign fcov_``__var_name = __default_val; \
    end \
\
    `MARK_UNUSED(__var_type, __var_name) \
  `endif

