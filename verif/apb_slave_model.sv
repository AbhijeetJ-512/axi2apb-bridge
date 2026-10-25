// apb_slave_model - behavioural APB3 slave used by the testbench: 64 x 32-bit words, programmable wait states, an error region.
//   address decode : word index = paddr[7:2]
//   error region   : paddr[11:8] == 4'hF  -> PSLVERR with the access completed, no memory change, read data poisoned
//   wait states    : chosen per access from the input `wait_max` (0 = PREADY in the first access cycle)
// PREADY, PRDATA and PSLVERR are combinational functions of registered state, so the bridge sees them in the same cycle (APB3).
module apb_slave_model (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] paddr,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] pwdata,
    input  int unsigned wait_max,
    output logic        pready,
    output logic [31:0] prdata,
    output logic        pslverr
);
    logic [31:0] mem [0:63];
    logic [3:0]  cnt;
    logic        in_access_q;

    wire access  = psel && penable;
    wire err_reg = (paddr[11:8] == 4'hF);

    // wait counter: loaded in the setup phase (psel && !penable), counts down during the access phase
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cnt <= 4'd0;
            for (int i = 0; i < 64; i++) mem[i] <= 32'h0;
        end else begin
            if (psel && !penable) cnt <= 4'(wait_max == 0 ? 0 : $urandom_range(wait_max, 0));
            else if (access && cnt != 0) cnt <= cnt - 4'd1;
            if (access && pready && pwrite && !err_reg) mem[paddr[7:2]] <= pwdata;
        end
    end

    assign pready  = access && (cnt == 4'd0);
    assign pslverr = pready && err_reg;
    assign prdata  = (pready && !pwrite) ? (err_reg ? 32'hBAD0_BAD0 : mem[paddr[7:2]]) : 32'hDEAD_BEEF;   // poison when not valid
endmodule
