//==============================================================================
// axi_seq_item — AXI4 transaction class
//------------------------------------------------------------------------------
// Models a complete AXI4 burst (read or write). Dynamic arrays (data/strb)
// hold one entry per beat; the size constraint keeps them in lockstep with
// AWLEN/ARLEN.
//
// Constraints enforce: legal burst types (no WRAP), data-width-bound size,
// burst length capped at AXI_MAX_BURST_LEN, address aligned to size, and
// the AXI4 4KB-boundary rule for INCR bursts.
//
// UVM_NOCOMPARE on driver-timing knobs and on the response array, since the
// scoreboard will compare expected/observed transactions field-by-field and
// timing knobs aren't part of the protocol-level transaction equivalence.
//==============================================================================

class axi_seq_item extends uvm_sequence_item;

    //--------------------------------------------------------------------------
    // Protocol fields
    //--------------------------------------------------------------------------
    rand axi_op_e                       op;
    rand bit [AXI_ID_WIDTH-1:0]         id;
    rand bit [AXI_ADDR_WIDTH-1:0]       addr;
    rand bit [7:0]                      len;     // AWLEN/ARLEN: 0=1 beat, N=N+1 beats
    rand axi_size_e                     size;    // AWSIZE/ARSIZE
    rand axi_burst_e                    burst;   // AWBURST/ARBURST
    rand bit [AXI_DATA_WIDTH-1:0]       data[];  // per-beat
    rand bit [AXI_STRB_WIDTH-1:0]       strb[];  // per-beat
         axi_resp_e                     resp[];  // filled by monitor (writes: [0] only; reads: per-beat)

    //--------------------------------------------------------------------------
    // Driver-side timing knobs (NOCOMPARE — not part of protocol equivalence)
    //--------------------------------------------------------------------------
    rand int unsigned                   aw_valid_delay;
    rand int unsigned                   ar_valid_delay;
    rand int unsigned                   w_valid_delay[];   // per-beat
    rand int unsigned                   b_ready_delay;
    rand int unsigned                   r_ready_delay[];   // per-beat

    //--------------------------------------------------------------------------
    // UVM registration with field automation
    //--------------------------------------------------------------------------
    `uvm_object_utils_begin(axi_seq_item)
        `uvm_field_enum     (axi_op_e,    op,             UVM_DEFAULT)
        `uvm_field_int      (              id,            UVM_DEFAULT)
        `uvm_field_int      (              addr,          UVM_DEFAULT)
        `uvm_field_int      (              len,           UVM_DEFAULT)
        `uvm_field_enum     (axi_size_e,  size,           UVM_DEFAULT)
        `uvm_field_enum     (axi_burst_e, burst,          UVM_DEFAULT)
        `uvm_field_array_int(              data,          UVM_DEFAULT)
        `uvm_field_array_int(              strb,          UVM_DEFAULT)
        `uvm_field_array_enum(axi_resp_e, resp,           UVM_DEFAULT)
        `uvm_field_int      (              aw_valid_delay, UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_int      (              ar_valid_delay, UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_array_int(              w_valid_delay,  UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_int      (              b_ready_delay,  UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_array_int(              r_ready_delay,  UVM_DEFAULT | UVM_NOCOMPARE)
    `uvm_object_utils_end

    //--------------------------------------------------------------------------
    // Constraints
    //--------------------------------------------------------------------------
    // No WRAP bursts (DUT does not support)
    constraint c_burst_type {
        burst inside { AXI_BURST_FIXED, AXI_BURST_INCR };
    }

    // SIZE in bytes <= bus width
    constraint c_size_within_data_width {
        (32'd1 << size) <= AXI_STRB_WIDTH;
    }

    // Burst length capped (RTL supports 256, TB caps at 16 for tractability)
    constraint c_len_max {
        len < AXI_MAX_BURST_LEN;
    }

    // Address aligned to SIZE
    constraint c_address_alignment {
        (addr % (32'd1 << size)) == 32'd0;
    }

    // INCR burst must not cross 4KB boundary (AXI4 mandatory rule)
    constraint c_4kb_boundary {
        if (burst == AXI_BURST_INCR)
            ((addr & 32'h0000_0FFF) + ((int'(len) + 1) * (32'd1 << size))) <= 32'h0000_1000;
    }

    // Sync dynamic-array sizes with len
    constraint c_arrays_sized {
        data.size()           == int'(len) + 1;
        strb.size()           == int'(len) + 1;
        w_valid_delay.size()  == int'(len) + 1;
        r_ready_delay.size()  == int'(len) + 1;
    }

    // Default: all-byte-enables (tests can override to exercise WSTRB)
    constraint c_strb_default {
        foreach (strb[i]) soft strb[i] == {AXI_STRB_WIDTH{1'b1}};
    }

    // Default delays: small, but tests can stretch them
    constraint c_delays {
        soft aw_valid_delay inside {[0:3]};
        soft ar_valid_delay inside {[0:3]};
        soft b_ready_delay  inside {[0:3]};
        foreach (w_valid_delay[i]) soft w_valid_delay[i] inside {[0:2]};
        foreach (r_ready_delay[i]) soft r_ready_delay[i] inside {[0:2]};
    }

    //--------------------------------------------------------------------------
    // Construction
    //--------------------------------------------------------------------------
    function new(string name = "axi_seq_item");
        super.new(name);
    endfunction

    //--------------------------------------------------------------------------
    // Compact one-line summary used in UVM_INFO logging.
    // (Field macros provide sprint() for full multi-line dumps.)
    //--------------------------------------------------------------------------
    function string convert2string();
        string s;
        s = $sformatf("AXI %-5s id=%0d addr=0x%08x len=%0d size=%0dB burst=%s",
                      op.name(), id, addr, len, (1 << size), burst.name());
        if (op == AXI_WRITE) begin
            foreach (data[i])
                s = {s, $sformatf("\n    W[%0d] data=0x%08x strb=0x%0h", i, data[i], strb[i])};
            if (resp.size() > 0)
                s = {s, $sformatf("\n    BRESP=%s", resp[0].name())};
        end
        else begin
            foreach (data[i])
                s = {s, $sformatf("\n    R[%0d] data=0x%08x rresp=%s", i, data[i],
                                   (i < resp.size()) ? resp[i].name() : "PENDING")};
        end
        return s;
    endfunction

endclass : axi_seq_item
