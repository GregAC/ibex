proc yosys_select_in_to_out {out_net in_net} {
  yosys "select $out_net"
  yosys "select % %co*:-\$dff:-\$adff"
  yosys "select -set fanout %"
  yosys "select $in_net"
  yosys "select % %ci*:-\$dff:-\$adff"
  yosys "select -set fanin %"
  yosys "select @fanout @fanin %i"
  yosys "select -set feedthrough %"
}

proc yosys_select_in_to_out_pre_map {out_net in_net} {
  yosys "select $out_net"
  yosys "select % %co*:-\$_DFF_PN0_:-\$_DFF_PN1_:-\$_DFF_P_"
  yosys "select -set fanout %"
  yosys "select $in_net"
  yosys "select % %ci*:-\$_DFF_PN0_:-\$_DFF_PN1_:-\$_DFF_P_"
  yosys "select -set fanin %"
  yosys "select @fanout @fanin %i"
}

