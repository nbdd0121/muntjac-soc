const UART_RBR: usize = 0x0000;
const UART_THR: usize = 0x0000;
const UART_FCR: usize = 0x0008;
const UART_LSR: usize = 0x0014;
const UART_LCR: usize = 0x000C;
const UART_DLL: usize = 0x0000;
const UART_DLM: usize = 0x0004;

#[inline]
fn reg(addr: usize) -> *mut u32 {
    (super::address::UART_BASE + addr) as _
}

pub fn uart_init() {
    // Reset FIFO
    unsafe {
        core::ptr::write_volatile(reg(UART_FCR), 0b111);
    }
    // Set baud to 256,000 8N1
    // 40M / (16 * 256000) ~= 10
    uart_set_mode(Config {
        divisor: 10,
        lcr: 0b11,
    });
}

#[derive(Clone, Copy)]
pub struct Config {
    pub divisor: u16,
    pub lcr: u8,
}

pub fn uart_set_mode(config: Config) {
    unsafe {
        core::ptr::write_volatile(reg(UART_LCR), (config.lcr | 0x80) as u32);
        core::ptr::write_volatile(reg(UART_DLL), (config.divisor & 0xff) as u32);
        core::ptr::write_volatile(reg(UART_DLM), (config.divisor >> 8) as u32);
        core::ptr::write_volatile(reg(UART_LCR), config.lcr as u32);
    }
}

pub fn uart_get_mode() -> Config {
    unsafe {
        let lcr = (core::ptr::read_volatile(reg(UART_LCR)) as u8) & !0x80;
        core::ptr::write_volatile(reg(UART_LCR), (lcr | 0x80) as u32);
        let dll = core::ptr::read_volatile(reg(UART_DLL)) as u8;
        let dlm = core::ptr::read_volatile(reg(UART_DLM)) as u8;
        core::ptr::write_volatile(reg(UART_LCR), lcr as u32);
        Config {
            divisor: (dlm as u16) << 8 | dll as u16,
            lcr,
        }
    }
}

pub fn uart_send_byte(byte: u8) {
    unsafe {
        while core::ptr::read_volatile(reg(UART_LSR)) & 0x20 == 0 {}
        core::ptr::write_volatile(reg(UART_THR), byte as u32);
    }
}

pub fn uart_try_recv_byte() -> Option<u8> {
    unsafe {
        if core::ptr::read_volatile(reg(UART_LSR)) & 0x01 != 0 {
            let data = core::ptr::read_volatile(reg(UART_RBR));
            Some(data as u8)
        } else {
            None
        }
    }
}
