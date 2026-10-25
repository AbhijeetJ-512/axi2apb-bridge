//==============================================================================
// axi_agent — Composes driver, sequencer, and monitor for the AXI master side
//------------------------------------------------------------------------------
// Standard active/passive UVM agent. Config is fetched once and forwarded down
// to the driver and monitor via the config_db wildcard pattern.
//==============================================================================

class axi_agent extends uvm_agent;

    `uvm_component_utils(axi_agent)

    axi_driver       drv;
    axi_monitor      mon;
    axi_sequencer    sqr;
    axi_agent_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(axi_agent_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("AXI_AGT/CFG", "axi_agent_config not in config_db")

        // Forward cfg down to all children via wildcard
        uvm_config_db#(axi_agent_config)::set(this, "*", "cfg", cfg);

        // Monitor always built (active+passive)
        mon = axi_monitor::type_id::create("mon", this);

        // Driver + sequencer only when active
        if (cfg.is_active == UVM_ACTIVE) begin
            drv = axi_driver   ::type_id::create("drv", this);
            sqr = axi_sequencer::type_id::create("sqr", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (cfg.is_active == UVM_ACTIVE)
            drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass : axi_agent
