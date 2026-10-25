//==============================================================================
// axi_if — AXI4 SystemVerilog Interface
//------------------------------------------------------------------------------
// Carries all five AXI4 channels (AW, W, B, AR, R) with full burst signalling.
// Provides three modports / clocking blocks:
//   - master_mp / master_cb : used by the AXI master driver in the TB
//   - slave_mp  / slave_cb  : used if a slave-style driver were ever added
//   - monitor_mp / monitor_cb : used by the passive monitor
//
// Skew convention (industry-standard):
//   default input  #1step : sample just before posedge clk (post-update value)
//   default output #1     : drive 1 time-unit after posedge clk (avoids races
//                           with same-cycle combinational paths in the DUT)
//==============================================================================

interface axi_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH/8
) (
    input logic clk,
    input logic rst_n
);

    //--------------------------------------------------------------------------
    // Write Address Channel (AW)
    //--------------------------------------------------------------------------
    logic [ID_WIDTH-1:0]   awid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awvalid;
    logic                  awready;

    //--------------------------------------------------------------------------
    // Write Data Channel (W)
    //--------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0] wstrb;
    logic                  wlast;
    logic                  wvalid;
    logic                  wready;

    //--------------------------------------------------------------------------
    // Write Response Channel (B)
    //--------------------------------------------------------------------------
    logic [ID_WIDTH-1:0]   bid;
    logic [1:0]            bresp;
    logic                  bvalid;
    logic                  bready;

    //--------------------------------------------------------------------------
    // Read Address Channel (AR)
    //--------------------------------------------------------------------------
    logic [ID_WIDTH-1:0]   arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arvalid;
    logic                  arready;

    //--------------------------------------------------------------------------
    // Read Data Channel (R)
    //--------------------------------------------------------------------------
    logic [ID_WIDTH-1:0]   rid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rlast;
    logic                  rvalid;
    logic                  rready;

    //--------------------------------------------------------------------------
    // Master clocking block
    //   - Outputs: signals the master drives (AW/W/AR payload + valids, BREADY/RREADY)
    //   - Inputs : signals the master samples (AWREADY/WREADY/ARREADY, B/R payload + valids)
    //--------------------------------------------------------------------------
    clocking master_cb @(posedge clk);
        default input #1step output #1;

        // Outputs (master drives)
        output awid, awaddr, awlen, awsize, awburst, awvalid;
        output wdata, wstrb, wlast, wvalid;
        output bready;
        output arid, araddr, arlen, arsize, arburst, arvalid;
        output rready;

        // Inputs (master samples)
        input  awready;
        input  wready;
        input  bid, bresp, bvalid;
        input  arready;
        input  rid, rdata, rresp, rlast, rvalid;
    endclocking

    //--------------------------------------------------------------------------
    // Slave clocking block (mirror of master_cb)
    //--------------------------------------------------------------------------
    clocking slave_cb @(posedge clk);
        default input #1step output #1;

        // Outputs (slave drives)
        output awready;
        output wready;
        output bid, bresp, bvalid;
        output arready;
        output rid, rdata, rresp, rlast, rvalid;

        // Inputs (slave samples)
        input  awid, awaddr, awlen, awsize, awburst, awvalid;
        input  wdata, wstrb, wlast, wvalid;
        input  bready;
        input  arid, araddr, arlen, arsize, arburst, arvalid;
        input  rready;
    endclocking

    //--------------------------------------------------------------------------
    // Monitor clocking block — every signal is an input
    //--------------------------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1step;

        input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    //--------------------------------------------------------------------------
    // Modports — exported for agent components
    //--------------------------------------------------------------------------
    modport master_mp  (clocking master_cb,  input clk, input rst_n);
    modport slave_mp   (clocking slave_cb,   input clk, input rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface : axi_if
