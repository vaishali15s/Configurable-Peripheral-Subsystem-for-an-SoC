module uart_top #(
    parameter int CLK_FREQ = 50000000,
    parameter int BAUD_RATE = 115200
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        wr_en,
    input  logic [7:0]  din,
    output logic [7:0]  dout,
    output logic        rx_valid,
    output logic        tx_busy,
    output logic        tx,
    input  logic        rx
);

    localparam int BIT_CLKS   = CLK_FREQ / BAUD_RATE;
    localparam int DIVISOR    = BIT_CLKS / 16;
    localparam int DIV_WIDTH  = ($clog2(DIVISOR) > 0) ? $clog2(DIVISOR) : 1;

    logic [DIV_WIDTH-1:0] baud_counter;
    logic tick_16x;

    // 16x Baud Tick Generator
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_counter <= '0;
            tick_16x     <= 1'b0;
        end else if (baud_counter == DIVISOR - 1) begin
            baud_counter <= '0;
            tick_16x     <= 1'b1;
        end else begin
            baud_counter <= baud_counter + 1'b1;
            tick_16x     <= 1'b0;
        end
    end

    // ==========================================
    // TRANSMITTER (TX) SECTION
    // ==========================================
    typedef enum logic [1:0] {
        TX_IDLE  = 2'b00,
        TX_START = 2'b01,
        TX_DATA  = 2'b10,
        TX_STOP  = 2'b11
    } tx_state_t;

    tx_state_t tx_state;
    logic [3:0] tx_bit_cnt;
    
    localparam int TX_BIT_CLKS   = BIT_CLKS;
    localparam int TX_CNT_WIDTH  = ($clog2(TX_BIT_CLKS) > 0) ? $clog2(TX_BIT_CLKS) : 1;
    
    logic [TX_CNT_WIDTH-1:0] tx_clk_cnt;
    logic [7:0] tx_shift_reg;
    logic tx_bit_tick;

    assign tx_bit_tick = (tx_state != TX_IDLE) && (tx_clk_cnt == TX_BIT_CLKS - 1);
    assign tx_busy     = (tx_state != TX_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_clk_cnt <= '0;
        end else if (tx_state == TX_IDLE) begin
            tx_clk_cnt <= '0;
        end else if (tx_clk_cnt == TX_BIT_CLKS - 1) begin
            tx_clk_cnt <= '0;
        end else begin
            tx_clk_cnt <= tx_clk_cnt + 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state     <= TX_IDLE;
            tx           <= 1'b1;
            tx_shift_reg <= '0;
            tx_bit_cnt   <= '0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx <= 1'b1;
                    if (wr_en && !tx_busy) begin
                        tx_shift_reg <= din;
                        tx_state     <= TX_START;
                        tx_bit_cnt   <= '0;
                        tx           <= 1'b0; // Start bit
                    end
                end

                TX_START: begin
                    tx <= 1'b0;
                    if (tx_bit_tick) begin
                        tx           <= tx_shift_reg[0];
                        tx_shift_reg <= tx_shift_reg >> 1;
                        tx_bit_cnt   <= 4'd0;
                        tx_state     <= TX_DATA;
                    end
                end

                TX_DATA: begin
                    if (tx_bit_tick) begin
                        if (tx_bit_cnt == 4'd7) begin
                            tx       <= 1'b1; // Stop bit start
                            tx_state <= TX_STOP;
                        end else begin
                            tx           <= tx_shift_reg[0];
                            tx_shift_reg <= tx_shift_reg >> 1;
                            tx_bit_cnt   <= tx_bit_cnt + 1'b1;
                        end
                    end
                end

                TX_STOP: begin
                    tx <= 1'b1;
                    if (tx_bit_tick) begin
                        tx_state <= TX_IDLE;
                    end
                end
            endcase
        end
    end

    // ==========================================
    // RECEIVER (RX) SECTION
    // ==========================================
    logic rx_sync1, rx_sync2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    typedef enum logic [1:0] {
        RX_IDLE  = 2'b00,
        RX_START = 2'b01,
        RX_DATA  = 2'b10,
        RX_STOP  = 2'b11
    } rx_state_t;

    rx_state_t rx_state;
    logic [3:0] rx_sample_cnt;
    logic [3:0] rx_bit_cnt;
    logic [7:0] rx_shift_reg;
    logic [1:0] rx_start_low_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state         <= RX_IDLE;
            rx_sample_cnt    <= '0;
            rx_bit_cnt       <= '0;
            rx_shift_reg     <= '0;
            rx_start_low_cnt <= '0;
            dout             <= '0;
            rx_valid         <= 1'b0;
        end else begin
            rx_valid <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (rx_sync2 == 1'b0) begin
                        if (rx_start_low_cnt == 2'd1) begin
                            rx_state         <= RX_START;
                            rx_sample_cnt    <= '0;
                            rx_start_low_cnt <= '0;
                        end else begin
                            rx_start_low_cnt <= rx_start_low_cnt + 1'b1;
                        end
                    end else begin
                        rx_start_low_cnt <= '0;
                    end
                end

                RX_START: begin
                    if (tick_16x) begin
                        if (rx_sample_cnt == 4'd7) begin
                            if (rx_sync2 == 1'b0) begin
                                rx_state      <= RX_DATA;
                                rx_sample_cnt <= '0;
                                rx_bit_cnt    <= '0;
                            end else begin
                                rx_state         <= RX_IDLE;
                                rx_start_low_cnt <= '0;
                            end
                        end else begin
                            rx_sample_cnt <= rx_sample_cnt + 1'b1;
                        end
                    end
                end

                RX_DATA: begin
                    if (tick_16x) begin
                        if (rx_sample_cnt == 4'd15) begin
                            rx_sample_cnt <= '0;
                            rx_shift_reg  <= {rx_sync2, rx_shift_reg[7:1]};
                            if (rx_bit_cnt == 4'd7) begin
                                rx_bit_cnt <= '0;
                                rx_state   <= RX_STOP;
                            end else begin
                                rx_bit_cnt <= rx_bit_cnt + 1'b1;
                            end
                        end else begin
                            rx_sample_cnt <= rx_sample_cnt + 1'b1;
                        end
                    end
                end

                RX_STOP: begin
                    if (tick_16x) begin
                        if (rx_sample_cnt == 4'd15) begin
                            rx_state         <= RX_IDLE;
                            rx_sample_cnt    <= '0;
                            rx_start_low_cnt <= '0;

                            if (rx_sync2 == 1'b1) begin
                                dout     <= rx_shift_reg;
                                rx_valid <= 1'b1;
                            end
                        end else begin
                            rx_sample_cnt <= rx_sample_cnt + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule