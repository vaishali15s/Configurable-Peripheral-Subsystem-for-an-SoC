module peripheral_subsystem_apb #(
    parameter int DATA_WIDTH = 8,
    parameter int FIFO_DEPTH = 16,
    parameter int CLK_DIV_W  = 8,
    parameter int PADDR_W    = 4
)(
    input  logic                   pclk,
    input  logic                   presetn,
    input  logic                   psel,
    input  logic                   penable,
    input  logic                   pwrite,
    input  logic [PADDR_W-1:0]     paddr,
    input  logic [31:0]            pwdata,
    output logic [31:0]            prdata,
    output logic                   pready,
    output logic                   pslverr,

    output logic                   sclk,
    output logic                   mosi,
    input  logic                   miso,
    output logic                   ss_n
);

    localparam logic [PADDR_W-1:0] REG_TX_DATA  = 4'h0;
    localparam logic [PADDR_W-1:0] REG_RX_DATA  = 4'h4;
    localparam logic [PADDR_W-1:0] REG_CONTROL  = 4'h8;
    localparam logic [PADDR_W-1:0] REG_STATUS   = 4'hC;

    logic [CLK_DIV_W-1:0] spi_clk_div_reg;
    logic [1:0]           spi_cpol_cpha_reg;

    logic                 apb_access;
    logic                 apb_write;
    logic                 apb_read;

    logic                 tx_fifo_wr_en;
    logic [DATA_WIDTH-1:0] tx_fifo_din;
    logic                 tx_fifo_rd_en;
    logic [DATA_WIDTH-1:0] tx_fifo_dout;
    logic                 tx_fifo_full;
    logic                 tx_fifo_empty;

    logic                 rx_fifo_wr_en;
    logic                 rx_fifo_rd_en;
    logic [DATA_WIDTH-1:0] rx_fifo_din;
    logic [DATA_WIDTH-1:0] rx_fifo_dout;
    logic                 rx_fifo_full;
    logic                 rx_fifo_empty;

    logic                 spi_start;
    logic                 spi_busy;
    logic                 spi_done;
    logic [DATA_WIDTH-1:0] spi_dout;

    typedef enum logic [0:0] {
        IDLE     = 1'b0,
        SPI_EXEC = 1'b1
    } state_t;

    state_t state;

    assign pready = 1'b1;
    assign apb_access = psel && penable;
    assign apb_write  = apb_access && pwrite;
    assign apb_read   = apb_access && !pwrite;

    always @(*) begin
        tx_fifo_wr_en = 1'b0;
        tx_fifo_din   = pwdata[DATA_WIDTH-1:0];
        rx_fifo_rd_en = 1'b0;
        pslverr       = 1'b0;

        if (apb_write && paddr == REG_TX_DATA) begin
            tx_fifo_wr_en = !tx_fifo_full;
        end

        if (apb_read && paddr == REG_RX_DATA) begin
            rx_fifo_rd_en = !rx_fifo_empty;
        end

        if (apb_access) begin
            case (paddr)
                REG_TX_DATA, REG_RX_DATA, REG_CONTROL, REG_STATUS: pslverr = 1'b0;
                default: pslverr = 1'b1;
            endcase
        end
    end

    always @(*) begin
        prdata = 32'h0;
        case (paddr)
            REG_RX_DATA: begin
                prdata = {24'h0, (rx_fifo_empty ? 8'h00 : rx_fifo_dout)};
            end
            REG_CONTROL: begin
                prdata = {22'h0, spi_clk_div_reg, spi_cpol_cpha_reg};
            end
            REG_STATUS: begin
                prdata[0] = tx_fifo_empty;
                prdata[1] = tx_fifo_full;
                prdata[2] = rx_fifo_empty;
                prdata[3] = rx_fifo_full;
                prdata[4] = spi_busy;
            end
            default: begin
                prdata = 32'h0;
            end
        endcase
    end

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            spi_clk_div_reg <= 8'd2;
            spi_cpol_cpha_reg <= 2'b00;
        end else if (apb_write && paddr == REG_CONTROL) begin
            spi_cpol_cpha_reg <= pwdata[1:0];
            spi_clk_div_reg   <= pwdata[9:2];
        end
    end

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_spi_tx_fifo (
        .clk(pclk),
        .rst_n(presetn),
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

    spi_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .CLK_DIV_WIDTH(CLK_DIV_W)
    ) u_spi_master (
        .clk(pclk),
        .rst_n(presetn),
        .start(spi_start),
        .clk_div(spi_clk_div_reg),
        .cpol_cpha(spi_cpol_cpha_reg),
        .din(tx_fifo_dout),
        .dout(spi_dout),
        .busy(spi_busy),
        .done(spi_done),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .ss_n(ss_n)
    );

    assign rx_fifo_wr_en = spi_done;
    assign rx_fifo_din   = spi_dout;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_spi_rx_fifo (
        .clk(pclk),
        .rst_n(presetn),
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

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state       <= IDLE;
            tx_fifo_rd_en <= 1'b0;
            spi_start   <= 1'b0;
        end else begin
            tx_fifo_rd_en <= 1'b0;
            spi_start   <= 1'b0;

            case (state)
                IDLE: begin
                    if (!tx_fifo_empty && !spi_busy) begin
                        tx_fifo_rd_en <= 1'b1;
                        spi_start     <= 1'b1;
                        state         <= SPI_EXEC;
                    end
                end
                SPI_EXEC: begin
                    if (spi_done) begin
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
