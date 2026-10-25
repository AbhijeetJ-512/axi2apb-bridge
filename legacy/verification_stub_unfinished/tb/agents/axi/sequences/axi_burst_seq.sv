//==============================================================================
// axi_burst_seq — Multi-beat burst write/read sequences
//------------------------------------------------------------------------------
// Drives an INCR or FIXED burst with explicit length. Used by the burst tests
// in Stage 10. Tests can also point start_addr / burst_len / burst_type to
// specific corners.
//==============================================================================

class axi_burst_write_seq extends axi_base_seq;

    `uvm_object_utils(axi_burst_write_seq)

    rand bit [AXI_ADDR_WIDTH-1:0] start_addr;
    rand bit [7:0]                burst_len;     // AWLEN value (0..15 here)
    rand axi_burst_e              burst_type = AXI_BURST_INCR;

    constraint c_len_range { burst_len inside {[0:AXI_MAX_BURST_LEN-1]}; }

    function new(string name = "axi_burst_write_seq");
        super.new(name);
    endfunction

    virtual task body();
        req = axi_seq_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with {
            op    == AXI_WRITE;
            len   == local::burst_len;
            burst == local::burst_type;
            addr  == local::start_addr;
        }) `uvm_fatal("AXI_SEQ", "burst_write randomization failed")
        finish_item(req);
    endtask

endclass : axi_burst_write_seq


class axi_burst_read_seq extends axi_base_seq;

    `uvm_object_utils(axi_burst_read_seq)

    rand bit [AXI_ADDR_WIDTH-1:0] start_addr;
    rand bit [7:0]                burst_len;
    rand axi_burst_e              burst_type = AXI_BURST_INCR;

    constraint c_len_range { burst_len inside {[0:AXI_MAX_BURST_LEN-1]}; }

    function new(string name = "axi_burst_read_seq");
        super.new(name);
    endfunction

    virtual task body();
        req = axi_seq_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with {
            op    == AXI_READ;
            len   == local::burst_len;
            burst == local::burst_type;
            addr  == local::start_addr;
        }) `uvm_fatal("AXI_SEQ", "burst_read randomization failed")
        finish_item(req);
    endtask

endclass : axi_burst_read_seq
