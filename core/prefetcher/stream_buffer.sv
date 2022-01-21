`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: UPC
// Engineer: Imad Al Assir
 
// Module Name: stream_buffer
// Project Name: Hardware Instruction Prefetcher for Ariane
// Description: The stream buffer lives alongside a cache and interacts with lower memory. 
//              In our case, it will live alongside the Instruction cache and send/receive requests to/from DRAM 
//              since Ariane only has a 1-level cache. 
//
// How it works:When a miss occurs, the stream buffer begins prefetching successive lines starting at the cacheline after the miss target.
//              As each prefetch request is sent out, the tag for the address is entered into the stream buffer, and the available
//              bit is set to false. When the prefetch data returns it is placed in the entry with its tag and the available bit is set to 1.
//////////////////////////////////////////////////////////////////////////////////


module stream_buffer import ariane_pkg::*; import wt_cache_pkg::*; #(
    parameter SB_DEPTH = 4, //Number of entries in the Stream Buffer
    parameter LOG2_PAGE_SIZE = 12,   //assuming 4K pages
    parameter logic [CACHE_ID_WIDTH-1:0]    TxId    = 0     //transaction ID, needed for Ariane
) (
    input logic clk_i,
    input logic rst_ni,
    input logic flush_i,
    input logic en_i,
    output logic SB_full_o, //stream buffer full
    output logic SB_empty_o, //stream buffer empty 
    
    //Cache Interface
    input logic  [riscv::PLEN-1:0] addr_fromCache_i,     //address that missed in cache
    output logic [ICACHE_LINE_WIDTH-1:0] pf_data_o,     //prefetched data
    input logic  pf_req_i,   //prefetch request, i.e. cache miss so need to check the stream buffer
    output logic found_block_o,     //indicates if the request is found in the stream buffer or not
    output logic ready_block_o,     //indicates if the cacheline requested is ready
    
    //Memory (AXI) Interface
    output ipref_req_t mem_data_o,
    output logic mem_data_req_o,   //memory request
    input ipref_rtrn_t mem_rtrn_i, //data coming from memory
    input logic mem_rtrn_vld_i,   //memory request completed
    input logic mem_data_ack_i,
        
    //To Performance Counters
    output logic ipref_hit_o,
    output logic ipref_miss_o
 );
    localparam ADDR_WIDTH = riscv::PLEN;
    localparam TAG_SIZE = ICACHE_TAG_WIDTH; //tag size according to ariane_pkg
    localparam CL_SIZE = ICACHE_LINE_WIDTH; //cache line size according to ariane_pkg (in bits)
    localparam CL_SIZE_BYTES = CL_SIZE >> 3; //cache line size according to ariane_pkg (in bytes)
    localparam SB_ADDR_DEPTH = SB_DEPTH > 1? $clog2(SB_DEPTH) : 1;

    
    //Stream Buffer Entries
    logic [SB_DEPTH-1:0][TAG_SIZE-1:0] SB_tags_n, SB_tags_q;
    logic [SB_DEPTH-1:0]               SB_available_n, SB_available_q;
    logic [SB_DEPTH-1:0][CL_SIZE-1:0]  SB_data_n, SB_data_q;
    
    // pointer to the read and write section of the queue
    logic [SB_ADDR_DEPTH-1:0] read_pointer_n, read_pointer_q, write_pointer_n, write_pointer_q;
    // keep a counter to keep track of the current queue status
    logic [SB_ADDR_DEPTH:0] status_cnt_n, status_cnt_q;  // this integer will be truncated by the synthesis tool
    //latest address requested from memory
    logic [ADDR_WIDTH-1:0] latest_addr_toMem_n, latest_addr_toMem_q;
      
////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////BEGIN LOGIC//////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
    
    logic  req_tag;
    assign req_tag = addr_fromCache_i[ICACHE_TAG_WIDTH+ICACHE_INDEX_WIDTH-1:ICACHE_INDEX_WIDTH];
    
    assign mem_data_o.tid = TxId;
        
    // status flags
    assign SB_full_o  = (status_cnt_q == SB_DEPTH );
    assign SB_empty_o = (status_cnt_q == 0);
    
    
    // read and write queue logic
    always_comb begin : read_write_comb
        // default assignment to avoid inferring unwanted latches
        read_pointer_n  = read_pointer_q;
        write_pointer_n = write_pointer_q;
        status_cnt_n    = status_cnt_q;
        latest_addr_toMem_n = latest_addr_toMem_q;
        pf_data_o       = (en_i && req_tag == SB_tags_q[read_pointer_q] && SB_available_q[read_pointer_q])? SB_data_q[read_pointer_q]: 0;     //if matching tag and available, read it.
        SB_tags_n       = SB_tags_q;
        SB_available_n  = SB_available_q;
        SB_data_n       = SB_data_q;
        
        found_block_o   = 0;
        mem_data_req_o  = 0;
        mem_data_o.paddr= '0;
        ready_block_o   = 0;
        ipref_hit_o     = 0;
        ipref_miss_o    = 0;
                
        if(en_i && pf_req_i && ~SB_empty_o) begin
            //tags match and data is available
            if (req_tag == SB_tags_q[read_pointer_q]) begin
                if(SB_available_q[read_pointer_q]) begin    //cacheline requested found and available; send it to the processor.
                    found_block_o = 1;
                    ready_block_o = 1;
                    ipref_hit_o  = 1;
                    pf_data_o = SB_data_q[read_pointer_q];
                    if (read_pointer_n == SB_DEPTH - 1) read_pointer_n = '0;
                    else read_pointer_n = read_pointer_q + 1;
                    
                    if(SB_full_o) begin //if the SB was full then issue a new prefetch now because the entry is now free after the read.
                        if(((latest_addr_toMem_q >> LOG2_PAGE_SIZE) << LOG2_PAGE_SIZE) == (((latest_addr_toMem_q+CL_SIZE_BYTES) >> LOG2_PAGE_SIZE) << LOG2_PAGE_SIZE)) begin
                            //insert the new request into the SB with available=0
                            SB_tags_n[write_pointer_n] = req_tag;
                            SB_available_n[write_pointer_n] = 0;
                            SB_data_n[write_pointer_n] = '0;
                            
                            mem_data_o.paddr = latest_addr_toMem_q + CL_SIZE_BYTES;
                            latest_addr_toMem_n = latest_addr_toMem_q + CL_SIZE_BYTES;
                            mem_data_req_o = 1;
                        end else begin
                                //error: cannot prefetch past page boundary because do not know its physical address, and it is highly unprobable that the next virtual page also corresponds to the adjacent physical page.
                                $warning(1, "cannot prefetch past page boundary");
                        end
                    end
                    
                    status_cnt_n = status_cnt_q - 1;
                    
                end 
                else begin  //cacheline requested found but not available yet.
                    found_block_o = 1;
                end
            //tags do not match, so this is a new stream: Flush the current buffer and issue a new request.
            end else if( req_tag != SB_tags_q[read_pointer_q]) begin 
                //flush the stream buffer...
                read_pointer_n  = '0;
                write_pointer_n = '0;
                status_cnt_n    = '0;
                latest_addr_toMem_n = '0;
                ipref_miss_o   = 1;
                //check if next cache line is within same page.
                //TODO: would it better to make 1 wire and assign to it the value of addr_fromCache_i+CL_SIZE, instead of doing it 3 times?
                if(((addr_fromCache_i >> LOG2_PAGE_SIZE) << LOG2_PAGE_SIZE) == (((addr_fromCache_i+CL_SIZE_BYTES) >> LOG2_PAGE_SIZE) << LOG2_PAGE_SIZE)) begin
                    //send request for next cache line to memory 
                    mem_data_o.paddr = addr_fromCache_i + CL_SIZE_BYTES;
                    latest_addr_toMem_n = addr_fromCache_i + CL_SIZE_BYTES;
                    mem_data_req_o  = 1;
                    //... and insert the new request into the SB with available=0
                    SB_tags_n[0] = mem_data_o.paddr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_SIZE];
                    SB_available_n[0] = 0;
                    SB_data_n[0] = '0;
                end else begin
                        //error: cannot prefetch past page boundary because do not know its physical address, and it is highly unprobable that the next virtual page also corresponds to the adjacent physical page.
                        $warning(1, "cannot prefetch past page boundary");
                end
            end
        end
        
        // push a new element to the SB when the memory request previously sent is received
        if (en_i && mem_rtrn_vld_i && ~SB_full_o ) begin
            // push the request onto the SB and set available bit to 1 
            SB_data_n[write_pointer_q] = mem_rtrn_i.data;
            SB_available_n[write_pointer_q] = 1;  
            
            // increment the write counter
            if (write_pointer_q == SB_DEPTH - 1) write_pointer_n = '0;
            else write_pointer_n = write_pointer_q + 1;
            
            // increment the overall counter
            status_cnt_n = status_cnt_q + 1;
            
            //fetch the new cache block IF NOT FULL after that write 
            if(status_cnt_q < SB_DEPTH-1 ) begin //because if it were >= SB_DEPTH-1, then the above write filled it
                if(((latest_addr_toMem_q >> LOG2_PAGE_SIZE) << LOG2_PAGE_SIZE) == (((latest_addr_toMem_q+CL_SIZE_BYTES) >> LOG2_PAGE_SIZE) << LOG2_PAGE_SIZE)) begin
                    //insert the new request into the SB with available=0
                    SB_tags_n[write_pointer_n] = req_tag;
                    SB_available_n[write_pointer_n] = 0;
                    SB_data_n[write_pointer_n] = '0;
                    
                    mem_data_o.paddr = latest_addr_toMem_q + CL_SIZE_BYTES;
                    latest_addr_toMem_n = latest_addr_toMem_q + CL_SIZE_BYTES;
                    mem_data_req_o  = 1;
                end else begin
                        //error: cannot prefetch past page boundary because do not know its physical address, and it is highly unprobable that the next virtual page also corresponds to the adjacent physical page.
                        $warning(1, "cannot prefetch past page boundary");
                end
            end else begin 
                $warning(1, "Instruction Stream Buffer Full");
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
          latest_addr_toMem_q <= '0;
        end else begin
          SB_tags_q      <= SB_tags_n;
          SB_available_q <= SB_available_n;
          SB_data_q      <= SB_data_n;
          latest_addr_toMem_q <= latest_addr_toMem_n;
        end
    end
    
    
    //TODO: on write-back, need to invalidate stream buffer entries that have the same address as the current write address. 
endmodule
