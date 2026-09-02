`timescale 1ns/1ps

module peripheral_subsystem_tb;

    parameter int DATA_WIDTH = 8;
    parameter int FIFO_DEPTH = 16;
    parameter int CLK_DIV_W  = 8;
    localparam int CLK_FREQ  = 50_000_000;
    localparam int BAUD_RATE = 115_200;
    localparam int BIT_CLKS  = CLK_FREQ / BAUD_RATE;
    localparam int HALF_BIT  = BIT_CLKS / 2;

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

    initial begin
        bit_index = 7;
        miso      = slave_resp_data[7];
    end

    always @(negedge ss_n) begin
        bit_index <= 7;
        miso      <= slave_resp_data[7];
    end

    always @(negedge sclk) begin
        if (!ss_n) begin
            if (bit_index > 0) begin
                bit_index <= bit_index - 1;
                miso      <= slave_resp_data[bit_index - 1];
            end else begin
                miso <= slave_resp_data[0];
            end
        end
    end

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

    task automatic wait_for_ss;
        input bit target_level;
        input int timeout_cycles;
        int cycle_idx;
        bit matched;
        begin
            matched = 1'b0;
            for (cycle_idx = 0; cycle_idx < timeout_cycles; cycle_idx++) begin
                if (ss_n === target_level) begin
                    matched = 1'b1;
                    cycle_idx = timeout_cycles;
                end else begin
                    @(posedge clk);
                end
            end
            check(matched, $sformatf("Timeout waiting for ss_n=%0b", target_level));
        end
    endtask

    task automatic drive_uart_rx_byte;
        input logic [7:0] value;
        int bit_idx;
        begin
            // Start bit
            @(negedge clk);
            uart_rx = 1'b0;
            repeat (BIT_CLKS) @(posedge clk);

            // Data bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
                uart_rx = value[bit_idx];
                repeat (BIT_CLKS) @(posedge clk);
            end

            // Stop bit and idle recovery
            uart_rx = 1'b1;
            repeat (BIT_CLKS * 3) @(posedge clk);
        end
    endtask

    task automatic expect_uart_tx_byte;
        input logic [7:0] expected;
        input int timeout_cycles;
        logic [7:0] observed;
        int bit_idx;
        int cycle_idx;
        begin
            observed = '0;

            // Wait for start bit
            cycle_idx = 0;
            while (uart_tx !== 1'b0 && cycle_idx < timeout_cycles) begin
                @(posedge clk);
                cycle_idx++;
            end
            check(uart_tx === 1'b0, "UART TX start bit was not observed");

            // Mid-start sample
            repeat (HALF_BIT) @(posedge clk);
            check(uart_tx === 1'b0, "UART TX start bit not held low to midpoint");

            // Sample 8 data bits
            for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
                repeat (BIT_CLKS) @(posedge clk);
                observed[bit_idx] = uart_tx;
            end

            // Stop bit
            repeat (BIT_CLKS) @(posedge clk);
            check(uart_tx === 1'b1, "UART TX stop bit not high");

            check(observed === expected,
                $sformatf("UART TX byte mismatch: expected %02h got %02h", expected, observed));
        end
    endtask

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
        
        // Drive one byte into UART RX with physical UART timing.
        // Expected full path: UART RX -> TX FIFO -> SPI -> RX FIFO -> UART TX
        fork
            begin
                drive_uart_rx_byte(8'hA6);
            end
            begin
                // Verify SPI transaction is started and completed.
                wait_for_ss(1'b0, BIT_CLKS * 40);
                wait_for_ss(1'b1, BIT_CLKS * 40);
            end
            begin
                // SPI slave returns 0x5A; verify that value is retransmitted on UART TX.
                expect_uart_tx_byte(8'h5A, BIT_CLKS * 120);
            end
        join

        // Let line settle back to idle.
        wait_cycles(BIT_CLKS * 2);
        check(uart_tx === 1'b1, "UART TX did not return to idle high");
        
        $display("[%0t] Peripheral Subsystem loopback test completed successfully.", $time);
        $finish;
    end

endmodule