module spi_master #(
    parameter int DATA_WIDTH = 8,
    parameter int CLK_DIV_WIDTH = 8
)(
    input  logic                   clk,
    input  logic                   rst_n,
    
    // Control & Status Interface
    input  logic                   start,
    input  logic [CLK_DIV_WIDTH-1:0] clk_div,
    input  logic [1:0]             cpol_cpha, // {CPOL, CPHA}
    input  logic [DATA_WIDTH-1:0]  din,
    output logic [DATA_WIDTH-1:0]  dout,
    output logic                   busy,
    output logic                   done,
    
    // SPI Physical Interface
    output logic                   sclk,
    output logic                   mosi,
    input  logic                   miso,
    output logic                   ss_n
);

    // This controller converts a parallel word into an SPI transaction and
    // reconstructs the simultaneously received serial word.

    // Unpack mode bits
    logic cpol, cpha;
    assign cpol = cpol_cpha[1];
    assign cpha = cpol_cpha[0];

    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        SETUP = 2'b01,
        SHIFT = 2'b10,
        DONE  = 2'b11
    } state_t;

    state_t state;

    logic [CLK_DIV_WIDTH-1:0] clk_cnt;
    logic [$clog2(DATA_WIDTH):0] bit_cnt;
    logic [DATA_WIDTH-1:0] mosi_shift;
    logic [DATA_WIDTH-1:0] miso_shift;
    logic sample_edge;
    logic shift_edge;

    assign busy = (state != IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            sclk        <= 1'b0;
            mosi        <= 1'b0;
            ss_n        <= 1'b1;
            dout        <= '0;
            done        <= 1'b0;
            clk_cnt     <= '0;
            bit_cnt     <= '0;
            mosi_shift  <= '0;
            miso_shift  <= '0;
            sample_edge <= 1'b0;
            shift_edge  <= 1'b0;
        end else begin
            done <= 1'b0;
            
            // The FSM holds chip select active during setup and shifting,
            // then publishes the received word for one completion cycle.
            case (state)
                IDLE: begin
                    sclk <= cpol;
                    ss_n <= 1'b1;
                    if (start) begin
                        mosi_shift <= din;
                        state      <= SETUP;
                        ss_n       <= 1'b0;
                        clk_cnt    <= '0;
                        bit_cnt    <= DATA_WIDTH;
                    end
                end

                SETUP: begin
                    // Clock divider tick generation
                    if (clk_cnt == clk_div) begin
                        clk_cnt <= '0;
                        sclk    <= ~sclk;
                        state   <= SHIFT;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                SHIFT: begin
                    if (clk_cnt == clk_div) begin
                        clk_cnt <= '0;
                        sclk    <= ~sclk;

                        // Check if we finished the transfer
                        if (bit_cnt == 1 && sclk == (cpol ^ cpha)) begin
                            state <= DONE;
                        end else if (sclk == (cpol ^ cpha)) begin
                            // Shift out next bit
                            mosi       <= mosi_shift[DATA_WIDTH-1];
                            mosi_shift <= {mosi_shift[DATA_WIDTH-2:0], 1'b0};
                            bit_cnt    <= bit_cnt - 1'b1;
                        end else begin
                            // Sample MISO on alternate edge
                            miso_shift <= {miso_shift[DATA_WIDTH-2:0], miso};
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DONE: begin
                    ss_n <= 1'b1;
                    sclk <= cpol;
                    dout <= miso_shift;
                    done <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule