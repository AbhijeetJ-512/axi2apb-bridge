module axi2apb#(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    // Global Signals
    input                        clk,          // Clock signal
    input                        rst_n,        // Active-low reset

    // AXI Read Address Channel
    input       [ADDR_WIDTH-1:0] S_AXI_ARADDR, // Read address
    input                        S_AXI_ARVALID,// Read address valid
    output  reg                  S_AXI_ARREADY,// Read address ready

    // AXI Read Data Channel
    output  reg [DATA_WIDTH-1:0] S_AXI_RDATA,  // Read data
    output  reg [1:0]            S_AXI_RRESP,  // Read response
    output  reg                  S_AXI_RVALID, // Read data valid
    input                        S_AXI_RREADY, // Read data ready

    // AXI Write Address Channel
    input       [ADDR_WIDTH-1:0] S_AXI_AWADDR, // Write address
    input                        S_AXI_AWVALID,// Write address valid
    output  reg                  S_AXI_AWREADY,// Write address ready

    // AXI Write Data Channel
    input       [DATA_WIDTH-1:0] S_AXI_WDATA,  // Write data
    input                        S_AXI_WVALID, // Write data valid
    output  reg                  S_AXI_WREADY, // Write data ready

    // AXI Write Response Channel
    output  reg [1:0]            S_AXI_BRESP,  // Write response
    output  reg                  S_AXI_BVALID, // Write response valid
    input                        S_AXI_BREADY, // Write response ready

    // APB Interface
    output  reg [ADDR_WIDTH-1:0] M_APB_PADDR,  // APB address
    output  reg                  M_APB_PSEL,   // APB select
    output  reg                  M_APB_PENABLE,// APB enable
    output  reg                  M_APB_PWRITE, // APB write
    output  reg [DATA_WIDTH-1:0] M_APB_PWDATA, // APB write data
    input                        M_APB_PREADY, // APB ready
    input       [DATA_WIDTH-1:0] M_APB_PRDATA, // APB read data
    input                        M_APB_PSLVERR  // APB slave error
);

// FSM state definitions
localparam IDLE                         = 3'b000,
           WRITE_ADDRESS_RECEIVED_STATE = 3'b001,
           WRITE_DATA_RECEIVED_STATE    = 3'b010,
           PENABLE_WRITE_SIGNAL         = 3'b011,
           WDATA_TRANSFERRED_STATE      = 3'b100,
           READ_ADDRESS_RECEIVED_STATE  = 3'b101,
           PENABLE_READ_SIGNAL          = 3'b110,
           RDATA_TRANSFERRED_STATE      = 3'b111;

reg [2:0] present_state, next_state;

reg [DATA_WIDTH-1:0] sampled_wdata;  // Temporarily stores AXI write data
reg [ADDR_WIDTH-1:0] sampled_addr;   // Temporarily stores AXI address

// FSM State transition
always @(posedge clk) begin
    if(~rst_n)
        present_state <= IDLE;
    else
        present_state <= next_state;
end

// FSM Next state logic
always @(*) begin
    case (present_state)
        IDLE: begin
            // Give priority to read if both valid
            if (S_AXI_ARVALID)
                next_state = READ_ADDRESS_RECEIVED_STATE;
            else if (S_AXI_AWVALID)
                next_state = WRITE_ADDRESS_RECEIVED_STATE;
            else
                next_state = IDLE;
        end

        WRITE_ADDRESS_RECEIVED_STATE: begin
            if (S_AXI_WVALID)
                next_state = WRITE_DATA_RECEIVED_STATE;
            else
                next_state = WRITE_ADDRESS_RECEIVED_STATE;
        end

        WRITE_DATA_RECEIVED_STATE:
            next_state = PENABLE_WRITE_SIGNAL;

        PENABLE_WRITE_SIGNAL: begin
            if (M_APB_PREADY)
                next_state = WDATA_TRANSFERRED_STATE;
            else
                next_state = PENABLE_WRITE_SIGNAL;
        end

        WDATA_TRANSFERRED_STATE: begin
            if (S_AXI_BREADY)
                next_state = IDLE;
            else
                next_state = WDATA_TRANSFERRED_STATE;
        end

        READ_ADDRESS_RECEIVED_STATE:
            next_state = PENABLE_READ_SIGNAL;

        PENABLE_READ_SIGNAL: begin
            if (M_APB_PREADY)
                next_state = RDATA_TRANSFERRED_STATE;
            else
                next_state = PENABLE_READ_SIGNAL;
        end

        RDATA_TRANSFERRED_STATE: begin
            if (S_AXI_RREADY)
                next_state = IDLE;
            else
                next_state = RDATA_TRANSFERRED_STATE;
        end
    endcase
end

// Output control signals based on state
always @(*) begin
    // Default values
    S_AXI_ARREADY = 0;
    S_AXI_AWREADY = 0;
    S_AXI_RVALID  = 0;
    S_AXI_WREADY  = 0;
    S_AXI_BVALID  = 0;
    M_APB_PSEL    = 0;
    M_APB_PENABLE = 0;
    M_APB_PWRITE  = 0;

    case (present_state)
        WRITE_ADDRESS_RECEIVED_STATE: begin
            S_AXI_AWREADY = 1;
            S_AXI_WREADY  = 1;
        end

        WRITE_DATA_RECEIVED_STATE: begin
            M_APB_PSEL   = 1;
            M_APB_PWRITE = 1;
        end

        PENABLE_WRITE_SIGNAL: begin
            M_APB_PSEL    = 1;
            M_APB_PENABLE = 1;
            M_APB_PWRITE  = 1;
        end

        WDATA_TRANSFERRED_STATE: begin
            S_AXI_BVALID = 1;
        end

        READ_ADDRESS_RECEIVED_STATE: begin
            S_AXI_ARREADY = 1;
            M_APB_PSEL    = 1;
        end

        PENABLE_READ_SIGNAL: begin
            M_APB_PSEL    = 1;
            M_APB_PENABLE = 1;
        end

        RDATA_TRANSFERRED_STATE: begin
            S_AXI_RVALID = 1;
        end
    endcase
end

// Sample AXI address
always @(posedge clk) begin
    if(~rst_n)
        sampled_addr <= 0;
    else if(present_state == IDLE) begin
        if(S_AXI_ARVALID)
            sampled_addr <= S_AXI_ARADDR;
        else if(S_AXI_AWVALID)
            sampled_addr <= S_AXI_AWADDR;
    end
end

// Sample AXI write data
always @(posedge clk) begin
    if(~rst_n)
        sampled_wdata <= 0;
    else if ((present_state == WRITE_ADDRESS_RECEIVED_STATE && S_AXI_WVALID) || 
             (present_state == WDATA_TRANSFERRED_STATE && S_AXI_WVALID))
        sampled_wdata <= S_AXI_WDATA;
end

// Drive APB address and write data
always @(posedge clk) begin
    if(~rst_n) begin
        M_APB_PWDATA <= 0;
        M_APB_PADDR  <= 0;
    end
    else begin
        if ((present_state == WRITE_ADDRESS_RECEIVED_STATE && S_AXI_WVALID) || 
            (present_state == WDATA_TRANSFERRED_STATE && S_AXI_WVALID)) begin
            M_APB_PADDR  <= sampled_addr;
            M_APB_PWDATA <= S_AXI_WDATA;
        end
        else if (present_state == IDLE && S_AXI_ARVALID)
            M_APB_PADDR <= S_AXI_ARADDR;
        else if (present_state == RDATA_TRANSFERRED_STATE && S_AXI_RREADY)
            M_APB_PADDR <= sampled_addr;
    end
end

// AXI Write Response
always @(posedge clk) begin
    if(~rst_n)
        S_AXI_BRESP <= 2'b00;
    else if (present_state == PENABLE_WRITE_SIGNAL && M_APB_PREADY)
        S_AXI_BRESP <= (M_APB_PSLVERR) ? 2'b10 : 2'b00; // PSLVERR -> SLVERR (2'b10); 2'b11 would be DECERR
end

// AXI Read Data
always @(posedge clk) begin
    if(~rst_n)
        S_AXI_RDATA <= 0;
    else if (present_state == PENABLE_READ_SIGNAL && M_APB_PREADY && !M_APB_PSLVERR)
        S_AXI_RDATA <= M_APB_PRDATA;
end

// AXI Read Response
always @(posedge clk) begin
    if(~rst_n)
        S_AXI_RRESP <= 2'b00;
    else if (present_state == PENABLE_READ_SIGNAL && M_APB_PREADY)
        S_AXI_RRESP <= (M_APB_PSLVERR) ? 2'b10 : 2'b00;   // PSLVERR -> SLVERR (2'b10)
end

endmodule
