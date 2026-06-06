`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// Robust 8-bit SPI master for Verilator/FPGA demo
// - SPI mode 0: CPOL=0, CPHA=0
// - MSB first
// - MOSI is driven from a fixed TX register and bit index, not from a shift
//   register. This avoids any one-bit slip in loopback simulation.
// - start is a one-clock pulse. busy stays high until done.
// -----------------------------------------------------------------------------
module spi #(
    parameter integer CLK_DIV = 4
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       start,
    input  logic [7:0] data,
    input  logic       miso,

    output logic       select,   // CS_N, active low
    output logic       sclk,
    output logic       sdata,    // MOSI
    output logic       busy,
    output logic       done,
    output logic [7:0] rx_data,
    output logic [3:0] counter
);

    localparam logic [1:0] ST_IDLE = 2'd0;
    localparam logic [1:0] ST_LOW  = 2'd1;
    localparam logic [1:0] ST_HIGH = 2'd2;
    localparam logic [1:0] ST_DONE = 2'd3;

    logic [1:0]  state;
    logic [7:0]  tx_reg;
    logic [7:0]  rx_reg;
    logic [2:0]  bit_idx;      // current bit, 7 down to 0
    logic [31:0] div_count;

    wire div_done = (div_count == (CLK_DIV - 1));
    assign counter = {1'b0, bit_idx};

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= ST_IDLE;
            tx_reg    <= 8'h00;
            rx_reg    <= 8'h00;
            rx_data   <= 8'h00;
            bit_idx   <= 3'd7;
            div_count <= 32'd0;
            select    <= 1'b1;
            sclk      <= 1'b0;
            sdata     <= 1'b0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    select    <= 1'b1;
                    sclk      <= 1'b0;
                    sdata     <= 1'b0;
                    busy      <= 1'b0;
                    div_count <= 32'd0;
                    bit_idx   <= 3'd7;

                    if (start) begin
                        tx_reg    <= data;
                        rx_reg    <= 8'h00;
                        bit_idx   <= 3'd7;
                        select    <= 1'b0;
                        busy      <= 1'b1;
                        sclk      <= 1'b0;
                        sdata     <= data[7]; // first MSB is stable before first rising edge
                        div_count <= 32'd0;
                        state     <= ST_LOW;
                    end
                end

                // SCLK low phase: MOSI is stable here. After CLK_DIV cycles,
                // create the rising edge and sample MISO for mode 0.
                ST_LOW: begin
                    select <= 1'b0;
                    busy   <= 1'b1;
                    sclk   <= 1'b0;
                    sdata  <= tx_reg[bit_idx];

                    if (div_done) begin
                        div_count       <= 32'd0;
                        sclk            <= 1'b1;
                        rx_reg[bit_idx] <= miso;
                        state           <= ST_HIGH;
                    end else begin
                        div_count <= div_count + 1'b1;
                    end
                end

                // SCLK high phase. After CLK_DIV cycles, return low and either
                // prepare the next bit or finish the byte.
                ST_HIGH: begin
                    select <= 1'b0;
                    busy   <= 1'b1;
                    sclk   <= 1'b1;

                    if (div_done) begin
                        div_count <= 32'd0;
                        sclk      <= 1'b0;

                        if (bit_idx == 3'd0) begin
                            rx_data <= rx_reg;
                            state   <= ST_DONE;
                        end else begin
                            bit_idx <= bit_idx - 1'b1;
                            sdata   <= tx_reg[bit_idx - 1'b1];
                            state   <= ST_LOW;
                        end
                    end else begin
                        div_count <= div_count + 1'b1;
                    end
                end

                ST_DONE: begin
                    select <= 1'b1;
                    sclk   <= 1'b0;
                    sdata  <= 1'b0;
                    busy   <= 1'b0;
                    done   <= 1'b1;
                    state  <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
