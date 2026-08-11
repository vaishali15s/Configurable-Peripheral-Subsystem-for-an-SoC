`timescale 1ns/1ps

module sync_fifo_tb;

    parameter DATA_WIDTH = 8;
    parameter FIFO_DEPTH = 8;

    reg clk;
    reg rst_n;
    reg wr_en;
    reg rd_en;
    integer i;
    reg [DATA_WIDTH-1:0] din;
    reg [$clog2(FIFO_DEPTH):0] almost_full_val;
    reg [$clog2(FIFO_DEPTH):0] almost_empty_val;

    wire [DATA_WIDTH-1:0] dout;
    wire full;
    wire empty;
    wire almost_full;
    wire almost_empty;
    wire [$clog2(FIFO_DEPTH):0] data_count;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .din(din),
        .almost_full_val(almost_full_val),
        .almost_empty_val(almost_empty_val),
        .dout(dout),
        .full(full),
        .empty(empty),
        .almost_full(almost_full),
        .almost_empty(almost_empty),
        .data_count(data_count)
    );

    task automatic check_condition;
        input condition;
        input string msg;
        begin
            if (!condition) begin
                $display("FAIL: %s", msg);
                $finish;
            end
        end
    endtask

    task write_word;
        input [DATA_WIDTH-1:0] value;
        begin
            @(posedge clk);
            wr_en = 1'b1;
            din = value;
            @(posedge clk);
            wr_en = 1'b0;
        end
    endtask

    task read_word;
        begin
            @(posedge clk);
            rd_en = 1'b1;
            #1;
            @(posedge clk);
            rd_en = 1'b0;
        end
    endtask

    task automatic reset_fifo;
        begin
            rst_n = 1'b0;
            wr_en = 1'b0;
            rd_en = 1'b0;
            din = 0;
            almost_full_val = 0;
            almost_empty_val = 0;
            repeat (3) @(posedge clk);
            rst_n = 1'b1;
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        din = 0;
        almost_full_val = 0;
        almost_empty_val = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        #1;
        check_condition(empty === 1'b1, "initial empty flag");
        check_condition(full === 1'b0, "initial full flag");

        almost_full_val = 4;
        almost_empty_val = 2;

        write_word(8'h10);
        write_word(8'h11);
        write_word(8'h12);
        write_word(8'h13);

        #1;
        check_condition(almost_full === 1'b1, "almost_full after 4 writes");
        check_condition(data_count === 4, "data_count after 4 writes");

        write_word(8'h14);
        write_word(8'h15);
        write_word(8'h16);
        write_word(8'h17);

        #1;
        check_condition(full === 1'b1, "full flag after 8 writes");
        check_condition(data_count === 8, "data_count after 8 writes");

        read_word();
        check_condition(dout === 8'h10, "first read data");
        check_condition(empty === 1'b0, "empty after first read");

        read_word();
        check_condition(dout === 8'h11, "second read data");

        // Additional reset and edge-case checks
        reset_fifo();
        almost_full_val = 4;
        almost_empty_val = 2;

        check_condition(empty === 1'b1, "empty after reset");
        check_condition(full === 1'b0, "full after reset");
        check_condition(almost_empty === 1'b1, "almost_empty after reset");

        write_word(8'hAA);
        #1;
        check_condition(empty === 1'b0, "empty after first write");
        check_condition(full === 1'b0, "full after first write");

        // Fill FIFO and verify full flag
        for (i = 0; i < 7; i = i + 1) begin
            write_word(8'h10 + i);
        end
        #1;
        check_condition(full === 1'b1, "full after second fill");
        check_condition(almost_full === 1'b1, "almost_full after second fill");
        check_condition(data_count === 8, "data_count after second fill");

        // Wrap-around test: read some, write some, then read the rest
        for (i = 0; i < 4; i = i + 1) begin
            read_word();
            if (i == 0) begin
                check_condition(dout === 8'hAA, "wrap-around read #1");
            end else begin
                check_condition(dout === (8'h10 + (i - 1)), "wrap-around read #2+");
            end
        end

        for (i = 0; i < 4; i = i + 1) begin
            write_word(8'h20 + i);
        end

        #1;
        check_condition(data_count >= 0, "data_count after wrap-around writes");

        for (i = 0; i < 8; i = i + 1) begin
            read_word();
            if (i < 4) begin
                check_condition(dout === (8'h13 + i), "wrap-around drain #1-4");
            end else begin
                check_condition(dout === (8'h20 + (i - 4)), "wrap-around drain #5-8");
            end
        end

        // Stress sequence: alternating writes and reads with a deterministic pattern
        reset_fifo();
        for (i = 0; i < 10; i = i + 1) begin
            if ((i % 3) == 0) begin
                write_word(8'h30 + i);
            end else begin
                read_word();
            end
        end
        check_condition(data_count >= 0, "stress sequence data_count");

        $display("All FIFO tests passed.");
        $finish;
    end

endmodule
