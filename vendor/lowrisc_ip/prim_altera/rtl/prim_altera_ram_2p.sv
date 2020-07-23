
// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Synchronous dual-port SRAM register model
//   This module is for simulation and small size SRAM.
//   Implementing ECC should be done inside wrapper not this model.

module prim_altera_ram_2p #(
  parameter  int Width           = 32, // bit
  parameter  int Depth           = 128,
  parameter  int DataBitsPerMask = 1, // Number of data bits per bit of write mask
  parameter      MemInitFile     = "", // VMEM file to initialize the memory with

  parameter int Aw              = $clog2(Depth)  // derived parameter
) (
  input clk_a_i,
  input clk_b_i,

  input                    a_req_i,
  input                    a_write_i,
  input        [Aw-1:0]    a_addr_i,
  input        [Width-1:0] a_wdata_i,
  input  logic [Width-1:0] a_wmask_i,
  output logic [Width-1:0] a_rdata_o,


  input                    b_req_i,
  input                    b_write_i,
  input        [Aw-1:0]    b_addr_i,
  input        [Width-1:0] b_wdata_i,
  input  logic [Width-1:0] b_wmask_i,
  output logic [Width-1:0] b_rdata_o
);
  // Width of internal write mask. Note *_wmask_i input into the module is always assumed
  // to be the full bit mask.
  localparam int MaskWidth = Width / DataBitsPerMask;

  logic [MaskWidth-1:0] a_wmask;
  logic [MaskWidth-1:0] b_wmask;

  logic wren_a;
  logic wren_b;

  generate
    genvar k;
    for (k = 0; k < MaskWidth; k++) begin : gen_wmask
      assign a_wmask[k] = &a_wmask_i[k*DataBitsPerMask +: DataBitsPerMask];
      assign b_wmask[k] = &b_wmask_i[k*DataBitsPerMask +: DataBitsPerMask];
    end
  endgenerate

  assign wren_a = a_req_i & a_write_i;
  assign wren_b = b_req_i & b_write_i;

	altsyncram	altsyncram_component (
				.address_a (a_addr_i),
				.address_b (b_addr_i),
				.byteena_a (a_wmask),
				.byteena_b (b_wmask),
				.clock0 (clk_a_i),
				.clock1 (clk_b_i),
				.data_a (a_wdata_i),
				.data_b (b_wdata_i),
				.wren_a (wren_a),
				.wren_b (wren_b),
				.q_a (a_rdata_o),
				.q_b (b_rdata_o),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.eccstatus (),
				.rden_a (1'b1),
				.rden_b (1'b1));
	defparam
		altsyncram_component.address_reg_b = "CLOCK1",
		altsyncram_component.byteena_reg_b = "CLOCK1",
		altsyncram_component.byte_size = DataBitsPerMask,
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.indata_reg_b = "CLOCK1",
		altsyncram_component.init_file = MemInitFile,
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = Depth,
		altsyncram_component.numwords_b = Depth,
		altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_a = "UNREGISTERED",
		altsyncram_component.outdata_reg_b = "UNREGISTERED",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.widthad_a = Aw,
		altsyncram_component.widthad_b = Aw,
		altsyncram_component.width_a = Width,
		altsyncram_component.width_b = Width,
		altsyncram_component.width_byteena_a = MaskWidth,
		altsyncram_component.width_byteena_b = MaskWidth,
		altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK1";

endmodule
