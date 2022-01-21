`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: UPC
// Engineer: Imad Al Assir 
// Module Name: stream_buffer_axi_wrapper
// Project Name: Hardware Instruction Prefetcher for Ariane
// Description: wrapper module to connect the I-prefetcher to a 64bit AXI bus
// 
//////////////////////////////////////////////////////////////////////////////////


module stream_buffer_axi_wrapper import ariane_pkg::*; (
    input  logic clk_i,
    input  logic rst_ni,    //reset the stream buffer
    input  logic flush_i,   //flush the stream buffer
    input  logic en_i,      //enable the prefetcher
    output logic SB_full_o, //stream buffer full
    output logic SB_empty_o,//stream buffer empty 
    
    //to performance counters
    output logic ipref_hit_o,
    output logic ipref_miss_o,
    
    //to I$
    //Cache Interface
    input  logic [riscv::PLEN-1:0] addr_fromCache_i,     //address that missed in cache
    output logic [ICACHE_LINE_WIDTH-1:0] pf_data_o,     //prefetched data
    input  logic pf_req_i,   //prefetch request, i.e. cache miss so need to check the stream buffer
    output logic found_block_o,     //indicates if the request is found in the stream buffer or not
    output logic ready_block_o,     //indicates if the cacheline requested is ready
    
    // AXI refill port
    output ariane_axi::req_t  axi_req_o,
    input  ariane_axi::resp_t axi_resp_i
    );

  localparam AxiNumWords = (ICACHE_LINE_WIDTH/64) * (ICACHE_LINE_WIDTH  > DCACHE_LINE_WIDTH)  +
                           (DCACHE_LINE_WIDTH/64) * (ICACHE_LINE_WIDTH <= DCACHE_LINE_WIDTH) ;

  logic                                  ipref_mem_rtrn_vld;
  ipref_rtrn_t                           ipref_mem_rtrn;
  logic                                  ipref_mem_data_req;
  logic                                  ipref_mem_data_ack;
  ipref_req_t                            ipref_mem_data;

  logic                                  axi_rd_req;
  logic                                  axi_rd_gnt;
  logic [63:0]                           axi_rd_addr;
  logic [$clog2(AxiNumWords)-1:0]        axi_rd_blen;
  logic [1:0]                            axi_rd_size;
  logic [$size(axi_resp_i.r.id)-1:0]     axi_rd_id_in;
  logic                                  axi_rd_rdy;
  logic                                  axi_rd_lock;
  logic                                  axi_rd_last;
  logic                                  axi_rd_valid;
  logic [63:0]                           axi_rd_data;
  logic [$size(axi_resp_i.r.id)-1:0]     axi_rd_id_out;
  logic                                  axi_rd_exokay;

  logic                                  req_valid_d, req_valid_q;
  ipref_req_t                            req_data_d,  req_data_q;
  logic                                  first_d,     first_q;
  logic [ICACHE_LINE_WIDTH/64-1:0][63:0] rd_shift_d,  rd_shift_q;

  // Keep read request asserted until we have an AXI grant. This is not guaranteed by icache (but
  // required by AXI).
  assign req_valid_d           = ~axi_rd_gnt & (ipref_mem_data_req | req_valid_q);

  // Update read request information on a new request
  assign req_data_d            = (ipref_mem_data_req) ? ipref_mem_data : req_data_q;

  // We have a new or pending read request
  assign axi_rd_req            = ipref_mem_data_req | req_valid_q;
  assign axi_rd_addr           = {{64-riscv::PLEN{1'b0}}, req_data_d.paddr};

  // Fetch a full cache line when the prefetcher requests it
  assign axi_rd_blen           = ariane_pkg::ICACHE_LINE_WIDTH/64-1;
  assign axi_rd_size           = 2'b11;
  assign axi_rd_id_in          = req_data_d.tid;
  assign axi_rd_rdy            = 1'b1;
  assign axi_rd_lock           = 1'b0;

  // Immediately acknowledge read request. This is an implicit requirement for the icache.
  assign ipref_mem_data_ack   = ipref_mem_data_req;

  // Return data as soon as last word arrives
  assign ipref_mem_rtrn_vld   = axi_rd_valid & axi_rd_last;
  assign ipref_mem_rtrn.data  = rd_shift_d;
  assign ipref_mem_rtrn.tid   = req_data_q.tid;

  // -------
  // I-Prefetcher
  // -------
  stream_buffer #(
    .SB_DEPTH           ( 4             ), //Number of entries in the Stream Buffer
    .LOG2_PAGE_SIZE     ( 12            ),   //assuming 4K pages
    .TxId               ( 0             )     //transaction ID, needed for Ariane
  ) i_ipref (
    .clk_i      (clk_i     ),
    .rst_ni     (rst_ni    ),
    .flush_i    (flush_i   ),
    .en_i       (en_i      ),
    .SB_full_o  (SB_full_o ), //stream buffer full
    .SB_empty_o (SB_empty_o), //stream buffer empty 
    
    .addr_fromCache_i (addr_fromCache_i),     //address that missed in cache
    .pf_data_o        (pf_data_o       ),     //prefetched data
    .pf_req_i         (pf_req_i        ),   //prefetch request, i.e. cache miss so need to check the stream buffer
    .found_block_o    (found_block_o   ),     //indicates if the request is found in the stream buffer or not
    .ready_block_o    (ready_block_o   ),
    
    .mem_rtrn_vld_i     ( ipref_mem_rtrn_vld ), 
    .mem_rtrn_i         ( ipref_mem_rtrn     ), 
    .mem_data_req_o     ( ipref_mem_data_req ), 
    .mem_data_ack_i     ( ipref_mem_data_ack ), 
    .mem_data_o         ( ipref_mem_data     ),
    
    .ipref_hit_o        ( ipref_hit_o        ),
    .ipref_miss_o       ( ipref_miss_o       )
  );

  // --------
  // AXI shim
  // --------
    axi_shim #(
    .AxiNumWords     ( AxiNumWords            ),
    .AxiIdWidth      ( $size(axi_resp_i.r.id) )
  ) i_axi_shim (
    .clk_i           ( clk_i             ),
    .rst_ni          ( rst_ni            ),
    .rd_req_i        ( axi_rd_req        ),
    .rd_gnt_o        ( axi_rd_gnt        ),
    .rd_addr_i       ( axi_rd_addr       ),
    .rd_blen_i       ( axi_rd_blen       ),
    .rd_size_i       ( axi_rd_size       ),
    .rd_id_i         ( axi_rd_id_in      ),
    .rd_rdy_i        ( axi_rd_rdy        ),
    .rd_lock_i       ( axi_rd_lock       ),
    .rd_last_o       ( axi_rd_last       ),
    .rd_valid_o      ( axi_rd_valid      ),
    .rd_data_o       ( axi_rd_data       ),
    .rd_id_o         ( axi_rd_id_out     ),
    .rd_exokay_o     ( axi_rd_exokay     ),
    .wr_req_i        ( '0                ), 
    .wr_gnt_o        (                   ),
    .wr_addr_i       ( '0                ),
    .wr_data_i       ( '0                ),
    .wr_be_i         ( '0                ),
    .wr_blen_i       ( '0                ),
    .wr_size_i       ( '0                ),
    .wr_id_i         ( '0                ),
    .wr_lock_i       ( '0                ),
    .wr_atop_i       ( '0                ),
    .wr_rdy_i        ( '0                ),
    .wr_valid_o      (                   ),
    .wr_id_o         (                   ),
    .wr_exokay_o     (                   ),
    .axi_req_o       ( axi_req_o         ),
    .axi_resp_i      ( axi_resp_i        )
  );

  // Buffer burst data in shift register
  always_comb begin : p_axi_rtrn_shift
    first_d    = first_q;
    rd_shift_d = rd_shift_q;

    if (axi_rd_valid) begin
      first_d    = axi_rd_last;
      rd_shift_d = {axi_rd_data, rd_shift_q[ICACHE_LINE_WIDTH/64-1:1]};

      // If this is a single word transaction, we need to make sure that word is placed at offset 0
      if (first_q) begin
        rd_shift_d[0] = axi_rd_data;
      end
    end
  end

  // Registers
  always_ff @(posedge clk_i or negedge rst_ni) begin : p_rd_buf
    if (!rst_ni) begin
      req_valid_q <= 1'b0;
      req_data_q  <= '0;
      first_q     <= 1'b1;
      rd_shift_q  <= '0;
    end else begin
      req_valid_q <= req_valid_d;
      req_data_q  <= req_data_d;
      first_q     <= first_d;
      rd_shift_q  <= rd_shift_d;
    end
  end

endmodule
