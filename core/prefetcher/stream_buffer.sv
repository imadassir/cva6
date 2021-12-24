`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: UPC
// Engineer: Imad Al Assir
 
// Module Name: stream_buffer
// Project Name: Hardware Instruction Prefetcher for Ariane
// Description: The stream buffer lives alongside a cache and interacts with lower memory. 
//              In our case, it will live alongside the Instruction cache and send/receive requests to/from DRAM 
//              since Ariane has only 1-level cache. 
//
// How it works:When a miss occurs, the stream buffer begins prefetching successive lines starting at the miss target.
//              As each prefetch request is sent out, the tag for the address is entered into the stream buffer, and the available
//              bit is set to false. When the prefetch data returns it is placed in the entry with its tag and the available bit is set to 1.
//////////////////////////////////////////////////////////////////////////////////


module stream_buffer import ariane_pkg::*; #(
    parameter SB_DEPTH = 4, //Number of entries in the Stream Buffer
    parameter SB_ADDR_DEPTH = SB_DEPTH > 1? $clog2(SB_DEPTH) : 1,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter TAG_SIZE = ICACHE_TAG_WIDTH, //tag size according to ariane_pkg
    parameter CL_SIZE = ICACHE_LINE_WIDTH //cache line size according to ariane_pkg (in bits)
) (
    input logic clk_i,
    input logic rst_ni,
    input logic flush_i,
    input logic en_i,
    output logic SB_full_o, //stream buffer full
    output logic SB_empty_o, //stream buffer empty 
    
    //Cache Interface
    input logic [ADDR_WIDTH-1:0] addr_fromCache_i,     //address that missed in cache
    output logic [CL_SIZE-1:0] pf_data_o,     //prefetched data
    input logic  pf_req_i,   //prefetch request, i.e. cache miss so need to check the stream buffer
    output logic found_block_o,     //indicates if the request is found in the stream buffer or not
    
    //Memory (DRAM) Interface
    output logic [ADDR_WIDTH-1:0] addr_toMem_o,     //address of memory request
    output logic req_toMem_o,   //memory request
    input logic [CL_SIZE-1:0] data_fromMem_i,   //data coming from memory
    input logic mem_req_done_i  //memory request completed
    //input logic req_fromMem_valid //the request from memory is valid (i.e. not bypassing page boundaries). TODO: check if should be input or interior logic
 );
    
    //Stream Buffer Entries
    logic [SB_DEPTH-1:0][TAG_SIZE-1:0] SB_tags_n, SB_tags_q;
    logic [SB_DEPTH-1:0]               SB_available_n, SB_available_q;
    logic [SB_DEPTH-1:0][CL_SIZE-1:0]  SB_data_n, SB_data_q;
    
    // pointer to the read and write section of the queue
    logic [SB_ADDR_DEPTH-1:0] read_pointer_n, read_pointer_q, write_pointer_n, write_pointer_q;
    // keep a counter to keep track of the current queue status
    logic [SB_ADDR_DEPTH:0] status_cnt_n, status_cnt_q;  // this integer will be truncated by the synthesis tool
  
////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////BEGIN LOGIC//////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
    
    logic  req_tag;
    assign req_tag = addr_fromCache_i[ADDR_WIDTH-1:ADDR_WIDTH-TAG_SIZE]; //TODO: double check that
    
    // status flags
    assign SB_full_o  = (status_cnt_q == SB_DEPTH );
    assign SB_empty_o = (status_cnt_q == 0);
    
    
    // read and write queue logic
    always_comb begin : read_write_comb
        // default assignment to avoid inferring unwanted latches
        read_pointer_n  = read_pointer_q;
        write_pointer_n = write_pointer_q;
        status_cnt_n    = status_cnt_q;
        pf_data_o       = (req_tag == SB_tags_q[read_pointer_q] && SB_available_q[read_pointer_q])? SB_data_q[read_pointer_q]: 0;     //if matching tag and available, read it.
        SB_tags_n       = SB_tags_q;
        SB_available_n  = SB_available_q;
        SB_data_n       = SB_data_q;
        
        found_block_o   = 0;
        req_toMem_o     = 0;
        addr_toMem_o    = '0;
        
        //TODO: should I read first or write first? Doesn't matter cause conditions are based on q
        
        if(pf_req_i && ~SB_empty_o) begin
            //tags match and data is available
            if(req_tag == SB_tags_q[read_pointer_q] && SB_available_q[read_pointer_q]) begin
                //read is the default case handled above ...
                //... but increment the read pointer, ...
                if (read_pointer_n == SB_DEPTH - 1) read_pointer_n = '0;
                else read_pointer_n = read_pointer_q + 1;
                //...decrement the overall count ...
                status_cnt_n = status_cnt_q - 1;
                //... and notify the processor that the request was sucessful
                found_block_o = 1;
            end
            //tags match but data not available yet
            else if(req_tag == SB_tags_q[read_pointer_q] && ~SB_available_q[read_pointer_q]) begin  
                //stall and wait for the memory to send the request TODO: how to stall?
                req_toMem_o = 1; 
                addr_toMem_o= addr_fromCache_i;
            end
            //tags do not match, so this is a new stream: Flush the current buffer and issue a new request.
            else if( req_tag != SB_tags_q[read_pointer_q]) begin 
                //flush the stream buffer...
                read_pointer_n  = '0;
                write_pointer_n = '0;
                status_cnt_n    = '0;
                
                //and insert the new request into the SB with available=0
                SB_tags_n[write_pointer_n] = req_tag;
                SB_available_n[write_pointer_n] = 0;
                SB_data_n[write_pointer_n] = '0;
                
                //send request to memory
                req_toMem_o = 1; 
                addr_toMem_o= addr_fromCache_i;
                
                //wait for request 
                //TODO: should I say that the block was found in this case?
            end
        end
        
        // push a new element to the SB when the memory request previously sent is received
        if (mem_req_done_i) begin
            // push the request onto the SB and set available bit to 1 
            SB_data_n[write_pointer_q] = data_fromMem_i;
            SB_available_n[write_pointer_q] = 1;  
            
            // increment the write counter
            if (write_pointer_q == SB_DEPTH - 1) write_pointer_n = '0;
            else write_pointer_n = write_pointer_q + 1;
            
            // increment the overall counter
            status_cnt_n = status_cnt_q + 1;
            
            //fetch the new cache block IF NOT FULL after that write 
            if(status_cnt_q < SB_DEPTH-1 ) begin //because if it were >= SB_DEPTH-1, then the above write filled it
                addr_toMem_o = data_fromMem_i + CL_SIZE; //TODO: check what is the next read address, and check if it is in the same page.
                req_toMem_o  = 1;
            end  
        end
    end
    
    // sequential process to update utility pointers and counters
    always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      read_pointer_q  <= '0;
      write_pointer_q <= '0;
      status_cnt_q    <= '0;
    end else begin
      unique case (1'b1)
        // Flush the FIFO
        flush_i: begin
          read_pointer_q  <= '0;
          write_pointer_q <= '0;
          status_cnt_q    <= '0;
        end
        // If we are not flushing, update the pointers
        default: begin
          read_pointer_q  <= read_pointer_n;
          write_pointer_q <= write_pointer_n;
          status_cnt_q    <= status_cnt_n;
        end
      endcase
    end
    end
    
    always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      SB_tags_q      <= '0;
      SB_available_q <= '0;
      SB_data_q      <= '0;
    end else begin
      SB_tags_q      <= SB_tags_n;
      SB_available_q <= SB_available_n;
      SB_data_q      <= SB_data_n;
    end
    end
    
    
    //TODO: on write-back, need to invalidate stream buffer entries that have the same address as the current write address. 
endmodule
