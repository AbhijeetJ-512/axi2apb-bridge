//==============================================================================
// apb_seq_item — APB4 transaction class
//------------------------------------------------------------------------------
// One transaction == one APB transfer (no bursts in APB). Carries both the
// request fields (paddr/pwrite/pwdata/pstrb) and the response fields
// (prdata/pslverr) so the same item flows through monitor and slave-driver.
//
// Slave-side knobs:
//   wait_cycles  : number of extra cycles to hold PREADY=0 in the access phase
//   inject_error : when set, slave will assert PSLVERR on this transfer
//
// Optional rdata_override allows tests to pin a specific PRDATA without
// needing a full memory model (the env's default APB slave uses memory).
//==============================================================================

class apb_seq_item extends uvm_sequence_item;

    //--------------------------------------------------------------------------
    // Request fields (filled by master / observed by monitor)
    //--------------------------------------------------------------------------
    bit [APB_ADDR_WIDTH-1:0]  paddr;
    bit                       pwrite;
    bit [APB_DATA_WIDTH-1:0]  pwdata;
    bit [APB_STRB_WIDTH-1:0]  pstrb;

    //--------------------------------------------------------------------------
    // Response fields (filled by slave / observed by monitor)
    //--------------------------------------------------------------------------
    bit [APB_DATA_WIDTH-1:0]  prdata;
    bit                       pslverr;

    //--------------------------------------------------------------------------
    // Slave-side timing / injection knobs
    //--------------------------------------------------------------------------
    rand int unsigned         wait_cycles;
    rand bit                  inject_error;

    //--------------------------------------------------------------------------
    // UVM registration
    //--------------------------------------------------------------------------
    `uvm_object_utils_begin(apb_seq_item)
        `uvm_field_int(paddr,        UVM_DEFAULT)
        `uvm_field_int(pwrite,       UVM_DEFAULT)
        `uvm_field_int(pwdata,       UVM_DEFAULT)
        `uvm_field_int(pstrb,        UVM_DEFAULT)
        `uvm_field_int(prdata,       UVM_DEFAULT)
        `uvm_field_int(pslverr,      UVM_DEFAULT)
        `uvm_field_int(wait_cycles,  UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_int(inject_error, UVM_DEFAULT | UVM_NOCOMPARE)
    `uvm_object_utils_end

    //--------------------------------------------------------------------------
    // Default constraints (tests override as needed)
    //--------------------------------------------------------------------------
    constraint c_wait_cycles_default {
        soft wait_cycles inside {[0:4]};
    }

    constraint c_no_error_default {
        soft inject_error == 1'b0;
    }

    //--------------------------------------------------------------------------
    // Construction
    //--------------------------------------------------------------------------
    function new(string name = "apb_seq_item");
        super.new(name);
    endfunction

    //--------------------------------------------------------------------------
    // One-line summary
    //--------------------------------------------------------------------------
    function string convert2string();
        return $sformatf("APB %-2s addr=0x%08x %s=0x%08x strb=0x%0h wait=%0d %s",
                          pwrite ? "WR" : "RD",
                          paddr,
                          pwrite ? "wdata" : "rdata",
                          pwrite ? pwdata : prdata,
                          pstrb,
                          wait_cycles,
                          pslverr ? "SLVERR" : "OKAY");
    endfunction

endclass : apb_seq_item
