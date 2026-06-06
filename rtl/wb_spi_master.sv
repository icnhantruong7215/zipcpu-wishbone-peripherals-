`timescale 1ns/1ps
`default_nettype none

module wb_spi_master #(
    parameter integer SPI_CLK_DIV = 4
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

    input  logic        i_spi_miso,
    output logic        o_spi_mosi,
    output logic        o_spi_sclk,
    output logic        o_spi_cs_n
);
    localparam logic [4:0] REG_RXDATA  = 5'h00;
    localparam logic [4:0] REG_TXDATA  = 5'h04;
    localparam logic [4:0] REG_STATUS  = 5'h08;
    localparam logic [4:0] REG_CONTROL = 5'h0c;
    localparam logic [4:0] REG_SSMASK  = 5'h10;

    logic [7:0] r_rxdata;
    logic [7:0] r_control;
    logic [7:0] r_ssmask;
    logic       r_rrdy;
    logic       r_toe;
    logic       r_roe;
    logic       spi_start;
    logic [7:0] spi_txdata;
    logic       spi_busy;
    logic       spi_done;
    logic [7:0] spi_rxdata;
    logic [3:0] spi_counter;
    logic       spi_select;

    wire trdy = !spi_busy && !spi_start;
    wire tmt  = !spi_busy;
    wire err  = r_toe | r_roe;
    wire [7:0] status = {err, r_rrdy, trdy, tmt, r_toe, r_roe, 2'b00};

    assign o_wb_stall = 1'b0;
    assign o_irq = (r_control[4] & r_rrdy) | (r_control[3] & trdy) |
                   (r_control[5] & err) | (r_control[1] & r_toe) |
                   (r_control[0] & r_roe);
    assign o_spi_cs_n = (spi_busy || spi_start) ? spi_select : ~(|r_ssmask);

    spi #(.CLK_DIV(SPI_CLK_DIV)) u_spi (
        .clk     (i_clk),
        .reset   (i_reset),
        .start   (spi_start),
        .data    (spi_txdata),
        .miso    (i_spi_miso),
        .select  (spi_select),
        .sclk    (o_spi_sclk),
        .sdata   (o_spi_mosi),
        .busy    (spi_busy),
        .done    (spi_done),
        .rx_data (spi_rxdata),
        .counter (spi_counter)
    );

    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            o_wb_ack  <= 1'b0;
            o_wb_data <= 32'h0;
            spi_start <= 1'b0;
            spi_txdata <= 8'h00;
            r_rxdata  <= 8'h00;
            r_control <= 8'h00;
            r_ssmask  <= 8'h01;
            r_rrdy    <= 1'b0;
            r_toe     <= 1'b0;
            r_roe     <= 1'b0;
        end else begin
            o_wb_ack  <= i_wb_cyc && i_wb_stb && !o_wb_ack;
            spi_start <= 1'b0;

            if (spi_done) begin
                if (r_rrdy)
                    r_roe <= 1'b1;
                r_rxdata <= spi_rxdata;
                r_rrdy   <= 1'b1;
            end

            if (i_wb_cyc && i_wb_stb && !o_wb_ack) begin
                if (i_wb_we) begin
                    case (i_wb_addr)
                        REG_TXDATA: begin
                            if (spi_busy)
                                r_toe <= 1'b1;
                            else begin
                                spi_txdata <= i_wb_data[7:0];
                                spi_start  <= 1'b1;
                            end
                        end
                        REG_CONTROL: begin
                            r_control <= i_wb_data[7:0];
                            r_toe <= 1'b0;
                            r_roe <= 1'b0;
                        end
                        REG_SSMASK: r_ssmask <= i_wb_data[7:0];
                        default: begin end
                    endcase
                end else begin
                    case (i_wb_addr)
                        REG_RXDATA: begin
                            o_wb_data <= {24'h0, r_rxdata};
                            r_rrdy <= 1'b0;
                        end
                        REG_STATUS:  o_wb_data <= {24'h0, status};
                        REG_CONTROL: o_wb_data <= {24'h0, r_control};
                        REG_SSMASK:  o_wb_data <= {24'h0, r_ssmask};
                        default:     o_wb_data <= 32'h0;
                    endcase
                end
            end
        end
    end
endmodule
`default_nettype wire
