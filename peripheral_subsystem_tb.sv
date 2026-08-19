`timescale 1ns/1ps

module peripheral_subsystem_tb;

    parameter int DATA_WIDTH = 8;
    parameter int FIFO_DEPTH = 16;
    parameter int CLK_DIV_W  = 8;

    // Testbench signals
    logic                   clk;
    logic                   rst_n;
    logic                   uart_rx;
    logic                   uart_tx;
    logic                   sclk;
    logic                   mosi;
    logic                   miso;
    logic                   ss_n;
    logic [CLK_DIV_W-1:0]   spi_clk_div;
    logic [1:0]             spi_cpol_cpha;

    // Instantiate DUT (Device Under Test)
    peripheral_subsystem #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .CLK_DIV_W(CLK_DIV_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .ss_n(ss_n),
        .spi_clk_div(spi_clk_div),
        .spi_cpol_cpha(spi_cpol_cpha)
    );

    // Clock Generation: 50MHz (20ns period matches uart_top CLK_FREQ default)
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // Mock SPI Slave Response Driver on MISO
    // Whenever chip select (ss_n) drops low, shift back a fixed response byte (e.g., 8'h5A)
    logic [7:0] slave_resp_data = 8'h5A;
    int bit_index;

    always_ff @(negedge ss_n or posedge sclk) begin
        if (ss_n) begin
            bit_index = 7;
            miso <= slave_resp_data[7];
        end else begin
            if (bit_index > 0) begin
                bit_index--;
                miso <= slave_resp_data[bit_index];
            end
        end
    end

    // Test Sequence
    initial begin
        // Initialize Inputs
        rst_n         = 1'b0;
        uart_rx       = 1'b1; // UART line idles high
        spi_clk_div   = 8'd2;
        spi_cpol_cpha = 2'b00; // Mode 0

        // Apply Reset
        #100;
        rst_n = 1'b1;
        #100;

        $display("[%0t] Starting Peripheral Subsystem Integration Test...", $time);

        // Let simulation run long enough to exercise reset recovery and internal states
        #2000;
        
        $display("[%0t] Peripheral Subsystem simulation cycle completed successfully.", $time);
        $finish;
    end

endmodule