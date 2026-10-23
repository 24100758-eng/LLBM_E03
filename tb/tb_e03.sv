
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

    // Device Under Test
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

    // Check expected condition
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

    // Send exactly one bit
    task send_bit;
        input bit_value;
        begin
            @(negedge clk);
            ui_in[0] = bit_value;
            ui_in[1] = 1'b1;

            @(posedge clk);
            #1;
        end
    endtask

    // Send one complete byte
    task send_byte;
        input [7:0] value;
        input mode;

        reg bit_value;
        integer j;
        integer errors_before;

        begin
            tests = tests + 1;
            errors_before = errors;

            // Disable reception before setup
            @(negedge clk);
            ui_in[1] = 1'b0;
            ui_in[2] = mode;

            previous_data = uo_out;

            $display("----------------------------");
            $display("TEST BYTE = %h, MSB = %b",
                     value, mode);

            for (j = 0; j < 8; j = j + 1) begin

                if (mode == 1'b1)
                    bit_value = value[7-j];
                else
                    bit_value = value[j];

                // Put data on input before clock edge
                @(negedge clk);
                ui_in[0] = bit_value;
                ui_in[1] = 1'b1;

                @(posedge clk);
                #1;

                // Before receiving eighth bit
                if (j < 7) begin
                    check(uio_out[0] == 1'b0,
                          "Valid asserted too early");

                    check(uo_out == previous_data,
                          "Output changed before 8 bits");
                end
            end

            // Check completed byte
            check(uo_out == value,
                  "Incorrect parallel output");

            check(uio_out[0] == 1'b1,
                  "Missing data_valid pulse");

            // Disable reception before next clock
            @(negedge clk);
            ui_in[1] = 1'b0;

            @(posedge clk);
            #1;

            check(uio_out[0] == 1'b0,
                  "data_valid longer than one cycle");

            check(uo_out == value,
                  "Output not held after frame");

            if (errors == errors_before)
                $display("PASS: Byte %h, mode %b",
                         value, mode);
            else
                $display("FAIL: Byte %h, mode %b",
                         value, mode);
        end
    endtask

    // Reset DUT safely
    task reset_dut;
        begin
            @(negedge clk);
            ui_in[1] = 1'b0;
            rst_n = 1'b0;

            @(posedge clk);
            #1;

            check(uo_out == 8'h00,
                  "Reset output error");

            check(uio_out[0] == 1'b0,
                  "Reset valid error");

            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("e03.vcd");
        $dumpvars(0, tb_e03);

        errors = 0;
        tests = 0;

        rst_n = 0;
        ena = 1;
        ui_in = 0;
        uio_in = 0;
        previous_data = 0;

        // Initial reset
        repeat (3) @(posedge clk);
        #1;

        check(uo_out == 8'h00,
              "Initial reset output error");

        check(uio_out[0] == 1'b0,
              "Initial reset valid error");

        check(uio_oe == 8'h01,
              "Output enable error");

        @(negedge clk);
        rst_n = 1'b1;

        // ==========================
        // TEST 1: MSB FIRST
        // ==========================

        $display("TEST GROUP: MSB FIRST");

        send_byte(8'h00, 1'b1);
        send_byte(8'hFF, 1'b1);
        send_byte(8'hA5, 1'b1);

        // ==========================
        // TEST 2: LSB FIRST
        // ==========================

        $display("TEST GROUP: LSB FIRST");

        send_byte(8'h00, 1'b0);
        send_byte(8'hFF, 1'b0);
        send_byte(8'hA5, 1'b0);

        // ==========================
        // TEST 3: ASYMMETRIC BYTE
        // ==========================

        $display("TEST GROUP: BYTE B2");

        send_byte(8'hB2, 1'b1);
        send_byte(8'hB2, 1'b0);

        // ==========================
        // TEST 4: ENABLE PAUSE
        // ==========================

        $display("TEST GROUP: ENABLE PAUSE");

        reset_dut();

        @(negedge clk);
        ui_in[2] = 1'b1;

        // Send first 3 bits of A5: 101
        send_bit(1'b1);
        send_bit(1'b0);
        send_bit(1'b1);

        // Pause reception
        @(negedge clk);
        ui_in[1] = 1'b0;

        previous_data = uo_out;

        repeat (4) begin
            @(posedge clk);
            #1;

            check(uio_out[0] == 1'b0,
                  "Valid during enable pause");

            check(uo_out == previous_data,
                  "Output changed during pause");
        end

        // Resume: remaining bits 00101
        send_bit(1'b0);
        send_bit(1'b0);
        send_bit(1'b1);
        send_bit(1'b0);
        send_bit(1'b1);

        check(uo_out == 8'hA5,
              "Enable pause byte mismatch");

        check(uio_out[0] == 1'b1,
              "Missing valid after pause");

        // Stop before next rising edge
        @(negedge clk);
        ui_in[1] = 1'b0;

        @(posedge clk);
        #1;

        check(uio_out[0] == 1'b0,
              "Valid did not clear after pause test");

        // ==========================
        // TEST 5: RESET DURING FRAME
        // ==========================

        $display("TEST GROUP: RESET");

        reset_dut();

        @(negedge clk);
        ui_in[2] = 1'b1;

        send_bit(1'b1);
        send_bit(1'b0);
        send_bit(1'b1);

        // Reset while frame incomplete
        @(negedge clk);
        ui_in[1] = 1'b0;
        rst_n = 1'b0;

        #1;

        check(uo_out == 8'h00,
              "Reset during frame failed");

        check(uio_out[0] == 1'b0,
              "Valid not cleared by reset");

        @(negedge clk);
        rst_n = 1'b1;

        // Verify new frame after reset
        send_byte(8'hA5, 1'b1);

        // ==========================
        // FINAL RESULT
        // ==========================

        $display("============================");
        $display("E03 VERIFICATION RESULT");
        $display("Total byte tests: %0d", tests);
        $display("Total errors: %0d", errors);

        if (errors == 0) begin
            $display("ALL TESTS PASS");
        end else begin
            $display("FAIL: %0d errors", errors);
            $fatal(1, "E03 verification failed");
        end

        $display("============================");

        $finish;
    end

endmodule
