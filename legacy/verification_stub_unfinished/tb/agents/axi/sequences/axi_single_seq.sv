//==============================================================================
// axi_single_seq — Single-beat (AXI4-Lite-equivalent) write/read sequences
//------------------------------------------------------------------------------
// Two sequences here: write and read, each issuing one transaction with len=0.
// Useful for the sanity test and the single-beat regression test.
//==============================================================================

class axi_single_write_seq extends axi_base_seq;

    `uvm_object_utils(axi_single_write_seq)

    rand bit [AXI_ADDR_WIDTH-1:0] start_addr;
    rand bit [AXI_DATA_WIDTH-1:0] wr_data;

    function new(string name = "axi_single_write_seq");
        super.new(name);
    endfunction

    virtual task body();
        req = axi_seq_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with {
            op    == AXI_WRITE;
            len   == 0;
            burst == AXI_BURST_INCR;
            addr  == local::start_addr;
            data[0] == local::wr_data;
        }) `uvm_fatal("AXI_SEQ", "single_write randomization failed")
        finish_item(req);
    endtask

endclass : axi_single_write_seq


class axi_single_read_seq extends axi_base_seq;

    `uvm_object_utils(axi_single_read_seq)

    rand bit [AXI_ADDR_WIDTH-1:0] start_addr;

    function new(string name = "axi_single_read_seq");
        super.new(name);
    endfunction

    virtual task body();
        req = axi_seq_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with {
            op    == AXI_READ;
            len   == 0;
            burst == AXI_BURST_INCR;
            addr  == local::start_addr;
        }) `uvm_fatal("AXI_SEQ", "single_read randomization failed")
        finish_item(req);
    endtask

endclass : axi_single_read_seq
