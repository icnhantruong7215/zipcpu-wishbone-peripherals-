


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
