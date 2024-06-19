// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

//------------------------------------------------------------------------------
// CLASS: ibex_mem_intf_response_driver
//------------------------------------------------------------------------------

class ibex_mem_intf_response_driver extends uvm_driver #(ibex_mem_intf_seq_item);

  ibex_mem_intf_response_agent_cfg cfg;

  `uvm_component_utils(ibex_mem_intf_response_driver)
  `uvm_component_new

  mailbox #(ibex_mem_intf_seq_item) rdata_queue;

  rand int unsigned spurious_response_delay_cycles;

  constraint spurious_response_delay_cycles_c {
    spurious_response_delay_cycles inside {[cfg.spurious_response_delay_min :
                                            cfg.spurious_response_delay_max]};
  }

  event monitor_tick = null;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rdata_queue = new();
  endfunction: build_phase

  virtual task run_phase(uvm_phase phase);
    reset_signals();
    wait (cfg.vif.response_driver_cb.reset === 1'b0);
    forever begin
      fork begin : isolation_fork
        fork : drive_stimulus
          send_grant();
          get_and_drive();
          wait (cfg.vif.response_driver_cb.reset === 1'b1);
        join_any
        // Will only be reached after mid-test reset
        disable fork;
      end join
      handle_reset();
    end
  endtask : run_phase

  virtual protected task handle_reset();
    ibex_mem_intf_seq_item req;
    // Clear mailbox
    while (rdata_queue.try_get(req));
    // Clear seq_item_port
    do begin
      seq_item_port.try_next_item(req);
      if (req != null) begin
        seq_item_port.item_done();
      end
    end while (req != null);
    reset_signals();
    wait (cfg.vif.response_driver_cb.reset === 1'b0);
  endtask

  virtual protected task reset_signals();
    cfg.vif.response_driver_cb.rvalid  <= 1'b0;
    cfg.vif.response_driver_cb.grant   <= 1'b0;
    cfg.vif.response_driver_cb.rdata   <= 'b0;
    cfg.vif.response_driver_cb.rintg   <= 'b0;
    cfg.vif.response_driver_cb.error   <= 1'b0;
  endtask : reset_signals

  virtual protected task get_and_drive();
    wait (cfg.vif.response_driver_cb.reset === 1'b0);

    if (cfg.enable_spurious_response) begin
      `DV_CHECK_MEMBER_RANDOMIZE_FATAL(spurious_response_delay_cycles)
    end

    fork
      begin
        forever begin
          ibex_mem_intf_seq_item req, req_c;
          @(cfg.vif.response_driver_cb);
          seq_item_port.get_next_item(req);
          $cast(req_c, req.clone());
          if(~cfg.vif.response_driver_cb.reset) begin
            rdata_queue.put(req_c);
          end
          seq_item_port.item_done();
        end
      end
      begin
        send_read_data();
      end
    join
  endtask : get_and_drive

  virtual protected task send_grant();
    int gnt_delay;
    forever begin
      while(cfg.vif.response_driver_cb.request !== 1'b1) begin
        cfg.vif.wait_neg_clks(1);
      end
      if(cfg.zero_delays) begin
        gnt_delay = 0;
      end else begin
        if (!std::randomize(gnt_delay) with {
          gnt_delay dist {
            cfg.gnt_delay_min                           :/ 10,
            [cfg.gnt_delay_min+1 : cfg.gnt_delay_max-1] :/ cfg.valid_pick_medium_speed_weight,
            cfg.gnt_delay_max                           :/ cfg.valid_pick_slow_speed_weight
          };
        }) begin
          `uvm_fatal(`gfn, $sformatf("Cannot randomize grant"))
        end
      end
      cfg.vif.wait_neg_clks(gnt_delay);
      if(~cfg.vif.response_driver_cb.reset) begin
        cfg.vif.response_driver_cb.grant <= 1'b1;
        cfg.vif.wait_neg_clks(1);
        cfg.vif.response_driver_cb.grant <= 1'b0;
      end
    end
  endtask : send_grant

  virtual protected task send_read_data();
    ibex_mem_intf_seq_item tr;
    forever begin
      @(cfg.vif.response_driver_cb);
      cfg.vif.response_driver_cb.rvalid            <= 1'b0;
      cfg.vif.response_driver_cb.spurious_response <= 1'b0;
      cfg.vif.response_driver_cb.rdata             <= 'x;
      cfg.vif.response_driver_cb.rintg             <= 'x;
      cfg.vif.response_driver_cb.error             <= 'x;

      if (cfg.enable_spurious_response) begin
        while (1) begin
          @monitor_tick;

          cfg.vif.response_driver_cb.rvalid            <= 1'b0;
          cfg.vif.response_driver_cb.spurious_response <= 1'b0;
          cfg.vif.response_driver_cb.rdata             <= 'x;
          cfg.vif.response_driver_cb.rintg             <= 'x;
          cfg.vif.response_driver_cb.error             <= 'x;

          if (rdata_queue.try_get(tr) != 0) begin
            `uvm_info(`gfn, "Seen response in spin loop", UVM_LOW)
            break;
          end

          if (spurious_response_delay_cycles == 0) begin
            bit error;
            bit [DATA_WIDTH-1:0] rand_data;
            bit [INTG_WIDTH-1:0] intg;

            `DV_CHECK_STD_RANDOMIZE_FATAL(error)
            `DV_CHECK_STD_RANDOMIZE_FATAL(rand_data)

            `uvm_info(`gfn, "Injecting spurious memory response", UVM_HIGH)

            // Provide correct integrity with spurious response to avoid triggering an alert
            {intg, rand_data} = prim_secded_pkg::prim_secded_inv_39_32_enc(rand_data);

            cfg.vif.response_driver_cb.rvalid            <= 1'b1;
            cfg.vif.response_driver_cb.spurious_response <= 1'b1;
            cfg.vif.response_driver_cb.rdata             <= rand_data;
            cfg.vif.response_driver_cb.rintg             <= intg;
            cfg.vif.response_driver_cb.error             <= error;

            `DV_CHECK_MEMBER_RANDOMIZE_FATAL(spurious_response_delay_cycles)
          end else begin
            spurious_response_delay_cycles = spurious_response_delay_cycles - 1;
          end
        end
      end else begin
        rdata_queue.get(tr);
      end

      `uvm_info(`gfn, $sformatf("Got response for addr %x", tr.addr), UVM_HIGH)

      if(cfg.vif.response_driver_cb.reset) continue;

      for (int i = 0;i < tr.rvalid_delay; ++i) begin
        @(cfg.vif.response_driver_cb);
      end

      if(~cfg.vif.response_driver_cb.reset) begin
        `uvm_info(`gfn, $sformatf("Driving response for addr %x", tr.addr), UVM_HIGH)
        cfg.vif.response_driver_cb.rvalid <= 1'b1;
        cfg.vif.response_driver_cb.error  <= tr.error;
        if (tr.read_write == READ) begin
          cfg.vif.response_driver_cb.rdata <= tr.data;
          cfg.vif.response_driver_cb.rintg <= tr.intg;
        end else begin
          // rdata and intg fields aren't relevant to write responses
          if (cfg.fixed_data_write_response) begin
            // when fixed_data_write_response is set, sequence item is responsible for producing
            // fixed values so just copy them across here.
            cfg.vif.response_driver_cb.rdata <= tr.data;
            cfg.vif.response_driver_cb.rintg <= tr.intg;
          end else begin
            // when fixed_data_write_response is not set, drive the irrelevant fields to x.
            cfg.vif.response_driver_cb.rdata <= 'x;
            cfg.vif.response_driver_cb.rintg <= 'x;
          end
        end
      end
    end
  endtask : send_read_data

endclass : ibex_mem_intf_response_driver
