// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// This file is auto-generated.


// This is to prevent AscentLint warnings in the generated
// abstract prim wrapper. These warnings occur due to the .*
// use. TODO: we may want to move these inline waivers
// into a separate, generated waiver file for consistency.
//ri lint_check_off OUTPUT_NOT_DRIVEN INPUT_NOT_READ
module prim_flop

#(

  parameter int Width      = 1,
  localparam int WidthSubOne = Width-1,
  parameter logic [WidthSubOne:0] ResetValue = 0

) (
  input clk_i,
  input rst_ni,
  input [Width-1:0] d_i,
  output logic [Width-1:0] q_o
);
  (*ASYNC_REG="true"*) logic [Width-1:0] q;

  assign q_o = q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      q <= ResetValue;
    end else begin
      q <= d_i;
    end
  end

endmodule
//ri lint_check_on OUTPUT_NOT_DRIVEN INPUT_NOT_READ
