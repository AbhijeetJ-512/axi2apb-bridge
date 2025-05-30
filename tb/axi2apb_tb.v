`timescale 1ns / 1ps
`include "./src/axi2apb.v"

module tb_axi2apb;

    // Parameters
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 32;

    // DUT Signals
    reg clk;
    reg rst_n;

    // AXI signals
    reg  [ADDR_WIDTH-1:0] S_AXI_ARADDR;
    reg                   S_AXI_ARVALID;
    wire                  S_AXI_ARREADY;

    wire [DATA_WIDTH-1:0] S_AXI_RDATA;
    wire [1:0]            S_AXI_RRESP;
    wire                  S_AXI_RVALID;
    reg                   S_AXI_RREADY;

    reg  [ADDR_WIDTH-1:0] S_AXI_AWADDR;
    reg                   S_AXI_AWVALID;
    wire                  S_AXI_AWREADY;

    reg  [DATA_WIDTH-1:0] S_AXI_WDATA;
    reg                   S_AXI_WVALID;
    wire                  S_AXI_WREADY;

    wire [1:0]            S_AXI_BRESP;
    wire                  S_AXI_BVALID;
    reg                   S_AXI_BREADY;

    // APB signals
    wire [ADDR_WIDTH-1:0] M_APB_PADDR;
    wire                  M_APB_PSEL;
    wire                  M_APB_PENABLE;
    wire                  M_APB_PWRITE;
    wire [DATA_WIDTH-1:0] M_APB_PWDATA;
    reg                   M_APB_PREADY;
    reg  [DATA_WIDTH-1:0] M_APB_PRDATA;
    reg                   M_APB_PSLVERR;

    // Instantiate DUT
    axi2apb #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) DUT (
        .clk(clk),
        .rst_n(rst_n),

        .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),
        .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),

        .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),

        .M_APB_PADDR(M_APB_PADDR),
        .M_APB_PSEL(M_APB_PSEL),
        .M_APB_PENABLE(M_APB_PENABLE),
        .M_APB_PWRITE(M_APB_PWRITE),
        .M_APB_PWDATA(M_APB_PWDATA),
        .M_APB_PREADY(M_APB_PREADY),
        .M_APB_PRDATA(M_APB_PRDATA),
        .M_APB_PSLVERR(M_APB_PSLVERR)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz clock

    // APB response simulation
    always @(posedge clk) begin
        if (M_APB_PSEL && M_APB_PENABLE) begin
            M_APB_PREADY <= 1;
            M_APB_PRDATA <= 32'hABCD1234;
            M_APB_PSLVERR <= 0;
        end else begin
            M_APB_PREADY <= 0;
        end
    end

    // Task: AXI Write Transaction
    task axi_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        begin
            @(posedge clk);
            S_AXI_AWADDR  <= addr;
            S_AXI_AWVALID <= 1;
            S_AXI_WDATA   <= data;
            S_AXI_WVALID  <= 1;
            wait (S_AXI_AWREADY && S_AXI_WREADY);
            @(posedge clk);
            S_AXI_AWVALID <= 0;
            S_AXI_WVALID  <= 0;

            S_AXI_BREADY  <= 1;
            wait (S_AXI_BVALID);
            @(posedge clk);
            S_AXI_BREADY  <= 0;
        end
    endtask

    // Task: AXI Read Transaction
    task axi_read(input [ADDR_WIDTH-1:0] addr);
        begin
            @(posedge clk);
            S_AXI_ARADDR  <= addr;
            S_AXI_ARVALID <= 1;
            wait (S_AXI_ARREADY);
            @(posedge clk);
            S_AXI_ARVALID <= 0;

            S_AXI_RREADY <= 1;
            wait (S_AXI_RVALID);
            @(posedge clk);
            $display("Read Data: 0x%08X, RRESP: %b", S_AXI_RDATA, S_AXI_RRESP);
            S_AXI_RREADY <= 0;
        end
    endtask

    // Test sequence
    initial begin
        // Dump File 
        $dumpfile("tb_axi2apb.vcd");
        $dumpvars(0, tb_axi2apb);
        // Initialize signals
        S_AXI_ARADDR  = 0;
        S_AXI_ARVALID = 0;
        S_AXI_RREADY  = 0;
        S_AXI_AWADDR  = 0;
        S_AXI_AWVALID = 0;
        S_AXI_WDATA   = 0;
        S_AXI_WVALID  = 0;
        S_AXI_BREADY  = 0;
        M_APB_PREADY  = 0;
        M_APB_PRDATA  = 0;
        M_APB_PSLVERR = 0;

        // Reset sequence
        rst_n = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;

        // Test AXI Write
        $display("\nStarting AXI Write Transaction...");
        axi_write(32'h0000_1000, 32'hDEADBEEF);

        // Test AXI Read
        $display("\nStarting AXI Read Transaction...");
        axi_read(32'h0000_1000);

        $display("\nTest Completed.");
        #100;
        $finish;
        // $stop;
    end

endmodule
