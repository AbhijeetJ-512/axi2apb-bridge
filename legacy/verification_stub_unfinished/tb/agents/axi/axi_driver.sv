//==============================================================================
// axi_driver — Drives the AXI4 master side of the bus
//------------------------------------------------------------------------------
// One AXI burst transaction is driven as concurrent processes on the AW/W/B
// (write) or AR/R (read) channels via fork-join. Per-channel timing knobs in
// the seq_item let tests inject backpressure / delay independently on each
// handshake.
//
// Reset model: initialise outputs at run_phase entry, wait for rst_n=1, then
// service items forever. Mid-test reset is out of scope for this project.
//==============================================================================

class axi_driver extends uvm_driver #(axi_seq_item);

    `uvm_component_utils(axi_driver)

    virtual axi_if      vif;
    axi_agent_config    cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // Build: pull config, cache vif handle
    //--------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_agent_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("AXI_DRV/CFG", "axi_agent_config not in config_db")
        vif = cfg.vif;
    endfunction

    //--------------------------------------------------------------------------
    // run_phase
    //--------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        reset_signals();
        wait (vif.rst_n === 1'b1);
        @(vif.master_cb);

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info("AXI_DRV", $sformatf("Driving %s", req.convert2string()), UVM_MEDIUM)
            drive_transaction(req);
            seq_item_port.item_done();
        end
    endtask

    //--------------------------------------------------------------------------
    // Reset all master-driven signals to 0 via the clocking block
    //--------------------------------------------------------------------------
    task reset_signals();
        vif.master_cb.awvalid <= 1'b0;
        vif.master_cb.awid    <= '0;
        vif.master_cb.awaddr  <= '0;
        vif.master_cb.awlen   <= '0;
        vif.master_cb.awsize  <= '0;
        vif.master_cb.awburst <= '0;

        vif.master_cb.wvalid  <= 1'b0;
        vif.master_cb.wdata   <= '0;
        vif.master_cb.wstrb   <= '0;
        vif.master_cb.wlast   <= 1'b0;

        vif.master_cb.bready  <= 1'b0;

        vif.master_cb.arvalid <= 1'b0;
        vif.master_cb.arid    <= '0;
        vif.master_cb.araddr  <= '0;
        vif.master_cb.arlen   <= '0;
        vif.master_cb.arsize  <= '0;
        vif.master_cb.arburst <= '0;

        vif.master_cb.rready  <= 1'b0;
    endtask

    //--------------------------------------------------------------------------
    // Top-level dispatch
    //--------------------------------------------------------------------------
    task drive_transaction(axi_seq_item txn);
        if (txn.op == AXI_WRITE)
            drive_write(txn);
        else
            drive_read(txn);
    endtask

    //==========================================================================
    // WRITE PATH — AW, W, B in parallel
    //==========================================================================
    task drive_write(axi_seq_item txn);
        fork
            drive_aw(txn);
            drive_w (txn);
            collect_b(txn);
        join
    endtask

    task drive_aw(axi_seq_item txn);
        repeat (txn.aw_valid_delay) @(vif.master_cb);
        vif.master_cb.awid    <= txn.id;
        vif.master_cb.awaddr  <= txn.addr;
        vif.master_cb.awlen   <= txn.len;
        vif.master_cb.awsize  <= txn.size;
        vif.master_cb.awburst <= txn.burst;
        vif.master_cb.awvalid <= 1'b1;
        do @(vif.master_cb);
        while (vif.master_cb.awready !== 1'b1);
        vif.master_cb.awvalid <= 1'b0;
    endtask

    task drive_w(axi_seq_item txn);
        foreach (txn.data[i]) begin
            repeat (txn.w_valid_delay[i]) @(vif.master_cb);
            vif.master_cb.wdata  <= txn.data[i];
            vif.master_cb.wstrb  <= txn.strb[i];
            vif.master_cb.wlast  <= (i == txn.data.size() - 1);
            vif.master_cb.wvalid <= 1'b1;
            do @(vif.master_cb);
            while (vif.master_cb.wready !== 1'b1);
            vif.master_cb.wvalid <= 1'b0;
            vif.master_cb.wlast  <= 1'b0;
        end
    endtask

    task collect_b(axi_seq_item txn);
        repeat (txn.b_ready_delay) @(vif.master_cb);
        vif.master_cb.bready <= 1'b1;
        do @(vif.master_cb);
        while (vif.master_cb.bvalid !== 1'b1);
        @(vif.master_cb);
        vif.master_cb.bready <= 1'b0;
    endtask

    //==========================================================================
    // READ PATH — AR, R in parallel
    //==========================================================================
    task drive_read(axi_seq_item txn);
        fork
            drive_ar(txn);
            collect_r(txn);
        join
    endtask

    task drive_ar(axi_seq_item txn);
        repeat (txn.ar_valid_delay) @(vif.master_cb);
        vif.master_cb.arid    <= txn.id;
        vif.master_cb.araddr  <= txn.addr;
        vif.master_cb.arlen   <= txn.len;
        vif.master_cb.arsize  <= txn.size;
        vif.master_cb.arburst <= txn.burst;
        vif.master_cb.arvalid <= 1'b1;
        do @(vif.master_cb);
        while (vif.master_cb.arready !== 1'b1);
        vif.master_cb.arvalid <= 1'b0;
    endtask

    task collect_r(axi_seq_item txn);
        for (int i = 0; i < int'(txn.len) + 1; i++) begin
            repeat (txn.r_ready_delay[i]) @(vif.master_cb);
            vif.master_cb.rready <= 1'b1;
            do @(vif.master_cb);
            while (vif.master_cb.rvalid !== 1'b1);
            vif.master_cb.rready <= 1'b0;
        end
    endtask

endclass : axi_driver
