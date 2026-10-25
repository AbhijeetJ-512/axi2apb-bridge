//==============================================================================
// axi_monitor — Passively reconstructs AXI transactions from bus activity
//------------------------------------------------------------------------------
// Two parallel collectors (write, read), each consuming complete bursts and
// publishing a fully-populated axi_seq_item (data + response) on the analysis
// port. The DUT serialises AW->W and AR->R, so the simple sequential collector
// is correct here; a generic AXI4 monitor would track AW/W independently.
//
// Sanity checks: WLAST asserted on the last beat only; RLAST same. These fire
// `uvm_error so a buggy master is caught immediately, even before SVA.
//==============================================================================

class axi_monitor extends uvm_monitor;

    `uvm_component_utils(axi_monitor)

    virtual axi_if                          vif;
    axi_agent_config                        cfg;

    uvm_analysis_port #(axi_seq_item)       ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_agent_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("AXI_MON/CFG", "axi_agent_config not in config_db")
        vif = cfg.vif;
    endfunction

    task run_phase(uvm_phase phase);
        wait (vif.rst_n === 1'b1);
        fork
            collect_writes();
            collect_reads();
        join
    endtask

    //--------------------------------------------------------------------------
    // Wait for a (valid && ready) handshake on a generic channel
    //--------------------------------------------------------------------------

    //==========================================================================
    // Write-burst collection: AW handshake -> N W beats -> 1 B handshake
    //==========================================================================
    task collect_writes();
        axi_seq_item txn;
        forever begin
            // Wait for AW handshake
            do @(vif.monitor_cb);
            while (!(vif.monitor_cb.awvalid === 1'b1 && vif.monitor_cb.awready === 1'b1));

            txn       = axi_seq_item::type_id::create("axi_w_txn");
            txn.op    = AXI_WRITE;
            txn.id    = vif.monitor_cb.awid;
            txn.addr  = vif.monitor_cb.awaddr;
            txn.len   = vif.monitor_cb.awlen;
            txn.size  = axi_size_e'(vif.monitor_cb.awsize);
            txn.burst = axi_burst_e'(vif.monitor_cb.awburst);
            txn.data  = new[txn.len + 1];
            txn.strb  = new[txn.len + 1];
            txn.resp  = new[1];

            // Collect (len+1) W beats
            for (int i = 0; i <= int'(txn.len); i++) begin
                do @(vif.monitor_cb);
                while (!(vif.monitor_cb.wvalid === 1'b1 && vif.monitor_cb.wready === 1'b1));
                txn.data[i] = vif.monitor_cb.wdata;
                txn.strb[i] = vif.monitor_cb.wstrb;

                // WLAST sanity check
                if ((i == int'(txn.len)) && vif.monitor_cb.wlast !== 1'b1)
                    `uvm_error("AXI_MON/WLAST", $sformatf(
                                "WLAST not asserted on final beat (id=%0d, beat=%0d, len=%0d)",
                                txn.id, i, txn.len))
                if ((i != int'(txn.len)) && vif.monitor_cb.wlast === 1'b1)
                    `uvm_error("AXI_MON/WLAST", $sformatf(
                                "WLAST asserted on non-final beat (id=%0d, beat=%0d, len=%0d)",
                                txn.id, i, txn.len))
            end

            // Wait for B handshake (single response per burst)
            do @(vif.monitor_cb);
            while (!(vif.monitor_cb.bvalid === 1'b1 && vif.monitor_cb.bready === 1'b1));
            txn.resp[0] = axi_resp_e'(vif.monitor_cb.bresp);

            // BID echo check
            if (vif.monitor_cb.bid !== txn.id)
                `uvm_error("AXI_MON/BID", $sformatf(
                            "BID mismatch: expected=%0d observed=%0d",
                            txn.id, vif.monitor_cb.bid))

            `uvm_info("AXI_MON", $sformatf("Observed %s", txn.convert2string()), UVM_HIGH)
            ap.write(txn);
        end
    endtask

    //==========================================================================
    // Read-burst collection: AR handshake -> N R beats
    //==========================================================================
    task collect_reads();
        axi_seq_item txn;
        forever begin
            // Wait for AR handshake
            do @(vif.monitor_cb);
            while (!(vif.monitor_cb.arvalid === 1'b1 && vif.monitor_cb.arready === 1'b1));

            txn       = axi_seq_item::type_id::create("axi_r_txn");
            txn.op    = AXI_READ;
            txn.id    = vif.monitor_cb.arid;
            txn.addr  = vif.monitor_cb.araddr;
            txn.len   = vif.monitor_cb.arlen;
            txn.size  = axi_size_e'(vif.monitor_cb.arsize);
            txn.burst = axi_burst_e'(vif.monitor_cb.arburst);
            txn.data  = new[txn.len + 1];
            txn.strb  = new[txn.len + 1];
            txn.resp  = new[txn.len + 1];

            for (int i = 0; i <= int'(txn.len); i++) begin
                do @(vif.monitor_cb);
                while (!(vif.monitor_cb.rvalid === 1'b1 && vif.monitor_cb.rready === 1'b1));
                txn.data[i] = vif.monitor_cb.rdata;
                txn.resp[i] = axi_resp_e'(vif.monitor_cb.rresp);

                // RLAST + RID checks
                if ((i == int'(txn.len)) && vif.monitor_cb.rlast !== 1'b1)
                    `uvm_error("AXI_MON/RLAST", $sformatf(
                                "RLAST not asserted on final beat (id=%0d, beat=%0d, len=%0d)",
                                txn.id, i, txn.len))
                if ((i != int'(txn.len)) && vif.monitor_cb.rlast === 1'b1)
                    `uvm_error("AXI_MON/RLAST", $sformatf(
                                "RLAST asserted on non-final beat (id=%0d, beat=%0d, len=%0d)",
                                txn.id, i, txn.len))
                if (vif.monitor_cb.rid !== txn.id)
                    `uvm_error("AXI_MON/RID", $sformatf(
                                "RID mismatch: expected=%0d observed=%0d",
                                txn.id, vif.monitor_cb.rid))
            end

            `uvm_info("AXI_MON", $sformatf("Observed %s", txn.convert2string()), UVM_HIGH)
            ap.write(txn);
        end
    endtask

endclass : axi_monitor
