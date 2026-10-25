//==============================================================================
// axi_agent_config — Configuration object for the AXI master agent
//------------------------------------------------------------------------------
// Single config object passed via uvm_config_db. Carries the virtual interface
// handle, active/passive role, and per-agent feature flags.
//==============================================================================

class axi_agent_config extends uvm_object;

    `uvm_object_utils(axi_agent_config)

    // Virtual interface to the AXI bus
    virtual axi_if vif;

    // Active drives + monitors; passive only monitors
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // Coverage enable (off by default; env turns it on for the master agent)
    bit                     enable_coverage = 1'b0;

    function new(string name = "axi_agent_config");
        super.new(name);
    endfunction

endclass : axi_agent_config
