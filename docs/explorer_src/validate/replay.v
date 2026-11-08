`timescale 1ns/1ps
// Replays one scenario's input vectors (from the explorer's JS model) through the real axi2apb and compares every output each cycle.
module replay;
  reg clk=0, rst_n=0; always #5 clk=~clk;
  reg arvalid,awvalid,wvalid,bready,rready,pready,pslverr; reg [31:0] araddr,awaddr,wdata,prdata;
  wire arready,awready,wready,rvalid,bvalid,psel,penable,pwrite; wire [31:0] rdata,paddr,pwdata; wire [1:0] bresp,rresp;
  axi2apb dut(.clk(clk),.rst_n(rst_n),.S_AXI_ARADDR(araddr),.S_AXI_ARVALID(arvalid),.S_AXI_ARREADY(arready),.S_AXI_RDATA(rdata),.S_AXI_RRESP(rresp),
    .S_AXI_RVALID(rvalid),.S_AXI_RREADY(rready),.S_AXI_AWADDR(awaddr),.S_AXI_AWVALID(awvalid),.S_AXI_AWREADY(awready),.S_AXI_WDATA(wdata),
    .S_AXI_WVALID(wvalid),.S_AXI_WREADY(wready),.S_AXI_BRESP(bresp),.S_AXI_BVALID(bvalid),.S_AXI_BREADY(bready),.M_APB_PADDR(paddr),.M_APB_PSEL(psel),
    .M_APB_PENABLE(penable),.M_APB_PWRITE(pwrite),.M_APB_PWDATA(pwdata),.M_APB_PREADY(pready),.M_APB_PRDATA(prdata),.M_APB_PSLVERR(pslverr));
  integer fd, r, n, bad; reg [255:0] fname;
  reg [31:0] e_state,e_paddr,e_pwdata,e_bresp,e_rresp,e_rdata,e_arready,e_awready,e_wready,e_rvalid,e_bvalid,e_psel,e_penable,e_pwrite;
  reg [31:0] i0,i1,i2,i3,i4,i5,i6,i7,i8,i9,i10;
  initial begin
    if(!$value$plusargs("f=%s",fname)) $finish;
    fd=$fopen(fname,"r"); n=0; bad=0;
    repeat(3) @(posedge clk); #1 rst_n=1;
    while(!$feof(fd)) begin
      r=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",
        i0,i1,i2,i3,i4,i5,i6,i7,i8,i9,i10,e_state,e_paddr,e_pwdata,e_bresp,e_rresp,e_rdata,e_arready,e_awready,e_wready,e_rvalid,e_bvalid,e_psel,e_penable,e_pwrite);
      if(r==25) begin
        @(negedge clk);
        arvalid=i0; araddr=i1; awvalid=i2; awaddr=i3; wvalid=i4; wdata=i5; bready=i6; rready=i7; pready=i8; prdata=i9; pslverr=i10;
        #1;
        if(dut.present_state!==e_state[2:0] || paddr!==e_paddr || pwdata!==e_pwdata || bresp!==e_bresp[1:0] || rresp!==e_rresp[1:0] || rdata!==e_rdata ||
           arready!==e_arready[0] || awready!==e_awready[0] || wready!==e_wready[0] || rvalid!==e_rvalid[0] || bvalid!==e_bvalid[0] ||
           psel!==e_psel[0] || penable!==e_penable[0] || pwrite!==e_pwrite[0]) begin
          bad=bad+1; $display("MISMATCH cycle %0d: state %0d/%0d paddr %h/%h pwdata %h/%h bresp %b/%b rresp %b/%b rdata %h/%h rdy %b%b%b/%b%b%b rv %b/%b bv %b/%b ps %b%b%b/%b%b%b",
            n+1,dut.present_state,e_state,paddr,e_paddr,pwdata,e_pwdata,bresp,e_bresp[1:0],rresp,e_rresp[1:0],rdata,e_rdata,arready,awready,wready,e_arready[0],e_awready[0],e_wready[0],
            rvalid,e_rvalid[0],bvalid,e_bvalid[0],psel,penable,pwrite,e_psel[0],e_penable[0],e_pwrite[0]);
        end
        n=n+1;
      end
    end
    $display("REPLAY %0s: %0d cycles compared, %0d mismatches", fname, n, bad); $finish;
  end
endmodule
