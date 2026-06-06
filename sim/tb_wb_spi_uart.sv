`timescale 1ns/1ps
`default_nettype none

module tb_wb_spi_uart;
    localparam int CLK_PERIOD_NS = 10;
    localparam int UART_CLKS_PER_BAUD = 25;

    localparam logic [31:0] SPI_BASE      = 32'h0000_1000;
    localparam logic [31:0] SPI_RXDATA    = SPI_BASE  + 32'h00;
    localparam logic [31:0] SPI_TXDATA    = SPI_BASE  + 32'h04;
    localparam logic [31:0] SPI_STATUS    = SPI_BASE  + 32'h08;
    localparam logic [31:0] SPI_SSMASK    = SPI_BASE  + 32'h10;

    localparam logic [31:0] UART_BASE     = 32'h0000_2000;
    localparam logic [31:0] UART_RXDATA   = UART_BASE + 32'h00;
    localparam logic [31:0] UART_TXDATA   = UART_BASE + 32'h04;
    localparam logic [31:0] UART_STATUS   = UART_BASE + 32'h08;

    logic clk;
    logic reset;

    logic        wb_cyc;
    logic        wb_stb;
    logic        wb_we;
    logic [31:0] wb_addr;
    logic [31:0] wb_wdata;
    logic [31:0] wb_rdata;
    logic        wb_ack;
    logic        wb_stall;

    logic uart_rx_drv;
    logic uart_loopback_en;
    wire  uart_rx;
    logic uart_tx;
    logic spi_miso;
    logic spi_mosi;
    logic spi_sclk;
    logic spi_cs_n;

    assign spi_miso = spi_mosi; // SPI loopback for simulation
    assign uart_rx  = (uart_loopback_en) ? uart_tx : uart_rx_drv;

    wb_peripheral_subsystem #(
        .UART_CLOCKS_PER_BAUD(UART_CLKS_PER_BAUD),
        .SPI_CLK_DIV(4)
    ) dut (
        .i_clk(clk),
        .i_reset(reset),
        .i_wb_cyc(wb_cyc),
        .i_wb_stb(wb_stb),
        .i_wb_we(wb_we),
        .i_wb_addr(wb_addr),
        .i_wb_data(wb_wdata),
        .o_wb_data(wb_rdata),
        .o_wb_ack(wb_ack),
        .o_wb_stall(wb_stall),
        .i_uart_rx(uart_rx),
        .o_uart_tx(uart_tx),
        .i_spi_miso(spi_miso),
        .o_spi_mosi(spi_mosi),
        .o_spi_sclk(spi_sclk),
        .o_spi_cs_n(spi_cs_n)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS/2) clk = !clk;

    task automatic reset_dut;
        begin
            reset   = 1'b1;
            wb_cyc  = 1'b0;
            wb_stb  = 1'b0;
            wb_we   = 1'b0;
            wb_addr = 32'h0;
            wb_wdata= 32'h0;
            uart_rx_drv = 1'b1; // UART idle is high
            uart_loopback_en = 1'b0;
            repeat (10) @(posedge clk);
            reset = 1'b0;
            repeat (10) @(posedge clk);
        end
    endtask

    task automatic wb_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(posedge clk);
            wb_cyc   <= 1'b1;
            wb_stb   <= 1'b1;
            wb_we    <= 1'b1;
            wb_addr  <= addr;
            wb_wdata <= data;
            do @(posedge clk); while (!wb_ack);
            wb_cyc   <= 1'b0;
            wb_stb   <= 1'b0;
            wb_we    <= 1'b0;
            wb_addr  <= 32'h0;
            wb_wdata <= 32'h0;
            @(posedge clk);
        end
    endtask

    task automatic wb_read(input logic [31:0] addr, output logic [31:0] data);
        begin
            @(posedge clk);
            wb_cyc   <= 1'b1;
            wb_stb   <= 1'b1;
            wb_we    <= 1'b0;
            wb_addr  <= addr;
            wb_wdata <= 32'h0;

            do @(posedge clk); while (!wb_ack);

            // Important for Verilator/SystemVerilog scheduling:
            // peripheral read data is updated using non-blocking assignments
            // at the same clock edge that ACK is asserted. Wait one delta step
            // before sampling wb_rdata in the testbench.
            #1;
            data = wb_rdata;

            wb_cyc   <= 1'b0;
            wb_stb   <= 1'b0;
            wb_addr  <= 32'h0;
            @(posedge clk);
        end
    endtask

    task automatic wait_spi_trdy;
        logic [31:0] status;
        int timeout;
        begin
            timeout = 0;
            do begin
                wb_read(SPI_STATUS, status);
                timeout++;
                if (timeout > 1000) begin
                    $error("Timeout waiting SPI TRDY, last status = 0x%02x", status[7:0]);
                    $finish;
                end
            end while (status[5] != 1'b1);
        end
    endtask

    task automatic wait_spi_rrdy;
        logic [31:0] status;
        int timeout;
        begin
            timeout = 0;
            do begin
                wb_read(SPI_STATUS, status);
                timeout++;
                if (timeout > 1000) begin
                    $error("Timeout waiting SPI RRDY, last status = 0x%02x", status[7:0]);
                    $finish;
                end
            end while (status[6] != 1'b1);
        end
    endtask

    task automatic wait_uart_rx_ready;
        logic [31:0] status;
        int timeout;
        begin
            timeout = 0;
            do begin
                wb_read(UART_STATUS, status);
                timeout++;
                if (timeout > 1000) begin
                    $error("Timeout waiting UART RX ready, last status = 0x%02x", status[7:0]);
                    $finish;
                end
            // UART status map is defined by RTL, not by the testbench:
            // STATUS[0] = RX_VALID, STATUS[1] = TX_READY, STATUS[2] = RX_FULL,
            // STATUS[3] = TX_EMPTY, STATUS[4] = TX_BUSY, STATUS[5] = IRQ/RX_VALID.
            end while (status[0] != 1'b1);
        end
    endtask

    task automatic wait_uart_tx_ready;
        logic [31:0] status;
        int timeout;
        begin
            timeout = 0;
            do begin
                wb_read(UART_STATUS, status);
                timeout++;
                if (timeout > 1000) begin
                    $error("Timeout waiting UART TX ready, last status = 0x%02x", status[7:0]);
                    $finish;
                end
            end while (status[1] != 1'b1); // STATUS[1] = TX_READY
        end
    endtask

    // This task models an external UART source, such as a PC terminal,
    // sending one UART byte into FPGA uart_rx.
    // 8N1 format: start bit 0, 8 data bits LSB-first, stop bit 1.
    task automatic pc_uart_send_byte(input logic [7:0] data);
        int i;
        begin
            uart_rx_drv <= 1'b0; // start bit
            repeat (UART_CLKS_PER_BAUD) @(posedge clk);

            for (i = 0; i < 8; i++) begin
                uart_rx_drv <= data[i];
                repeat (UART_CLKS_PER_BAUD) @(posedge clk);
            end

            uart_rx_drv <= 1'b1; // stop bit
            repeat (UART_CLKS_PER_BAUD) @(posedge clk);
        end
    endtask

    task automatic test_uart_rx_from_external_source;
        logic [7:0] msg [0:7];
        logic [31:0] rdata;
        int i;
        begin
            msg[0] = 8'h31; // '1'
            msg[1] = 8'h32; // '2'
            msg[2] = 8'h33; // '3'
            msg[3] = 8'h34; // '4'
            msg[4] = 8'h35; // '5'
            msg[5] = 8'h36; // '6'
            msg[6] = 8'h37; // '7'
            msg[7] = 8'h38; // '8'

            $display("\n===== UART RX TEST: External UART source sends 12345678 =====");
            for (i = 0; i < 8; i++) begin
                pc_uart_send_byte(msg[i]);
                wait_uart_rx_ready();
                wb_read(UART_RXDATA, rdata);
                $display("UART RX[%0d] expected 0x%02x, got 0x%02x", i, msg[i], rdata[7:0]);
                if (rdata[7:0] !== msg[i]) begin
                    $error("UART RX mismatch at index %0d", i);
                    $finish;
                end
            end
            $display("UART RX TEST PASSED");
        end
    endtask

    task automatic test_uart_loopback_byte_0x13;
        logic [31:0] rdata;
        begin
            $display("\n===== UART 8-BIT LOOPBACK TEST: Wishbone writes 0x13, UART RX reads 0x13 =====");
            uart_loopback_en <= 1'b1;
            repeat (5) @(posedge clk);

            wait_uart_tx_ready();
            wb_write(UART_TXDATA, 32'h0000_0013);

            wait_uart_rx_ready();
            wb_read(UART_RXDATA, rdata);
            $display("UART LOOPBACK expected 0x13, got 0x%02x", rdata[7:0]);
            if (rdata[7:0] !== 8'h13) begin
                $error("UART 8-bit loopback mismatch");
                $finish;
            end

            uart_loopback_en <= 1'b0;
            uart_rx_drv <= 1'b1;
            repeat (5) @(posedge clk);
            $display("UART 8-BIT LOOPBACK TEST PASSED");
        end
    endtask

    task automatic test_spi_loopback;
        logic [7:0] msg [0:7];
        logic [31:0] rdata;
        int i;
        begin
            msg[0] = 8'h62; // 'b'
            msg[1] = 8'h6b; // 'k'
            msg[2] = 8'h5f; // '_'
            msg[3] = 8'h68; // 'h'
            msg[4] = 8'h63; // 'c'
            msg[5] = 8'h6d; // 'm'
            msg[6] = 8'h75; // 'u'
            msg[7] = 8'h74; // 't'

            $display("\n===== SPI LOOPBACK TEST: Wishbone master writes bk_hcmut to SPI TXDATA =====");
            wb_write(SPI_SSMASK, 32'h0000_0001);

            for (i = 0; i < 8; i++) begin
                wait_spi_trdy();
                wb_write(SPI_TXDATA, {24'h0, msg[i]});
                wait_spi_rrdy();
                wb_read(SPI_RXDATA, rdata);
                $display("SPI RX[%0d] expected 0x%02x, got 0x%02x", i, msg[i], rdata[7:0]);
                if (rdata[7:0] !== msg[i]) begin
                    $error("SPI loopback mismatch at index %0d", i);
                    $finish;
                end
            end
            $display("SPI LOOPBACK TEST PASSED");
        end
    endtask

    task automatic test_spi_single_byte_0x13;
        logic [31:0] rdata;
        begin
            $display("\n===== SPI 8-BIT LOOPBACK TEST: Wishbone writes 0x13, SPI RX reads 0x13 =====");
            wb_write(SPI_SSMASK, 32'h0000_0001);
            wait_spi_trdy();
            wb_write(SPI_TXDATA, 32'h0000_0013);
            wait_spi_rrdy();
            wb_read(SPI_RXDATA, rdata);
            $display("SPI LOOPBACK expected 0x13, got 0x%02x", rdata[7:0]);
            if (rdata[7:0] !== 8'h13) begin
                $error("SPI 8-bit loopback mismatch");
                $finish;
            end
            $display("SPI 8-BIT LOOPBACK TEST PASSED");
        end
    endtask

    initial begin
        $dumpfile("tb_wb_spi_uart.vcd");
        $dumpvars(0, tb_wb_spi_uart);

        reset_dut();
        test_uart_rx_from_external_source();
        test_uart_loopback_byte_0x13();
        test_spi_loopback();
        test_spi_single_byte_0x13();

        $display("\nALL TESTS PASSED: Wishbone + UART RX/TX loopback + SPI loopback are working.");
        $finish;
    end
endmodule
`default_nettype wire
