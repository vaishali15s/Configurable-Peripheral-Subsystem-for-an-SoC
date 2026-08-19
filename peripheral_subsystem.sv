`timescale 1ns/1ps

module peripheral_subsystem_top #(
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
    input  logic [1:0]             spi_cpol_cpha,
    input  logic [15:0]            uart_baud_div // If your UART takes a baud divisor
);

    // ----------------------------------------------------
    // Internal Wires & Signals
    // ----------------------------------------------------
    
    // UART Internal Interface Wires
    logic [DATA_WIDTH-1:0] uart_rx_data;
    logic                  uart_rx_valid;
    logic [DATA_WIDTH-1:0] uart_tx_data;
    logic                  uart_tx_start;
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
    // 1. UART Integration (Assuming standard uart_top ports)
    // ----------------------------------------------------
    // Note: Adjust port names below if your specific uart_top wrapper uses 
    // slightly different naming conventions for RX/TX streams.
    uart_top u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .tx(uart_tx),
        // RX path outputs to system/TX FIFO
        .rx_data(uart_rx_data),
        .rx_valid(uart_rx_valid),
        // TX path inputs from RX FIFO/system
        .tx_data(uart_tx_data),
        .tx_start(uart_tx_start),
        .tx_busy(uart_tx_busy)
    );

    // ----------------------------------------------------
    // 2. SPI TX FIFO (Buffers data from UART to send via SPI)
    // ----------------------------------------------------
    // Data coming from UART RX goes into SPI TX FIFO
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
        .almost_full_val(FIFO_DEPTH - 2),
        .almost_empty_val(2),
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
        .almost_full_val(FIFO_DEPTH - 2),
        .almost_empty_val(2),
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
    // Handles automated handshaking between the SPI TX FIFO, 
    // the SPI Master, and the UART TX channel.
    
    typedef enum logic [1:0] {
        IDLE        = 2'b00,
        SPI_EXEC    = 2'b01,
        UART_STREAM = 2'b10
    } state_t;

    state_t state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            spi_start     <= 1'b0;
            tx_fifo_rd_en <= 1'b0;
            rx_fifo_rd_en <= 1'b0;
            uart_tx_data  <= '0;
            uart_tx_start <= 1'b0;
        end else begin
            // Default control strobes
            spi_start     <= 1'b0;
            tx_fifo_rd_en <= 1'b0;
            rx_fifo_rd_en <= 1'b0;
            uart_tx_start <= 1'b0;

            case (state)
                IDLE: begin
                    // If there is data in SPI TX FIFO and SPI master is free
                    if (!tx_fifo_empty && !spi_busy) begin
                        tx_fifo_rd_en <= 1'b1; // Pop byte from TX FIFO
                        spi_start     <= 1'b1; // Trigger SPI transaction
                        state         <= SPI_EXEC;
                    end
                    // Or if we have received data in RX FIFO and UART is free to send
                    else if (!rx_fifo_empty && !uart_tx_busy) begin
                        rx_fifo_rd_en <= 1'b1; // Pop byte from RX FIFO
                        state         <= UART_STREAM;
                    end
                end

                SPI_EXEC: begin
                    // Wait for SPI transaction to finish, then stream RX data to UART if available
                    if (spi_done) begin
                        state <= IDLE;
                    end
                end

                UART_STREAM: begin
                    // Drive byte into UART TX channel
                    uart_tx_data  <= rx_fifo_dout;
                    uart_tx_start <= 1'b1;
                    state         <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule