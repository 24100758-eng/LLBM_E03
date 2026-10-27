
module e03_serial_to_parallel (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire ena,
    input  wire clk,
    input  wire rst_n
);

wire serial_in = uio_in[0];
wire enable   = uio_in[1];
wire msb_first = uio_in[2];

    reg [7:0] shift_reg;
    reg [7:0] data_out;
    reg [2:0] bit_count;
    reg data_valid;

    wire [7:0] next_shift =
        msb_first ?
        {shift_reg[6:0], serial_in} :
        {serial_in, shift_reg[7:1]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 8'b0;
            data_out   <= 8'b0;
            bit_count  <= 3'b0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            if (ena && enable) begin
                shift_reg <= next_shift;

                if (bit_count == 3'd7) begin
                    data_out   <= next_shift;
                    bit_count  <= 3'd0;
                    data_valid <= 1'b1;
                end else begin
                    bit_count <= bit_count + 3'd1;
                end
            end
        end
    end

    assign uo_out = data_out;

assign uio_out = {4'b0000, data_valid, 3'b000};
assign uio_oe  = 8'b00001000;

endmodule
