`timescale 1ns/1ps
`default_nettype none

// Wishbone master stub used before integrating the real ZipCPU.
// It is only a small FSM that creates WB read/write cycles for testing.
// Tests:
//   1) external UART bytes -> WB -> SPI slave echo
//   2) WB -> SPI string "bk_hcmut"
//   3) WB -> UART TX/RX loopback, byte 0x13
//   4) WB -> SPI slave echo, byte 0x13
//   5) SPI RXDATA -> WB -> UART TX/RX, byte 0x5a
module wb_master_stub (
    input  logic        i_clk,
    input  logic        i_reset,

    output logic        o_wb_cyc,
    output logic        o_wb_stb,
    output logic        o_wb_we,
    output logic [31:0] o_wb_addr,
    output logic [31:0] o_wb_wdata,
    input  logic [31:0] i_wb_rdata,
    input  logic        i_wb_ack,
    input  logic        i_wb_stall,

    output logic [1:0]  o_test_phase, // phase 2 enables UART TX->RX loopback in the TB
    output logic        o_done,
    output logic        o_pass,
    output logic        o_fail,
    output logic [7:0]  o_last_uart_byte,
    output logic [7:0]  o_last_spi_byte,
    output logic [7:0]  o_error_code
);
    localparam logic [31:0] SPI_RXDATA   = 32'h0000_1000;
    localparam logic [31:0] SPI_TXDATA   = 32'h0000_1004;
    localparam logic [31:0] SPI_STATUS   = 32'h0000_1008;
    localparam logic [31:0] SPI_SSMASK   = 32'h0000_1010;

    localparam logic [31:0] UART_RXDATA  = 32'h0000_2000;
    localparam logic [31:0] UART_TXDATA  = 32'h0000_2004;
    localparam logic [31:0] UART_STATUS  = 32'h0000_2008;

    localparam int EXT_UART_COUNT = 8;
    localparam int SPI_STR_COUNT  = 8;
    localparam logic [7:0] TEST_BYTE = 8'h13;
    localparam logic [7:0] SPI_TO_UART_BYTE = 8'h5a; // ASCII 'Z'

    typedef enum logic [7:0] {
        ST_RESET_WAIT,
        ST_INIT_SPI_SS,

        // Test 1: external UART source -> UART RX FIFO -> Wishbone -> SPI slave echo
        ST_WAIT_UART_STATUS,
        ST_EVAL_UART_STATUS,
        ST_READ_UART_DATA,
        ST_EVAL_UART_DATA,
        ST_WRITE_SPI_DATA,
        ST_WAIT_SPI_STATUS,
        ST_EVAL_SPI_STATUS,
        ST_READ_SPI_DATA,
        ST_EVAL_SPI_DATA,

        // Test 2: direct SPI string: "bk_hcmut"
        ST_SPI_STR_WRITE,
        ST_SPI_STR_STATUS,
        ST_SPI_STR_EVAL_STATUS,
        ST_SPI_STR_READ,
        ST_SPI_STR_EVAL,

        // Test 3: UART TX/RX loopback using 0x13
        ST_UART_LB_WRITE,
        ST_UART_LB_STATUS,
        ST_UART_LB_EVAL_STATUS,
        ST_UART_LB_READ,
        ST_UART_LB_EVAL,

        // Test 4: SPI direct byte 0x13
        ST_SPI_BYTE_WRITE,
        ST_SPI_BYTE_STATUS,
        ST_SPI_BYTE_EVAL_STATUS,
        ST_SPI_BYTE_READ,
        ST_SPI_BYTE_EVAL,

        // Test 5: SPI -> WB -> UART TX/RX, byte 0x5a
        ST_SPI_UART_WRITE_SPI,
        ST_SPI_UART_STATUS,
        ST_SPI_UART_EVAL_STATUS,
        ST_SPI_UART_READ_SPI,
        ST_SPI_UART_EVAL_SPI,
        ST_SPI_UART_WRITE_UART,
        ST_SPI_UART_UART_STATUS,
        ST_SPI_UART_EVAL_UART_STATUS,
        ST_SPI_UART_READ_UART,
        ST_SPI_UART_EVAL_UART,

        ST_PASS,
        ST_FAIL,
        ST_HALT
    } state_t;

    state_t state;
    logic [7:0] byte_count;
    logic [7:0] active_byte;
    logic [15:0] reset_delay;

    function automatic logic [7:0] spi_string_byte(input logic [7:0] idx);
        begin
            case (idx)
                8'd0: spi_string_byte = 8'h62; // b
                8'd1: spi_string_byte = 8'h6b; // k
                8'd2: spi_string_byte = 8'h5f; // _
                8'd3: spi_string_byte = 8'h68; // h
                8'd4: spi_string_byte = 8'h63; // c
                8'd5: spi_string_byte = 8'h6d; // m
                8'd6: spi_string_byte = 8'h75; // u
                8'd7: spi_string_byte = 8'h74; // t
                default: spi_string_byte = 8'h00;
            endcase
        end
    endfunction

    task automatic start_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            o_wb_cyc   <= 1'b1;
            o_wb_stb   <= 1'b1;
            o_wb_we    <= 1'b1;
            o_wb_addr  <= addr;
            o_wb_wdata <= data;
        end
    endtask

    task automatic start_read(input logic [31:0] addr);
        begin
            o_wb_cyc   <= 1'b1;
            o_wb_stb   <= 1'b1;
            o_wb_we    <= 1'b0;
            o_wb_addr  <= addr;
            o_wb_wdata <= 32'h0;
        end
    endtask

    task automatic stop_bus;
        begin
            o_wb_cyc   <= 1'b0;
            o_wb_stb   <= 1'b0;
            o_wb_we    <= 1'b0;
            o_wb_wdata <= 32'h0;
        end
    endtask

    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            state            <= ST_RESET_WAIT;
            o_wb_cyc         <= 1'b0;
            o_wb_stb         <= 1'b0;
            o_wb_we          <= 1'b0;
            o_wb_addr        <= 32'h0;
            o_wb_wdata       <= 32'h0;
            o_test_phase     <= 2'd0;
            o_done           <= 1'b0;
            o_pass           <= 1'b0;
            o_fail           <= 1'b0;
            o_last_uart_byte <= 8'h00;
            o_last_spi_byte  <= 8'h00;
            o_error_code     <= 8'h00;
            byte_count       <= 8'h00;
            active_byte      <= 8'h00;
            reset_delay      <= 16'd0;
        end else begin
            case (state)
                ST_RESET_WAIT: begin
                    stop_bus();
                    o_test_phase <= 2'd0;
                    if (reset_delay < 16'd50) begin
                        reset_delay <= reset_delay + 16'd1;
                    end else begin
                        $display("start test");
                        state <= ST_INIT_SPI_SS;
                    end
                end

                ST_INIT_SPI_SS: begin
                    start_write(SPI_SSMASK, 32'h0000_0001);
                    if (i_wb_ack) begin
                        stop_bus();
                        $display("init spi ss");
                        $display("test1: uart rx -> spi");
                        state <= ST_WAIT_UART_STATUS;
                    end
                end

                //  Test 1 
                ST_WAIT_UART_STATUS: begin
                    start_read(UART_STATUS);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_EVAL_UART_STATUS;
                    end
                end

                ST_EVAL_UART_STATUS: begin
                    if (i_wb_rdata[0]) state <= ST_READ_UART_DATA; // RX_VALID
                    else               state <= ST_WAIT_UART_STATUS;
                end

                ST_READ_UART_DATA: begin
                    start_read(UART_RXDATA);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_EVAL_UART_DATA;
                    end
                end

                ST_EVAL_UART_DATA: begin
                    active_byte      <= i_wb_rdata[7:0];
                    o_last_uart_byte <= i_wb_rdata[7:0];
                    state <= ST_WRITE_SPI_DATA;
                end

                ST_WRITE_SPI_DATA: begin
                    start_write(SPI_TXDATA, {24'h0, active_byte});
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_WAIT_SPI_STATUS;
                    end
                end

                ST_WAIT_SPI_STATUS: begin
                    start_read(SPI_STATUS);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_EVAL_SPI_STATUS;
                    end
                end

                ST_EVAL_SPI_STATUS: begin
                    if (i_wb_rdata[6]) state <= ST_READ_SPI_DATA; // RRDY
                    else               state <= ST_WAIT_SPI_STATUS;
                end

                ST_READ_SPI_DATA: begin
                    start_read(SPI_RXDATA);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_EVAL_SPI_DATA;
                    end
                end

                ST_EVAL_SPI_DATA: begin
                    o_last_spi_byte <= i_wb_rdata[7:0];
                    $display("  %0d uart=%02x spi=%02x", byte_count, active_byte, i_wb_rdata[7:0]);
                    if (i_wb_rdata[7:0] != active_byte) begin
                        o_error_code <= 8'hA1;
                        state <= ST_FAIL;
                    end else if (byte_count == EXT_UART_COUNT-1) begin
                        byte_count <= 8'h00;
                        o_test_phase <= 2'd1;
                        $display("test1 ok");
                        $display("test2: spi string bk_hcmut");
                        state <= ST_SPI_STR_WRITE;
                    end else begin
                        byte_count <= byte_count + 8'd1;
                        state <= ST_WAIT_UART_STATUS;
                    end
                end

                //  Test 2 
                ST_SPI_STR_WRITE: begin
                    active_byte <= spi_string_byte(byte_count);
                    start_write(SPI_TXDATA, {24'h0, spi_string_byte(byte_count)});
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_STR_STATUS;
                    end
                end

                ST_SPI_STR_STATUS: begin
                    start_read(SPI_STATUS);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_STR_EVAL_STATUS;
                    end
                end

                ST_SPI_STR_EVAL_STATUS: begin
                    if (i_wb_rdata[6]) state <= ST_SPI_STR_READ;
                    else               state <= ST_SPI_STR_STATUS;
                end

                ST_SPI_STR_READ: begin
                    start_read(SPI_RXDATA);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_STR_EVAL;
                    end
                end

                ST_SPI_STR_EVAL: begin
                    o_last_spi_byte <= i_wb_rdata[7:0];
                    $display("  %0d tx=%02x rx=%02x", byte_count, active_byte, i_wb_rdata[7:0]);
                    if (i_wb_rdata[7:0] != active_byte) begin
                        o_error_code <= 8'hB1;
                        state <= ST_FAIL;
                    end else if (byte_count == SPI_STR_COUNT-1) begin
                        byte_count <= 8'h00;
                        o_test_phase <= 2'd2;
                        $display("test2 ok");
                        $display("test3: uart loop 13");
                        state <= ST_UART_LB_WRITE;
                    end else begin
                        byte_count <= byte_count + 8'd1;
                        state <= ST_SPI_STR_WRITE;
                    end
                end

                //  Test 3
                ST_UART_LB_WRITE: begin
                    start_write(UART_TXDATA, {24'h0, TEST_BYTE});
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_UART_LB_STATUS;
                    end
                end

                ST_UART_LB_STATUS: begin
                    start_read(UART_STATUS);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_UART_LB_EVAL_STATUS;
                    end
                end

                ST_UART_LB_EVAL_STATUS: begin
                    if (i_wb_rdata[0]) state <= ST_UART_LB_READ;
                    else               state <= ST_UART_LB_STATUS;
                end

                ST_UART_LB_READ: begin
                    start_read(UART_RXDATA);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_UART_LB_EVAL;
                    end
                end

                ST_UART_LB_EVAL: begin
                    o_last_uart_byte <= i_wb_rdata[7:0];
                    $display("  tx=%02x rx=%02x", TEST_BYTE, i_wb_rdata[7:0]);
                    if (i_wb_rdata[7:0] != TEST_BYTE) begin
                        o_error_code <= 8'hC1;
                        state <= ST_FAIL;
                    end else begin
                        o_test_phase <= 2'd3;
                        $display("test3 ok");
                        $display("test4: spi byte 13");
                        state <= ST_SPI_BYTE_WRITE;
                    end
                end

                //  Test 4 
                ST_SPI_BYTE_WRITE: begin
                    start_write(SPI_TXDATA, {24'h0, TEST_BYTE});
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_BYTE_STATUS;
                    end
                end

                ST_SPI_BYTE_STATUS: begin
                    start_read(SPI_STATUS);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_BYTE_EVAL_STATUS;
                    end
                end

                ST_SPI_BYTE_EVAL_STATUS: begin
                    if (i_wb_rdata[6]) state <= ST_SPI_BYTE_READ;
                    else               state <= ST_SPI_BYTE_STATUS;
                end

                ST_SPI_BYTE_READ: begin
                    start_read(SPI_RXDATA);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_BYTE_EVAL;
                    end
                end

                ST_SPI_BYTE_EVAL: begin
                    o_last_spi_byte <= i_wb_rdata[7:0];
                    $display("  tx=%02x rx=%02x", TEST_BYTE, i_wb_rdata[7:0]);
                    if (i_wb_rdata[7:0] != TEST_BYTE) begin
                        o_error_code <= 8'hD1;
                        state <= ST_FAIL;
                    end else begin
                        $display("test4 ok");
                        $display("test5: spi -> wb -> uart, byte 5a");
                        state <= ST_SPI_UART_WRITE_SPI;
                    end
                end

                //  Test 5 
                ST_SPI_UART_WRITE_SPI: begin
                    start_write(SPI_TXDATA, {24'h0, SPI_TO_UART_BYTE});
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_UART_STATUS;
                    end
                end

                ST_SPI_UART_STATUS: begin
                    start_read(SPI_STATUS);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_UART_EVAL_STATUS;
                    end
                end

                ST_SPI_UART_EVAL_STATUS: begin
                    if (i_wb_rdata[6]) state <= ST_SPI_UART_READ_SPI;
                    else               state <= ST_SPI_UART_STATUS;
                end

                ST_SPI_UART_READ_SPI: begin
                    start_read(SPI_RXDATA);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_UART_EVAL_SPI;
                    end
                end

                ST_SPI_UART_EVAL_SPI: begin
                    o_last_spi_byte <= i_wb_rdata[7:0];
                    active_byte <= i_wb_rdata[7:0];
                    $display("  spi rx=%02x", i_wb_rdata[7:0]);
                    if (i_wb_rdata[7:0] != SPI_TO_UART_BYTE) begin
                        o_error_code <= 8'hE1;
                        state <= ST_FAIL;
                    end else begin
                        o_test_phase <= 2'd2; // enable UART TX->RX loopback in tb
                        state <= ST_SPI_UART_WRITE_UART;
                    end
                end

                ST_SPI_UART_WRITE_UART: begin
                    start_write(UART_TXDATA, {24'h0, active_byte});
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_UART_UART_STATUS;
                    end
                end

                ST_SPI_UART_UART_STATUS: begin
                    start_read(UART_STATUS);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_UART_EVAL_UART_STATUS;
                    end
                end

                ST_SPI_UART_EVAL_UART_STATUS: begin
                    if (i_wb_rdata[0]) state <= ST_SPI_UART_READ_UART;
                    else               state <= ST_SPI_UART_UART_STATUS;
                end

                ST_SPI_UART_READ_UART: begin
                    start_read(UART_RXDATA);
                    if (i_wb_ack) begin
                        stop_bus();
                        state <= ST_SPI_UART_EVAL_UART;
                    end
                end

                ST_SPI_UART_EVAL_UART: begin
                    o_last_uart_byte <= i_wb_rdata[7:0];
                    $display("  uart rx=%02x", i_wb_rdata[7:0]);
                    if (i_wb_rdata[7:0] != SPI_TO_UART_BYTE) begin
                        o_error_code <= 8'hE2;
                        state <= ST_FAIL;
                    end else begin
                        $display("test5 ok");
                        state <= ST_PASS;
                    end
                end

                ST_PASS: begin
                    stop_bus();
                    o_test_phase <= 2'd3;
                    o_done <= 1'b1;
                    o_pass <= 1'b1;
                    o_fail <= 1'b0;
                    $display("all pass");
                    state <= ST_HALT;
                end

                ST_FAIL: begin
                    stop_bus();
                    o_test_phase <= 2'd3;
                    o_done <= 1'b1;
                    o_pass <= 1'b0;
                    o_fail <= 1'b1;
                    $display("fail code=%02x", o_error_code);
                    state <= ST_HALT;
                end

                ST_HALT: begin
                    stop_bus();
                end

                default: begin
                    o_error_code <= 8'hFF;
                    state <= ST_FAIL;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
