use core::time::Duration;

const SPI_BASE: *mut u32 = 0x1005_0000 as _;

// Global interrupt enable register [Write]
const SPI_GIER: *mut u32 = (0x1005_0000 + 0x7 * 4) as _;

// // IP interrupt status register [Read/Toggle to write]
// #define SPI_ISR 0x08u

// // IP interrupt enable register [Read/Write]
// #define SPI_IER 0x0Au

// Software reset register [Write]
const SPI_SRR: *mut u32 = (0x1005_0000 + 0x10 * 4) as _;

// SPI control register [Read/Write]
const SPI_CR: *mut u32 = (0x1005_0000 + 0x18 * 4) as _;

// SPI status register [Read]
const SPI_SR: *mut u32 = (0x1005_0000 + 0x19 * 4) as _;

// SPI data transmit register, FIFO-16 [Write]
const SPI_DTR: *mut u32 = (0x1005_0000 + 0x1A * 4) as _;

// SPI data receive register, FIFO-16 [Read]
const SPI_DRR: *mut u32 = (0x1005_0000 + 0x1B * 4) as _;

// SPI Slave select register, [Read/Write]
const SPI_SSR: *mut u32 = (0x1005_0000 + 0x1C * 4) as _;

// // Transmit FIFO occupancy register [Read]
// #define SPI_TFOR 0x1Du

// // Receive FIFO occupancy register [Read]
// #define SPI_RFROR 0x1Eu

pub fn spi_init() {
    unsafe {
        // disable interrupt, full polling mode
        core::ptr::write_volatile(SPI_GIER, 0x0);

        // MSB first, master, reset FIFOs, SPI enabled, clock 00 mode
        core::ptr::write_volatile(SPI_CR, 0x86 | 0b11000);
    }
}

pub fn test() {
    spi_init();

    // Make STARTUP work
    spi_send(&[0; 16]);

    let mut recv_buf = [0u8; 10];
    spi_select_slave();
    spi_send(&[0xB, 0, 0, 0, 0]);
    spi_recv(&mut recv_buf);
    spi_deselect_slave();
    spi_fini();
    for &b in recv_buf.iter() {
        println!("{:x}", b);
    }
}

pub fn spi_fini() {
    unsafe {
        core::ptr::write_volatile(SPI_CR, 0xE4);
    }
}

pub fn spi_send(tx: &[u8]) {
    for tx in tx.chunks(16) {
        for byte in tx {
            unsafe {
                core::ptr::write_volatile(SPI_DTR, *byte as u32);
            }
        }
        while unsafe { core::ptr::read_volatile(SPI_SR) } & 4 == 0 {}
        unsafe { core::ptr::write_volatile(SPI_CR, 0xC6) }
    }
}

pub fn spi_recv(rx: &mut [u8]) {
    for rx in rx.chunks_mut(16) {
        for _ in 0..rx.len() {
            unsafe {
                core::ptr::write_volatile(SPI_DTR, 0xFF);
            }
        }
        while unsafe { core::ptr::read_volatile(SPI_SR) } & 4 == 0 {}
        for byte in rx {
            *byte = unsafe { core::ptr::read_volatile(SPI_DRR) } as u8;
        }
    }
}

pub fn spi_exchange(tx: &[u8], rx: &mut [u8]) {
    assert_eq!(tx.len(), rx.len());
    for (tx, rx) in tx.chunks(16).zip(rx.chunks_mut(16)) {
        for byte in tx {
            unsafe {
                core::ptr::write_volatile(SPI_DTR, *byte as u32);
            }
        }
        while unsafe { core::ptr::read_volatile(SPI_SR) } & 4 == 0 {}
        for byte in rx {
            *byte = unsafe { core::ptr::read_volatile(SPI_DRR) } as u8;
        }
    }
}

pub fn spi_send_byte(tx: u8) {
    spi_send_recv_byte(tx);
}

pub fn spi_send_recv_byte(tx: u8) -> u8 {
    let mut ret: u8 = 0;
    spi_exchange(&[tx], core::slice::from_mut(&mut ret));
    ret
}

pub fn spi_recv_byte() -> u8 {
    spi_send_recv_byte(0xFF)
}

pub fn spi_select_slave() {
    unsafe { core::ptr::write_volatile(SPI_SSR, 0xFFFFFFFE) }
}

pub fn spi_deselect_slave() {
    unsafe { core::ptr::write_volatile(SPI_SSR, 0xFFFFFFFF) }
}
