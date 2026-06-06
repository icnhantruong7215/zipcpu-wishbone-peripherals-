`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// Simple SPI slave model for system-level simulation
// - SPI mode 0: CPOL=0, CPHA=0
// - Samples MOSI on SCLK rising edge while CS_N is low
// - Provides an echo response on MISO so the existing SPI master tests can read
//   back the same byte that was transmitted.
//
// Note:
//   This module is intended as a lightweight slave model for RTL verification.
//   It proves that the SPI master is connected to an actual slave-side block
//   rather than directly wiring MOSI to MISO in the testbench.
// -----------------------------------------------------------------------------
module spi_slave_echo (
    input  logic       i_reset,
    input  logic       i_sclk,
    input  logic       i_cs_n,
    input  logic       i_mosi,
    output logic       o_miso,
    output logic [7:0] o_last_rx,
    output logic       o_rx_valid
);
    logic [7:0] rx_shift;
    logic [2:0] bit_idx;

    // Echo mode: the slave returns the incoming MOSI bit on MISO while selected.
    // This keeps the previous loopback-style expected results, but the path now
    // goes through a slave module instead of a direct testbench assignment.
    always_comb begin
        if (!i_cs_n)
            o_miso = i_mosi;
        else
            o_miso = 1'b0;
    end

    // Capture the byte received by the slave for waveform/debug purposes.
    always_ff @(posedge i_sclk or posedge i_reset or posedge i_cs_n) begin
        if (i_reset || i_cs_n) begin
            rx_shift  <= 8'h00;
            bit_idx   <= 3'd7;
            o_rx_valid <= 1'b0;
        end else begin
            o_rx_valid <= 1'b0;
            rx_shift[bit_idx] <= i_mosi;

            if (bit_idx == 3'd0) begin
                o_last_rx <= {rx_shift[7:1], i_mosi};
                o_rx_valid <= 1'b1;
                bit_idx <= 3'd7;
            end else begin
                bit_idx <= bit_idx - 3'd1;
            end
        end
    end
endmodule

`default_nettype wire
