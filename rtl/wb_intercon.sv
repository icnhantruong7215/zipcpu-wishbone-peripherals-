`timescale 1ns/1ps
`default_nettype none

// Simple two-slave Wishbone interconnect.
// Address map:
//   0x0000_1000 - 0x0000_1fff : SPI Wishbone slave
//   0x0000_2000 - 0x0000_2fff : UART FIFO Wishbone slave
module wb_intercon (
    input  logic        i_clk,
    input  logic        i_reset,

    // Master side
    input  logic        i_m_cyc,
    input  logic        i_m_stb,
    input  logic        i_m_we,
    input  logic [31:0] i_m_addr,
    input  logic [31:0] i_m_wdata,
    output logic [31:0] o_m_rdata,
    output logic        o_m_ack,
    output logic        o_m_stall,

    // SPI slave side
    output logic        o_spi_cyc,
    output logic        o_spi_stb,
    output logic        o_spi_we,
    output logic [4:0]  o_spi_addr,
    output logic [31:0] o_spi_wdata,
    input  logic [31:0] i_spi_rdata,
    input  logic        i_spi_ack,
    input  logic        i_spi_stall,

    // UART slave side
    output logic        o_uart_cyc,
    output logic        o_uart_stb,
    output logic        o_uart_we,
    output logic [4:0]  o_uart_addr,
    output logic [31:0] o_uart_wdata,
    input  logic [31:0] i_uart_rdata,
    input  logic        i_uart_ack,
    input  logic        i_uart_stall
);
    wire sel_spi_addr  = (i_m_addr[15:12] == 4'h1);
    wire sel_uart_addr = (i_m_addr[15:12] == 4'h2);
    wire sel_bad_addr  = !sel_spi_addr && !sel_uart_addr;

    logic bad_ack;

    assign o_spi_cyc   = i_m_cyc && sel_spi_addr;
    assign o_spi_stb   = i_m_stb && sel_spi_addr;
    assign o_spi_we    = i_m_we;
    assign o_spi_addr  = i_m_addr[4:0];
    assign o_spi_wdata = i_m_wdata;

    assign o_uart_cyc   = i_m_cyc && sel_uart_addr;
    assign o_uart_stb   = i_m_stb && sel_uart_addr;
    assign o_uart_we    = i_m_we;
    assign o_uart_addr  = i_m_addr[4:0];
    assign o_uart_wdata = i_m_wdata;

    // Keep rdata selected by address only. This lets a simple master evaluate
    // read data one cycle after ACK while keeping the address stable.
    always_comb begin
        if (sel_spi_addr)       o_m_rdata = i_spi_rdata;
        else if (sel_uart_addr) o_m_rdata = i_uart_rdata;
        else                    o_m_rdata = 32'h0;
    end

    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            bad_ack <= 1'b0;
        end else begin
            bad_ack <= i_m_cyc && i_m_stb && sel_bad_addr && !bad_ack;
        end
    end

    assign o_m_ack   = i_spi_ack | i_uart_ack | bad_ack;
    assign o_m_stall = (sel_spi_addr  & i_spi_stall) |
                       (sel_uart_addr & i_uart_stall);
endmodule

`default_nettype wire
