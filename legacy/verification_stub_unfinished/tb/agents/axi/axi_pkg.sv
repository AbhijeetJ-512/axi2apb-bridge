//==============================================================================
// axi_pkg — UVM package for the AXI master agent
//------------------------------------------------------------------------------
// Aggregates types, transaction class, agent components, and sequences.
// Test code does `import axi_pkg::*;` to get everything in one shot.
//
// File include order matters: typedefs first, then dependents.
//==============================================================================

package axi_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //--------------------------------------------------------------------------
    // Bus parameters (must match the DUT instantiation in tb_top)
    //--------------------------------------------------------------------------
    parameter int AXI_ADDR_WIDTH    = 32;
    parameter int AXI_DATA_WIDTH    = 32;
    parameter int AXI_ID_WIDTH      = 4;
    parameter int AXI_STRB_WIDTH    = AXI_DATA_WIDTH/8;
    parameter int AXI_MAX_BURST_LEN = 16;   // TB caps at 16 even though spec allows 256

    //--------------------------------------------------------------------------
    // Protocol enums
    //--------------------------------------------------------------------------
    typedef enum bit { AXI_READ = 1'b0, AXI_WRITE = 1'b1 } axi_op_e;

    typedef enum bit [1:0] {
        AXI_BURST_FIXED = 2'b00,
        AXI_BURST_INCR  = 2'b01,
        AXI_BURST_WRAP  = 2'b10
    } axi_burst_e;

    typedef enum bit [1:0] {
        AXI_RESP_OKAY   = 2'b00,
        AXI_RESP_EXOKAY = 2'b01,
        AXI_RESP_SLVERR = 2'b10,
        AXI_RESP_DECERR = 2'b11
    } axi_resp_e;

    typedef enum bit [2:0] {
        AXI_SIZE_1B = 3'd0,
        AXI_SIZE_2B = 3'd1,
        AXI_SIZE_4B = 3'd2,
        AXI_SIZE_8B = 3'd3
    } axi_size_e;

    //--------------------------------------------------------------------------
    // Class includes
    //--------------------------------------------------------------------------
    `include "axi_seq_item.sv"
    `include "axi_agent_config.sv"
    `include "axi_sequencer.sv"
    `include "axi_driver.sv"
    `include "axi_monitor.sv"
    `include "axi_agent.sv"

    `include "sequences/axi_base_seq.sv"
    `include "sequences/axi_single_seq.sv"
    `include "sequences/axi_burst_seq.sv"
    `include "sequences/axi_random_seq.sv"

endpackage : axi_pkg
