`timescale 1ns/1ps

module spi_master_tb;

    parameter int DATA_WIDTH = 8;
    parameter int CLK_DIV_WIDTH = 8;

    logic                   clk;
    logic                   rst_n;
    logic                   start;
    logic [CLK_DIV_WIDTH-1:0] clk_div;
    logic [1:0]             cpol_cpha;
    logic [DATA_WIDTH-1:0]  din;
    logic [DATA_WIDTH-1:0]  dout;
    logic                   busy;
    logic                   done;
    logic                   sclk;
    logic                   mosi;
    logic                   miso;
    logic                   ss_n;

    // Instantiate DUT (Device Under Test)
    spi_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .CLK_DIV_WIDTH(CLK_DIV_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .clk_div(clk_div),
        .cpol_cpha(cpol_cpha),
        .din(din),
        .dout(dout),
        .busy(busy),
        .done(done),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .ss_n(ss_n)
    );

    // Clock Generation: 100MHz (10ns period)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Loopback / Mock Miso Driver (simply echoes MOSI back or sends a fixed byte)
    // For a real test, you can drive MISO with specific responses.
    logic [7:0] miso_pattern = 8'h5A;
    int miso_bit_idx = 7;

    always_ff @(posedge sclk or posedge ss_n) begin
        if (ss_n) begin
            miso_bit_idx = 7;
            miso <= miso_pattern[7];
        end else begin
            // Shift out mock data on MISO edges
            miso <= miso_pattern[miso_bit_idx];
            if (miso_bit_idx > 0) begin
                miso_bit_idx--;
            end
        end
    end

    // Test Sequence
    initial begin
        // Initialize Signals
        rst_n     = 1'b0;
        start     = 1'b0;
        clk_div   = 8'd2;      // Divider setting
        cpol_cpha = 2'b00;     // Mode 0 (CPOL=0, CPHA=0)
        din       = 8'hA5;     // Data to transmit

        // Apply Reset
        #20;
        rst_n = 1'b1;
        #20;

        // Test 1: SPI Mode 0 Transaction
        $display("[%0t] Starting SPI Mode 0 Transaction...", $time);
        @(posedge clk);
        din   = 8'hA5;
        cpol_cpha = 2'b00;
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // Wait until transaction is complete
        @(posedge done);
        $display("[%0t] Transaction finished! Received Data: 0%h", $time, dout);

        // Test 2: SPI Mode 3 Transaction with a different divisor
        #50;
        $display("[%0t] Starting SPI Mode 3 Transaction...", $time);
        @(posedge clk);
        din   = 8'h3C;
        clk_div = 8'd4;
        cpol_cpha = 2'b11; // Mode 3 (CPOL=1, CPHA=1)
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        @(posedge done);
        $display("[%0t] Transaction finished! Received Data: 0%h", $time, dout);

        #50;
        $display("All SPI Master tests completed successfully.");
        $finish;
    end

endmodule