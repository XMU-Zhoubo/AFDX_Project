// C18 conservative shaping: saturating age, not a wrapping deadline.
// Input now is sampled at each clk; formal now advances exactly one cycle.
// Public now also permits deterministic unit-test jumps (< one full wrap).
module bag #(parameter CYCLES_PER_MS=100000) (
    input wire clk, rst_n,
    input wire [31:0] now,
    input wire [2:0] configured_exponent,
    input wire start_confirmed,
    input wire [2:0] transmitted_exponent,
    input wire rebase, rebase_seen,
    input wire [31:0] rebase_age,
    input wire [2:0] rebase_exponent,
    output wire eligible,
    output wire [31:0] configured_cycles, required_cycles,
    output reg [31:0] age,
    output reg seen
);
    localparam [31:0] MAX_CYCLES=CYCLES_PER_MS*128;
    reg [31:0] previous_time;
    reg [2:0] previous_exponent;
    wire [31:0] step=now-previous_time;
    wire [32:0] advanced_age={1'b0,age}+{1'b0,step};
    wire [2:0] conservative_exponent=previous_exponent>configured_exponent ? previous_exponent:configured_exponent;
    assign configured_cycles=CYCLES_PER_MS << configured_exponent;
    assign required_cycles=CYCLES_PER_MS << conservative_exponent;
    assign eligible=rst_n && (!seen || age>=required_cycles);
    always @(posedge clk) begin
        if(!rst_n) begin previous_time<=now;age<=0;seen<=0;previous_exponent<=0;end
        else begin
            previous_time<=now;
            if(start_confirmed) begin
                age<=0;seen<=1;
                previous_exponent<=transmitted_exponent>configured_exponent ? transmitted_exponent:configured_exponent;
            end else if(rebase) begin
                // Atomic-table APPLY preserves a global conservative floor,
                // including a VL moving to the other entry. No history erasure.
                age<=rebase_age;seen<=rebase_seen;
                previous_exponent<=rebase_exponent>configured_exponent ? rebase_exponent:configured_exponent;
            end else begin
                if(age<MAX_CYCLES) age<=advanced_age>=MAX_CYCLES ? MAX_CYCLES:advanced_age[31:0];
                if(configured_exponent>previous_exponent) previous_exponent<=configured_exponent;
            end
        end
    end
endmodule
