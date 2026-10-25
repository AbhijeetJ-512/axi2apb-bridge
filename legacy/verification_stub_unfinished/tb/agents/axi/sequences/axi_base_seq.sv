//==============================================================================
// axi_base_seq — Base class for all AXI sequences
//------------------------------------------------------------------------------
// Holds the single-item helper send_item() so derived sequences don't repeat
// the start_item / randomize / finish_item boilerplate. Inline-randomize via
// constraint-block argument lets each test express its constraint without
// subclassing the seq_item.
//==============================================================================

class axi_base_seq extends uvm_sequence #(axi_seq_item);

    `uvm_object_utils(axi_base_seq)

    function new(string name = "axi_base_seq");
        super.new(name);
    endfunction

    virtual task body();
        // Base sequences are not standalone; tests use subclasses
        `uvm_fatal("AXI_SEQ", "axi_base_seq.body() must be overridden")
    endtask

endclass : axi_base_seq
