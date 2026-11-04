// C20: RAM-backed, frame-quiescent atomic configuration, bounded directory.
// No asynchronous reset of memories. init_done follows a sequential clear.
module snmp_config_table #(
    parameter TX_ENTRIES=128, RX_ENTRIES=4096,
    parameter TX_HASH_SLOTS=256, RX_HASH_SLOTS=8192,
    parameter MAX_PROBES=32, SHARED_OVERHEAD_CYCLES=512
) (
    input wire clk, rst_n,
    input wire wr_valid, wr_bank,
    input wire [12:0] wr_index,
    input wire [3:0] wr_word,
    input wire [31:0] wr_data,
    output wire wr_ready,
    output reg wr_error,
    input wire rd_valid, rd_shadow, rd_bank,
    input wire [12:0] rd_index,
    input wire [3:0] rd_word,
    output wire rd_ready,
    output reg rd_result_valid, rd_error,
    input wire rd_result_ready,
    output reg [31:0] rd_data,
    output reg [15:0] rd_version,
    input wire commit_valid, quiescent, budget_only,
    output wire commit_ready, freeze,
    output reg pending, applied,
    output reg result_valid, result_ok,
    input wire result_ready,
    output reg [2:0] result_code,
    output reg [15:0] version, result_version,
    output reg init_done,
    input wire q_valid, q_dir,
    input wire [12:0] q_index,
    input wire [15:0] q_vl,
    output wire q_ready,
    output reg q_result_valid, q_found, q_error,
    input wire q_result_ready,
    output reg [12:0] q_result_index,
    output reg [255:0] q_config,
    output reg [15:0] q_version,
    input wire [15:0] mgmt_max_client,
    input wire [2:0] mgmt_period_exp,
    input wire [31:0] line_limit_kbps, service_limit_cycles,
    output reg [15:0] active_mgmt_max_client,
    output reg [2:0] active_mgmt_period_exp,
    output reg [31:0] active_line_limit_kbps, active_service_limit_cycles,
    output reg [31:0] active_line_sum, active_service_sum,
    output reg active_admitted,
    output reg [2:0] active_max_bag_exp,
    output reg [15:0] active_tx_count, active_rx_count
);
    localparam TX_WORDS=TX_ENTRIES*8, RX_WORDS=RX_ENTRIES*8;
    localparam CFG_WORDS=2*(TX_WORDS+RX_WORDS);
    localparam DIR_WORDS=2*(TX_HASH_SLOTS+RX_HASH_SLOTS);
    localparam ONE_WORDS=TX_WORDS+RX_WORDS;
    localparam S_INIT=0, S_IDLE=1, S_RD_ISSUE=2, S_RD_CAP=3,
      S_FETCH_ISSUE=4,S_FETCH_CAP=5,S_QUERY_DONE=6,
      S_HASH_READ=7,S_HASH_CHECK=8,S_HASH_WRITE=9,
      S_CLEAR=10,S_VALIDATE=11,S_NEXT=12,S_DIV=13,S_BUDGET=14,
      S_MGMT=15,S_TOTAL=16,S_QUIET=17,S_COPY_READ=18,S_COPY_CAP=19,
      S_COPY_WRITE=20,S_FAIL=21;
    reg [4:0] state;
    // One logical word space, physically bounded 2048-word RAM banks.
    // A >64K-word inferred array produced an official VO with a 16-bit
    // address parameter wired to 12 bits. Preserve that failure; do not
    // patch its VO. Bank the source RAM so the native export has bounded
    // address ports. Logical capacity, addressing and latency stay intact.
    localparam CFG_BANK_WORDS=2048;
    localparam CFG_BANKS=(CFG_WORDS+CFG_BANK_WORDS-1)/CFG_BANK_WORDS;
    wire [CFG_BANKS*32-1:0] cfg_bank_q;
    reg [5:0] cfg_read_bank;
    reg [31:0] dir_mem[0:DIR_WORDS-1];
    wire [31:0] cfg_q;
    reg [31:0] dir_q;
    reg cfg_en,cfg_we,dir_en,dir_we;
    reg [16:0] cfg_addr;
    reg [14:0] dir_addr;
    reg [31:0] cfg_wdata,dir_wdata;
    reg active_bank,frozen_budget_only;
    reg [16:0] clear_count,copy_count;
    reg [31:0] copy_data;
    reg cur_dir,cur_bank,rd_target_shadow,query_mode,hash_query;
    reg [12:0] cur_index,hash_slot;
    reg [3:0] cur_word;
    reg [15:0] search_vl;
    reg [6:0] probe_count;
    reg [255:0] entry;
    reg [2:0] fail_code,max_bag;
    reg [15:0] tx_count,rx_count;
    reg [15:0] frozen_mgmt;
    reg [2:0] frozen_period;
    reg [31:0] frozen_line,frozen_service,line_sum,service_sum,burst_sum;
    reg [7:0] min_period;
    reg div_mgmt;
    reg [15:0] div_shift,div_quot,wire_cycles;
    reg [2:0] div_rem;
    reg [4:0] div_count;
    wire [3:0] rem_step={div_rem,div_shift[15]};
    wire [2:0] rem_next=rem_step>=5 ? rem_step-5:rem_step;
    wire [15:0] quot_next={div_quot[14:0],rem_step>=5};
    wire [31:0] rt_service=((({16'd0,entry[223:208]}-47)<<2)+43+256+{16'd0,wire_cycles}+128+SHARED_OVERHEAD_CYCLES+32);
    wire [31:0] management_service=({16'd0,frozen_mgmt}<<1)+{16'd0,wire_cycles}+128+SHARED_OVERHEAD_CYCLES+32;
    wire [15:0] management_wire=(frozen_mgmt+16'd4<64)?16'd64:frozen_mgmt+16'd4;
    wire idle_ok=rst_n && init_done && state==S_IDLE && !pending;
    assign commit_ready=idle_ok && !result_valid;
    assign wr_ready=idle_ok && !commit_valid;
    assign rd_ready=idle_ok && !commit_valid && !wr_valid && (!rd_result_valid || rd_result_ready);
    assign q_ready=idle_ok && !commit_valid && !wr_valid && !rd_valid && (!q_result_valid || q_result_ready);
    assign freeze=rst_n && (!init_done || pending || commit_valid);

    function [16:0] config_address;
        input direction,bank;
        input [12:0] index;
        input [3:0] word;
        begin
            if(direction)config_address=2*TX_WORDS+(bank?RX_WORDS:0)+({4'd0,index}<<3)+word;
            else config_address=(bank?TX_WORDS:0)+({4'd0,index}<<3)+word;
        end
    endfunction
    function [14:0] directory_address;
        input direction,bank;
        input [12:0] slot;
        begin
            if(direction)directory_address=2*TX_HASH_SLOTS+(bank?RX_HASH_SLOTS:0)+slot;
            else directory_address=(bank?TX_HASH_SLOTS:0)+slot;
        end
    endfunction
    function [12:0] hash_value;
        input direction;
        input [15:0] vl;
        reg [15:0] mixed;
        begin
            // Full tag is ALWAYS compared. Mixing reduces simple high-bit collisions.
            mixed=vl^(vl>>8);
            hash_value=mixed & (direction ? RX_HASH_SLOTS-1:TX_HASH_SLOTS-1);
        end
    endfunction
    function legal_entry;
        input direction;
        input [255:0] e;
        begin
            legal_entry=(e[255:247]==0 && e[245:244]!=3) && (!direction || e[243:241]==0) &&
             (!e[240] || (e[239:224]!=0 && e[223:208]>=64 && e[223:208]<=1518 &&
               e[207:192]!=0 && e[191:144]!=0 && !e[184] && e[151:144]==8'h20 &&
               e[143:96]=={32'h03000000,e[239:224]} && e[95:64]!=0 &&
               e[63:32]=={16'he0e0,e[239:224]} && e[31:16]!=0 && e[15:0]!=0));
        end
    endfunction

    always @* begin
        cfg_en=0;cfg_we=0;cfg_addr=0;cfg_wdata=0;
        dir_en=0;dir_we=0;dir_addr=0;dir_wdata=0;
        case(state)
          S_INIT:begin
            if(clear_count<CFG_WORDS)begin cfg_en=1;cfg_we=1;cfg_addr=clear_count;end
            if(clear_count<DIR_WORDS)begin dir_en=1;dir_we=1;dir_addr=clear_count[14:0];end
          end
          S_IDLE:if(wr_valid && wr_ready && wr_word<8 &&
                      ((!wr_bank && wr_index<TX_ENTRIES)||(wr_bank && wr_index<RX_ENTRIES)))begin
            cfg_en=1;cfg_we=1;cfg_addr=config_address(wr_bank,!active_bank,wr_index,wr_word);cfg_wdata=wr_data;
          end
          S_RD_ISSUE:begin cfg_en=1;cfg_addr=config_address(cur_dir,cur_bank,cur_index,cur_word);end
          S_FETCH_ISSUE:begin cfg_en=1;cfg_addr=config_address(cur_dir,cur_bank,cur_index,cur_word);end
          S_HASH_READ:begin dir_en=1;dir_addr=directory_address(cur_dir,cur_bank,hash_slot);end
          S_HASH_WRITE:begin
            dir_en=1;dir_we=1;dir_addr=directory_address(cur_dir,cur_bank,hash_slot);
            dir_wdata={1'b1,2'd0,entry[239:224],cur_index};
          end
          S_CLEAR:begin
            dir_en=1;dir_we=1;
            if(clear_count<TX_HASH_SLOTS)dir_addr=directory_address(0,!active_bank,clear_count[12:0]);
            else dir_addr=directory_address(1,!active_bank,clear_count-TX_HASH_SLOTS);
          end
          S_COPY_READ:begin
            cfg_en=1;
            if(copy_count<TX_WORDS)cfg_addr=config_address(0,active_bank,copy_count>>3,{1'b0,copy_count[2:0]});
            else cfg_addr=config_address(1,active_bank,(copy_count-TX_WORDS)>>3,{1'b0,copy_count[2:0]});
          end
          S_COPY_WRITE:begin
            cfg_en=1;cfg_we=1;cfg_wdata=copy_data;
            if(copy_count<TX_WORDS)cfg_addr=config_address(0,!active_bank,copy_count>>3,{1'b0,copy_count[2:0]});
            else cfg_addr=config_address(1,!active_bank,(copy_count-TX_WORDS)>>3,{1'b0,copy_count[2:0]});
          end
          default:begin end
        endcase
    end
    genvar cfg_bank_number;
    generate for(cfg_bank_number=0;cfg_bank_number<CFG_BANKS;cfg_bank_number=cfg_bank_number+1)begin:config_banks
        config_ram_bank storage(.clk(clk),
            .read_enable(cfg_en && !cfg_we && cfg_addr[16:11]==cfg_bank_number),
            .write_enable(cfg_en && cfg_we && cfg_addr[16:11]==cfg_bank_number),
            .address(cfg_addr[10:0]),.write_data(cfg_wdata),
            .read_data(cfg_bank_q[cfg_bank_number*32 +:32]));
    end endgenerate
    always @(posedge clk)if(cfg_en && !cfg_we)cfg_read_bank<=cfg_addr[16:11];
    assign cfg_q=cfg_read_bank<CFG_BANKS?cfg_bank_q[cfg_read_bank*32 +:32]:32'd0;
    always @(posedge clk) begin
        if(dir_en)begin
            dir_q<=dir_mem[dir_addr];
            if(dir_we)dir_mem[dir_addr]<=dir_wdata;
        end
    end
    always @(posedge clk) begin
        if(!rst_n)begin
            state<=S_INIT;clear_count<=0;copy_count<=0;copy_data<=0;active_bank<=0;frozen_budget_only<=0;init_done<=0;
            cur_dir<=0;cur_bank<=0;cur_index<=0;cur_word<=0;rd_target_shadow<=0;
            query_mode<=0;hash_query<=0;hash_slot<=0;search_vl<=0;probe_count<=0;entry<=0;
            wr_error<=0;rd_result_valid<=0;rd_error<=0;rd_data<=0;rd_version<=0;
            q_result_valid<=0;q_found<=0;q_error<=0;q_result_index<=0;q_config<=0;q_version<=0;
            pending<=0;applied<=0;result_valid<=0;result_ok<=0;result_code<=0;version<=0;result_version<=0;
            frozen_mgmt<=1514;frozen_period<=0;frozen_line<=700000;frozen_service<=80000;
            active_mgmt_max_client<=1514;active_mgmt_period_exp<=0;active_line_limit_kbps<=700000;active_service_limit_cycles<=80000;
            active_line_sum<=0;active_service_sum<=0;active_admitted<=0;active_max_bag_exp<=0;
            active_tx_count<=0;active_rx_count<=0;line_sum<=0;service_sum<=0;burst_sum<=0;
            tx_count<=0;rx_count<=0;max_bag<=0;min_period<=1;fail_code<=0;
            div_shift<=0;div_quot<=0;div_rem<=0;div_count<=0;div_mgmt<=0;wire_cycles<=0;
        end else begin
            wr_error<=0;applied<=0;
            if(rd_result_valid && rd_result_ready)rd_result_valid<=0;
            if(q_result_valid && q_result_ready)q_result_valid<=0;
            if(result_valid && result_ready)result_valid<=0;
            case(state)
              S_INIT:begin
                if(clear_count+1>=CFG_WORDS && clear_count+1>=DIR_WORDS)begin init_done<=1;state<=S_IDLE;end
                else clear_count<=clear_count+1;
              end
              S_IDLE:begin
                if(commit_valid && commit_ready)begin
                    pending<=1;frozen_budget_only<=budget_only;frozen_mgmt<=mgmt_max_client;frozen_period<=mgmt_period_exp;
                    frozen_line<=line_limit_kbps;frozen_service<=service_limit_cycles;
                    line_sum<=0;service_sum<=0;burst_sum<=0;tx_count<=0;rx_count<=0;max_bag<=0;
                    min_period<=8'd1<<mgmt_period_exp;clear_count<=0;query_mode<=0;hash_query<=0;
                    if(mgmt_max_client<43 || mgmt_max_client>1514 || line_limit_kbps==0 || line_limit_kbps>700000 ||
                       service_limit_cycles==0 || service_limit_cycles>80000)begin fail_code<=1;state<=S_FAIL;end
                    else if(budget_only)begin
                      cur_dir<=0;cur_bank<=active_bank;cur_index<=0;cur_word<=0;entry<=0;state<=S_FETCH_ISSUE;
                    end else state<=S_CLEAR;
                end else if(wr_valid && wr_ready)begin
                    if(wr_word>=8 || (!wr_bank && wr_index>=TX_ENTRIES)||(wr_bank && wr_index>=RX_ENTRIES))wr_error<=1;
                end else if(rd_valid && rd_ready)begin
                    rd_version<=version;cur_dir<=rd_bank;cur_bank<=rd_shadow?!active_bank:active_bank;
                    cur_index<=rd_index;cur_word<=rd_word;
                    if(rd_word>=8 || (!rd_bank && rd_index>=TX_ENTRIES)||(rd_bank && rd_index>=RX_ENTRIES))begin
                        rd_result_valid<=1;rd_error<=1;rd_data<=0;
                    end else begin rd_error<=0;state<=S_RD_ISSUE;end
                end else if(q_valid && q_ready)begin
                    q_version<=version;q_config<=0;q_found<=0;q_error<=0;q_result_index<=0;
                    cur_dir<=q_dir;cur_bank<=active_bank;cur_index<=q_index;cur_word<=0;entry<=0;query_mode<=1;
                    if(!q_dir)begin
                        if(q_index>=TX_ENTRIES)begin q_result_valid<=1;q_error<=1;end
                        else state<=S_FETCH_ISSUE;
                    end else if(q_vl==0)begin q_result_valid<=1;end
                    else begin search_vl<=q_vl;hash_slot<=hash_value(1,q_vl);probe_count<=0;hash_query<=1;state<=S_HASH_READ;end
                end
              end
              S_RD_ISSUE:state<=S_RD_CAP;
              S_RD_CAP:begin rd_data<=cfg_q;rd_result_valid<=1;state<=S_IDLE;end
              S_FETCH_ISSUE:state<=S_FETCH_CAP;
              S_FETCH_CAP:begin
                entry[cur_word*32 +:32]<=cfg_q;
                if(cur_word==7)begin if(query_mode)state<=S_QUERY_DONE;else state<=S_VALIDATE;end
                else begin cur_word<=cur_word+1;state<=S_FETCH_ISSUE;end
              end
              S_QUERY_DONE:begin
                q_config<=entry;q_found<=entry[240];q_result_index<=cur_index;q_result_valid<=1;state<=S_IDLE;
              end
              S_CLEAR:begin
                if(clear_count==TX_HASH_SLOTS+RX_HASH_SLOTS-1)begin
                    cur_dir<=0;cur_bank<=!active_bank;cur_index<=0;cur_word<=0;entry<=0;state<=S_FETCH_ISSUE;
                end else clear_count<=clear_count+1;
              end
              S_VALIDATE:begin
                if(!legal_entry(cur_dir,entry))begin fail_code<=1;state<=S_FAIL;end
                else if(!entry[240])state<=S_NEXT;
                else begin
                    if(cur_dir)rx_count<=rx_count+1;else begin
                        tx_count<=tx_count+1;
                        if(entry[243:241]>max_bag)max_bag<=entry[243:241];
                        if((8'd1<<entry[243:241])<min_period)min_period<=8'd1<<entry[243:241];
                    end
                    search_vl<=entry[239:224];hash_slot<=hash_value(cur_dir,entry[239:224]);probe_count<=0;
                    hash_query<=0;
                    if(frozen_budget_only)begin
                      if(cur_dir)state<=S_NEXT;
                      else begin div_shift<=({16'd0,entry[223:208]}+20)<<2;div_quot<=0;div_rem<=0;div_count<=0;div_mgmt<=0;state<=S_DIV;end
                    end else state<=S_HASH_READ;
                end
              end
              S_HASH_READ:state<=S_HASH_CHECK;
              S_HASH_CHECK:begin
                if(!dir_q[31])begin
                    if(hash_query)begin q_result_valid<=1;q_found<=0;state<=S_IDLE;end
                    else state<=S_HASH_WRITE;
                end else if(dir_q[28:13]==search_vl)begin
                    if(hash_query)begin cur_index<=dir_q[12:0];cur_word<=0;entry<=0;state<=S_FETCH_ISSUE;end
                    else begin fail_code<=2;state<=S_FAIL;end
                end else if(probe_count+1>=MAX_PROBES)begin
                    if(hash_query)begin q_result_valid<=1;q_found<=0;state<=S_IDLE;end
                    else begin fail_code<=5;state<=S_FAIL;end
                end else begin
                    probe_count<=probe_count+1;
                    hash_slot<=(hash_slot+1)&(cur_dir?RX_HASH_SLOTS-1:TX_HASH_SLOTS-1);state<=S_HASH_READ;
                end
              end
              S_HASH_WRITE:begin
                if(cur_dir)state<=S_NEXT;
                else begin
                    div_shift<=({16'd0,entry[223:208]}+20)<<2;div_quot<=0;div_rem<=0;div_count<=0;div_mgmt<=0;state<=S_DIV;
                end
              end
              S_DIV:begin
                div_shift<={div_shift[14:0],1'b0};div_quot<=quot_next;div_rem<=rem_next;
                if(div_count==15)begin wire_cycles<=quot_next+(rem_next!=0);state<=S_BUDGET;end
                else div_count<=div_count+1;
              end
              S_BUDGET:begin
                if(div_mgmt)begin
                    line_sum<=line_sum+((({16'd0,management_wire}+20)<<3)<<(7-frozen_period));
                    service_sum<=service_sum+(management_service<<(7-frozen_period));
                    burst_sum<=burst_sum+management_service;state<=S_TOTAL;
                end else begin
                    line_sum<=line_sum+((({16'd0,entry[223:208]}+20)<<3)<<(7-entry[243:241]));
                    service_sum<=service_sum+(rt_service<<(7-entry[243:241]));burst_sum<=burst_sum+rt_service;state<=S_NEXT;
                end
              end
              S_NEXT:begin
                cur_word<=0;entry<=0;
                if(cur_index+1<(cur_dir?RX_ENTRIES:TX_ENTRIES))begin cur_index<=cur_index+1;state<=S_FETCH_ISSUE;end
                else if(!cur_dir)begin cur_dir<=1;cur_index<=0;state<=S_FETCH_ISSUE;end
                else state<=S_MGMT;
              end
              S_MGMT:begin
                div_shift<=({16'd0,management_wire}+20)<<2;div_quot<=0;div_rem<=0;div_count<=0;div_mgmt<=1;state<=S_DIV;
              end
              S_TOTAL:begin
                if(line_sum>(frozen_line<<7))begin fail_code<=3;state<=S_FAIL;end
                else if(service_sum>(frozen_service<<7) || burst_sum+128>({24'd0,min_period}*100000))begin fail_code<=4;state<=S_FAIL;end
                else state<=S_QUIET;
              end
              S_QUIET:if(quiescent)begin
                if(!frozen_budget_only)active_bank<=!active_bank;version<=version+1;applied<=1;
                active_mgmt_max_client<=frozen_mgmt;active_mgmt_period_exp<=frozen_period;
                active_line_limit_kbps<=frozen_line;active_service_limit_cycles<=frozen_service;
                active_line_sum<=line_sum;active_service_sum<=service_sum;active_admitted<=1;
                active_tx_count<=tx_count;active_rx_count<=rx_count;active_max_bag_exp<=max_bag;
                if(frozen_budget_only)begin pending<=0;result_valid<=1;result_ok<=1;result_code<=0;result_version<=version+1'b1;state<=S_IDLE;end
                else begin copy_count<=0;state<=S_COPY_READ;end
              end
              S_COPY_READ:state<=S_COPY_CAP;
              S_COPY_CAP:begin copy_data<=cfg_q;state<=S_COPY_WRITE;end
              S_COPY_WRITE:begin
                if(copy_count==ONE_WORDS-1)begin
                    pending<=0;result_valid<=1;result_ok<=1;result_code<=0;result_version<=version;state<=S_IDLE;
                end else begin copy_count<=copy_count+1;state<=S_COPY_READ;end
              end
              S_FAIL:begin
                pending<=0;result_valid<=1;result_ok<=0;result_code<=fail_code;result_version<=version;state<=S_IDLE;
              end
              default:state<=S_INIT;
            endcase
        end
    end
endmodule
