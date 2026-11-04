// Scheduling cycles only. No RTC, wall-clock or software time input.
module timebase #(parameter TIME_WIDTH=32) (
    input wire clk, rst_n,
    output reg [TIME_WIDTH-1:0] now
);
    always @(posedge clk) begin
        if (!rst_n) now <= 0;
        else now <= now + 1'b1;
    end
endmodule
