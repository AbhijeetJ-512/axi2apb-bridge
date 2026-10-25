//==============================================================================
// axi_sequencer — Standard UVM sequencer parameterised on axi_seq_item
//==============================================================================

class axi_sequencer extends uvm_sequencer #(axi_seq_item);

    `uvm_component_utils(axi_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass : axi_sequencer
