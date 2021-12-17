use core::arch::asm;
use core::sync::atomic::{AtomicU32, AtomicUsize, Ordering};
use spin::Mutex;

use super::address::{CLINT_BASE, MAX_HART_COUNT};
use crate::hart_mask::HartMask;

static HART_COUNT: AtomicUsize = AtomicUsize::new(0);

pub fn hart_count() -> usize {
    HART_COUNT.load(Ordering::Relaxed)
}

fn probe_hart(hart: usize) -> bool {
    unsafe {
        let ptr = (CLINT_BASE + 0x4000 + hart * 8) as *mut u64;
        // Write a value to MTIMECMP and read back to see if it actually exists.
        core::ptr::write_volatile(ptr, u64::MAX - 1);
        if core::ptr::read_volatile(ptr) != u64::MAX - 1 {
            return false;
        }
        core::ptr::write_volatile(ptr, u64::MAX);
        if core::ptr::read_volatile(ptr) != u64::MAX {
            return false;
        }
        true
    }
}

pub fn probe_hart_count() {
    let count = (1..MAX_HART_COUNT)
        .find(|&i| !probe_hart(i))
        .unwrap_or(MAX_HART_COUNT);
    info!("{} cores probed from CLINT", count);
    HART_COUNT.store(count, Ordering::Relaxed);
}

pub fn set_msip(hart_id: usize, value: bool) {
    assert!(hart_id < hart_count());
    unsafe {
        core::ptr::write_volatile((CLINT_BASE + hart_id * 4) as *mut u32, value as u32);
    }
}

fn cpu_relax() {
    unsafe {
        asm!("nop; nop; nop", options(nomem, nostack));
    }
}

fn disable_irq() {
    unsafe {
        asm!("csrc mstatus, 8", options(nomem, nostack));
    }
    core::sync::atomic::compiler_fence(Ordering::Acquire);
}

fn enable_irq() {
    core::sync::atomic::compiler_fence(Ordering::Release);
    unsafe {
        asm!("csrs mstatus, 8", options(nomem, nostack));
    }
}

fn run_on_hart_common(
    mask: HartMask,
    f: &'static (dyn Fn() + Sync),
    wait: Option<&'static AtomicU32>,
) -> u32 {
    let cur_id = super::hartid();
    let mut wait_num = 0;
    for hart_id in 0..hart_count() {
        // Check the mask to determine if we need to run on this hart
        if hart_id == cur_id || !mask.is_set(hart_id) {
            continue;
        }

        wait_num += 1;

        // Set IPI_DATA
        loop {
            let mut guard = IPI_DATA[hart_id].lock();
            if guard.is_none() {
                *guard = Some(IpiData { func: f, wait });
                break;
            }
            // Some one has already send a IPI to this hart and it hasn't been processed yet.
            // Release the lock and wait for it to be cleared.
            drop(guard);

            // We expect the other hart to handle this relatively quickly, so busy wait.
            // Enable interrupt so we can deal with IPIs send to us
            enable_irq();
            cpu_relax();
            disable_irq();
        }

        // Kick the hart
        set_msip(hart_id, true);
    }

    if mask.is_set(cur_id) {
        f();
    }

    wait_num
}

pub fn run_on_hart(mask: HartMask, f: &'static (dyn Fn() + Sync)) {
    run_on_hart_common(mask, f, None);
}

pub fn run_on_hart_wait(mask: HartMask, f: &(dyn Fn() + Sync)) {
    let wait = AtomicU32::new(0);

    // This is okay, because we will wait for the call to complete. By the time wait is completed
    // we would have no copies of `f`, so this lifetime transmute is safe.
    let wait_num = run_on_hart_common(
        mask,
        unsafe { core::mem::transmute(f) },
        Some(unsafe { core::mem::transmute(&wait) }),
    );

    // Wait for the response of the ACK.
    loop {
        if wait.load(Ordering::Acquire) == wait_num {
            break;
        }
        enable_irq();
        cpu_relax();
        disable_irq();
    }
}

struct IpiData {
    func: &'static (dyn Fn() + Sync),
    wait: Option<&'static AtomicU32>,
}

static IPI_DATA: [Mutex<Option<IpiData>>; MAX_HART_COUNT] = {
    const INIT: Mutex<Option<IpiData>> = Mutex::new(None);
    [INIT; MAX_HART_COUNT]
};

pub fn process_ipi() {
    let cur_id = super::hartid();
    set_msip(cur_id, false);

    let mut guard = IPI_DATA[cur_id].lock();
    if let Some(data) = guard.take() {
        (data.func)();
        if let Some(wait) = data.wait {
            wait.fetch_add(1, Ordering::Release);
        }
    }
}
