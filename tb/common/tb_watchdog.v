`timescale 1ns/1ps
// Simulation helper; TIMEOUT_NS is a simulation-time limit.
module tb_watchdog #(
    parameter TIMEOUT_NS = 100000
) (
    input wire done,
    output reg timeout_seen
);
    initial begin
        timeout_seen = 1'b0;
        #TIMEOUT_NS;
        if (done !== 1'b1) begin
            timeout_seen = 1'b1;
            $display("C04_TIMEOUT time=%0t limit_ns=%0d", $time, TIMEOUT_NS);
            // Let the output port propagate before Tcl examines the root wire.
            #1;
            $finish;
        end
    end
endmodule
