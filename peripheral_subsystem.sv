`timescale 1ns/1ps

module peripheral_subsystem #(
    parameter int DATA_WIDTH  = 8,
    parameter int FIFO_DEPTH  = 16,
    parameter int CLK_DIV_W   = 8
)(
    input  logic                   clk,
    input  logic                   rst_n,
    
    // UART Physical Interface
    input  logic                   uart_rx,
    output logic                   uart_tx,
    
    // SPI Physical Interface
    output logic                   sclk,
    output logic                   mosi,
    input  logic                   miso,
    output logic                   ss_n,
    
    // Configuration / Control Inputs
    input  logic [CLK_DIV_W-1:0]   spi_clk_div,
    input  logic [1:0]             spi_cpol_cpha
);

    // This top-level data path bridges UART input to SPI output and returns
    // SPI input through UART, using FIFOs to decouple the two peripherals.

    // ----------------------------------------------------
    // Internal Wires & Signals
    // ----------------------------------------------------
    
    // UART Internal Interface Wires
    logic [DATA_WIDTH-1:0] uart_rx_data;
    logic                  uart_rx_valid;
    logic [DATA_WIDTH-1:0] uart_tx_data;
    logic                  uart_tx_wr_en;
    logic                  uart_tx_busy;

    // SPI TX FIFO Wires
    logic                  tx_fifo_wr_en;
    logic                  tx_fifo_rd_en;
    logic [DATA_WIDTH-1:0] tx_fifo_din;
    logic [DATA_WIDTH-1:0] tx_fifo_dout;
    logic                  tx_fifo_full;
    logic                  tx_fifo_empty;

    // SPI RX FIFO Wires
    logic                  rx_fifo_wr_en;
    logic                  rx_fifo_rd_en;
    logic [DATA_WIDTH-1:0] rx_fifo_din;
    logic [DATA_WIDTH-1:0] rx_fifo_dout;
    logic                  rx_fifo_full;
    logic                  rx_fifo_empty;

    // SPI Master Control Wires
    logic                  spi_start;
    logic                  spi_busy;
    logic                  spi_done;
    logic [DATA_WIDTH-1:0] spi_dout;

    // ----------------------------------------------------
    // 1. UART Integration (Using exact ports from uart_top)
    // ----------------------------------------------------
    uart_top #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(115200)
    ) u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(uart_tx_wr_en),
        .din(uart_tx_data),
        .dout(uart_rx_data),
        .rx_valid(uart_rx_valid),
        .tx_busy(uart_tx_busy),
        .tx(uart_tx),
        .rx(uart_rx)
    );

    // ----------------------------------------------------
    // 2. SPI TX FIFO (Buffers data from UART to send via SPI)
    // ----------------------------------------------------
    assign tx_fifo_wr_en = uart_rx_valid;
    assign tx_fifo_din   = uart_rx_data;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_spi_tx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(tx_fifo_wr_en),
        .rd_en(tx_fifo_rd_en),
        .din(tx_fifo_din),
        .almost_full_val  (5'd14),
        .almost_empty_val (5'd2),
        .dout(tx_fifo_dout),
        .full(tx_fifo_full),
        .empty(tx_fifo_empty),
        .almost_full(),
        .almost_empty(),
        .data_count()
    );

    // ----------------------------------------------------
    // 3. SPI Master Controller
    // ----------------------------------------------------
    spi_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .CLK_DIV_WIDTH(CLK_DIV_W)
    ) u_spi_master (
        .clk(clk),
        .rst_n(rst_n),
        .start(spi_start),
        .clk_div(spi_clk_div),
        .cpol_cpha(spi_cpol_cpha),
        .din(tx_fifo_dout),
        .dout(spi_dout),
        .busy(spi_busy),
        .done(spi_done),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .ss_n(ss_n)
    );

    // ----------------------------------------------------
    // 4. SPI RX FIFO (Buffers incoming data from SPI to send via UART)
    // ----------------------------------------------------
    assign rx_fifo_wr_en = spi_done;
    assign rx_fifo_din   = spi_dout;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_spi_rx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(rx_fifo_wr_en),
        .rd_en(rx_fifo_rd_en),
        .din(rx_fifo_din),
        .almost_full_val  (5'd14),
        .almost_empty_val (5'd2),
        .dout(rx_fifo_dout),
        .full(rx_fifo_full),
        .empty(rx_fifo_empty),
        .almost_full(),
        .almost_empty(),
        .data_count()
    );

    // ----------------------------------------------------
    // 5. Subsystem Bridge Controller FSM
    // ----------------------------------------------------
    typedef enum logic [1:0] {
        IDLE        = 2'b00,
        SPI_EXEC    = 2'b01,
        UART_STREAM = 2'b10
    } state_t;

    state_t state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            spi_start      <= 1'b0;
            tx_fifo_rd_en  <= 1'b0;
            rx_fifo_rd_en  <= 1'b0;
            uart_tx_data   <= '0;
            uart_tx_wr_en  <= 1'b0;
        end else begin
            // Default control strobes
            spi_start      <= 1'b0;
            tx_fifo_rd_en  <= 1'b0;
            rx_fifo_rd_en  <= 1'b0;
            uart_tx_wr_en  <= 1'b0;

            // Priority is given to launching queued SPI work; completed SPI
            // words are then drained to UART whenever the transmitter is free.
            case (state)
                IDLE: begin
                    if (!tx_fifo_empty && !spi_busy) begin
                        tx_fifo_rd_en <= 1'b1; 
                        spi_start     <= 1'b1; 
                        state         <= SPI_EXEC;
                    end
                    else if (!rx_fifo_empty && !uart_tx_busy) begin
                        rx_fifo_rd_en <= 1'b1; 
                        state         <= UART_STREAM;
                    end
                end

                SPI_EXEC: begin
                    if (spi_done) begin
                        state <= IDLE;
                    end
                end

                UART_STREAM: begin
                    uart_tx_data  <= rx_fifo_dout;
                    uart_tx_wr_en <= 1'b1; // Trigger UART transmission
                    state         <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule