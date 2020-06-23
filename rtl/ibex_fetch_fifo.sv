// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Fetch Fifo for 32 bit memory interface
 *
 * input port: send address and data to the FIFO
 * clear_i clears the FIFO for the following cycle, including any new request
 */

`include "prim_assert.sv"

module ibex_fetch_fifo #(
  parameter int unsigned NUM_REQS = 2
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // control signals
    input  logic        clear_i,          // clears the contents of the FIFO
    // On a branch mis-predict need to ignore clear_on_next_push and just give out contents of FIFO,
    // however ignore any incoming data. Also need to consider how we deal with changing meaning of
    // in_branch_discard, when we've predicted the branch we want to store things with this set,
    // when we mispredict we want to discard them (as they'll be for the branch we're not taking at
    // this point). Only need things to work smoothly when we're seeing single cycle iside return,
    // as if you don't have that performance is awful anyway! Though with icache perhaps we will see
    // a bit of that and don't want to be too awful at it...
    input  logic        branch_mispredict_i,
    // input port
    input  logic        in_valid_i,
    input  logic        in_branch_discard_i,
    output logic        in_ready_o,
    input  logic [31:0] in_addr_i,
    input  logic [31:0] in_rdata_i,
    input  logic        in_err_i,

    // output port
    output logic        out_valid_o,
    input  logic        out_ready_i,
    output logic [31:0] out_addr_o,
    output logic [31:0] out_addr_next_o,
    output logic [31:0] out_rdata_o,
    output logic        out_err_o,
    output logic        out_err_plus2_o,
    output logic        out_buffered_o,

    output logic        clear_pending_o,
    output logic [31:1] clear_addr_o
);

  // Need to deal with mispredict case when we've already had instruction data back from the
  // predicted branch fetch so we've cleared out the previous FIFO data. Here a mispredict will
  // clear the FIFO and prefetch buffer needs to start fetching from the first instruction after the
  // not-taken branch again as we'll have thrown away the data that we would otherwise have had.
  // This occurs when a branch condition is dependent on load data from the instruction before, so
  // branch stalls in ID/EX before the mis-predict is resolved.
  // Can we avoid this refetching? Could detect the case and stop the branch from being predicted
  // until the load is ready to retire? Though that may cause stalls we don't need for the correctly
  // predicted case?

  // To gain extra performance DEPTH should be increased, this is due to some inefficiencies in the
  // way the fetch fifo operates see issue #574 for more details
  localparam int unsigned DEPTH = NUM_REQS+6;

  logic                     in_valid_masked;

  // index 0 is used for output
  logic [DEPTH-1:0] [31:0]  rdata_d,   rdata_q;
  logic [DEPTH-1:0]         err_d,     err_q;
  logic [DEPTH-1:0]         valid_d,   valid_q, valid, valid_masked;
  logic [DEPTH-1:0]         lowest_free_entry;
  logic [DEPTH-1:0]         valid_pushed, valid_popped;
  logic [DEPTH-1:0]         entry_en;

  logic                     pop_fifo;
  logic             [31:0]  rdata, rdata_unaligned;
  logic                     err,   err_unaligned, err_plus2;
  logic                     valid_out, valid_out_unaligned;

  logic                     aligned_is_compressed, unaligned_is_compressed;

  logic                     addr_incr_two;
  logic [31:1]              instr_addr_next;
  logic [31:1]              instr_addr, instr_addr_d, instr_addr_q;
  logic [31:1]              instr_clear_addr_d, instr_clear_addr_q;
  logic                     instr_addr_en;
  logic                     unused_addr_in;

  //logic                     next_instr_buf_valid_q;
  //logic [31:0]              next_instr_buf_q;

  //logic                     next_instr_buf_valid_d;
  //logic [31:0]              next_instr_buf_d;

  logic                     clear_on_next_push_d;
  logic                     clear_on_next_push_q;
  logic                     clear_on_next_push;
  logic                     clear_fifo;
  logic                     clear_on_mispredict;

  /////////////////
  // Output port //
  /////////////////

  assign rdata     = valid[0] ? rdata_q[0] : in_rdata_i;
  assign err       = valid[0] ? err_q[0]   : in_err_i;
  assign valid_out = valid_masked[0] | (in_valid_i & ~(in_branch_discard_i | branch_mispredict_i));

  // The FIFO contains word aligned memory fetches, but the instructions contained in each entry
  // might be half-word aligned (due to compressed instructions)
  // e.g.
  //              | 31               16 | 15               0 |
  // FIFO entry 0 | Instr 1 [15:0]      | Instr 0 [15:0]     |
  // FIFO entry 1 | Instr 2 [15:0]      | Instr 1 [31:16]    |
  //
  // The FIFO also has a direct bypass path, so a complete instruction might be made up of data
  // from the FIFO and new incoming data.
  //

  // Construct the output data for an unaligned instruction
  assign rdata_unaligned = valid[1] ? {rdata_q[1][15:0], rdata[31:16]} :
                                        {in_rdata_i[15:0], rdata[31:16]};

  // If entry[1] is valid, an error can come from entry[0] or entry[1], unless the
  // instruction in entry[0] is compressed (entry[1] is a new instruction)
  // If entry[1] is not valid, and entry[0] is, an error can come from entry[0] or the incoming
  // data, unless the instruction in entry[0] is compressed
  // If entry[0] is not valid, the error must come from the incoming data
  assign err_unaligned   = valid[1] ? ((err_q[1] & ~unaligned_is_compressed) | err_q[0]) :
                                        ((valid[0] & err_q[0]) |
                                         (in_err_i & (~valid[0] | ~unaligned_is_compressed)));

  // Record when an error is caused by the second half of an unaligned 32bit instruction.
  // Only needs to be correct when unaligned and if err_unaligned is set
  assign err_plus2       = valid[1] ? (err_q[1] & ~err_q[0]) :
                                        (in_err_i & valid[0] & ~err_q[0]);

  // An uncompressed unaligned instruction is only valid if both parts are available
  assign valid_out_unaligned = valid_masked[1] ? 1'b1 :
                                                 (valid_masked[0] & (in_valid_i & ~(in_branch_discard_i | branch_mispredict_i)));

  assign unaligned_is_compressed    = rdata[17:16] != 2'b11;
  assign aligned_is_compressed      = rdata[ 1: 0] != 2'b11;

  assign clear_on_next_push_d = clear_i |
    (clear_on_next_push & ~(in_valid_i & in_ready_o));

  assign clear_on_next_push = clear_on_next_push_q & ~branch_mispredict_i;

  assign clear_pending_o = clear_on_next_push_q;

  //always_comb begin
  //  if (out_ready_i) begin
  //    next_instr_buf_d = valid[1] ? rdata_q[1] : in_rdata_i;
  //    next_instr_buf_valid_d = (valid[1] | (valid[0] & in_valid_i)) & ~clear_i;

  //    if (out_addr_o[1]) begin
  //      if(~unaligned_is_compressed) begin
  //        next_instr_buf_d = valid[2] ? {rdata_q[2][15:0], rdata_q[1][31:16]} :
  //                           valid[1] ? {in_rdata_i[15:0], rdata_q[1][31:16]} :
  //                                        {in_rdata_i[15:0], in_rdata_i[31:16]};

  //        next_instr_buf_valid_d =
  //          (valid[2]                                               |
  //           ((in_valid_i | rdata_q[1][17:16] != 2'b11) & valid[1]) |
  //           (in_valid_i & valid[0] & in_rdata_i[17:16] != 2'b11)
  //          )                                                          &
  //           ~clear_i;
  //      end
  //    end else begin
  //      if(aligned_is_compressed) begin
  //        next_instr_buf_d = valid[1] ? {rdata_q[1][15:0], rdata_q[0][31:16]} :
  //                                        {in_rdata_i[15:0], rdata_q[0][31:16]};

  //        next_instr_buf_valid_d = (valid[1] |
  //                                  ((in_valid_i | rdata_q[0][17:16] != 2'b11) & valid[0])
  //                                 )                                                        &
  //                                 ~clear_i;
  //      end
  //    end
  //  end else begin
  //    if (clear_i) begin
  //      next_instr_buf_valid_d = 1'b0;
  //    end
  //  end
  //end

  //always_ff @(negedge rst_ni or posedge clk_i) begin
  //  if (~rst_ni) begin
  //    next_instr_buf_q <= '0;
  //  end else begin
  //    next_instr_buf_q       <= next_instr_buf_d;
  //    next_instr_buf_valid_q <= next_instr_buf_valid_d;
  //  end
  //end

  //always_ff @(posedge clk_i) begin
  //  if(next_instr_buf_valid) begin
  //    if(~out_valid_o) begin
  //      $display("%t ERROR: Ins buf valid mismatch!", $time);
  //    end else begin
  //      if((out_addr_o[1] & unaligned_is_compressed) |
  //         (out_addr_o[0] & aligned_is_compressed)) begin
  //        if(out_rdata_o[15:0] != next_instr_buf_q[15:0]) begin
  //          $display("%t ERROR: Ins buf data mismatch!", $time);
  //        end
  //      end else if(out_rdata_o != next_instr_buf_q) begin
  //        $display("%t ERROR: Ins buf data mismatch!", $time);
  //      end
  //    end
  //  end
  //end

  ////////////////////////////////////////
  // Instruction aligner (if unaligned) //
  ////////////////////////////////////////

  always_comb begin
    out_buffered_o = 1'b0;
    if (out_addr_o[1]) begin
      // unaligned case
      out_rdata_o     = rdata_unaligned;
      out_err_o       = err_unaligned;
      out_err_plus2_o = err_plus2;
      out_buffered_o  = valid[1];

      if (unaligned_is_compressed) begin
        out_valid_o = valid_out;
      end else begin
        out_valid_o = valid_out_unaligned;
      end
    end else begin
      // aligned case
      out_rdata_o     = rdata;
      out_err_o       = err;
      out_err_plus2_o = 1'b0;
      out_valid_o     = valid_out;
      out_buffered_o  = valid[0];
    end
  end

  /////////////////////////
  // Instruction address //
  /////////////////////////

  // Update the address on branches and every time an instruction is driven
  assign instr_addr_en = clear_fifo | (out_ready_i & out_valid_o);

  // Increment the address by two every time a compressed instruction is popped
  assign addr_incr_two = instr_addr[1] ? unaligned_is_compressed :
                                           aligned_is_compressed;

  assign instr_addr_next = (instr_addr[31:1] +
                            // Increment address by 4 or 2
                            {29'd0,~addr_incr_two,addr_incr_two});

  assign instr_addr_d = clear_on_mispredict         ? instr_clear_addr_q :
                        (out_ready_i & out_valid_o) ? instr_addr_next :
                                                      instr_addr;

  // For saving previous address that's getting cleared out we're assuming instr_addr_q hasn't been
  // incremented before mispredict appears, this constraint should hold but worth some
  // assertions/comments to explain.
  assign instr_addr = clear_on_next_push ? instr_clear_addr_q :
                                           instr_addr_q;

  always_ff @(posedge clk_i) begin
    if (instr_addr_en) begin
      instr_addr_q <= instr_addr_d;
    end
  end

  logic instr_clear_addr_en;

  assign instr_clear_addr_en = clear_i | clear_fifo;

  assign instr_clear_addr_d = clear_i ? in_addr_i[31:1] :
                                        instr_addr_q;

  always_ff @(posedge clk_i) begin
    if (instr_clear_addr_en) begin
      instr_clear_addr_q <= instr_clear_addr_d;
    end
  end

  // Output both PC of current instruction and instruction following. PC of instruction following is
  // required for the branch predictor. It's used to fetch the instruction following a branch that
  // was not-taken but (mis)predicted taken.
  assign out_addr_next_o = {instr_addr_next, 1'b0};
  assign out_addr_o      = clear_on_next_push ? {instr_clear_addr_q, 1'b0} :
                                                {instr_addr_q,       1'b0};

  // The LSB of the address is unused, since all addresses are halfword aligned
  assign unused_addr_in = in_addr_i[0];

  ////////////////
  // input port //
  ////////////////

  // Accept data as long as our FIFO has space to accept the maximum number of outstanding
  // requests. Note that the prefetch buffer does not count how many requests are actually
  // outstanding, so space must be reserved for the maximum number.
  assign in_ready_o = (~valid[DEPTH-NUM_REQS] | (~in_branch_discard_i & clear_on_next_push));

  /////////////////////
  // FIFO management //
  /////////////////////

  // We have out_ready_i when branching, which causes the next instruction that would be
  // executed were that branch not taken to get popped off the FIFO. Suppress ready in this case? Or
  // don't actuaaly care as in branch prediction case that's the branch resolving so know what
  // should be kept.
  // Since an entry can contain unaligned instructions, popping an entry can leave the entry valid
  assign pop_fifo = out_ready_i & out_valid_o & (~aligned_is_compressed | out_addr_o[1]);

  assign clear_on_mispredict = branch_mispredict_i & ~clear_on_next_push_q;

  // Only actually clear the fifo when the first push is seen after clear
  assign clear_fifo = (clear_on_next_push & in_valid_i & ~in_branch_discard_i) | clear_on_mispredict;

  assign clear_addr_o = instr_clear_addr_q;

  assign in_valid_masked = in_valid_i & ~branch_mispredict_i;

  for (genvar i = 0; i < (DEPTH - 1); i++) begin : g_fifo_next
    assign valid[i] = valid_q[i] & ~clear_fifo;
    assign valid_masked[i] = valid[i] & ~(clear_on_next_push_q ^ branch_mispredict_i);

    // Calculate lowest free entry (write pointer), entry 0 is always lowest_free_entry when a clear
    // is pending.
    if (i == 0) begin : g_ent0
      assign lowest_free_entry[i] = ~valid[i];
    end else begin : g_ent_others
      assign lowest_free_entry[i] = ~valid[i] & valid[i-1];
    end

    // An entry is set when an incoming request chooses the lowest available entry
    assign valid_pushed[i] = (in_valid_masked & lowest_free_entry[i]) |
                             valid[i];
    // Popping the FIFO shifts all entries down
    assign valid_popped[i] = pop_fifo ? valid_pushed[i+1] : valid_pushed[i];
    // All entries are wiped out on a clear
    assign valid_d[i] = valid_popped[i];

    // data flops are enabled if there is new data to shift into it, or
    assign entry_en[i] = (valid_pushed[i+1] & pop_fifo) |
                         // a new request is incoming and this is the lowest free entry
                         (in_valid_masked & lowest_free_entry[i] & ~pop_fifo);

    // take the next entry or the incoming data
    assign rdata_d[i]  = valid[i+1] ? rdata_q[i+1] : in_rdata_i;
    assign err_d  [i]  = valid[i+1] ? err_q  [i+1] : in_err_i;
  end
  // The top entry is similar but with simpler muxing
  assign valid[DEPTH-1] = valid_q[DEPTH-1] & ~clear_fifo;
  assign valid_masked[DEPTH-1] = valid[DEPTH-1] & ~clear_on_next_push;
  assign lowest_free_entry[DEPTH-1] = ~valid[DEPTH-1] & valid[DEPTH-2];
  assign valid_pushed     [DEPTH-1] = valid[DEPTH-1] | (in_valid_masked & lowest_free_entry[DEPTH-1]);
  assign valid_popped     [DEPTH-1] = pop_fifo ? 1'b0 : valid_pushed[DEPTH-1];
  assign valid_d [DEPTH-1]          = valid_popped[DEPTH-1];
  assign entry_en[DEPTH-1]          = in_valid_masked & lowest_free_entry[DEPTH-1];
  assign rdata_d [DEPTH-1]          = in_rdata_i;
  assign err_d   [DEPTH-1]          = in_err_i;

  ////////////////////
  // FIFO registers //
  ////////////////////

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_q              <= '0;
      clear_on_next_push_q <= '0;
    end else begin
      valid_q              <= valid_d;
      clear_on_next_push_q <= clear_on_next_push_d;
    end
  end

  for (genvar i = 0; i < DEPTH; i++) begin : g_fifo_regs
    always_ff @(posedge clk_i) begin
      if (entry_en[i]) begin
        rdata_q[i]   <= rdata_d[i];
        err_q[i]     <= err_d[i];
      end
    end
  end

  ////////////////
  // Assertions //
  ////////////////

  // Must not push and pop simultaneously when FIFO full.
  `ASSERT(IbexFetchFifoPushPopFull,
      (in_valid_i && pop_fifo) |-> (!valid[DEPTH-1]))

  // Must not push to FIFO when full.
  `ASSERT(IbexFetchFifoPushFull,
      (in_valid_i) |-> (!valid[DEPTH-1]))

endmodule
