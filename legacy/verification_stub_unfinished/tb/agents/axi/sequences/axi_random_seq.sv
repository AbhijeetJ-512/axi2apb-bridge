//==============================================================================
// axi_random_seq — Pure random transactions (within seq_item constraints)
//------------------------------------------------------------------------------
// Used by the random / stress tests. num_txns is a knob the test can set
// before .start(); default of 50 gives reasonable coverage in a single run.
//==============================================================================

class axi_random_seq extends axi_base_seq;

    `uvm_object_utils(axi_random_seq)

    rand int unsigned num_txns;

    constraint c_num_txns_default {
        soft num_txns inside {[20:50]};
    }

    function new(string name = "axi_random_seq");
        super.new(name);
    endfunction

    virtual task body();
        repeat (num_txns) begin
            req = axi_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize())
                `uvm_fatal("AXI_SEQ", "random txn randomization failed")
            finish_item(req);
        end
    endtask

endclass : axi_random_seq


// Aggressive stress sequence: more pressure on backpressure and burst length
class axi_stress_seq extends axi_base_seq;

    `uvm_object_utils(axi_stress_seq)

    rand int unsigned num_txns;

    constraint c_num_txns_stress {
        soft num_txns inside {[80:150]};
    }

    function new(string name = "axi_stress_seq");
        super.new(name);
    endfunction

    virtual task body();
        repeat (num_txns) begin
            req = axi_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with {
                len > 2;                          // bias toward bursts
                aw_valid_delay  inside {[0:6]};
                ar_valid_delay  inside {[0:6]};
                b_ready_delay   inside {[0:6]};
                foreach (w_valid_delay[i])
                    w_valid_delay[i] inside {[0:4]};
                foreach (r_ready_delay[i])
                    r_ready_delay[i] inside {[0:4]};
            }) `uvm_fatal("AXI_SEQ", "stress txn randomization failed")
            finish_item(req);
        end
    endtask

endclass : axi_stress_seq
