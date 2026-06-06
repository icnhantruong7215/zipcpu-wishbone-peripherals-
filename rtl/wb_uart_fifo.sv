`timescale 1ns/1ps
`default_nettype none

module wb_uart_fifo #(
    parameter [15:0] CLOCKS_PER_BAUD = 16'd25,
    parameter integer LGFLEN = 4
) (
    input  logic        i_clk,
    input  logic        i_reset,

    input  logic        i_wb_cyc,
    input  logic        i_wb_stb,
    input  logic        i_wb_we,
    input  logic [4:0]  i_wb_addr,
    input  logic [31:0] i_wb_data,
    output logic [31:0] o_wb_data,
    output logic        o_wb_ack,
    output logic        o_wb_stall,
    output logic        o_irq,

    input  wire         i_uart_rx,
    output wire         o_uart_tx
);
    localparam logic [4:0] REG_RXDATA = 5'h00;
    localparam logic [4:0] REG_TXDATA = 5'h04;
    localparam logic [4:0] REG_STATUS = 5'h08;

    wire [7:0] rxuart_data;
    wire       rxuart_wr;
    wire [7:0] rx_fifo_data;
    wire       rx_fifo_full, rx_fifo_empty;
    wire [LGFLEN:0] rx_fill;
    logic      rx_fifo_rd;

    wire [7:0] tx_fifo_data;
    wire       tx_fifo_full, tx_fifo_empty;
    wire [LGFLEN:0] tx_fill;
    wire       tx_fifo_wr;
    logic      tx_fifo_rd;
    wire       tx_busy;
    logic      txuart_wr;
    logic [7:0] txuart_data;
    logic       tx_start_pending;

    assign o_wb_stall = 1'b0;
    assign o_irq = !rx_fifo_empty;

    // UART status register map (kept simple and explicit for firmware/testbench)
    // bit[0] RX_VALID : RX FIFO has at least one byte to read
    // bit[1] TX_READY : TX FIFO can accept one more byte
    // bit[2] RX_FULL  : RX FIFO is full
    // bit[3] TX_EMPTY : TX FIFO is empty
    // bit[4] TX_BUSY  : UART transmitter is currently sending a frame
    // bit[5] IRQ      : same as RX_VALID, useful as a simple receive interrupt flag
    // bit[7:6] reserved
    wire [7:0] status = {
        2'b00,
        !rx_fifo_empty,
        tx_busy,
        tx_fifo_empty,
        rx_fifo_full,
        !tx_fifo_full,
        !rx_fifo_empty
    };

    rxuart #(.CLOCKS_PER_BAUD(CLOCKS_PER_BAUD)) u_rxuart (
        .i_clk     (i_clk),
        .i_uart_rx (i_uart_rx),
        .o_wr      (rxuart_wr),
        .o_data    (rxuart_data)
    );

    sfifo #(.BW(8), .LGFLEN(LGFLEN)) u_rx_fifo (
        .i_clk   (i_clk),
        .i_wr    (rxuart_wr && !rx_fifo_full),
        .i_data  (rxuart_data),
        .o_full  (rx_fifo_full),
        .o_fill  (rx_fill),
        .i_rd    (rx_fifo_rd),
        .o_data  (rx_fifo_data),
        .o_empty (rx_fifo_empty)
    );

    // Write into TX FIFO directly from the active Wishbone write cycle.
    // Do not delay i_wr by one clock, because the Wishbone master may
    // release i_wb_data immediately after ACK.
    assign tx_fifo_wr = i_wb_cyc && i_wb_stb && !o_wb_ack
                      && i_wb_we && (i_wb_addr == REG_TXDATA)
                      && !tx_fifo_full;

    sfifo #(.BW(8), .LGFLEN(LGFLEN)) u_tx_fifo (
        .i_clk   (i_clk),
        .i_wr    (tx_fifo_wr),
        .i_data  (i_wb_data[7:0]),
        .o_full  (tx_fifo_full),
        .o_fill  (tx_fill),
        .i_rd    (tx_fifo_rd),
        .o_data  (tx_fifo_data),
        .o_empty (tx_fifo_empty)
    );

    txuart #(.CLOCKS_PER_BAUD(CLOCKS_PER_BAUD)) u_txuart (
        .i_clk      (i_clk),
        .i_wr       (txuart_wr),
        .i_data     (txuart_data),
        .o_uart_tx  (o_uart_tx),
        .o_busy     (tx_busy)
    );

    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            o_wb_ack  <= 1'b0;
            o_wb_data <= 32'h0;
            tx_fifo_rd      <= 1'b0;
            rx_fifo_rd      <= 1'b0;
            txuart_wr       <= 1'b0;
            txuart_data     <= 8'h00;
            tx_start_pending<= 1'b0;
        end else begin
            o_wb_ack   <= i_wb_cyc && i_wb_stb && !o_wb_ack;
            tx_fifo_rd <= 1'b0;
            rx_fifo_rd <= 1'b0;
            txuart_wr  <= 1'b0;

            // Safe TX FIFO -> txuart handshake.
            // First latch the byte at the FIFO output and pop the FIFO.
            // On the next clock, pulse txuart_wr using the latched byte.
            // This avoids giving txuart a FIFO output that is changing in
            // the same clock as the FIFO read pointer moves.
            if (tx_start_pending && !tx_busy) begin
                txuart_wr        <= 1'b1;
                tx_start_pending <= 1'b0;
            end else if (!tx_busy && !tx_fifo_empty && !tx_start_pending) begin
                txuart_data      <= tx_fifo_data;
                tx_fifo_rd       <= 1'b1;
                tx_start_pending <= 1'b1;
            end

            if (i_wb_cyc && i_wb_stb && !o_wb_ack) begin
                if (i_wb_we) begin
                    // TXDATA write is handled by combinational tx_fifo_wr above
                    // so i_wb_data is captured in the same clock as the request.
                end else begin
                    case (i_wb_addr)
                        REG_RXDATA: begin
                            o_wb_data <= {24'h0, rx_fifo_data};
                            if (!rx_fifo_empty)
                                rx_fifo_rd <= 1'b1;
                        end
                        REG_STATUS: o_wb_data <= {24'h0, status};
                        default:    o_wb_data <= 32'h0;
                    endcase
                end
            end
        end
    end
endmodule
`default_nettype wire
