`timescale 1ns/1ps

module peripheral_subsystem_apb_tb;

    // APB verification covers register access, SPI completion, RX data
    // visibility, FIFO status transitions, and invalid-address reporting.

    parameter int DATA_WIDTH = 8;
    parameter int FIFO_DEPTH = 16;
    parameter int CLK_DIV_W  = 8;
    parameter int PADDR_W    = 4;

    logic                   pclk;
    logic                   presetn;
    logic                   psel;
    logic                   penable;
    logic                   pwrite;
    logic [PADDR_W-1:0]     paddr;
    logic [31:0]            pwdata;
    logic [31:0]            prdata;
    logic                   pready;
    logic                   pslverr;

    logic                   sclk;
    logic                   mosi;
    logic                   miso;
    logic                   ss_n;

    peripheral_subsystem_apb #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .CLK_DIV_W(CLK_DIV_W),
        .PADDR_W(PADDR_W)
    ) dut (
        .pclk(pclk),
        .presetn(presetn),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .ss_n(ss_n)
    );

    logic [7:0] miso_pattern = 8'h5A;
    int miso_bit_idx;

    initial begin
        pclk = 1'b0;
        forever #10 pclk = ~pclk; // 50 MHz
    end

    initial begin
        miso_bit_idx = 7;
        miso         = miso_pattern[7];
    end

    always @(negedge ss_n) begin
        miso_bit_idx <= 7;
        miso         <= miso_pattern[7];
    end

    always @(negedge sclk) begin
        // Present the fixed slave response one bit at a time on MISO.
        if (!ss_n) begin
            if (miso_bit_idx > 0) begin
                miso_bit_idx <= miso_bit_idx - 1;
                miso         <= miso_pattern[miso_bit_idx - 1];
            end else begin
                miso <= miso_pattern[0];
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
            repeat (cycles) @(posedge pclk);
        end
    endtask

    task automatic apb_write32;
        // Perform the APB setup, access, and teardown phases for a write.
        input logic [PADDR_W-1:0] addr;
        input logic [31:0] data;
        begin
            @(negedge pclk);
            psel    <= 1'b1;
            penable <= 1'b0;
            pwrite  <= 1'b1;
            paddr   <= addr;
            pwdata  <= data;

            @(negedge pclk);
            penable <= 1'b1;

            @(negedge pclk);
            psel    <= 1'b0;
            penable <= 1'b0;
            pwrite  <= 1'b0;
            paddr   <= '0;
            pwdata  <= '0;
        end
    endtask

    task automatic apb_read32;
        // Perform an APB read and capture PRDATA during the access phase.
        input logic [PADDR_W-1:0] addr;
        output logic [31:0] data;
        begin
            @(negedge pclk);
            psel    <= 1'b1;
            penable <= 1'b0;
            pwrite  <= 1'b0;
            paddr   <= addr;

            @(negedge pclk);
            penable <= 1'b1;
            #1 data = prdata;

            @(negedge pclk);
            psel    <= 1'b0;
            penable <= 1'b0;
            paddr   <= '0;
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
                    @(posedge pclk);
                end
            end
            check(matched, $sformatf("Timeout waiting for ss_n=%0b", target_level));
        end
    endtask

    initial begin
        logic [31:0] rd_data;
        logic [31:0] status_data;
        int poll_count;
        bit rx_ready;

        presetn = 1'b0;
        psel    = 1'b0;
        penable = 1'b0;
        pwrite  = 1'b0;
        paddr   = '0;
        pwdata  = 32'h0;

        wait_cycles(5);
        presetn = 1'b1;
        wait_cycles(2);

        // Program SPI control: mode=2'b00, clk_div=8'd2.
        apb_write32(4'h8, 32'h0000_0008); // [9:2]=2, [1:0]=0
        apb_read32(4'h8, rd_data);
        check(rd_data[9:2] == 8'd2, "Control register clk_div mismatch");
        check(rd_data[1:0] == 2'b00, "Control register cpol/cpha mismatch");

        // Write one byte into TX FIFO and wait for SPI transfer.
        apb_write32(4'h0, 32'h0000_00A6);
        wait_for_ss(1'b0, 5000);
        wait_for_ss(1'b1, 5000);

        // Poll status until RX FIFO has data (rx_empty bit [2] == 0)
        poll_count = 0;
        rx_ready   = 1'b0;
        while (poll_count < 200 && !rx_ready) begin
            apb_read32(4'hC, status_data);
            if (status_data[2] == 1'b0) begin
                rx_ready = 1'b1;
            end
            poll_count++;
        end
        check(rx_ready, "RX FIFO did not receive SPI return data");

        // Read RX FIFO and verify returned byte from MISO slave pattern.
        apb_read32(4'h4, rd_data);
        check(rd_data[7:0] == 8'h5A, $sformatf("Expected 0x5A in RX data, got 0x%02h", rd_data[7:0]));

        // Verify RX FIFO returns to empty after pop.
        apb_read32(4'hC, status_data);
        check(status_data[2] == 1'b1, "RX FIFO empty flag not set after read");

        // Invalid address should assert PSLVERR during access.
        @(negedge pclk);
        psel    <= 1'b1;
        penable <= 1'b0;
        pwrite  <= 1'b0;
        paddr   <= 4'hE;
        @(negedge pclk);
        penable <= 1'b1;
        #1 check(pslverr == 1'b1, "pslverr not asserted for invalid APB address");
        @(negedge pclk);
        psel    <= 1'b0;
        penable <= 1'b0;
        paddr   <= '0;

        $display("APB wrapper register-map test passed.");
        $finish;
    end

endmodule
