// Formal properties for the Gray-pointer dual-clock FIFO, attached with `bind` (RTL untouched).
// wclk and rclk are free, independent inputs (sby multiclock): any interleaving of edges is explored.
//
// Environment contract (from the RTL header): resets are asserted together at the start and are never re-asserted;
// each domain may release its reset at an arbitrary later time.
module async_fifo_props #(parameter int WIDTH = 4, parameter int DEPTH = 4) (
  input logic        wclk, wrst, wvalid, wready,
  input logic [WIDTH-1:0] wdata,
  input logic        rclk, rrst, rvalid, rready,
  input logic [WIDTH-1:0] rdata,
  input logic [$clog2(DEPTH):0] wb, wg, rb, rg, wg1, wg2, rg1, rg2,
  input logic [WIDTH-1:0] storage [DEPTH]
);
  localparam int A = $clog2(DEPTH);
  logic wpv = 1'b0, rpv = 1'b0;                      // each domain has seen at least one clock edge
  always @(posedge wclk) wpv <= 1'b1;
  always @(posedge rclk) rpv <= 1'b1;
  wire past_valid = wpv && rpv;

  // ---- reset contract
  always @* if (!past_valid) assume (wrst && rrst);      // both resets asserted until both clocks have ticked
  logic wrst_released = 1'b0, rrst_released = 1'b0;
  always @(posedge wclk) if (!wrst) wrst_released <= 1'b1;
  always @(posedge rclk) if (!rrst) rrst_released <= 1'b1;
  always @* begin
    if (wrst_released) assume (!wrst);               // never re-asserted
    if (rrst_released) assume (!rrst);
  end
  wire live = !wrst && !rrst;

  // ---- environment: a producer must hold its request until accepted (matches the RTL's own assertion)
  logic w_stall_q = 1'b0; logic [WIDTH-1:0] w_data_q = '0;
  always @(posedge wclk) begin w_stall_q <= wvalid && !wready; w_data_q <= wdata; end
  always @* if (w_stall_q && !wrst) assume (wvalid && wdata == w_data_q);

  // ---- S1/S2: no overflow, no underflow, occupancy bound (observing both domains' true pointers)
  wire [A:0] occupancy = wb - rb;
  always @* if (live) begin
    assert (occupancy <= (A+1)'(DEPTH));
    if (wvalid && wready) assert (occupancy != (A+1)'(DEPTH));      // a write is never accepted into a full FIFO
    if (rvalid && rready) assert (wb != rb);                         // a read is never accepted from an empty FIFO
    if (rvalid) assert (wb != rb);                                   // `valid` only when data really is there
    if (wready) assert (occupancy != (A+1)'(DEPTH));                 // `ready` only when there is room
  end

  // ---- S3: Gray pointers change by at most one bit per source-clock edge
  logic [A:0] wg_q = '0, rg_q = '0;
  always @(posedge wclk) wg_q <= wg;
  always @(posedge rclk) rg_q <= rg;
  always @(posedge wclk) if (past_valid && !wrst) assert (((wg ^ wg_q) & ((wg ^ wg_q) - 1'b1)) == '0);
  always @(posedge rclk) if (past_valid && !rrst) assert (((rg ^ rg_q) & ((rg ^ rg_q) - 1'b1)) == '0);

  // ---- S4: data integrity and ordering via a ghost FIFO driven only by the handshake events
  //          (written on wclk when a write is accepted, popped on rclk when a read is accepted).
  //          Independent of the DUT's own pointers: a pointer or write-enable bug makes the two diverge.
  logic [WIDTH-1:0] gq [DEPTH];
  logic [A:0]       gw = '0, gr = '0;
  always @(posedge wclk) if (!wrst && wvalid && wready) begin gq[gw[A-1:0]] <= wdata; gw <= gw + 1'b1; end
  always @(posedge rclk) if (!rrst && rvalid && rready) gr <= gr + 1'b1;
  always @* if (live) begin
    assert (gw - gr <= (A+1)'(DEPTH));                // the ghost never over/underflows either
    if (rvalid) begin
      assert (gw != gr);                              // data offered means the ghost has something too
      assert (rdata == gq[gr[A-1:0]]);                // the DUT offers exactly the oldest unread word
    end
  end

`ifdef STRENGTHEN
  // ---- helper invariants for the unbounded (k-induction) proof only.
  // Ghost binary shadows of the Gray synchronizer chains: wb -> gwb1 -> gwb2 (read domain), rb -> grb1 -> grb2 (write domain).
  logic [A:0] gwb1 = '0, gwb2 = '0, grb1 = '0, grb2 = '0;
  // (reset like the DUT's synchronizers: the read-domain chain is held in reset by rrst, the write-domain chain by wrst)
  always @(posedge rclk) if (rrst) begin gwb1 <= '0; gwb2 <= '0; end else begin gwb1 <= wb; gwb2 <= gwb1; end
  always @(posedge wclk) if (wrst) begin grb1 <= '0; grb2 <= '0; end else begin grb1 <= rb; grb2 <= grb1; end
  function automatic logic [A:0] g(input logic [A:0] b); return (b >> 1) ^ b; endfunction
  always @* if (live) begin
    assert (gw == wb);                                // the ghost counters track the DUT's binary pointers
    assert (gr == rb);
    assert (wg == g(wb));
    assert (rg == g(rb));
    assert (wg1 == g(gwb1));                          // the synchronizer chains carry Gray codes of earlier pointers
    assert (wg2 == g(gwb2));
    assert (rg1 == g(grb1));
    assert (rg2 == g(grb2));
    assert ((wb - gwb1) <= (wb - rb));                // ordering: rb <= gwb2 <= gwb1 <= wb (modular, within one FIFO depth)
    assert ((gwb1 - gwb2) <= (gwb1 - rb));
    assert ((gwb2 - rb) <= (A+1)'(DEPTH));
    assert ((rb - grb1) <= (wb - grb1));
    assert ((grb1 - grb2) <= (grb1 - grb2));
    for (int i = 0; i < DEPTH; i++)                   // every occupied slot holds exactly the ghost's word
      if (((A+1)'(i) - {1'b0, gr[A-1:0]}) % (A+1)'(DEPTH) < (gw - gr)) assert (storage[i] == gq[i]);
  end
`endif

  // ---- cover: nothing above is vacuous
  always @* begin
    cover (live && wvalid && wready);
    cover (live && rvalid && rready);
    cover (live && occupancy == (A+1)'(DEPTH));                        // the FIFO really fills
    cover (live && rvalid && rready && gw - gr >= (A+1)'(2));            // reading while more words are queued behind
  end
endmodule

bind async_fifo async_fifo_props #(.WIDTH(WIDTH), .DEPTH(DEPTH)) props (.*, .wg1(wg1), .wg2(wg2), .rg1(rg1), .rg2(rg2));
