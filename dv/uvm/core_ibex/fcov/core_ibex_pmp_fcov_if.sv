// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "prim_assert.sv"

interface core_ibex_pmp_fcov_if import ibex_pkg::*; #(
    // Granularity of NAPOT access,
    // 0 = No restriction, 1 = 8 byte, 2 = 16 byte, 3 = 32 byte, etc.
    parameter int unsigned PMPGranularity = 0,
    // Number of implemented regions
    parameter int unsigned PMPNumRegions  = 4
) (
  input clk_i,
  input rst_ni,

  input ibex_pkg::pmp_cfg_t  csr_pmp_cfg     [PMPNumRegions],
  input logic                pmp_req_err     [2],
  input pmp_mseccfg_t        csr_pmp_mseccfg,

  input logic instr_req_out,
  input logic data_req_out,

  input logic lsu_req_done
);
  `include "dv_fcov_macros.svh"
  import uvm_pkg::*;

  // Enum to give more readable coverage results for privilege bits. 4 bits are from the pmpcfg CSF
  // (L, X, W, R) and the 5th is the MML bit. Setting the MML bit changes the meaning of the other
  // 4 bits
  // TODO: Better MML names?
  typedef enum logic [4:0] {
    PMP_PRIV_NONE     = 5'b00000,
    PMP_PRIV_R        = 5'b00001,
    PMP_PRIV_W        = 5'b00010,
    PMP_PRIV_WR       = 5'b00011,
    PMP_PRIV_X        = 5'b00100,
    PMP_PRIV_XR       = 5'b00101,
    PMP_PRIV_XW       = 5'b00110,
    PMP_PRIV_XWR      = 5'b00111,
    PMP_PRIV_L        = 5'b01000,
    PMP_PRIV_LR       = 5'b01001,
    PMP_PRIV_LW       = 5'b01010,
    PMP_PRIV_LWR      = 5'b01011,
    PMP_PRIV_LX       = 5'b01100,
    PMP_PRIV_LXR      = 5'b01101,
    PMP_PRIV_LXW      = 5'b01110,
    PMP_PRIV_LXWR     = 5'b01111,
    PMP_PRIV_MML_NONE = 5'b10000,
    PMP_PRIV_MML_R    = 5'b10001,
    PMP_PRIV_MML_W    = 5'b10010,
    PMP_PRIV_MML_WR   = 5'b10011,
    PMP_PRIV_MML_X    = 5'b10100,
    PMP_PRIV_MML_XR   = 5'b10101,
    PMP_PRIV_MML_XW   = 5'b10110,
    PMP_PRIV_MML_XWR  = 5'b10111,
    PMP_PRIV_MML_L    = 5'b11000,
    PMP_PRIV_MML_LR   = 5'b11001,
    PMP_PRIV_MML_LW   = 5'b11010,
    PMP_PRIV_MML_LWR  = 5'b11011,
    PMP_PRIV_MML_LX   = 5'b11100,
    PMP_PRIV_MML_LXR  = 5'b11101,
    PMP_PRIV_MML_LXW  = 5'b11110,
    PMP_PRIV_MML_LXWR = 5'b11111
  } pmp_priv_bits_e;

  // Break out PMP signals into individually named signals for direct use in `cross` as it cannot
  // deal with hierarchical references or unpacked arrays.
  logic pmp_iside_req_err;
  logic pmp_dside_req_err;

  assign pmp_iside_req_err = pmp_req_err[PMP_I];
  assign pmp_dside_req_err = pmp_req_err[PMP_D];

  pmp_req_e  pmp_req_type_iside, pmp_req_type_dside;
  priv_lvl_e pmp_priv_lvl_iside, pmp_priv_lvl_dside;

  assign pmp_req_type_iside = g_pmp.pmp_req_type[PMP_I];
  assign pmp_req_type_dside = g_pmp.pmp_req_type[PMP_D];

  assign pmp_priv_lvl_iside = g_pmp.pmp_priv_lvl[PMP_I];
  assign pmp_priv_lvl_dside = g_pmp.pmp_priv_lvl[PMP_D];

  bit en_pmp_fcov;

  initial begin
   void'($value$plusargs("enable_ibex_fcov=%d", en_pmp_fcov));
  end

  for (genvar i_region = 0; i_region < PMPNumRegions; i_region += 1) begin : g_pmp_region_fcov
    pmp_priv_bits_e pmp_region_priv_bits;

    assign pmp_region_priv_bits = pmp_priv_bits_e'({csr_pmp_mseccfg.mml,
                                                    csr_pmp_cfg[i_region].lock,
                                                    csr_pmp_cfg[i_region].exec,
                                                    csr_pmp_cfg[i_region].write,
                                                    csr_pmp_cfg[i_region].read});

    covergroup pmp_region_cg @(posedge clk_i);
      cp_region_mode : coverpoint csr_pmp_cfg[i_region].mode;
      cp_region_priv_bits : coverpoint pmp_region_priv_bits;

      pmp_iside_mode_cross : cross cp_region_mode, pmp_iside_req_err
        iff (g_pmp_fcov_signals[i_region].fcov_pmp_region_ichan_access);

      pmp_dside_mode_cross : cross cp_region_mode, pmp_dside_req_err
        iff (g_pmp_fcov_signals[i_region].fcov_pmp_region_dchan_access);

      pmp_iside_priv_bits_cross :
        cross cp_region_priv_bits, pmp_req_type_iside, pmp_priv_lvl_iside, pmp_iside_req_err
          iff (g_pmp_fcov_signals[i_region].fcov_pmp_region_ichan_access);

      pmp_dside_priv_bits_cross :
        cross cp_region_priv_bits, pmp_req_type_dside, pmp_priv_lvl_dside, pmp_dside_req_err
          iff (g_pmp_fcov_signals[i_region].fcov_pmp_region_dchan_access);
    endgroup

    `DV_FCOV_INSTANTIATE_CG(pmp_region_cg, en_pmp_fcov)
  end

  logic lsu_first_req_valid;
  logic lsu_first_req_pmp_err;

  logic lsu_second_req_valid;
  logic lsu_second_req_pmp_err;

  logic lsu_req_done_last_cycle;

  logic [PMPNumRegions-1:0] lsu_first_req_pmp_region;
  logic [PMPNumRegions-1:0] lsu_second_req_pmp_region;

  logic lsu_first_second_regions_match;

  assign lsu_first_second_regions_match = (lsu_first_req_pmp_region == lsu_second_req_pmp_region) &
    lsu_first_req_valid &
    lsu_second_req_valid;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      lsu_first_req_valid       <= 1'b0;
      lsu_first_req_pmp_err     <= 1'b0;
      lsu_second_req_valid      <= 1'b0;
      lsu_second_req_pmp_err    <= 1'b0;
      lsu_first_req_pmp_region  <= '0;
      lsu_second_req_pmp_region <= '0;
      lsu_req_done_last_cycle   <= 1'b0;
    end else begin
      lsu_req_done_last_cycle <= lsu_req_done;

      if (data_req_out) begin
        if (load_store_unit_i.fcov_ls_first_req) begin
          lsu_first_req_valid       <= 1'b1;
          lsu_first_req_pmp_err     <= pmp_dside_req_err;
          lsu_first_req_pmp_region  <= g_pmp.pmp_i.region_match_all[PMP_D];
          lsu_second_req_valid      <= 1'b0;
          lsu_second_req_pmp_err    <= 1'b0;
          lsu_second_req_pmp_region <= '0;
        end else if (load_store_unit_i.fcov_ls_second_req) begin
          lsu_second_req_valid      <= 1'b1;
          lsu_second_req_pmp_err    <= pmp_dside_req_err;
          lsu_second_req_pmp_region <= g_pmp.pmp_i.region_match_all[PMP_D];
        end
      end
    end
  end

  covergroup pmp_top_cg @(posedge clk_i);
    cp_pmp_iside_region_override :
      coverpoint g_pmp.pmp_i.g_access_check[PMP_I].fcov_pmp_region_override iff (instr_req_out);

    cp_pmp_dside_region_override :
      coverpoint g_pmp.pmp_i.g_access_check[PMP_D].fcov_pmp_region_override iff (data_req_out);

    cp_pmp_dside_cross_foo :
      coverpoint {lsu_first_req_valid, lsu_first_req_pmp_err, lsu_second_req_valid,
                  lsu_second_req_pmp_err, lsu_first_second_regions_match}
        iff (lsu_req_done_last_cycle & (|(lsu_first_req_pmp_region | lsu_second_req_pmp_region)));
  endgroup

  `DV_FCOV_INSTANTIATE_CG(pmp_top_cg, en_pmp_fcov)
endinterface
