// Cycle model of src/axi2apb.v with the testbench's channel drivers/receivers and verif/apb_slave_model.sv.
// Each cycle: eval() computes every combinational signal from the registers and the master/slave inputs; commit() is the clock edge.
const ST=['IDLE','WRITE_ADDRESS_RECEIVED','WRITE_DATA_RECEIVED','PENABLE_WRITE','WDATA_TRANSFERRED','READ_ADDRESS_RECEIVED','PENABLE_READ','RDATA_TRANSFERRED'];
const AB=['I','WA','WS','WE','B','RS','RE','R'];
const [S_I,S_WA,S_WD,S_PW,S_WT,S_RA,S_PR,S_RT]=[0,1,2,3,4,5,6,7];
const hx=(v,n=8)=>'0x'+(v>>>0).toString(16).padStart(n,'0');
const hs=v=>'0x'+(v>>>0).toString(16);
const SC=[
 {id:'write',name:'Write, no wait states',desc:'One AXI write: AW and W are accepted together, one APB access with PREADY in the first cycle, then the B response.',
  aw:[{v:0x10,d:0}],w:[{v:0xCAFE0001,d:0}],ar:[],b:[{d:0}],r:[],waits:[0],plan:[{k:'W',a:0x10,v:0xCAFE0001}]},
 {id:'wr_rd',name:'Write then read the same word',desc:'The read is requested while the write is still in flight; the bridge serves it after the write finishes and returns the value that was written.',
  aw:[{v:0x10,d:0}],w:[{v:0xCAFE0001,d:0}],ar:[{v:0x10,d:3}],b:[{d:0}],r:[{d:0}],waits:[1,0],plan:[{k:'W',a:0x10,v:0xCAFE0001},{k:'R',a:0x10}]},
 {id:'waits',name:'APB wait states',desc:'The slave inserts 3 wait states on the write and 2 on the read. The access phase is stretched; PADDR, PWDATA and PWRITE hold still.',
  aw:[{v:0x20,d:0}],w:[{v:0x1234ABCD,d:0}],ar:[{v:0x20,d:2}],b:[{d:0}],r:[{d:0}],waits:[3,2],plan:[{k:'W',a:0x20,v:0x1234ABCD},{k:'R',a:0x20}]},
 {id:'err',name:'APB error → SLVERR',desc:'Addresses 0xF00..0xFFF are an error region in the slave. PSLVERR comes back with the access completed and the bridge answers SLVERR (2\'b10) on both B and R.',
  aw:[{v:0xF20,d:0}],w:[{v:0xDEAD0001,d:0}],ar:[{v:0xF24,d:2}],b:[{d:0}],r:[{d:0}],waits:[0,1],plan:[{k:'W',a:0xF20,v:0xDEAD0001},{k:'R',a:0xF24}]},
 {id:'bp',name:'Response back-pressure',desc:'The master delays BREADY and RREADY. BVALID and RVALID stay high with a stable response; the FSM waits in the transferred state and accepts nothing new.',
  aw:[{v:0x30,d:0}],w:[{v:0x55AA55AA,d:0}],ar:[{v:0x30,d:14}],b:[{d:10}],r:[{d:22}],waits:[0,0],plan:[{k:'W',a:0x30,v:0x55AA55AA},{k:'R',a:0x30}]},
 {id:'prio',name:'Read and write requested together',desc:'ARVALID and AWVALID are both high in IDLE. The read wins; the write is accepted after the read response has been taken.',
  aw:[{v:0x24,d:0}],w:[{v:0x0BADF00D,d:0}],ar:[{v:0x20,d:0}],b:[{d:0}],r:[{d:0}],waits:[0,0],plan:[{k:'R',a:0x20},{k:'W',a:0x24,v:0x0BADF00D}]},
];
// a testbench channel process: waits d edges, raises its signal, holds it until the partner signal is seen at an edge
function arm(x){ if(!x.q.length){x.sig=0;x.cur=null;x.cnt=-1;return;} x.cur=x.q.shift(); x.cnt=x.cur.d; x.sig=x.cnt===0?1:0; }
function mkdrv(items){ const x={q:items.map(i=>({...i})),sig:0,cur:null,cnt:-1,hs:0}; arm(x); return x; }
function drvEdge(x,partner){ x.hs=0; if(x.sig&&partner){ x.sig=0; x.hs=1; arm(x); } else if(x.cnt>0){ x.cnt--; if(x.cnt===0) x.sig=1; } }
const SIM={
 scenarios:SC.map(s=>({id:s.id,name:s.name,desc:s.desc})),
 options:[],
 chartTitle:'Transaction timeline',rowLabel:'transaction',chartWindow:60,maxCycles:120,preroll:2,
 chartHint:'one row per AXI transaction · cell = FSM state · hatched = waiting for PREADY / BREADY / RREADY',
 reset(id){
  const s=SC.find(x=>x.id===id)||SC[0];
  return {sc:s,state:S_I,sa:0,sw:0,paddr:0,pwdata:0,bresp:0,rresp:0,rdata:0,
   aw:mkdrv(s.aw),w:mkdrv(s.w),ar:mkdrv(s.ar),b:mkdrv(s.b),r:mkdrv(s.r),
   slv:{cnt:0,wi:0,mem:new Map()},txns:[],cur:null,plan:s.plan.map(p=>({...p,tx:null})),
   n:{wr:0,rd:0,err:0,wait:0},prev:null,doneAll:false};
 },
 eval(M){
  const s=M.state, cyc=M.cyc, ev=[], act=new Set(), A=(...x)=>x.forEach(i=>act.add(i));
  const arvalid=M.ar.sig, awvalid=M.aw.sig, wvalid=M.w.sig, bready=M.b.sig, rready=M.r.sig;
  const araddr=M.ar.cur?M.ar.cur.v:0, awaddr=M.aw.cur?M.aw.cur.v:0, wdata=M.w.cur?M.w.cur.v:0;
  // Moore outputs (rtl: output control block)
  const arready=s===S_RA, awready=s===S_WA, wready=s===S_WA, rvalid=s===S_RT, bvalid=s===S_WT;
  const psel=[S_WD,S_PW,S_RA,S_PR].includes(s), penable=s===S_PW||s===S_PR, pwrite=s===S_WD||s===S_PW;
  // slave model
  const access=psel&&penable, err=((M.paddr>>>8)&15)===15, pready=access&&M.slv.cnt===0, pslverr=pready&&err;
  const mw=(M.paddr>>>2)&63;
  const prdata=(pready&&!pwrite)?(err?0xBAD0BAD0:(M.slv.mem.get(mw)??0)):0xDEADBEEF;
  // next-state logic
  let ns=s;
  switch(s){
   case S_I: ns=arvalid?S_RA:awvalid?S_WA:S_I; break;
   case S_WA: ns=wvalid?S_WD:S_WA; break;
   case S_WD: ns=S_PW; break;
   case S_PW: ns=pready?S_WT:S_PW; break;
   case S_WT: ns=bready?S_I:S_WT; break;
   case S_RA: ns=S_PR; break;
   case S_PR: ns=pready?S_RT:S_PR; break;
   case S_RT: ns=rready?S_I:S_RT; break;
  }
  // register updates (computed here, applied in commit)
  const nx={sa:M.sa,sw:M.sw,paddr:M.paddr,pwdata:M.pwdata,bresp:M.bresp,rresp:M.rresp,rdata:M.rdata};
  if(s===S_I){ if(arvalid) nx.sa=araddr; else if(awvalid) nx.sa=awaddr; }
  const wload=(s===S_WA&&wvalid)||(s===S_WT&&wvalid);
  if(wload) nx.sw=wdata;
  let padSrc='';
  if(wload){ nx.paddr=M.sa; nx.pwdata=wdata; padSrc='w'; }
  else if(s===S_I&&arvalid){ nx.paddr=araddr; padSrc='ar'; }
  else if(s===S_RT&&rready){ nx.paddr=M.sa; padSrc='rt'; }
  if(s===S_PW&&pready) nx.bresp=pslverr?2:0;
  if(s===S_PR&&pready&&!pslverr) nx.rdata=prdata;
  if(s===S_PR&&pready) nx.rresp=pslverr?2:0;
  // transaction bookkeeping (display only)
  if(s===S_I&&(arvalid||awvalid)&&!M.cur){
    const kind=arvalid?'R':'W', a=arvalid?araddr:awaddr;
    const pl=M.plan.find(p=>!p.tx&&p.k===kind&&p.a===a);
    const t={id:M.txns.length,kind,addr:a,label:kind==='W'?`W ${hs(a)} ← ${hs(pl?pl.v:0)}`:`R ${hs(a)}`,color:`var(--t${M.txns.length%8})`,cells:{},notes:[],status:'in flight',
      wait:0,data:pl?pl.v:0};
    M.txns.push(t); M.cur=t; if(pl) pl.tx=t.id;
    ev.push(['ctl',`IDLE → ${ST[ns]}: ${kind==='R'?'ARVALID seen'+(awvalid?' (AWVALID too: the read wins)':''):'AWVALID seen'}`]);
  }
  const t=M.cur;
  if(t){
    const apb=[S_WD,S_PW,S_RA,S_PR].includes(s);
    const waiting=(s===S_PW||s===S_PR)?!pready:(s===S_WT?!bready:(s===S_RT?!rready:false));
    t.cells[cyc]={t:AB[s],col:apb?'--b2':(s===S_I?'--muted':'--b0'),cls:waiting?'st':'',title:ST[s]+(waiting?' (waiting)':'')};
    if((s===S_PW||s===S_PR)&&!pready){ t.wait++; M.n.wait++; }
    const note=(col,txt)=>t.notes.push({c:cyc,t:AB[s],col,txt});
    switch(s){
     case S_I: note('--muted',`request seen: ${t.kind==='R'?'ARVALID, address '+hs(araddr):'AWVALID, address '+hs(awaddr)}; address sampled`); break;
     case S_WA: note('--b0',`AWREADY = WREADY = 1${wvalid?'; WVALID seen, PADDR ← '+hs(M.sa)+', PWDATA ← '+hx(wdata):'; waiting for WVALID'}`); break;
     case S_WD: note('--b2',`APB setup: PSEL=1, PWRITE=1, PENABLE=0; PADDR=${hs(M.paddr)} PWDATA=${hx(M.pwdata)}`); break;
     case S_PW: note('--b2',pready?`APB access: PREADY=1${pslverr?', PSLVERR=1 (error region)':''}; ${err?'write blocked by the slave':'mem['+hs(M.paddr)+'] ← '+hx(M.pwdata)}`:`APB access: PREADY=0, wait state (${M.slv.cnt} left)`); break;
     case S_WT: note('--b0',`BVALID=1, BRESP=${M.bresp===2?'SLVERR (10)':'OKAY (00)'}${bready?'; BREADY seen, response taken':'; waiting for BREADY'}`); break;
     case S_RA: note('--b2',`ARREADY=1; APB setup: PSEL=1, PWRITE=0, PENABLE=0; PADDR=${hs(M.paddr)}`); break;
     case S_PR: note('--b2',pready?`APB access: PREADY=1${pslverr?', PSLVERR=1 (error region)':', PRDATA='+hx(prdata)}`:`APB access: PREADY=0, wait state (${M.slv.cnt} left)`); break;
     case S_RT: note('--b0',`RVALID=1, RDATA=${hx(M.rdata)}, RRESP=${M.rresp===2?'SLVERR (10)':'OKAY (00)'}${rready?'; RREADY seen, response taken':'; waiting for RREADY'}`); break;
    }
  }
  // events
  if(s===S_WA) ev.push(['ctl',`AWREADY = WREADY = 1${wvalid?'; WVALID seen → WRITE_DATA_RECEIVED':'; waiting for WVALID'}`]);
  if(s===S_WD) ev.push(['data',`APB setup phase: PSEL=1 PWRITE=1; PADDR=${hs(M.paddr)} PWDATA=${hx(M.pwdata)}`]);
  if(s===S_RA) ev.push(['data',`ARREADY=1; APB setup phase: PSEL=1 PWRITE=0; PADDR=${hs(M.paddr)}`]);
  if((s===S_PW||s===S_PR)&&!pready) ev.push(['info',`APB access, PREADY=0 (${M.slv.cnt} wait state${M.slv.cnt===1?'':'s'} left)`]);
  if((s===S_PW||s===S_PR)&&pready){
    if(pslverr) ev.push(['trap',`PREADY=1 with PSLVERR=1 at ${hs(M.paddr)}: ${s===S_PW?'BRESP':'RRESP'} ← SLVERR (2'b10)${s===S_PW?'; write blocked':'; RDATA not captured (PRDATA 0xBAD0BAD0)'}`]);
    else if(s===S_PW) ev.push(['data',`PREADY=1: slave writes mem[${hs(M.paddr)}] ← ${hx(M.pwdata)}; BRESP ← OKAY`]);
    else ev.push(['data',`PREADY=1: PRDATA=${hx(prdata)} captured into RDATA; RRESP ← OKAY`]);
  }
  if(s===S_WT&&!bready) ev.push(['info','BVALID=1, BREADY=0: response held (back-pressure)']);
  if(s===S_RT&&!rready) ev.push(['info','RVALID=1, RREADY=0: response held (back-pressure)']);
  let fin=false;
  if(s===S_WT&&bready){ ev.push(['ret',`B handshake: BRESP=${M.bresp===2?'SLVERR':'OKAY'}; write complete → IDLE`]); fin=true; }
  if(s===S_RT&&rready){ ev.push(['ret',`R handshake: RDATA=${hx(M.rdata)} RRESP=${M.rresp===2?'SLVERR':'OKAY'}; read complete → IDLE`]); fin=true; }
  let completes=null;
  if(fin&&t){ t.status=(M.bresp===2&&s===S_WT)||(M.rresp===2&&s===S_RT)?'complete, SLVERR':'complete, OKAY';
    completes=t; if(M.bresp===2&&s===S_WT||M.rresp===2&&s===S_RT) M.n.err++; if(s===S_WT) M.n.wr++; else M.n.rd++; }
  // active wires
  if(s===S_I&&(arvalid||awvalid)){ A('E01','E02','E13'); if(arvalid) A('E03','E12'); }
  if(s===S_WA){ if(wvalid) A('E01','E10','E03','E12'); }
  if(s===S_RT&&rready) A('E10','E12');
  A('E05','E06'); if(ns!==s) A('E04');
  if(arready||awready) A('E07');
  if(bvalid||rvalid) A('E08','E23');
  if(s===S_WT||s===S_RT) A('E09');
  if(psel) A('E14','E15','E16');
  if(s===S_PW||s===S_PR){ A('E17','E20','E27'); if(pready) A('E11'); }
  if(access&&pready&&pwrite&&!err) A('E18');
  if(access&&err) A('E19');
  if(pready&&!pwrite) A('E21');
  if(pslverr) A('E22');
  if(fin) A('E24');
  if(s!==S_I) A('E25'); if(pready||fin) A('E26');
  // done?
  const doneNow=fin&&(M.n.wr+M.n.rd)>=M.plan.length;
  const marks={}; if(s!==S_I&&s!==S_WA&&s!==S_RA) marks.st='live'; if(pslverr) marks.slv_err='trapped'; if((s===S_WT&&!bready)||(s===S_RT&&!rready)) marks.dec='stalled'; if((s===S_PW||s===S_PR)&&!pready) marks.slv_wait='stalled';
  const lit=['st','nxt','dec'];
  const vals={st:ST[s].replace('_RECEIVED','').replace('_STATE',''),samp:hs(M.sa),apbd:`${hs(M.paddr)} / ${M.pwdata?hx(M.pwdata):'0'}`,
    resp_r:`B${M.bresp.toString(2).padStart(2,'0')} R${M.rresp.toString(2).padStart(2,'0')}`,slv_wait:`cnt ${M.slv.cnt}`};
  const occ={M:[arvalid?`ARVALID ${hs(araddr)}`:'',awvalid?`AWVALID ${hs(awaddr)}`:'',wvalid?`WVALID`:'',bready?'BREADY':'',rready?'RREADY':''].filter(Boolean).join(' · ')||'idle',
    B:ST[s]+(waitingText()),S:psel?(penable?(pready?'access: PREADY':`access: wait (cnt ${M.slv.cnt})`):'setup'):'idle'};
  function waitingText(){ return ((s===S_PW||s===S_PR)&&!pready)||(s===S_WT&&!bready)||(s===S_RT&&!rready)?'  (waiting)':''; }
  const chips=[['ARVALID',arvalid,'ctl'],['AWVALID',awvalid,'ctl'],['WVALID',wvalid,'ctl'],['ARREADY',arready,'ctl'],['AW/WREADY',awready,'ctl'],['BVALID',bvalid,'ctl'],['RVALID',rvalid,'ctl'],['BREADY',bready,'ctl'],['RREADY',rready,'ctl'],
    ['PSEL',psel,'data'],['PENABLE',penable,'data'],['PWRITE',pwrite,'data'],['PREADY',pready,'mem'],['PSLVERR',pslverr,'trap']];
  const R={act:[...act],lit,marks,vals,occ,chips,events:ev,done:doneNow,doneText:'all transactions in the scenario are complete',
    sig:{s,ns,arvalid,awvalid,wvalid,bready,rready,pready,pslverr,access,err,psel,penable,pwrite,prdata,nx,padSrc,fin,mw,araddr,awaddr,wdata},completes};
  return R;
 },
 commit(M,R){
  const g=R.sig;
  // slave edge
  const sl=M.slv;
  if(g.psel&&!g.penable){ sl.cnt=M.sc.waits[sl.wi]??0; sl.wi++; }
  else if(g.access&&sl.cnt!==0) sl.cnt--;
  if(g.access&&g.pready&&g.pwrite&&!g.err) sl.mem.set(g.mw,M.pwdata>>>0);
  // master drivers: handshake uses the pre-edge ready of the bridge
  const arready=g.s===S_RA, awready=g.s===S_WA, wready=g.s===S_WA, bvalid=g.s===S_WT, rvalid=g.s===S_RT;
  drvEdge(M.ar,arready); drvEdge(M.aw,awready); drvEdge(M.w,wready); drvEdge(M.b,bvalid); drvEdge(M.r,rvalid);
  M.prev={sa:M.sa,sw:M.sw,paddr:M.paddr,pwdata:M.pwdata,bresp:M.bresp,rresp:M.rresp,rdata:M.rdata,cnt:sl.cnt,mem:new Map(sl.mem)};
  Object.assign(M,g.nx); M.state=g.ns;
  if(g.fin) M.cur=null;
 },
 stats(M){ return [['done',M.n.wr+M.n.rd+' / '+M.plan.length],['APB wait cyc',M.n.wait],['SLVERR',M.n.err]]; },
 listing(M){
  return M.plan.map((p,i)=>{ const t=p.tx!=null?M.txns[p.tx]:null;
   const lbl=p.k==='W'?`write ${hs(p.a)} ← ${hx(p.v)}`:`read  ${hs(p.a)}`;
   return {tx:t?t.id:null,badge:p.k,badgeCol:p.k==='W'?'--b1':'--b0',html:`${lbl} <span class="cm">${t?'# '+t.status:'# pending'}</span>`}; });
 },
 stateHTML(M,R){
  const pv=M.prev||{}; const reg=(n,v,cur)=>`<div class="reg${pv[cur]!==undefined&&pv[cur]!==v?' chg':''}"><span class="r">${n}</span><span class="v">${v}</span></div>`;
  let h='<div class="regs">'+reg('state',ST[M.state].replace('_RECEIVED','').replace('_STATE',''),'__')+reg('sampled_addr',hs(M.sa),'sa')+reg('PADDR',hs(M.paddr),'paddr')+reg('PWDATA',hx(M.pwdata),'pwdata')+
   reg('BRESP',M.bresp.toString(2).padStart(2,'0'),'bresp')+reg('RRESP',M.rresp.toString(2).padStart(2,'0'),'rresp')+reg('RDATA',hx(M.rdata),'rdata')+reg('slave cnt',String(M.slv.cnt),'cnt')+'</div>';
  const words=[...M.slv.mem.entries()].sort((a,b)=>a[0]-b[0]);
  h+='<div class="small muted">APB slave memory (64 × 32, written words only)</div><div class="regs">'+(words.length?words.map(([k,v])=>`<div class="reg"><span class="r">[${hs(k*4)}]</span><span class="v">${hx(v)}</span></div>`).join(''):'<span class="small muted">nothing written yet</span>')+'</div>';
  return h;
 },
};
