// Fixed 1G SDR GMII boundary, with a supplied 125 MHz GTX clock.
// Board-specific clock forwarding and I/O constraints are future work.
module gmii_phy_static (
    input wire reset_request,
    input wire gtx_clk,
    input wire phy_rx_clk,
    input wire [7:0] phy_rxd,
    input wire phy_rx_dv,
    input wire phy_rx_er,
    output wire phy_tx_clk,
    output reg [7:0] phy_txd,
    output reg phy_tx_en,
    output reg phy_tx_er,
    output wire tx_rst,
    output wire rx_rst,
    input wire [7:0] mac_txd,
    input wire mac_tx_en,
    input wire mac_tx_er,
    output reg [7:0] mac_rxd,
    output reg mac_rx_dv,
    output reg mac_rx_er
);
    (* async_reg = "true" *) reg [3:0] tx_reset_pipe = 4'hf;
    (* async_reg = "true" *) reg [3:0] rx_reset_pipe = 4'hf;
    assign phy_tx_clk = gtx_clk;
    assign tx_rst = tx_reset_pipe[3];
    assign rx_rst = rx_reset_pipe[3];
    always @(posedge gtx_clk or posedge reset_request) begin
        if (reset_request) tx_reset_pipe <= 4'hf;
        else tx_reset_pipe <= {tx_reset_pipe[2:0], 1'b0};
    end
    always @(posedge phy_rx_clk or posedge reset_request) begin
        if (reset_request) rx_reset_pipe <= 4'hf;
        else rx_reset_pipe <= {rx_reset_pipe[2:0], 1'b0};
    end
    always @(posedge gtx_clk) begin
        if (tx_rst) begin
            phy_txd <= 8'h00;
            phy_tx_en <= 1'b0;
            phy_tx_er <= 1'b0;
        end else begin
            phy_txd <= mac_txd;
            phy_tx_en <= mac_tx_en;
            phy_tx_er <= mac_tx_er;
        end
    end
    always @(posedge phy_rx_clk) begin
        if (rx_rst) begin
            mac_rxd <= 8'h00;
            mac_rx_dv <= 1'b0;
            mac_rx_er <= 1'b0;
        end else begin
            mac_rxd <= phy_rxd;
            mac_rx_dv <= phy_rx_dv;
            mac_rx_er <= phy_rx_er;
        end
    end
endmodule
