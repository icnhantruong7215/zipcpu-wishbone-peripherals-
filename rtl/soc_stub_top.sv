`timescale 1ns/1ps
`default_nettype none

module soc_stub_top #(
    parameter [15:0] UART_CLOCKS_PER_BAUD = 16'd25,
    parameter integer SPI_CLK_DIV = 4,
    parameter bit USE_INTERNAL_SPI_SLAVE = 1'b1
) (
    input  logic        i_clk,
    input  logic        i_reset,

    input  logic        i_uart_rx,
    output logic        o_uart_tx,

    input  logic        i_spi_miso,     // external MISO, used when USE_INTERNAL_SPI_SLAVE=0
    output logic        o_spi_mosi,
    output logic        o_spi_sclk,
    output logic        o_spi_cs_n,

    output logic [1:0]  o_test_phase,
    output logic        o_done,
    output logic        o_pass,
    output logic        o_fail,
    output logic [7:0]  o_last_uart_byte,
    output logic [7:0]  o_last_spi_byte,
    output logic [7:0]  o_error_code
);
    logic        m_cyc, m_stb, m_we;
    logic [31:0] m_addr, m_wdata, m_rdata;
    logic        m_ack, m_stall;

    logic        spi_cyc, spi_stb, spi_we;
    logic [4:0]  spi_addr;
    logic [31:0] spi_wdata, spi_rdata;
    logic        spi_ack, spi_stall, spi_irq;

    logic        uart_cyc, uart_stb, uart_we;
    logic [4:0]  uart_addr;
    logic [31:0] uart_wdata, uart_rdata;
    logic        uart_ack, uart_stall, uart_irq;

    logic        spi_slave_miso;
    logic [7:0]  spi_slave_last_rx;
    logic        spi_slave_rx_valid;
    logic        spi_miso_to_master;

    assign spi_miso_to_master = USE_INTERNAL_SPI_SLAVE ? spi_slave_miso : i_spi_miso;

    wb_master_stub u_master (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .o_wb_cyc(m_cyc),
        .o_wb_stb(m_stb),
        .o_wb_we(m_we),
        .o_wb_addr(m_addr),
        .o_wb_wdata(m_wdata),
        .i_wb_rdata(m_rdata),
        .i_wb_ack(m_ack),
        .i_wb_stall(m_stall),
        .o_test_phase(o_test_phase),
        .o_done(o_done),
        .o_pass(o_pass),
        .o_fail(o_fail),
        .o_last_uart_byte(o_last_uart_byte),
        .o_last_spi_byte(o_last_spi_byte),
        .o_error_code(o_error_code)
    );

    wb_intercon u_intercon (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_m_cyc(m_cyc),
        .i_m_stb(m_stb),
        .i_m_we(m_we),
        .i_m_addr(m_addr),
        .i_m_wdata(m_wdata),
        .o_m_rdata(m_rdata),
        .o_m_ack(m_ack),
        .o_m_stall(m_stall),
        .o_spi_cyc(spi_cyc),
        .o_spi_stb(spi_stb),
        .o_spi_we(spi_we),
        .o_spi_addr(spi_addr),
        .o_spi_wdata(spi_wdata),
        .i_spi_rdata(spi_rdata),
        .i_spi_ack(spi_ack),
        .i_spi_stall(spi_stall),
        .o_uart_cyc(uart_cyc),
        .o_uart_stb(uart_stb),
        .o_uart_we(uart_we),
        .o_uart_addr(uart_addr),
        .o_uart_wdata(uart_wdata),
        .i_uart_rdata(uart_rdata),
        .i_uart_ack(uart_ack),
        .i_uart_stall(uart_stall)
    );

    wb_spi_master #(.SPI_CLK_DIV(SPI_CLK_DIV)) u_spi_wb (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_wb_cyc(spi_cyc),
        .i_wb_stb(spi_stb),
        .i_wb_we(spi_we),
        .i_wb_addr(spi_addr),
        .i_wb_data(spi_wdata),
        .o_wb_data(spi_rdata),
        .o_wb_ack(spi_ack),
        .o_wb_stall(spi_stall),
        .o_irq(spi_irq),
        .i_spi_miso(spi_miso_to_master),
        .o_spi_mosi(o_spi_mosi),
        .o_spi_sclk(o_spi_sclk),
        .o_spi_cs_n(o_spi_cs_n)
    );

    spi_slave_echo u_spi_slave_echo (
        .i_reset   (i_reset),
        .i_sclk    (o_spi_sclk),
        .i_cs_n    (o_spi_cs_n),
        .i_mosi    (o_spi_mosi),
        .o_miso    (spi_slave_miso),
        .o_last_rx (spi_slave_last_rx),
        .o_rx_valid(spi_slave_rx_valid)
    );

    wb_uart_fifo #(.CLOCKS_PER_BAUD(UART_CLOCKS_PER_BAUD), .LGFLEN(4)) u_uart_wb (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_wb_cyc(uart_cyc),
        .i_wb_stb(uart_stb),
        .i_wb_we(uart_we),
        .i_wb_addr(uart_addr),
        .i_wb_data(uart_wdata),
        .o_wb_data(uart_rdata),
        .o_wb_ack(uart_ack),
        .o_wb_stall(uart_stall),
        .o_irq(uart_irq),
        .i_uart_rx(i_uart_rx),
        .o_uart_tx(o_uart_tx)
    );
endmodule

`default_nettype wire
