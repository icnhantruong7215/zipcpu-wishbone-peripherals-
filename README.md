# zipcpu_spi_wb_verilator_v14_spi_to_uart

Bản này là SoC stub dùng Wishbone Master Stub để kiểm tra UART/SPI trước khi tích hợp ZipCPU thật.

Thêm so với v13:
- Có SPI Slave Echo.
- Có test mới: SPI -> Wishbone -> UART.
- Log terminal được giữ đơn giản hơn để dễ chụp báo cáo.

## Chạy mô phỏng

```bash
make clean
make sim
```

## Các test chính

1. External UART source gửi `12345678`, master đọc UART RX FIFO rồi ghi sang SPI.
2. Master gửi chuỗi `bk_hcmut` sang SPI.
3. UART TX/RX loopback với `0x13`.
4. SPI byte test với `0x13`.
5. SPI nhận `0x5a`, master đọc qua Wishbone rồi ghi ra UART TX, UART RX loopback đọc lại `0x5a`.

Mở waveform:

```bash
make wave
```
