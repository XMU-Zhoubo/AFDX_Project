// C38 final application boundary. Compile this file, never the legacy rtl/AFDX_top.v in the same library.
module AFDX_top #(
 parameter [31:0] TFTP_RTO_MIN=32'd100000000,TFTP_RTO_MAX=32'd800000000,TFTP_DALLY=32'd1600000000,
 parameter [3:0] TFTP_RETRIES=4'd5
) (
 input wire clk,rst_n,gtx_clk,phy_a_rx_clk,
 input wire [7:0] phy_a_rxd,input wire phy_a_rx_dv,phy_a_rx_er,
 output wire phy_a_tx_clk,output wire [7:0] phy_a_txd,output wire phy_a_tx_en,phy_a_tx_er,
 // One management bus reuses address/data lines for config, state and stats.
 input wire phy_b_rx_clk,input wire [7:0] phy_b_rxd,input wire phy_b_rx_dv,phy_b_rx_er,
 output wire phy_b_tx_clk,output wire [7:0] phy_b_txd,output wire phy_b_tx_en,phy_b_tx_er,
 output wire rx_network,
 input wire cfg_valid,cfg_write,input wire [1:0] cfg_kind,
 input wire cfg_bank,cfg_shadow,input wire [12:0] cfg_index,
 input wire [3:0] cfg_word,input wire [31:0] cfg_data,
 output wire cfg_ready,output wire cfg_resp_valid,input wire cfg_resp_ready,
 output wire cfg_resp_error,output wire [31:0] cfg_resp_data,
 input wire cfg_commit_valid,output wire cfg_commit_ready,cfg_pending,cfg_applied,
 output wire cfg_result_valid,cfg_result_ok,input wire cfg_result_ready,
 output wire [2:0] cfg_result_code,
 output wire init_done,
 input wire tx_cmd_valid,output wire tx_cmd_ready,
 input wire [15:0] tx_vlid,input wire [15:0] tx_length,
 input wire [7:0] tx_data,input wire tx_valid,tx_sop,tx_last,
 output wire tx_ready,input wire tx_commit_valid,tx_abort,
 output wire tx_commit_ready,tx_error_valid,input wire tx_error_ready,
 output wire [3:0] tx_error_code,
 output wire rx_desc_valid,input wire rx_desc_ready,
 output wire [15:0] rx_desc_length,rx_desc_vl,rx_desc_app_id,rx_desc_version,
 output wire [7:0] rx_desc_sn,output wire rx_desc_udp_checked,
 output wire [7:0] rx_data,output wire rx_valid,rx_sop,rx_last,
 input wire rx_ready,
 output wire [7:0] store_tx_data,output wire store_tx_valid,store_tx_last,input wire store_tx_ready,
 input wire [7:0] store_rx_data,input wire store_rx_valid,store_rx_last,output wire store_rx_ready,store_cancel,
 output wire [7:0] events,output wire line_management

);
 // Full VLID lookup uses the real active TX table, not a duplicate mirror.
 // A bounded scan reads word7 of all128 entries through the existing bus.
 // External table commit is held until the core accepts the selected index.
 // Internal SNMP SET changes budgets only; it cannot reassign a VL entry.
 localparam IDLE=0,QREQ=1,QWAIT=2,COMMAND=3,DATA=4,ERROR=5;
 reg [2:0] state;
 reg [15:0] saved_vlid,saved_length,byte_count;
 reg [6:0] scan_index;
 reg [12:0] mapped_index;
 reg local_error,abort_seen,bad_sop;
 reg [3:0] local_code;
 reg bus_busy,bus_map,bus_message;
 wire message_select=cfg_kind==3 && cfg_index==15;
 wire [31:0] message_allocated,message_released,message_rejected,message_completed;
 wire [1:0] message_used,message_peak;
 reg message_cancel;reg message_seed_valid;reg [15:0] message_seed;wire message_seed_ready;
 reg [31:0] message_response;reg message_error;
 wire lookup_lock=state==QREQ || state==QWAIT || state==COMMAND;
 wire c_cfg_valid,c_cfg_write,c_cfg_bank,c_cfg_shadow,c_cfg_ready;
 wire [1:0] c_cfg_kind;wire [12:0] c_cfg_index;wire [3:0] c_cfg_word;
 wire [31:0] c_cfg_data,c_cfg_resp_data;
 wire c_cfg_resp_valid,c_cfg_resp_ready,c_cfg_resp_error;
 wire c_cfg_commit_valid,c_cfg_commit_ready;
 wire core_cmd_valid,core_cmd_ready,core_data_valid,core_data_ready;
 wire core_commit_valid,core_commit_ready,core_abort,core_error_valid;
 wire [3:0] core_error_code;
 assign c_cfg_valid=!bus_busy && ((state==QREQ && !tx_abort) || (!lookup_lock && cfg_valid && !message_select));
 assign c_cfg_write=lookup_lock?1'b0:cfg_write;
 assign c_cfg_kind=lookup_lock?2'd0:cfg_kind;
 assign c_cfg_bank=lookup_lock?1'b0:cfg_bank;
 assign c_cfg_shadow=lookup_lock?1'b0:cfg_shadow;
 assign c_cfg_index=lookup_lock?{6'd0,scan_index}:cfg_index;
 assign c_cfg_word=lookup_lock?4'd7:cfg_word;
 assign c_cfg_data=lookup_lock?32'd0:cfg_data;
 assign cfg_ready=!lookup_lock && !bus_busy && (message_select || c_cfg_ready);
 assign cfg_resp_valid=bus_busy && !bus_map && (bus_message || c_cfg_resp_valid);
 assign cfg_resp_data=bus_message?message_response:c_cfg_resp_data;
 assign cfg_resp_error=bus_message?message_error:c_cfg_resp_error;
 assign c_cfg_resp_ready=bus_busy && !bus_message && (bus_map?state==QWAIT:cfg_resp_ready);
 assign c_cfg_commit_valid=cfg_commit_valid && !lookup_lock;
 assign cfg_commit_ready=c_cfg_commit_ready && !lookup_lock;
 assign tx_cmd_ready=rst_n && init_done && state==IDLE && !bus_busy &&
     !cfg_valid && !cfg_commit_valid && !cfg_pending && !cfg_result_valid && !core_error_valid;
 assign core_cmd_valid=rst_n && state==COMMAND && !tx_abort;
 assign core_data_valid=rst_n && state==DATA && tx_valid && !tx_abort && !bad_sop;
 assign tx_ready=rst_n && state==DATA && !tx_abort && !bad_sop && core_data_ready;
 assign core_commit_valid=rst_n && state==DATA && tx_commit_valid && !tx_abort && !bad_sop;
 assign tx_commit_ready=rst_n && state==DATA && !tx_abort && !bad_sop && core_commit_ready;
 assign core_abort=tx_abort || bad_sop;
 assign tx_error_valid=local_error || core_error_valid;
 assign tx_error_code=local_error?local_code:core_error_code;
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;saved_vlid<=0;saved_length<=0;byte_count<=0;scan_index<=0;mapped_index<=0;
   local_error<=0;local_code<=0;abort_seen<=0;bad_sop<=0;bus_busy<=0;bus_map<=0;bus_message<=0;message_response<=0;message_error<=0;message_seed_valid<=0;message_seed<=0;message_cancel<=0;end
  else begin
   bad_sop<=0;message_seed_valid<=0;message_cancel<=0;
   if(c_cfg_resp_valid && c_cfg_resp_ready)bus_busy<=0;
   if(bus_message && cfg_resp_valid && cfg_resp_ready)begin bus_busy<=0;bus_message<=0;end
   if(!lookup_lock && !bus_busy && cfg_valid && message_select)begin
    bus_busy<=1;bus_map<=0;bus_message<=1;
    message_error<=(cfg_write && !((cfg_word==6 && message_seed_ready && cfg_data!=0 && cfg_data<=65535) || (cfg_word==7 && cfg_data==1))) || cfg_word>7;
    if(cfg_write && cfg_word==7 && cfg_data==1)message_cancel<=1;
    if(cfg_write && cfg_word==6 && message_seed_ready && cfg_data!=0 && cfg_data<=65535)begin message_seed<=cfg_data[15:0];message_seed_valid<=1;end
    case(cfg_word)
     0:message_response<=32'h43343253;1:message_response<=message_allocated;2:message_response<=message_released;
     3:message_response<=message_rejected;4:message_response<=message_completed;
     5:message_response<={28'd0,message_peak,message_used};6:message_response<={15'd0,!message_seed_ready,message_seed};7:message_response<=0;default:message_response<=0;
    endcase
   end
   if(c_cfg_valid && c_cfg_ready)begin bus_busy<=1;bus_map<=state==QREQ;bus_message<=0;end
   case(state)
    IDLE:if(tx_cmd_valid && tx_cmd_ready)begin
     saved_vlid<=tx_vlid;saved_length<=tx_length;scan_index<=0;abort_seen<=0;byte_count<=0;
     if(tx_length==0 || tx_length>4096)begin local_error<=1;local_code<=13;state<=ERROR;end
     else if(tx_vlid==0)begin local_error<=1;local_code<=14;state<=ERROR;end
     else state<=QREQ;
    end
    QREQ:if(tx_abort)state<=IDLE;else if(c_cfg_valid && c_cfg_ready)state<=QWAIT;
    QWAIT:begin
     if(tx_abort)abort_seen<=1;
     if(c_cfg_resp_valid && c_cfg_resp_ready)begin
      if(tx_abort || abort_seen)state<=IDLE;
      else if(c_cfg_resp_error)begin local_error<=1;local_code<=15;state<=ERROR;end
      else if(c_cfg_resp_data[16] && c_cfg_resp_data[15:0]==saved_vlid)begin mapped_index<={6'd0,scan_index};state<=COMMAND;end
      else if(scan_index==127)begin local_error<=1;local_code<=14;state<=ERROR;end
      else begin scan_index<=scan_index+1'b1;state<=QREQ;end
     end
    end
    COMMAND:if(tx_abort)state<=IDLE;else if(core_cmd_valid && core_cmd_ready)state<=DATA;
    DATA:begin
     if(tx_abort)state<=IDLE;
     else if(core_error_valid)state<=IDLE;
     else if(tx_valid && tx_ready)begin
      byte_count<=byte_count+1'b1;
      if(tx_sop!=(byte_count==0))begin local_error<=1;local_code<=13;bad_sop<=1;state<=ERROR;end
     end
     if(core_commit_valid && core_commit_ready)state<=IDLE;
    end
    ERROR:if(local_error && tx_error_ready)begin local_error<=0;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
 wire [127:0] rx_fragment;
 wire p_desc_valid,p_desc_ready,p_valid,p_ready,p_sop,p_last,p_checked,p_network;
 wire [15:0] p_length,p_vl,p_app,p_version;wire [7:0] p_sn,p_data;
 message_rx messages(.clk(clk),.rst_n(rst_n),.config_applied(cfg_applied || message_cancel),
  .s_fragment(rx_fragment),.s_desc_valid(p_desc_valid),.s_desc_ready(p_desc_ready),
  .s_length(p_length),.s_vl(p_vl),.s_app(p_app),.s_version(p_version),.s_sn(p_sn),.s_checked(p_checked),.s_network(p_network),
  .s_data(p_data),.s_valid(p_valid),.s_ready(p_ready),.s_sop(p_sop),.s_last(p_last),
  .m_desc_valid(rx_desc_valid),.m_desc_ready(rx_desc_ready),.m_length(rx_desc_length),.m_vl(rx_desc_vl),.m_app(rx_desc_app_id),.m_version(rx_desc_version),
  .m_sn(rx_desc_sn),.m_checked(rx_desc_udp_checked),.m_network(rx_network),
  .m_data(rx_data),.m_valid(rx_valid),.m_ready(rx_ready),.m_sop(rx_sop),.m_last(rx_last),
  .allocated(message_allocated),.released(message_released),.rejected(message_rejected),.completed(message_completed),.used(message_used),.peak(message_peak));
 loading_system_top #(.TFTP_RTO_MIN(TFTP_RTO_MIN),.TFTP_RTO_MAX(TFTP_RTO_MAX),.TFTP_DALLY(TFTP_DALLY),.TFTP_RETRIES(TFTP_RETRIES)) core(
  .final_app_frame(rx_valid && rx_ready && rx_last),.final_app_byte(rx_valid && rx_ready),.message_seed_valid(message_seed_valid),.message_seed(message_seed),.message_seed_ready(message_seed_ready),.clk(clk),
  .rst_n(rst_n),
  .gtx_clk(gtx_clk),
  .phy_a_rx_clk(phy_a_rx_clk),
  .phy_a_rxd(phy_a_rxd),
  .phy_a_rx_dv(phy_a_rx_dv),
  .phy_a_rx_er(phy_a_rx_er),
  .phy_a_tx_clk(phy_a_tx_clk),
  .phy_a_txd(phy_a_txd),
  .phy_a_tx_en(phy_a_tx_en),
  .phy_a_tx_er(phy_a_tx_er),
  .phy_b_rx_clk(phy_b_rx_clk),
  .phy_b_rxd(phy_b_rxd),
  .phy_b_rx_dv(phy_b_rx_dv),
  .phy_b_rx_er(phy_b_rx_er),
  .phy_b_tx_clk(phy_b_tx_clk),
  .phy_b_txd(phy_b_txd),
  .phy_b_tx_en(phy_b_tx_en),
  .phy_b_tx_er(phy_b_tx_er),
  .app_rx_network(p_network),
  .cfg_valid(c_cfg_valid),
  .cfg_write(c_cfg_write),
  .cfg_kind(c_cfg_kind),
  .cfg_bank(c_cfg_bank),
  .cfg_shadow(c_cfg_shadow),
  .cfg_index(c_cfg_index),
  .cfg_word(c_cfg_word),
  .cfg_data(c_cfg_data),
  .cfg_ready(c_cfg_ready),
  .cfg_resp_valid(c_cfg_resp_valid),
  .cfg_resp_ready(c_cfg_resp_ready),
  .cfg_resp_error(c_cfg_resp_error),
  .cfg_resp_data(c_cfg_resp_data),
  .cfg_commit_valid(c_cfg_commit_valid),
  .cfg_commit_ready(c_cfg_commit_ready),
  .cfg_pending(cfg_pending),
  .cfg_applied(cfg_applied),
  .cfg_result_valid(cfg_result_valid),
  .cfg_result_ok(cfg_result_ok),
  .cfg_result_ready(cfg_result_ready),
  .cfg_result_code(cfg_result_code),
  .init_done(init_done),
  .app_tx_cmd_valid(core_cmd_valid),
  .app_tx_cmd_ready(core_cmd_ready),
  .app_tx_cmd_index(mapped_index),
  .app_tx_cmd_length(saved_length),
  .app_tx_data(tx_data),
  .app_tx_valid(core_data_valid),
  .app_tx_last(tx_last),
  .app_tx_ready(core_data_ready),
  .app_tx_commit_valid(core_commit_valid),
  .app_tx_abort(core_abort),
  .app_tx_commit_ready(core_commit_ready),
  .app_tx_error_valid(core_error_valid),
  .app_tx_error_ready(tx_error_ready && !local_error),
  .app_tx_error_code(core_error_code),
  .app_rx_desc_valid(p_desc_valid),
  .app_rx_desc_ready(p_desc_ready),
  .app_rx_desc_length(p_length),
  .app_rx_desc_vl(p_vl),
  .app_rx_desc_app_id(p_app),
  .app_rx_desc_version(p_version),
  .app_rx_desc_sn(p_sn),
  .app_rx_desc_udp_checked(p_checked),
  .app_rx_fragment(rx_fragment),.app_rx_data(p_data),
  .app_rx_valid(p_valid),
  .app_rx_sop(p_sop),
  .app_rx_last(p_last),
  .app_rx_ready(p_ready),
  .store_tx_data(store_tx_data),
  .store_tx_valid(store_tx_valid),
  .store_tx_last(store_tx_last),
  .store_tx_ready(store_tx_ready),
  .store_rx_data(store_rx_data),
  .store_rx_valid(store_rx_valid),
  .store_rx_last(store_rx_last),
  .store_rx_ready(store_rx_ready),
  .store_cancel(store_cancel),
  .events(events),
  .line_management(line_management)
 );
endmodule
