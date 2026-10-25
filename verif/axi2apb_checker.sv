// axi2apb_checker - bound protocol assertions and cover points for the AXI4-Lite -> APB3 bridge.
// APB rules follow the AMBA APB protocol (setup phase, access phase, wait states); AXI rules are the channel-stability rules for the bridge's
// slave-side outputs. Verilator 5.020: implications and $past/$stable only (no ## delays), so each rule is stated as `A |-> B` or `A |=> B`.
module axi2apb_checker (
    input logic        clk,
    input logic        rst_n,
    input logic [2:0]  present_state,        // the bridge's FSM state (IDLE = 0, READ_ADDRESS_RECEIVED_STATE = 5)
    input logic [31:0] S_AXI_ARADDR, S_AXI_AWADDR, S_AXI_WDATA, S_AXI_RDATA,
    input logic        S_AXI_ARVALID, S_AXI_ARREADY, S_AXI_RVALID, S_AXI_RREADY,
    input logic        S_AXI_AWVALID, S_AXI_AWREADY, S_AXI_WVALID, S_AXI_WREADY, S_AXI_BVALID, S_AXI_BREADY,
    input logic [1:0]  S_AXI_RRESP, S_AXI_BRESP,
    input logic [31:0] M_APB_PADDR, M_APB_PWDATA, M_APB_PRDATA,
    input logic        M_APB_PSEL, M_APB_PENABLE, M_APB_PWRITE, M_APB_PREADY, M_APB_PSLVERR
);
    wire access = M_APB_PSEL && M_APB_PENABLE;
    wire setup  = M_APB_PSEL && !M_APB_PENABLE;

    // ---------------------------------------------------------------- APB3 protocol
    a_penable_needs_psel:   assert property (@(posedge clk) disable iff (!rst_n) M_APB_PENABLE |-> M_APB_PSEL);
    a_setup_then_access:    assert property (@(posedge clk) disable iff (!rst_n) setup |=> (M_APB_PSEL && M_APB_PENABLE));
    a_access_until_ready:   assert property (@(posedge clk) disable iff (!rst_n) (access && !M_APB_PREADY) |=> (M_APB_PSEL && M_APB_PENABLE));
    a_penable_drops:        assert property (@(posedge clk) disable iff (!rst_n) (access && M_APB_PREADY) |=> !M_APB_PENABLE);
    a_first_cycle_is_setup: assert property (@(posedge clk) disable iff (!rst_n) $rose(M_APB_PSEL) |-> !M_APB_PENABLE);
    a_addr_stable:          assert property (@(posedge clk) disable iff (!rst_n) (access && !M_APB_PREADY) |=> $stable(M_APB_PADDR));
    a_dir_stable:           assert property (@(posedge clk) disable iff (!rst_n) (access && !M_APB_PREADY) |=> $stable(M_APB_PWRITE));
    a_wdata_stable:         assert property (@(posedge clk) disable iff (!rst_n) (access && M_APB_PWRITE && !M_APB_PREADY) |=> $stable(M_APB_PWDATA));
    a_setup_to_access_same: assert property (@(posedge clk) disable iff (!rst_n) setup |=> ($stable(M_APB_PADDR) && $stable(M_APB_PWRITE)));
    // ---------------------------------------------------------------- AXI4-Lite channel rules (bridge outputs)
    a_bvalid_holds:         assert property (@(posedge clk) disable iff (!rst_n) (S_AXI_BVALID && !S_AXI_BREADY) |=> (S_AXI_BVALID && $stable(S_AXI_BRESP)));
    a_rvalid_holds:         assert property (@(posedge clk) disable iff (!rst_n) (S_AXI_RVALID && !S_AXI_RREADY) |=> (S_AXI_RVALID && $stable(S_AXI_RDATA) && $stable(S_AXI_RRESP)));
    // an APB bridge has no decode error and AXI4-Lite has no exclusive access: only OKAY (00) and SLVERR (10) are legal responses
    a_bresp_legal:          assert property (@(posedge clk) disable iff (!rst_n) S_AXI_BVALID |-> (S_AXI_BRESP == 2'b00 || S_AXI_BRESP == 2'b10));
    a_rresp_legal:          assert property (@(posedge clk) disable iff (!rst_n) S_AXI_RVALID |-> (S_AXI_RRESP == 2'b00 || S_AXI_RRESP == 2'b10));
    // the APB result decides the AXI response: PSLVERR -> SLVERR, otherwise OKAY (checked one cycle later, when the response register is visible)
    a_bresp_maps_slverr:    assert property (@(posedge clk) disable iff (!rst_n) (access && M_APB_PREADY && M_APB_PWRITE) |=> (S_AXI_BRESP == ($past(M_APB_PSLVERR) ? 2'b10 : 2'b00)));
    a_rresp_maps_slverr:    assert property (@(posedge clk) disable iff (!rst_n) (access && M_APB_PREADY && !M_APB_PWRITE) |=> (S_AXI_RRESP == ($past(M_APB_PSLVERR) ? 2'b10 : 2'b00)));
    a_rdata_is_prdata:      assert property (@(posedge clk) disable iff (!rst_n) (access && M_APB_PREADY && !M_APB_PWRITE && !M_APB_PSLVERR) |=> (S_AXI_RDATA == $past(M_APB_PRDATA)));
    // one transaction at a time: no APB activity while a response is waiting, and a response never appears together with a new request phase
    a_one_outstanding:      assert property (@(posedge clk) disable iff (!rst_n) (S_AXI_BVALID || S_AXI_RVALID) |-> !M_APB_PSEL);
    a_aw_w_ready_together:  assert property (@(posedge clk) disable iff (!rst_n) S_AXI_AWREADY == S_AXI_WREADY);
    a_no_resp_both:         assert property (@(posedge clk) disable iff (!rst_n) !(S_AXI_BVALID && S_AXI_RVALID));
    a_bvalid_only_after_write: assert property (@(posedge clk) disable iff (!rst_n) $rose(S_AXI_BVALID) |-> $past(access && M_APB_PREADY && M_APB_PWRITE, 1) || $past(S_AXI_BVALID));
    a_rvalid_only_after_read:  assert property (@(posedge clk) disable iff (!rst_n) $rose(S_AXI_RVALID) |-> $past(access && M_APB_PREADY && !M_APB_PWRITE, 1) || $past(S_AXI_RVALID));

    // arbitration: a read request wins over a simultaneous write request (the documented policy), and a request is never ignored in IDLE
    a_read_priority:        assert property (@(posedge clk) disable iff (!rst_n) (present_state == 3'd0 && S_AXI_ARVALID) |=> present_state == 3'd5);
    a_write_when_no_read:   assert property (@(posedge clk) disable iff (!rst_n) (present_state == 3'd0 && !S_AXI_ARVALID && S_AXI_AWVALID) |=> present_state == 3'd1);

    // ---------------------------------------------------------------- functional coverage (named cover points)
    c_write_ok:        cover property (@(posedge clk) disable iff (!rst_n) access && M_APB_PREADY && M_APB_PWRITE && !M_APB_PSLVERR);
    c_write_err:       cover property (@(posedge clk) disable iff (!rst_n) access && M_APB_PREADY && M_APB_PWRITE && M_APB_PSLVERR);
    c_read_ok:         cover property (@(posedge clk) disable iff (!rst_n) access && M_APB_PREADY && !M_APB_PWRITE && !M_APB_PSLVERR);
    c_read_err:        cover property (@(posedge clk) disable iff (!rst_n) access && M_APB_PREADY && !M_APB_PWRITE && M_APB_PSLVERR);
    c_write_wait1:     cover property (@(posedge clk) disable iff (!rst_n) access && !M_APB_PREADY && M_APB_PWRITE);
    c_read_wait1:      cover property (@(posedge clk) disable iff (!rst_n) access && !M_APB_PREADY && !M_APB_PWRITE);
    c_write_wait2:     cover property (@(posedge clk) disable iff (!rst_n) access && !M_APB_PREADY && M_APB_PWRITE && $past(access && !M_APB_PREADY && M_APB_PWRITE));
    c_read_wait2:      cover property (@(posedge clk) disable iff (!rst_n) access && !M_APB_PREADY && !M_APB_PWRITE && $past(access && !M_APB_PREADY && !M_APB_PWRITE));
    c_write_wait3:     cover property (@(posedge clk) disable iff (!rst_n) access && !M_APB_PREADY && M_APB_PWRITE && $past(access && !M_APB_PREADY && M_APB_PWRITE) && $past(access && !M_APB_PREADY && M_APB_PWRITE, 2));
    c_b_backpressure:  cover property (@(posedge clk) disable iff (!rst_n) S_AXI_BVALID && !S_AXI_BREADY);
    c_r_backpressure:  cover property (@(posedge clk) disable iff (!rst_n) S_AXI_RVALID && !S_AXI_RREADY);
    c_b_backpressure2: cover property (@(posedge clk) disable iff (!rst_n) S_AXI_BVALID && !S_AXI_BREADY && $past(S_AXI_BVALID && !S_AXI_BREADY));
    c_ar_and_aw:       cover property (@(posedge clk) disable iff (!rst_n) S_AXI_ARVALID && S_AXI_AWVALID);
    c_w_before_aw:     cover property (@(posedge clk) disable iff (!rst_n) S_AXI_WVALID && !S_AXI_AWVALID && !S_AXI_AWREADY);
    c_aw_before_w:     cover property (@(posedge clk) disable iff (!rst_n) S_AXI_AWREADY && !S_AXI_WVALID);
    c_back_to_back_w:  cover property (@(posedge clk) disable iff (!rst_n) S_AXI_BVALID && S_AXI_BREADY && S_AXI_AWVALID);
    c_read_wins:       cover property (@(posedge clk) disable iff (!rst_n) S_AXI_ARVALID && S_AXI_AWVALID && M_APB_PSEL && !M_APB_PWRITE);
endmodule
