//==============================================================================
// apb_if — APB4 SystemVerilog Interface
//------------------------------------------------------------------------------
// Single APB4 channel between the bridge (master) and a TB-side slave model.
// Exposes PSTRB and PSLVERR (APB4 additions over APB3).
//
// Modports:
//   - master_mp  : if a TB master driver is ever needed (not used by this DUT)
//   - slave_mp   : used by the APB slave driver (reactive responder)
//   - monitor_mp : used by the APB monitor
//
// Skew convention matches axi_if.sv:
//   default input #1step output #1
//==============================================================================

interface apb_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int STRB_WIDTH = DATA_WIDTH/8
) (
    input logic clk,
    input logic rst_n
);

    //--------------------------------------------------------------------------
    // APB4 signals
    //--------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] paddr;
    logic                  psel;
    logic                  penable;
    logic                  pwrite;
    logic [DATA_WIDTH-1:0] pwdata;
    logic [STRB_WIDTH-1:0] pstrb;
    logic                  pready;
    logic [DATA_WIDTH-1:0] prdata;
    logic                  pslverr;

    //--------------------------------------------------------------------------
    // Master clocking block (drives address phase, samples response phase)
    //--------------------------------------------------------------------------
    clocking master_cb @(posedge clk);
        default input #1step output #1;

        output paddr, psel, penable, pwrite, pwdata, pstrb;
        input  pready, prdata, pslverr;
    endclocking

    //--------------------------------------------------------------------------
    // Slave clocking block (drives response, samples requests)
    //--------------------------------------------------------------------------
    clocking slave_cb @(posedge clk);
        default input #1step output #1;

        input  paddr, psel, penable, pwrite, pwdata, pstrb;
        output pready, prdata, pslverr;
    endclocking

    //--------------------------------------------------------------------------
    // Monitor clocking block — every signal is an input
    //--------------------------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1step;

        input paddr, psel, penable, pwrite, pwdata, pstrb;
        input pready, prdata, pslverr;
    endclocking

    //--------------------------------------------------------------------------
    // Modports
    //--------------------------------------------------------------------------
    modport master_mp  (clocking master_cb,  input clk, input rst_n);
    modport slave_mp   (clocking slave_cb,   input clk, input rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface : apb_if
