`timescale 1ns/1ps
`default_nettype none

module wb_peripheral_subsystem #(
    parameter [15:0] UART_CLOCKS_PER_BAUD = 16'd25,
    parameter integer SPI_CLK_DIV = 4
) (
    input  logic        i_clk,
    input  logic        i_reset,

    input  logic        i_wb_cyc,
    input  logic        i_wb_stb,
    input  logic        i_wb_we,
    input  logic [31:0] i_wb_addr,
    input  logic [31:0] i_wb_data,
    output logic [31:0] o_wb_data,
    output logic        o_wb_ack,
    output logic        o_wb_stall,

    input  logic        i_uart_rx,
    output logic        o_uart_tx,

    input  logic        i_spi_miso,
    output logic        o_spi_mosi,
    output logic        o_spi_sclk,
    output logic        o_spi_cs_n
);
    localparam logic [31:0] SPI_BASE  = 32'h0000_1000;
    localparam logic [31:0] UART_BASE = 32'h0000_2000;

    wire sel_spi  = i_wb_cyc && i_wb_stb && (i_wb_addr[15:12] == SPI_BASE[15:12]);
    wire sel_uart = i_wb_cyc && i_wb_stb && (i_wb_addr[15:12] == UART_BASE[15:12]);

    logic [31:0] spi_rdata, uart_rdata;
    logic spi_ack, uart_ack;
    logic spi_stall, uart_stall;
    logic spi_irq, uart_irq;

    wb_spi_master #(.SPI_CLK_DIV(SPI_CLK_DIV)) u_wb_spi (
        .i_clk(i_clk), .i_reset(i_reset),
        .i_wb_cyc(i_wb_cyc && sel_spi),
        .i_wb_stb(i_wb_stb && sel_spi),
        .i_wb_we(i_wb_we),
        .i_wb_addr(i_wb_addr[4:0]),
        .i_wb_data(i_wb_data),
        .o_wb_data(spi_rdata),
        .o_wb_ack(spi_ack),
        .o_wb_stall(spi_stall),
        .o_irq(spi_irq),
        .i_spi_miso(i_spi_miso),
        .o_spi_mosi(o_spi_mosi),
        .o_spi_sclk(o_spi_sclk),
        .o_spi_cs_n(o_spi_cs_n)
    );

    wb_uart_fifo #(.CLOCKS_PER_BAUD(UART_CLOCKS_PER_BAUD), .LGFLEN(4)) u_wb_uart (
        .i_clk(i_clk), .i_reset(i_reset),
        .i_wb_cyc(i_wb_cyc && sel_uart),
        .i_wb_stb(i_wb_stb && sel_uart),
        .i_wb_we(i_wb_we),
        .i_wb_addr(i_wb_addr[4:0]),
        .i_wb_data(i_wb_data),
        .o_wb_data(uart_rdata),
        .o_wb_ack(uart_ack),
        .o_wb_stall(uart_stall),
        .o_irq(uart_irq),
        .i_uart_rx(i_uart_rx),
        .o_uart_tx(o_uart_tx)
    );

    always_comb begin
        if (sel_spi)       o_wb_data = spi_rdata;
        else if (sel_uart) o_wb_data = uart_rdata;
        else               o_wb_data = 32'h0;
    end

    assign o_wb_ack   = spi_ack | uart_ack | (i_wb_cyc && i_wb_stb && !sel_spi && !sel_uart);
    assign o_wb_stall = (sel_spi & spi_stall) | (sel_uart & uart_stall);
endmodule
`default_nettype wire
