use core::time::Duration;

use super::address::CLINT_BASE;

pub fn time_u64() -> u64 {
    // We assume I/O are 32-bits, so this prevents HI change while we are reading low
    let time = 'l: loop {
        let hi = unsafe { core::ptr::read_volatile((CLINT_BASE + 0xBFFC) as *const u32) };
        let lo = unsafe { core::ptr::read_volatile((CLINT_BASE + 0xBFF8) as *const u32) };
        let hi2 = unsafe { core::ptr::read_volatile((CLINT_BASE + 0xBFFC) as *const u32) };
        if hi == hi2 {
            break 'l (hi as u64) << 32 | lo as u64;
        }
    };
    time
}

pub fn set_timer_u64(hart: usize, time: u64) {
    unsafe {
        // This is safe because it's okay if 64-bit write is broken into halves.
        core::ptr::write_volatile((CLINT_BASE + 0x4000 + hart * 8) as *mut u64, time);
    }
}

pub fn time() -> Duration {
    Duration::from_micros(time_u64())
}

pub fn sleep(duration: Duration) {
    let timer = Timer::new(duration);
    while !timer.fired() {}
}

pub struct Timer(pub Duration);

impl Timer {
    pub fn new(duration: Duration) -> Self {
        Timer(time() + duration)
    }

    pub fn fired(&self) -> bool {
        self.0 < time()
    }
}
