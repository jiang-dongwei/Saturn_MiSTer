module aps6408_diag_ddio_input (
    input clk,
    input [8:0] data,
    output [8:0] rising,
    output [8:0] falling
);
`ifdef APS6408_DIAG_SIM
    reg [8:0] negative_sample;
    reg [8:0] rising_sample;
    reg [8:0] falling_sample;
    always @(negedge clk) negative_sample <= data;
    always @(posedge clk) begin
        rising_sample <= data;
        falling_sample <= negative_sample;
    end
    assign rising = rising_sample;
    assign falling = falling_sample;
`else
    altddio_in #(
        .width(9),
        .intended_device_family("Cyclone V"),
        .power_up_high("OFF"),
        .lpm_type("altddio_in")
    ) input_ddr (
        .datain(data), .inclock(clk), .inclocken(1'b1),
        .aclr(1'b0), .aset(1'b0),
        .dataout_h(rising), .dataout_l(falling)
    );
`endif
endmodule
