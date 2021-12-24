`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Design Name: 
// Module Name: stream_buffer_tb
// Project Name: Hardware Instruction Prefetcher for Ariane
// Description: Stream Buffer Testbench
// 
// Dependencies: stream_buffer
//////////////////////////////////////////////////////////////////////////////////


module stream_buffer_tb();
    localparam int SB_DEPTH = 4; //Number of entries in the Stream Buffer
    localparam int SB_ADDR_DEPTH = 2;
    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 32;
    localparam int TAG_SIZE = 15; //tag size     TODO: check tag size in Ariane
    localparam int CL_SIZE = 64; //cache line size 
    
    
    reg clk_i, rst_ni, flush_i, en_i, mem_req_done_i, pf_req_i;
    wire SB_full_o, SB_empty_o, found_block_o, req_toMem_o;
    reg [ADDR_WIDTH-1:0] addr_fromCache_i;
    wire[ADDR_WIDTH-1:0] addr_toMem_o;
    reg [CL_SIZE-1:0] data_fromMem_i;
    wire[CL_SIZE-1:0] pf_data_o;
    

    stream_buffer #(
        .SB_DEPTH       (SB_DEPTH     ), //Number of entries in the Stream Buffer
        .SB_ADDR_DEPTH  (SB_ADDR_DEPTH),
        .DATA_WIDTH     (DATA_WIDTH   ),
        .ADDR_WIDTH     (ADDR_WIDTH   ),
        .TAG_SIZE       (TAG_SIZE     ), //tag size     TODO: check tag size in Ariane
        .CL_SIZE        (CL_SIZE      ) //cache line size
    ) dut (
        .clk_i      (clk_i     ),
        .rst_ni     (rst_ni    ),
        .flush_i    (flush_i   ),
        .en_i       (en_i      ),
        .SB_full_o  (SB_full_o ), //stream buffer full
        .SB_empty_o (SB_empty_o), //stream buffer empty 
        
        //Cache Interface
        .addr_fromCache_i (addr_fromCache_i),     //address that missed in cache
        .pf_data_o        (pf_data_o       ),     //prefetched data
        .pf_req_i         (pf_req_i        ),   //prefetch request, i.e. cache miss so need to check the stream buffer
        .found_block_o    (found_block_o   ),     //indicates if the request is found in the stream buffer or not
        
        //Memory (DRAM) Interface
        .addr_toMem_o     (addr_toMem_o  ),   //address of memory request
        .req_toMem_o      (req_toMem_o   ),   //memory request
        .data_fromMem_i   (data_fromMem_i),   //data coming from memory
        .mem_req_done_i   (mem_req_done_i)   //memory request completed
    );
 
    initial begin
    
    
    end
 
endmodule
