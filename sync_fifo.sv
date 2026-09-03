module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 16
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      wr_en,
    input  wire                      rd_en,
    input  wire [DATA_WIDTH-1:0]     din,
    input  wire [$clog2(FIFO_DEPTH):0] almost_full_val,
    input  wire [$clog2(FIFO_DEPTH):0] almost_empty_val,
    
    output reg [DATA_WIDTH-1:0]      dout,
    output wire                      full,
    output wire                      empty,
    output wire                      almost_full,
    output wire                      almost_empty,
    output wire [$clog2(FIFO_DEPTH):0] data_count
);

    // This synchronous FIFO stores words in order while allowing independent
    // write and read requests; pointer arithmetic supplies occupancy status.

    // Local parameters for pointer bit-widths (extra bit for wrap-around detection)
    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);

    // Memory array declaration
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // Pointers with an extra MSB for full/empty differentiation
    reg [ADDR_WIDTH:0] wr_ptr, rd_ptr;
    reg [ADDR_WIDTH:0] wr_ptr_next, rd_ptr_next;

    // Status flags internal wires
    reg full_val, empty_val;
    reg [ADDR_WIDTH:0] data_count_reg;

    // Assign output flags
    assign full  = full_val;
    assign empty = empty_val;
    assign data_count = data_count_reg;

    // Watermark generation logic
    assign almost_full  = (data_count_reg >= almost_full_val);
    assign almost_empty = (data_count_reg <= almost_empty_val);

    // Next pointer logic
    always @(*) begin
        // Advance only the pointers whose requests are valid and whose
        // corresponding boundary condition does not block the operation.
        wr_ptr_next = wr_ptr;
        rd_ptr_next = rd_ptr;

        if (wr_en && !full_val) begin
            wr_ptr_next = wr_ptr + 1'b1;
        end

        if (rd_en && !empty_val) begin
            rd_ptr_next = rd_ptr + 1'b1;
        end
    end

    // Sequential pointer registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_WIDTH+1{1'b0}};
            rd_ptr <= {ADDR_WIDTH+1{1'b0}};
        end else begin
            wr_ptr <= wr_ptr_next;
            rd_ptr <= rd_ptr_next;
        end
    end

    // Memory write operation
    always @(posedge clk) begin
        // Writes are committed on the clock edge at the current write index.
        if (wr_en && !full_val) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
        end
    end

    // Memory read operation (combinational read data output)
    always @(*) begin
        // The current read location is exposed combinationally for simple
        // synchronous control logic and testbench observation.
        dout = mem[rd_ptr[ADDR_WIDTH-1:0]];
    end

    // Full and Empty flag logic
    // Full: pointers match except the wrap-around MSB is inverted
    // Empty: all pointer bits match exactly
    always @(*) begin
        full_val  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                    (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
        empty_val = (wr_ptr == rd_ptr);
        data_count_reg = wr_ptr - rd_ptr;
    end

endmodule