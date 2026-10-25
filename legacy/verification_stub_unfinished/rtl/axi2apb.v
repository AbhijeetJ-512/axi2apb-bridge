//==============================================================================
// axi2apb — AXI4 to APB4 Bridge (extended for burst support)
//------------------------------------------------------------------------------
// Extends the AXI4-Lite reference design (../../src/axi2apb.v) with full AXI4
// burst capability. One AXI burst transaction is decomposed into N sequential
// APB transfers; only one AXI transaction is in flight at a time.
//
// Supported:
//   * AWLEN / ARLEN          : burst length 1..256 beats (testbench limits to 16)
//   * AWBURST / ARBURST      : INCR (2'b01), FIXED (2'b00)
//   * AWSIZE / ARSIZE        : up to log2(DATA_WIDTH/8) bytes per beat
//   * AWID / ARID -> BID/RID : single transaction in flight, ID echoed back
//   * WSTRB                  : passed through to PSTRB (APB4)
//   * WLAST / RLAST          : honoured / generated
//   * BRESP                  : aggregated worst-case across burst (any SLVERR)
//   * RRESP                  : per-beat
//
// Out of scope (documented as future work):
//   * AWBURST = WRAP         : not handled, master must not issue
//   * Multiple outstanding   : single transaction in flight
//   * Out-of-order completion: not applicable (single ID active at a time)
//   * Exclusive accesses     : AWLOCK ignored, EXOKAY response not generated
//==============================================================================

`default_nettype none

module axi2apb #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter STRB_WIDTH = DATA_WIDTH/8
)(
    // Global Signals
    input  wire                        clk,
    input  wire                        rst_n,

    //--------------------------------------------------------------------------
    // AXI4 Slave Interface (S_AXI_*)
    //--------------------------------------------------------------------------
    // Read Address Channel
    input  wire [ID_WIDTH-1:0]         S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]       S_AXI_ARADDR,
    input  wire [7:0]                  S_AXI_ARLEN,
    input  wire [2:0]                  S_AXI_ARSIZE,
    input  wire [1:0]                  S_AXI_ARBURST,
    input  wire                        S_AXI_ARVALID,
    output reg                         S_AXI_ARREADY,

    // Read Data Channel
    output reg  [ID_WIDTH-1:0]         S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]       S_AXI_RDATA,
    output reg  [1:0]                  S_AXI_RRESP,
    output reg                         S_AXI_RLAST,
    output reg                         S_AXI_RVALID,
    input  wire                        S_AXI_RREADY,

    // Write Address Channel
    input  wire [ID_WIDTH-1:0]         S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]       S_AXI_AWADDR,
    input  wire [7:0]                  S_AXI_AWLEN,
    input  wire [2:0]                  S_AXI_AWSIZE,
    input  wire [1:0]                  S_AXI_AWBURST,
    input  wire                        S_AXI_AWVALID,
    output reg                         S_AXI_AWREADY,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]       S_AXI_WDATA,
    input  wire [STRB_WIDTH-1:0]       S_AXI_WSTRB,
    input  wire                        S_AXI_WLAST,
    input  wire                        S_AXI_WVALID,
    output reg                         S_AXI_WREADY,

    // Write Response Channel
    output reg  [ID_WIDTH-1:0]         S_AXI_BID,
    output reg  [1:0]                  S_AXI_BRESP,
    output reg                         S_AXI_BVALID,
    input  wire                        S_AXI_BREADY,

    //--------------------------------------------------------------------------
    // APB4 Master Interface (M_APB_*)
    //--------------------------------------------------------------------------
    output reg  [ADDR_WIDTH-1:0]       M_APB_PADDR,
    output reg                         M_APB_PSEL,
    output reg                         M_APB_PENABLE,
    output reg                         M_APB_PWRITE,
    output reg  [DATA_WIDTH-1:0]       M_APB_PWDATA,
    output reg  [STRB_WIDTH-1:0]       M_APB_PSTRB,
    input  wire                        M_APB_PREADY,
    input  wire [DATA_WIDTH-1:0]       M_APB_PRDATA,
    input  wire                        M_APB_PSLVERR
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------
    // AXI burst types
    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_INCR  = 2'b01;
    localparam [1:0] BURST_WRAP  = 2'b10;  // Not supported

    // AXI response codes
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // FSM states (4-bit, one-hot is overkill for this size)
    localparam [3:0]
        S_IDLE         = 4'd0,
        // Write path
        S_W_ADDR_HSK   = 4'd1,   // Latch AW, drive AWREADY for one cycle
        S_W_DATA_WAIT  = 4'd2,   // Drive WREADY, wait for WVALID
        S_W_APB_SETUP  = 4'd3,   // PSEL=1, PENABLE=0 (APB setup phase)
        S_W_APB_ACCESS = 4'd4,   // PSEL=1, PENABLE=1, wait for PREADY
        S_W_RESP       = 4'd5,   // BVALID, wait for BREADY
        // Read path
        S_R_ADDR_HSK   = 4'd6,   // Latch AR, drive ARREADY for one cycle
        S_R_APB_SETUP  = 4'd7,
        S_R_APB_ACCESS = 4'd8,
        S_R_BEAT_SEND  = 4'd9;   // RVALID, wait for RREADY

    //--------------------------------------------------------------------------
    // FSM registers
    //--------------------------------------------------------------------------
    reg [3:0]            present_state, next_state;

    //--------------------------------------------------------------------------
    // Latched transaction context (single outstanding -> one set of registers)
    //--------------------------------------------------------------------------
    reg [ID_WIDTH-1:0]   stored_id;
    reg [ADDR_WIDTH-1:0] current_addr;
    reg [7:0]            stored_len;
    reg [2:0]            stored_size;
    reg [1:0]            stored_burst;
    reg [7:0]            beat_count;

    // Latched W beat
    reg [DATA_WIDTH-1:0] sampled_wdata;
    reg [STRB_WIDTH-1:0] sampled_wstrb;
    reg                  sampled_wlast;

    // Captured APB read data + per-beat response
    reg [DATA_WIDTH-1:0] captured_rdata;
    reg [1:0]            captured_rresp;

    // Worst-case write burst error tracking
    reg                  write_burst_err;

    //--------------------------------------------------------------------------
    // Combinational helpers
    //--------------------------------------------------------------------------
    wire is_last_beat = (beat_count == stored_len);

    // Address increment per AWBURST/AWSIZE
    function [ADDR_WIDTH-1:0] f_next_addr;
        input [ADDR_WIDTH-1:0] addr;
        input [2:0]            size;
        input [1:0]            burst;
        begin
            case (burst)
                BURST_FIXED: f_next_addr = addr;
                BURST_INCR:  f_next_addr = addr + (32'd1 << size);
                default:     f_next_addr = addr;  // WRAP unsupported
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // FSM state register
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (~rst_n)
            present_state <= S_IDLE;
        else
            present_state <= next_state;
    end

    //--------------------------------------------------------------------------
    // FSM next-state logic
    //--------------------------------------------------------------------------
    always @(*) begin
        next_state = present_state;
        case (present_state)
            S_IDLE: begin
                // Read priority preserved from baseline DUT
                if (S_AXI_ARVALID)
                    next_state = S_R_ADDR_HSK;
                else if (S_AXI_AWVALID)
                    next_state = S_W_ADDR_HSK;
            end

            // ------ Write path ------
            S_W_ADDR_HSK:
                next_state = S_W_DATA_WAIT;

            S_W_DATA_WAIT: begin
                if (S_AXI_WVALID)
                    next_state = S_W_APB_SETUP;
            end

            S_W_APB_SETUP:
                next_state = S_W_APB_ACCESS;

            S_W_APB_ACCESS: begin
                if (M_APB_PREADY) begin
                    if (sampled_wlast)
                        next_state = S_W_RESP;
                    else
                        next_state = S_W_DATA_WAIT;
                end
            end

            S_W_RESP: begin
                if (S_AXI_BREADY)
                    next_state = S_IDLE;
            end

            // ------ Read path ------
            S_R_ADDR_HSK:
                next_state = S_R_APB_SETUP;

            S_R_APB_SETUP:
                next_state = S_R_APB_ACCESS;

            S_R_APB_ACCESS: begin
                if (M_APB_PREADY)
                    next_state = S_R_BEAT_SEND;
            end

            S_R_BEAT_SEND: begin
                if (S_AXI_RREADY) begin
                    if (is_last_beat)
                        next_state = S_IDLE;
                    else
                        next_state = S_R_APB_SETUP;
                end
            end

            default:
                next_state = S_IDLE;
        endcase
    end

    //--------------------------------------------------------------------------
    // FSM output / handshake combinational logic
    //--------------------------------------------------------------------------
    always @(*) begin
        // Defaults — every signal driven exactly once per cycle
        S_AXI_AWREADY = 1'b0;
        S_AXI_WREADY  = 1'b0;
        S_AXI_ARREADY = 1'b0;
        M_APB_PSEL    = 1'b0;
        M_APB_PENABLE = 1'b0;
        M_APB_PWRITE  = 1'b0;

        case (present_state)
            S_W_ADDR_HSK:
                S_AXI_AWREADY = 1'b1;

            S_W_DATA_WAIT:
                S_AXI_WREADY  = 1'b1;

            S_W_APB_SETUP: begin
                M_APB_PSEL    = 1'b1;
                M_APB_PWRITE  = 1'b1;
            end

            S_W_APB_ACCESS: begin
                M_APB_PSEL    = 1'b1;
                M_APB_PENABLE = 1'b1;
                M_APB_PWRITE  = 1'b1;
            end

            S_R_ADDR_HSK:
                S_AXI_ARREADY = 1'b1;

            S_R_APB_SETUP: begin
                M_APB_PSEL    = 1'b1;
                M_APB_PWRITE  = 1'b0;
            end

            S_R_APB_ACCESS: begin
                M_APB_PSEL    = 1'b1;
                M_APB_PENABLE = 1'b1;
                M_APB_PWRITE  = 1'b0;
            end

            default: ;  // hold defaults
        endcase
    end

    //--------------------------------------------------------------------------
    // APB address / data / strobe driven from registered context
    //--------------------------------------------------------------------------
    always @(*) begin
        M_APB_PADDR  = current_addr;
        M_APB_PWDATA = sampled_wdata;
        M_APB_PSTRB  = sampled_wstrb;
    end

    //--------------------------------------------------------------------------
    // Latch AW / AR and maintain current_addr + beat_count
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (~rst_n) begin
            stored_id    <= {ID_WIDTH{1'b0}};
            stored_len   <= 8'd0;
            stored_size  <= 3'd0;
            stored_burst <= 2'd0;
            current_addr <= {ADDR_WIDTH{1'b0}};
            beat_count   <= 8'd0;
        end
        else begin
            if (present_state == S_IDLE && next_state == S_W_ADDR_HSK) begin
                stored_id    <= S_AXI_AWID;
                stored_len   <= S_AXI_AWLEN;
                stored_size  <= S_AXI_AWSIZE;
                stored_burst <= S_AXI_AWBURST;
                current_addr <= S_AXI_AWADDR;
                beat_count   <= 8'd0;
            end
            else if (present_state == S_IDLE && next_state == S_R_ADDR_HSK) begin
                stored_id    <= S_AXI_ARID;
                stored_len   <= S_AXI_ARLEN;
                stored_size  <= S_AXI_ARSIZE;
                stored_burst <= S_AXI_ARBURST;
                current_addr <= S_AXI_ARADDR;
                beat_count   <= 8'd0;
            end
            // Increment for next write beat (after APB completes, not last)
            else if (present_state == S_W_APB_ACCESS && M_APB_PREADY && !sampled_wlast) begin
                current_addr <= f_next_addr(current_addr, stored_size, stored_burst);
                beat_count   <= beat_count + 8'd1;
            end
            // Increment for next read beat (after AXI R handshake, not last)
            else if (present_state == S_R_BEAT_SEND && S_AXI_RREADY && !is_last_beat) begin
                current_addr <= f_next_addr(current_addr, stored_size, stored_burst);
                beat_count   <= beat_count + 8'd1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Sample the W beat (data, strobe, last)
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (~rst_n) begin
            sampled_wdata <= {DATA_WIDTH{1'b0}};
            sampled_wstrb <= {STRB_WIDTH{1'b0}};
            sampled_wlast <= 1'b0;
        end
        else if (present_state == S_W_DATA_WAIT && S_AXI_WVALID) begin
            sampled_wdata <= S_AXI_WDATA;
            sampled_wstrb <= S_AXI_WSTRB;
            sampled_wlast <= S_AXI_WLAST;
        end
    end

    //--------------------------------------------------------------------------
    // Capture APB read data + per-beat response
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (~rst_n) begin
            captured_rdata <= {DATA_WIDTH{1'b0}};
            captured_rresp <= RESP_OKAY;
        end
        else if (present_state == S_R_APB_ACCESS && M_APB_PREADY) begin
            captured_rdata <= M_APB_PRDATA;
            captured_rresp <= M_APB_PSLVERR ? RESP_SLVERR : RESP_OKAY;
        end
    end

    //--------------------------------------------------------------------------
    // Aggregate write burst error: sticky any-PSLVERR, cleared at burst start
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (~rst_n)
            write_burst_err <= 1'b0;
        else if (present_state == S_IDLE && next_state == S_W_ADDR_HSK)
            write_burst_err <= 1'b0;
        else if (present_state == S_W_APB_ACCESS && M_APB_PREADY && M_APB_PSLVERR)
            write_burst_err <= 1'b1;
    end

    //--------------------------------------------------------------------------
    // R channel outputs
    //--------------------------------------------------------------------------
    always @(*) begin
        S_AXI_RVALID = (present_state == S_R_BEAT_SEND);
        S_AXI_RDATA  = captured_rdata;
        S_AXI_RRESP  = captured_rresp;
        S_AXI_RID    = stored_id;
        S_AXI_RLAST  = (present_state == S_R_BEAT_SEND) && is_last_beat;
    end

    //--------------------------------------------------------------------------
    // B channel outputs
    //--------------------------------------------------------------------------
    always @(*) begin
        S_AXI_BVALID = (present_state == S_W_RESP);
        S_AXI_BRESP  = write_burst_err ? RESP_SLVERR : RESP_OKAY;
        S_AXI_BID    = stored_id;
    end

endmodule

`default_nettype wire
