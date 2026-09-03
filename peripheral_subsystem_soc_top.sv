module peripheral_subsystem_soc_top #(
    parameter int DATA_WIDTH = 8,
    parameter int FIFO_DEPTH = 16,
    parameter int CLK_DIV_W  = 8,
    parameter int PADDR_W    = 4
)(
    // AMBA APB slave interface (SoC-facing)
    input  logic                   PCLK,
    input  logic                   PRESETn,
    input  logic                   PSEL,
    input  logic                   PENABLE,
    input  logic                   PWRITE,
    input  logic [PADDR_W-1:0]     PADDR,
    input  logic [31:0]            PWDATA,
    output logic [31:0]            PRDATA,
    output logic                   PREADY,
    output logic                   PSLVERR,

    // External SPI pins
    output logic                   SCLK,
    output logic                   MOSI,
    input  logic                   MISO,
    output logic                   SS_n
);

    // The SoC-facing shell preserves APB naming and directly routes the
    // wrapper's SPI pins to the external peripheral interface.
    peripheral_subsystem_apb #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .CLK_DIV_W(CLK_DIV_W),
        .PADDR_W(PADDR_W)
    ) u_peripheral_subsystem_apb (
        .pclk(PCLK),
        .presetn(PRESETn),
        .psel(PSEL),
        .penable(PENABLE),
        .pwrite(PWRITE),
        .paddr(PADDR),
        .pwdata(PWDATA),
        .prdata(PRDATA),
        .pready(PREADY),
        .pslverr(PSLVERR),
        .sclk(SCLK),
        .mosi(MOSI),
        .miso(MISO),
        .ss_n(SS_n)
    );

endmodule
