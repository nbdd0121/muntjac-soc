module reset_sync #(
    parameter CYCLES = 5
) (
    input clk,
    input rstn_async,
    output rstn_sync
);

    reg [CYCLES-1:0] ff;

    always @(posedge clk or negedge rstn_async)
        if (!rstn_async) begin
            ff <= 0;
        end
        else begin
            ff <= {1'b1, ff[CYCLES-1:1]};
        end

    assign rstn_sync = ff[0];

endmodule

module sck_sync (
    input clk,
    input rstn_async,
    input rstn_sync,
    input sck_o,
    input sck_t
);

    wire cclk_o;
    wire cclk_t;
    (* KEEP = "true" *)
    STARTUPE2 #(
		.PROG_USR      ("FALSE"),
		.SIM_CCLK_FREQ (0.0   )
	) startupe2 (
		.CFGCLK    (),
		.CFGMCLK   (),
		.EOS       (),
		.PREQ      (),
		.CLK       (1'b0),
		.GSR       (1'b0),
		.GTS       (1'b0),
		.KEYCLEARB (1'b0),
		.PACK      (1'b0),
		.USRCCLKO  (cclk_o),
		.USRCCLKTS (cclk_t),
		.USRDONEO  (1'b1),
		.USRDONETS (1'b0)
	);

    // The first three clock cycles on USRCCLKO
    // after End of Startup are used to switch the clock source and will not be output on the
    // external CCLK pin.
    // Source: https://www.xilinx.com/support/documentation/user_guides/ug470_7Series_Config.pdf
    //
    // So we basically use it together with the reset synchroniser, so that by the time we switched
    // to sck, cclk should already observe needed clock cycles.
    assign cclk_o = rstn_sync ? sck_o : clk;
    assign cclk_t = rstn_sync ? sck_t : 1'b0;

endmodule
