
`timescale 1ns/1ps

module tb_e03;

    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    reg [7:0] uio_in;

    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    integer errors;
    integer tests;
    integer i;

    reg [7:0] previous_data;

    e03_serial_to_parallel dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    // Clock period = 10 ns
    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input condition;
        input [255:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    task send_bit;
        input bit_value;
        begin
            @(negedge clk);
            ui_in[0] = bit_value;
            @(posedge clk);
            #1;
        end
    endtask

    task send_byte;
        input [7:0] value;
        input mode;
        begin
            tests = tests + 1;

            @(negedge clk);
            ui_in[2] = mode;
            ui_in[1] = 1'b1;
            previous_data = uo_out;

            for (i = 0; i < 8; i = i + 1) begin
                if (mode)
                    send_bit(value[7-i]);
                else
                    send_bit(value[i]);

                if (i < 7) begin
                    check(uio_out[0] == 0,
                          "Valid asserted too early");
                    check(uo_out == previous_data,
                          "Output changed before 8 bits");
                end
            end

            check(uo_out == value,
                  "Incorrect parallel output");

            check(uio_out[0] == 1,
                  "Missing data_valid pulse");

            @(posedge clk);
            #1;

            check(uio_out[0] == 0,
                  "data_valid longer than one cycle");

            if (uo_out == value)
                $display("BYTE CHECK: %h mode=%b", value, mode);
        end
    endtask

    initial begin
        $dumpfile("e03.vcd");
        $dumpvars(0, tb_e03);

        errors = 0;
        tests = 0;

        rst_n = 0;
        ena = 1;
        ui_in = 0;
        uio_in = 0;

        repeat (3) @(posedge clk);
        #1;

        check(uo_out == 8'h00, "Reset output error");
        check(uio_out[0] == 0, "Reset valid error");
        check(uio_oe == 8'h01, "Output enable error");

        @(negedge clk);
        rst_n = 1;

        // MSB first
        send_byte(8'h00, 1'b1);
        send_byte(8'hFF, 1'b1);
        send_byte(8'hA5, 1'b1);

        // LSB first
        send_byte(8'h00, 1'b0);
        send_byte(8'hFF, 1'b0);
        send_byte(8'hA5, 1'b0);

        // Asymmetric byte
        send_byte(8'hB2, 1'b1);
        send_byte(8'hB2, 1'b0);

        // Enable pause test
        @(negedge clk);
        rst_n = 0;
        ui_in = 0;

        @(negedge clk);
        rst_n = 1;
        ui_in[1] = 1;
        ui_in[2] = 1;

        send_bit(1);
        send_bit(0);
        send_bit(1);

        @(negedge clk);
        ui_in[1] = 0;
        previous_data = uo_out;

        repeat (4) begin
            @(posedge clk);
            #1;
            check(uio_out[0] == 0,
                  "Valid during enable pause");
            check(uo_out == previous_data,
                  "Output changed during pause");
        end

        @(negedge clk);
        ui_in[1] = 1;

        send_bit(0);
        send_bit(0);
        send_bit(1);
        send_bit(0);
        send_bit(1);

        check(uo_out == 8'hA5,
              "Enable pause byte mismatch");
        check(uio_out[0] == 1,
              "Missing valid after pause");

        // Reset during partial frame
        @(negedge clk);
        rst_n = 0;
        #1;
        check(uo_out == 0,
              "Reset during frame failed");
        check(uio_out[0] == 0,
              "Valid not cleared by reset");

        if (errors == 0) begin
            $display("ALL TESTS PASS");
            $display("Total byte tests: %0d", tests);
        end else begin
            $display("FAIL: %0d errors", errors);
            $fatal(1, "E03 verification failed");
        end

        $finish;
    end

endmodule
