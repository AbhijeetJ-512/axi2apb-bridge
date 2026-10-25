//==============================================================================
// apb_pkg — UVM package for the APB slave agent
//------------------------------------------------------------------------------
// At the end of Stage 3 this only carries the seq_item (and the bus
// parameters used by axi_seq_item too). Stage 5 will extend it with the full
// active slave agent (driver, monitor, sequencer, sequences).
//==============================================================================

package apb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //--------------------------------------------------------------------------
    // Bus parameters (must match the DUT instantiation in tb_top)
    //--------------------------------------------------------------------------
    parameter int APB_ADDR_WIDTH = 32;
    parameter int APB_DATA_WIDTH = 32;
    parameter int APB_STRB_WIDTH = APB_DATA_WIDTH/8;

    //--------------------------------------------------------------------------
    // Class includes
    //--------------------------------------------------------------------------
    `include "apb_seq_item.sv"

endpackage : apb_pkg
