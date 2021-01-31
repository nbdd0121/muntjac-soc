module sync #(
    parameter W = 1
) (
    input clk,
    input [W-1:0] d,
    output [W-1:0] q
);

    reg [W-1:0] a, b;

    always @(posedge clk) begin
        a <= d;
        b <= a;
    end

    assign q = b;

endmodule
