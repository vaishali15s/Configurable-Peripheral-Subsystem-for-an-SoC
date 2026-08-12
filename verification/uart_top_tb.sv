`timescale 1ns/1ps

module uart_top_tb;

    localparam int CLK_FREQ  = 320;
    localparam int BAUD_RATE = 10;
    localparam int BIT_CLKS   = CLK_FREQ / BAUD_RATE;
    localparam int HALF_BIT   = BIT_CLKS / 2;

    logic clk;
    logic rst_n;
    logic wr_en;
    logic [7:0] din;
    logic [7:0] dout;
    logic rx_valid;
    logic tx_busy;
    logic tx;
    logic rx_line;

    uart_top #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .din(din),
        .dout(dout),
        .rx_valid(rx_valid),
        .tx_busy(tx_busy),
        .tx(tx),
        .rx(rx_line)
    );

    task automatic check;
        input bit condition;
        input string message;
        begin
            if (!condition) begin
                $fatal(1, "FAIL: %s", message);
            end
        end
    endtask

    task automatic wait_cycles;
        input int cycles;
        begin
            repeat (cycles) @(posedge clk);
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n   = 1'b0;
            wr_en   = 1'b0;
            din     = 8'h00;
            rx_line = 1'b1;
            wait_cycles(4);
            rst_n = 1'b1;
            wait_cycles(2);
        end
    endtask

    task automatic pulse_write;
        input logic [7:0] value;
        begin
            @(negedge clk);
            din   = value;
            wr_en = 1'b1;
            @(negedge clk);
            wr_en = 1'b0;
        end
    endtask

    task automatic drive_rx_frame;
        input logic [7:0] value;
        input bit stop_high;
        int bit_idx;
        begin
            @(negedge clk);
            rx_line = 1'b0;
            repeat (BIT_CLKS) @(posedge clk);

            for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
                rx_line = value[bit_idx];
                repeat (BIT_CLKS) @(posedge clk);
            end

            rx_line = stop_high;
            repeat (BIT_CLKS) @(posedge clk);

            rx_line = 1'b1;
            repeat (BIT_CLKS) @(posedge clk);
        end
    endtask

    task automatic drive_rx_byte;
        input logic [7:0] value;
        begin
            drive_rx_frame(value, 1'b1);
        end
    endtask

    task automatic drive_rx_glitch;
        input int low_cycles;
        begin
            @(negedge clk);
            rx_line = 1'b0;
            repeat (low_cycles) @(posedge clk);
            rx_line = 1'b1;
            repeat (BIT_CLKS) @(posedge clk);
        end
    endtask

    task automatic expect_rx_byte;
        input logic [7:0] expected;
        begin
            wait (rx_valid === 1'b1);
            #1;
            check(dout === expected, $sformatf("received byte expected %02h got %02h", expected, dout));
        end
    endtask

    task automatic expect_tx_frame;
        input logic [7:0] expected;
        int frame_cycles;
        begin
            wait (tx_busy === 1'b1);
            #1;
            check(tx === 1'b0, "tx start bit low");
            check(tx_busy === 1'b1, "tx_busy asserted during transmission");

            repeat (HALF_BIT) @(posedge clk);
            #1;
            check(tx === 1'b0, "start bit still low at midpoint");

            frame_cycles = 0;
            while (tx_busy === 1'b1 && frame_cycles < BIT_CLKS * 20) begin
                @(posedge clk);
                #1;
                frame_cycles++;
            end

            check(frame_cycles >= BIT_CLKS * 9, $sformatf("tx frame too short for %02h", expected));

            #1;
            check(tx === 1'b1, "tx idle high after frame");
        end
    endtask

    task automatic ensure_no_rx_valid;
        input int cycles;
        int cycle_idx;
        begin
            for (cycle_idx = 0; cycle_idx < cycles; cycle_idx++) begin
                @(posedge clk);
                #1;
                check(rx_valid === 1'b0, "rx_valid must remain low");
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n   = 1'b0;
        wr_en   = 1'b0;
        din     = 8'h00;
        rx_line = 1'b1;

        reset_dut();

        check(tx === 1'b1, "tx idle high after reset");
        check(tx_busy === 1'b0, "tx_busy low after reset");
        check(rx_valid === 1'b0, "rx_valid low after reset");

        // 1. Basic TX Test
        fork
            begin
                pulse_write(8'hA5);
            end
            begin
                expect_tx_frame(8'hA5);
            end
        join

        check(tx_busy === 1'b0, "tx_busy low after transmit");

        // 2. Basic RX Test
        fork
            begin
                drive_rx_byte(8'h3C);
            end
            begin
                expect_rx_byte(8'h3C);
            end
        join

        // 3. Busy Write Rejection Test
        fork
            begin
                pulse_write(8'h66);
            end
            begin
                wait (tx_busy === 1'b1);
                repeat (BIT_CLKS / 2) @(posedge clk);
                @(negedge clk);
                din   = 8'h99;
                wr_en = 1'b1;
                @(negedge clk);
                wr_en = 1'b0;
            end
            begin
                expect_tx_frame(8'h66);
            end
        join

        wait_cycles(BIT_CLKS * 2);
        check(tx_busy === 1'b0, "busy write rejected without extending transmit");
        check(tx === 1'b1, "tx returns idle high after rejected busy write");

        // 4. Reset During TX Test
        reset_dut();
        @(negedge clk);
        din   = 8'hC7;
        wr_en = 1'b1;
        @(negedge clk);
        wr_en = 1'b0;
        wait (tx_busy === 1'b1);
        repeat (BIT_CLKS / 2) @(posedge clk);
        rst_n = 1'b0;
        wait_cycles(3);
        rst_n = 1'b1;
        wait_cycles(4);
        check(tx_busy === 1'b0, "reset clears busy during TX");
        check(tx === 1'b1, "reset drives tx idle high during TX");
        check(rx_valid === 1'b0, "reset clears rx_valid during TX");

        // 5. Glitch and Bad Framing Tests
        drive_rx_glitch(1);
        ensure_no_rx_valid(BIT_CLKS * 2);

        drive_rx_frame(8'h5E, 1'b0); // Bad stop bit
        ensure_no_rx_valid(BIT_CLKS * 4);

        drive_rx_frame(8'h5E, 1'b1); // Good frame
        expect_rx_byte(8'h5E);

        // 6. Reset During RX Test
        fork
            begin
                drive_rx_byte(8'hA3);
            end
            begin
                repeat (BIT_CLKS * 2 + HALF_BIT) @(posedge clk);
                rst_n = 1'b0;
                wait_cycles(3);
                rst_n = 1'b1;
            end
        join

        wait_cycles(2);
        check(rx_valid === 1'b0, "reset clears rx_valid during RX");

        // 7. Stress Testing Multiple Packets
        for (int stress_idx = 0; stress_idx < 4; stress_idx++) begin
            fork
                begin
                    pulse_write(8'h40 + stress_idx[7:0]);
                end
                begin
                    drive_rx_byte(8'h80 + stress_idx[7:0]);
                end
                begin
                    expect_tx_frame(8'h40 + stress_idx[7:0]);
                end
                begin
                    expect_rx_byte(8'h80 + stress_idx[7:0]);
                end
            join
        end

        // 8. Full-Duplex Simultaneous Operation
        fork
            begin
                pulse_write(8'h5A);
            end
            begin
                drive_rx_byte(8'hC3);
            end
            begin
                wait (tx_busy === 1'b1);
                #1;
                check(tx_busy === 1'b1, "tx busy during full duplex");
            end
            begin
                expect_rx_byte(8'hC3);
            end
        join

        check(tx_busy === 1'b0, "tx_busy low after full duplex frame");
        check(tx === 1'b1, "tx idle high after full duplex frame");

        $display("All UART tests passed.");
        $fflush();
        $finish;
    end

endmodule