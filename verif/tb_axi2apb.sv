// tb_axi2apb - self-checking testbench for the AXI4-Lite -> APB3 bridge (Verilator, --timing --assert).
//
//   five channel drivers/receivers (AW, W, B, AR, R), each a free-running process fed by a queue with a per-item delay
//        -> axi2apb (DUT) -> apb_slave_model (programmable wait states, an error region)
//   scoreboard: a 64-word reference memory and in-order expectation queues; every read must return the last value written to that
//   word, every response must be OKAY (2'b00) or, for the error region, the response selected by +err_resp (default SLVERR = 2'b10:
//   an APB PSLVERR is a slave error, not a decode error).
//
//   +seed via +verilator+seed+N     +n=N  random transactions (default 3000)     +err_resp=N  expected response to an APB error (default 2)
//   +vcd=file  waveform               +mon_from=ns +mon_to=ns  cycle monitor
`timescale 1ns / 1ps

module tb_axi2apb;
    logic clk, rst_n;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    logic [31:0] araddr, awaddr, wdata;
    logic        arvalid, rready, awvalid, wvalid, bready;
    wire         arready, awready, wready, rvalid, bvalid;
    wire  [31:0] rdata;
    wire  [1:0]  rresp, bresp;
    wire  [31:0] paddr, pwdata, prdata;
    wire         psel, penable, pwrite, pready, pslverr;
    int unsigned wait_max;

    axi2apb #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) dut (
        .clk, .rst_n,
        .S_AXI_ARADDR(araddr), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .M_APB_PADDR(paddr), .M_APB_PSEL(psel), .M_APB_PENABLE(penable), .M_APB_PWRITE(pwrite),
        .M_APB_PWDATA(pwdata), .M_APB_PREADY(pready), .M_APB_PRDATA(prdata), .M_APB_PSLVERR(pslverr)
    );
    apb_slave_model slv (.clk, .rst_n, .paddr, .psel, .penable, .pwrite, .pwdata, .wait_max, .pready, .prdata, .pslverr);

    // ------------------------------------------------------------------ scoreboard state
    logic [31:0] ref_mem [0:63];
    int          checks, errors, n_writes, n_reads, n_err_resp, outstanding;
    logic [1:0]  exp_err_resp;

    // request queues (one entry per transaction, consumed by the drivers) and expectation queues (consumed by the receivers)
    logic [31:0] aw_a_q[$], w_d_q[$], ar_a_q[$];
    int          aw_dl_q[$], w_dl_q[$], ar_dl_q[$], b_dl_q[$], r_dl_q[$];
    logic [31:0] ew_a_q[$], ew_d_q[$], er_a_q[$];

    function automatic bit is_err_addr(input logic [31:0] a);
        return a[11:8] == 4'hF;
    endfunction

    task automatic fail(input string msg);
        errors++;
        if (errors <= 20) $display("TB ERROR @%0t: %s", $time, msg);
    endtask

    // ------------------------------------------------------------------ channel processes
    initial forever begin                                   // AW driver
        wait (aw_a_q.size() > 0);
        repeat (aw_dl_q.pop_front()) @(posedge clk);
        #1; awaddr = aw_a_q.pop_front(); awvalid = 1'b1;
        do @(posedge clk); while (!awready);
        #1; awvalid = 1'b0; awaddr = 32'hxxxx_xxxx;
    end
    initial forever begin                                   // W driver
        wait (w_d_q.size() > 0);
        repeat (w_dl_q.pop_front()) @(posedge clk);
        #1; wdata = w_d_q.pop_front(); wvalid = 1'b1;
        do @(posedge clk); while (!wready);
        #1; wvalid = 1'b0; wdata = 32'hxxxx_xxxx;
    end
    initial forever begin                                   // AR driver
        wait (ar_a_q.size() > 0);
        repeat (ar_dl_q.pop_front()) @(posedge clk);
        #1; araddr = ar_a_q.pop_front(); arvalid = 1'b1;
        do @(posedge clk); while (!arready);
        #1; arvalid = 1'b0; araddr = 32'hxxxx_xxxx;
    end
    initial forever begin                                   // B receiver + write scoreboard
        logic [31:0] a, v;
        wait (b_dl_q.size() > 0);
        repeat (b_dl_q.pop_front()) @(posedge clk);
        #1; bready = 1'b1;
        do @(posedge clk); while (!bvalid);
        a = ew_a_q.pop_front(); v = ew_d_q.pop_front();
        n_writes++; checks++; outstanding--;
        if (is_err_addr(a)) begin
            n_err_resp++;
            if (bresp !== exp_err_resp) fail($sformatf("write to error address %08x: BRESP=%b, expected %b", a, bresp, exp_err_resp));
        end else begin
            if (bresp !== 2'b00) fail($sformatf("write to %08x: BRESP=%b, expected OKAY", a, bresp));
            ref_mem[a[7:2]] = v;
        end
        #1; bready = 1'b0;
    end
    initial forever begin                                   // R receiver + read scoreboard
        logic [31:0] a;
        wait (r_dl_q.size() > 0);
        repeat (r_dl_q.pop_front()) @(posedge clk);
        #1; rready = 1'b1;
        do @(posedge clk); while (!rvalid);
        a = er_a_q.pop_front();
        n_reads++; checks++; outstanding--;
        if (is_err_addr(a)) begin
            n_err_resp++;
            if (rresp !== exp_err_resp) fail($sformatf("read of error address %08x: RRESP=%b, expected %b", a, rresp, exp_err_resp));
        end else begin
            if (rresp !== 2'b00) fail($sformatf("read of %08x: RRESP=%b, expected OKAY", a, rresp));
            if (rdata !== ref_mem[a[7:2]]) fail($sformatf("read of %08x: got %08x, expected %08x", a, rdata, ref_mem[a[7:2]]));
        end
        #1; rready = 1'b0;
    end

    // ------------------------------------------------------------------ transaction helpers
    task automatic put_write(input logic [31:0] a, input logic [31:0] v, input int aw_d, input int w_d, input int b_d);
        aw_a_q.push_back(a); aw_dl_q.push_back(aw_d);
        w_d_q.push_back(v);  w_dl_q.push_back(w_d);
        ew_a_q.push_back(a); ew_d_q.push_back(v); b_dl_q.push_back(b_d);
        outstanding++;
    endtask
    task automatic put_read(input logic [31:0] a, input int ar_d, input int r_d);
        ar_a_q.push_back(a); ar_dl_q.push_back(ar_d);
        er_a_q.push_back(a); r_dl_q.push_back(r_d);
        outstanding++;
    endtask
    task automatic idle();
        wait (outstanding == 0);
        @(posedge clk);
    endtask
    task automatic do_write(input logic [31:0] a, input logic [31:0] v, input int aw_d, input int w_d, input int b_d);
        put_write(a, v, aw_d, w_d, b_d); idle();
    endtask
    task automatic do_read(input logic [31:0] a, input int ar_d, input int r_d);
        put_read(a, ar_d, r_d); idle();
    endtask

    function automatic logic [31:0] rand_addr(input bit allow_err);
        logic [31:0] a;
        a = 32'h0;
        a[7:2] = 6'($urandom_range(63, 0));
        if (allow_err && $urandom_range(99, 0) < 15) a[11:8] = 4'hF;
        return a;
    endfunction

    // a burst of 2..4 requests of one kind issued back to back (the next request is presented while the previous response is still pending)
    task automatic burst();
        int n;
        bit wr;
        n = $urandom_range(4, 2);
        wr = $urandom_range(1, 0);
        for (int i = 0; i < n; i++) begin
            if (wr) put_write(rand_addr(1), $urandom(), 0, 0, $urandom_range(2, 0));
            else    put_read (rand_addr(1), 0, $urandom_range(2, 0));
        end
        idle();
    endtask

    // ------------------------------------------------------------------ stimulus
    int n_random, er;
    string dumpfile_s;
    initial begin
        if (!$value$plusargs("n=%d", n_random)) n_random = 3000;
        if (!$value$plusargs("err_resp=%d", er)) er = 2;
        exp_err_resp = 2'(er);
        if ($value$plusargs("vcd=%s", dumpfile_s)) begin $dumpfile(dumpfile_s); $dumpvars(0, tb_axi2apb); end
        for (int i = 0; i < 64; i++) ref_mem[i] = 32'h0;
        checks = 0; errors = 0; n_writes = 0; n_reads = 0; n_err_resp = 0; outstanding = 0;
        arvalid = 0; awvalid = 0; wvalid = 0; rready = 0; bready = 0;
        araddr = 'x; awaddr = 'x; wdata = 'x; wait_max = 0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;
        repeat (2) @(posedge clk);

        if (bvalid || rvalid || psel || penable || arready || awready || wready) fail("outputs not idle after reset");

        $display("TB phase 1: directed write/read");
        do_write(32'h0000_0010, 32'hA5A5_0001, 0, 0, 0);
        do_read (32'h0000_0010, 0, 0);
        do_write(32'h0000_0014, 32'h1234_5678, 0, 0, 0);
        do_read (32'h0000_0014, 0, 0);
        do_read (32'h0000_0010, 0, 0);
        do_read (32'h0000_0000, 0, 0);                      // never written: reads zero
        $display("TB phase 2: APB wait states");
        for (int w = 1; w <= 3; w++) begin
            wait_max = w;
            for (int k = 0; k < 6; k++) begin
                do_write(rand_addr(0), $urandom(), 0, 0, 0);
                do_read (rand_addr(0), 0, 0);
            end
        end
        wait_max = 0;
        $display("TB phase 3: error responses");
        do_write(32'h0000_0F20, 32'hDEAD_0001, 0, 0, 0);
        do_write(32'h0000_0024, 32'h0BAD_CAFE, 0, 0, 0);
        do_read (32'h0000_0F24, 0, 0);
        do_read (32'h0000_0024, 0, 0);
        wait_max = 2;
        do_write(32'h0000_0F28, 32'h5555_5555, 0, 0, 0);
        do_read (32'h0000_0F2C, 0, 0);
        wait_max = 0;
        $display("TB phase 4: back-pressure on B and R");
        do_write(32'h0000_0030, 32'hFEED_0030, 0, 0, 7);
        do_read (32'h0000_0030, 0, 7);
        do_write(32'h0000_0F30, 32'h1, 0, 0, 5);
        do_read (32'h0000_0F34, 0, 5);
        $display("TB phase 5: W before AW, AW before W");
        do_write(32'h0000_0034, 32'hAAAA_0034, 6, 0, 0);
        do_write(32'h0000_0038, 32'hBBBB_0038, 0, 6, 0);
        do_read (32'h0000_0034, 0, 0);
        do_read (32'h0000_0038, 0, 0);
        $display("TB phase 6: read and write requested together");
        for (int k = 0; k < 8; k++) begin
            put_write(32'h0000_0040 + 4 * k, 32'hC0DE_0000 + k, 0, 0, k % 3);
            put_read (32'h0000_0000, 0, k % 4);
            idle();
        end
        do_read(32'h0000_0040, 0, 0); do_read(32'h0000_005C, 0, 0);
        $display("TB phase 6b: pipelined bursts (requests issued while the previous response is pending)");
        for (int k = 0; k < 4; k++) begin
            for (int i = 0; i < 4; i++) put_write(32'h0000_0060 + 4 * i, 32'hB000_0000 + 16 * k + i, 0, 0, i % 2);
            idle();
            for (int i = 0; i < 4; i++) put_read(32'h0000_0060 + 4 * i, 0, i % 2);
            idle();
        end
        $display("TB phase 7: constrained-random mix (%0d items)", n_random);
        for (int n = 0; n < n_random; n++) begin
            logic [31:0] wa, ra;
            wait_max = $urandom_range(3, 0);
            case ($urandom_range(9, 0))
                7: burst();
                0, 1, 2, 3: do_write(rand_addr(1), $urandom(), $urandom_range(4, 0) / 3, $urandom_range(4, 0) / 3, $urandom_range(3, 0) / 2);
                4, 5, 6: do_read(rand_addr(1), $urandom_range(4, 0) / 3, $urandom_range(3, 0) / 2);
                default: begin                                 // a read and a write together, different words
                    wa = rand_addr(1);
                    ra = rand_addr(1);
                    if (ra[7:2] == wa[7:2]) ra[7:2] = ra[7:2] + 6'd1;
                    put_write(wa, $urandom(), $urandom_range(2, 0), $urandom_range(2, 0), $urandom_range(2, 0));
                    put_read (ra, $urandom_range(2, 0), $urandom_range(2, 0));
                    idle();
                end
            endcase
        end
        repeat (10) @(posedge clk);
        if (errors == 0 && checks > 0) $display("TB PASS checks=%0d writes=%0d reads=%0d error_responses=%0d", checks, n_writes, n_reads, n_err_resp);
        else $display("TB FAIL checks=%0d errors=%0d", checks, errors);
        $finish;
    end

    // optional cycle monitor
    longint mon_from, mon_to;
    initial begin
        mon_from = 0; mon_to = 0;
        void'($value$plusargs("mon_from=%d", mon_from));
        void'($value$plusargs("mon_to=%d", mon_to));
    end
    always @(posedge clk) if (mon_to != 0 && $time >= mon_from && $time <= mon_to)
        $display("M %0t st=%0d ar %b/%b aw %b/%b w %b/%b b %b/%b r %b/%b psel %b pen %b pwr %b prdy %b", $time, dut.present_state, arvalid, arready, awvalid, awready, wvalid, wready, bvalid, bready, rvalid, rready, psel, penable, pwrite, pready);

    // a response held for 80 cycles means the receiving side has stopped, a transaction stuck for 4000 means the bridge has
    int stall_cnt, idle_cnt;
    always @(posedge clk) begin
        if ((bvalid && !bready) || (rvalid && !rready)) stall_cnt <= stall_cnt + 1; else stall_cnt <= 0;
        if (outstanding != 0 && !bvalid && !rvalid) idle_cnt <= idle_cnt + 1; else idle_cnt <= 0;
        if (stall_cnt == 80) begin
            $display("TB FAIL: a response has been waiting for 80 cycles at %0t (state=%0d)", $time, dut.present_state);
            $finish;
        end
        if (idle_cnt == 4000) begin
            $display("TB FAIL: no response for 4000 cycles with %0d transactions outstanding at %0t (state=%0d)", outstanding, $time, dut.present_state);
            $finish;
        end
    end
    initial begin stall_cnt = 0; idle_cnt = 0; end
endmodule
