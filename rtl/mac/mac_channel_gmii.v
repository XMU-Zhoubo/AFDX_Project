// C05-R: 8bit/100MHz client <-> actual fixed 1G GMII MAC.
// Pinned IP owns asynchronous frame FIFOs; C04 stages remain same-clock.
module mac_channel_gmii #(
    parameter TX_FIFO_DEPTH = 4096,
    parameter RX_FIFO_DEPTH = 4096
) (
    input wire clk, rst_n,
    input wire [7:0] tx_data,
    input wire tx_valid,
    output wire tx_ready,
    input wire tx_last, tx_error,
    output wire [7:0] rx_data,
    output wire rx_valid,
    input wire rx_ready,
    output wire rx_sop, rx_last, rx_error,
    input wire gtx_clk, phy_rx_clk,
    input wire [7:0] phy_rxd,
    input wire phy_rx_dv, phy_rx_er,
    output wire phy_tx_clk,
    output wire [7:0] phy_txd,
    output wire phy_tx_en, phy_tx_er,
    input wire cfg_tx_enable, cfg_rx_enable,
    output wire tx_sop_to_mac,
    output wire tx_error_underflow, tx_fifo_overflow, tx_fifo_bad_frame, tx_fifo_good_frame,
    output wire rx_error_bad_frame, rx_error_bad_fcs,
    output wire rx_fifo_overflow, rx_fifo_bad_frame, rx_fifo_good_frame
);
    reg mac_reset = 1'b1;
    reg cfg_tx_latched = 1'b0;
    reg cfg_rx_latched = 1'b0;
    // Configuration is sampled only under reset, held in the running state.
    // It must settle before release; dynamic cross-domain changes are disallowed.
    always @(posedge clk) begin
        if (!rst_n) begin
            mac_reset <= 1'b1;
            cfg_tx_latched <= cfg_tx_enable;
            cfg_rx_latched <= cfg_rx_enable;
        end else mac_reset <= 1'b0;
    end
    wire stream_rst_n = rst_n && !mac_reset;
    wire tx_rst, rx_rst;
    wire [7:0] tx_axis_data, rx_axis_data;
    wire tx_axis_valid, tx_axis_ready, tx_axis_last, tx_axis_error;
    wire rx_axis_valid, rx_axis_ready, rx_axis_last, rx_axis_error;
    wire [7:0] mac_txd, mac_rxd, phy_txd_raw;
    wire mac_tx_en, mac_tx_er, mac_rx_dv, mac_rx_er;
    // Full byte path. The isolated fault copy changes this assignment only.
    assign phy_txd = phy_txd_raw;
    mac_stream_adapter tx_adapter (
        .clk(clk), .rst_n(stream_rst_n),
        .s_data(tx_data), .s_valid(tx_valid), .s_ready(tx_ready),
        .s_last(tx_last), .s_error(tx_error),
        .m_data(tx_axis_data), .m_valid(tx_axis_valid), .m_ready(tx_axis_ready),
        .m_sop(tx_sop_to_mac), .m_last(tx_axis_last), .m_error(tx_axis_error)
    );
    mac_stream_adapter rx_adapter (
        .clk(clk), .rst_n(stream_rst_n),
        .s_data(rx_axis_data), .s_valid(rx_axis_valid), .s_ready(rx_axis_ready),
        .s_last(rx_axis_last), .s_error(rx_axis_error),
        .m_data(rx_data), .m_valid(rx_valid), .m_ready(rx_ready),
        .m_sop(rx_sop), .m_last(rx_last), .m_error(rx_error)
    );
    gmii_phy_static phy_if (
        .reset_request(mac_reset), .gtx_clk(gtx_clk), .phy_rx_clk(phy_rx_clk),
        .phy_rxd(phy_rxd), .phy_rx_dv(phy_rx_dv), .phy_rx_er(phy_rx_er),
        .phy_tx_clk(phy_tx_clk), .phy_txd(phy_txd_raw),
        .phy_tx_en(phy_tx_en), .phy_tx_er(phy_tx_er),
        .tx_rst(tx_rst), .rx_rst(rx_rst),
        .mac_txd(mac_txd), .mac_tx_en(mac_tx_en), .mac_tx_er(mac_tx_er),
        .mac_rxd(mac_rxd), .mac_rx_dv(mac_rx_dv), .mac_rx_er(mac_rx_er)
    );
    eth_mac_1g_fifo #(
        .AXIS_DATA_WIDTH(8), .AXIS_KEEP_ENABLE(0), .AXIS_KEEP_WIDTH(1),
        .ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64),
        .TX_FIFO_DEPTH(TX_FIFO_DEPTH), .TX_FIFO_RAM_PIPELINE(1),
        .TX_FRAME_FIFO(1), .TX_DROP_OVERSIZE_FRAME(1),
        .TX_DROP_BAD_FRAME(1), .TX_DROP_WHEN_FULL(0),
        .RX_FIFO_DEPTH(RX_FIFO_DEPTH), .RX_FIFO_RAM_PIPELINE(1),
        .RX_FRAME_FIFO(1), .RX_DROP_OVERSIZE_FRAME(1),
        .RX_DROP_BAD_FRAME(1), .RX_DROP_WHEN_FULL(1)
    ) mac_ip (
        .tx_clk(gtx_clk), .tx_rst(tx_rst),
        .rx_clk(phy_rx_clk), .rx_rst(rx_rst),
        .logic_clk(clk), .logic_rst(mac_reset),
        .tx_axis_tdata(tx_axis_data), .tx_axis_tkeep(1'b1),
        .tx_axis_tvalid(tx_axis_valid), .tx_axis_tready(tx_axis_ready),
        .tx_axis_tlast(tx_axis_last), .tx_axis_tuser(tx_axis_error),
        .rx_axis_tdata(rx_axis_data), .rx_axis_tkeep(),
        .rx_axis_tvalid(rx_axis_valid), .rx_axis_tready(rx_axis_ready),
        .rx_axis_tlast(rx_axis_last), .rx_axis_tuser(rx_axis_error),
        .gmii_rxd(mac_rxd), .gmii_rx_dv(mac_rx_dv), .gmii_rx_er(mac_rx_er),
        .gmii_txd(mac_txd), .gmii_tx_en(mac_tx_en), .gmii_tx_er(mac_tx_er),
        .tx_clk_enable(1'b1), .rx_clk_enable(1'b1),
        .tx_mii_select(1'b0), .rx_mii_select(1'b0),
        .tx_error_underflow(tx_error_underflow),
        .tx_fifo_overflow(tx_fifo_overflow), .tx_fifo_bad_frame(tx_fifo_bad_frame),
        .tx_fifo_good_frame(tx_fifo_good_frame),
        .rx_error_bad_frame(rx_error_bad_frame), .rx_error_bad_fcs(rx_error_bad_fcs),
        .rx_fifo_overflow(rx_fifo_overflow), .rx_fifo_bad_frame(rx_fifo_bad_frame),
        .rx_fifo_good_frame(rx_fifo_good_frame),
        .cfg_ifg(8'd12), .cfg_tx_enable(cfg_tx_latched), .cfg_rx_enable(cfg_rx_latched)
    );
endmodule
