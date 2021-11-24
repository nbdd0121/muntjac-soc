#![no_std]
#![no_main]
#![feature(asm)]
#![feature(thread_local)]
#![feature(default_alloc_error_handler)]

#[macro_use]
extern crate alloc;
#[macro_use]
extern crate log;
extern crate compiler_builtins_local;
extern crate unwinding;

#[allow(dead_code)]
#[macro_use]
mod util;
#[macro_use]
mod fmt;

#[allow(dead_code)]
mod block;
mod fs;
mod hart_mask;
mod io;
mod iomem;
mod net;
mod panic;

#[allow(dead_code)]
mod memtest;

mod fp;

#[allow(dead_code)]
mod address {
    include!(concat!(env!("OUT_DIR"), "/address.rs"));

    pub const MAX_HART_COUNT: usize = 4;
}

mod allocator;
mod elf;
mod inflate;
mod interp;
mod ipi;
mod memory;
mod misalign;
mod sbi;
mod timer;
#[allow(dead_code)]
mod uart;

use core::sync::atomic::{AtomicUsize, Ordering};

use self::ipi::hart_count;

#[repr(C)]
pub struct Context {
    registers: [usize; 32],
    pc: usize,
    mstatus: usize,
}

impl core::fmt::Debug for Context {
    fn fmt(&self, f: &mut core::fmt::Formatter) -> core::fmt::Result {
        const NAMES: &[&str] = &[
            "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13",
            "x14", "x15", "x16", "x17", "x18", "x19", "x20", "x21", "x22", "x23", "x24", "x25",
            "x26", "x27", "x28", "x29", "x30", "x31",
        ];
        let mut dbg = f.debug_struct("Context");
        for i in 1..32 {
            dbg.field(NAMES[i], &format_args!("{:#x}", self.registers[i]));
        }
        dbg.field("pc", &format_args!("{:#x}", self.pc))
            .field("mstatus", &format_args!("{:#x}", self.mstatus))
            .finish()
    }
}

fn hartid() -> usize {
    unsafe {
        let hartid: usize;
        asm!("csrr {}, mhartid", out(reg) hartid, options(pure, nomem, nostack));
        hartid
    }
}

#[derive(Debug)]
pub struct TrapInfo {
    pub cause: usize,
    pub tval: usize,
}

fn load_kernel() -> alloc::vec::Vec<u8> {
    if true {
        let time = timer::time();
        let mut vec = net::load_kernel();
        let elapsed = timer::time() - time;
        info!("kernel downloaded, elapsed: {:?}", elapsed);

        if inflate::is_gzip(&vec) {
            info!("kernel is compressed with gzip");
            let time = timer::time();
            vec = inflate::inflate(&vec).unwrap();
            let elapsed = timer::time() - time;
            info!("kernel decompressed, elapsed: {:?}", elapsed);
        }
        vec
    } else {
        use alloc::sync::Arc;
        use io::Read;

        let sd = Arc::new(unsafe { block::Sd::new(crate::address::SD_BASE) });
        sd.power_on();

        // let part = Arc::new(block::Part::first_partition(sd.clone()).unwrap());

        let fs = fs::ext::FileSystem::new(sd.clone()).unwrap();
        let root = fs.root().unwrap();

        let mut kernel: Option<fs::ext::File> = None;

        for entry in root {
            let entry = entry.unwrap();
            if !entry.is_dir() {
                println!("/{}", entry.file_name());

                if entry.file_name() == "kernel" || entry.file_name() == "vmlinux" {
                    kernel = Some(entry.open().unwrap());
                }
            }
        }

        let mut kernel = kernel.expect("Cannot locate kernel");
        let size = kernel.size() as usize;

        println!("Loading kernel, size = {}KiB", size / 1024);
        let mut buffer = alloc::vec::Vec::with_capacity(size);
        unsafe { buffer.set_len(size) };
        let time = timer::time();
        kernel.read_exact(&mut buffer).unwrap();
        let elapsed = timer::time() - time;
        println!("Elapsed: {:?}", elapsed);

        drop(fs);
        drop(sd);

        buffer
    }
}

#[no_mangle]
extern "C" fn main(boot: bool) -> usize {
    static DTB_PTR: AtomicUsize = AtomicUsize::new(0);

    let hartid = hartid();

    if boot {
        uart::uart_init();
        fmt::logger_init();

        // Set baud to 230,400 8N1
        // 18.432M / (16 * 230,400) = 5
        uart::uart_set_mode(uart::Config {
            divisor: 5,
            lcr: 0b11,
        });

        println!("Booting...");

        fp::init_fp();

        // Probe number of harts available
        ipi::probe_hart_count();

        let kernel_memory_size = address::MEMORY_SIZE - 0x200000;

        // memtest::memtest(unsafe {
        //     core::slice::from_raw_parts_mut(address::MEMORY_BASE as *mut usize, kernel_memory_size / 8)
        // });

        let kernel_size = allocator::scoped_with_memory(
            unsafe {
                core::slice::from_raw_parts_mut(
                    (address::MEMORY_BASE + kernel_memory_size / 2) as *mut u8,
                    kernel_memory_size / 2,
                )
            },
            || {
                let elf_file = load_kernel();
                let kernel_size = unsafe { elf::load_elf(&elf_file, address::MEMORY_BASE) };
                kernel_size
            },
        );

        // Copy DTB to end of kenrel.
        let dtb = include_bytes!(concat!(env!("OUT_DIR"), "/device_tree.dtb"));
        let dtb_ptr = address::MEMORY_BASE + kernel_size;
        DTB_PTR.store(dtb_ptr, Ordering::Relaxed);
        unsafe { core::ptr::copy_nonoverlapping(dtb.as_ptr(), dtb_ptr as *mut u8, dtb.len()) };

        println!("Control transfer to kernel");

        // Wake up secondary processors
        for i in 1..hart_count() {
            ipi::set_msip(i, true);
        }
    } else {
        fp::init_fp();

        // Booting process will invoke IPI, clear it.
        ipi::process_ipi();
    }

    println!("Core {} up", hartid);

    DTB_PTR.load(Ordering::Relaxed)
}

/// Delegate a interrupt to S-mode
fn delegate_interrupt(ctx: &mut Context, trap: TrapInfo) {
    let mut mstatus = ctx.mstatus;

    // Retrieve MPP. We cannot delegate M-mode exception to S-mode.
    let mpp = (mstatus >> 11) & 3;
    assert!(mpp <= 1, "mpp = 3, mepc = {}", ctx.pc);

    // Set SPP according to MPP
    if mpp != 0 {
        mstatus |= 0x100;
    } else {
        mstatus &= !0x100;
    }

    // Set SPIE to SIE
    if mstatus & 2 != 0 {
        mstatus |= 0x20;
    } else {
        mstatus &= !0x20;
    }

    // Clear SIE
    mstatus &= !2;

    // Set MPP to S-mode so we will MRET to stvec
    mstatus = (mstatus & !0x1800) | 0x800;

    unsafe {
        // Set S-mode trap CSRs
        asm!("csrw scause, {}", in(reg) trap.cause, options(nomem, nostack));
        asm!("csrw stval, {}", in(reg) trap.tval, options(nomem, nostack));
        asm!("csrw sepc, {}", in(reg) ctx.pc, options(nomem, nostack));

        // Set ctx.pc to stvec MRET will return to S-mode
        asm!("csrr {}, stvec", out(reg) ctx.pc, options(nomem, nostack));
    }

    ctx.mstatus = mstatus;
}

fn handle_illegal_insn(ctx: &mut Context) {
    trace!("Handle illegal insn  {:x}", ctx.pc);
    let bits_lo = memory::load_u16_exec(ctx.pc).unwrap();
    let (bits, insn) = if bits_lo & 3 != 3 {
        (bits_lo as u32, riscv::decode_compressed(bits_lo))
    } else {
        let bits = bits_lo as u32 | ((memory::load_u16_exec(ctx.pc + 2).unwrap() as u32) << 16);
        (bits, riscv::decode(bits))
    };
    match interp::step(ctx, &insn) {
        Ok(_) => {
            ctx.pc += if bits & 3 != 3 { 2 } else { 4 };
        }
        Err(mut trap) => {
            if trap.cause == 2 {
                trap.tval = bits as usize;
            }
            delegate_interrupt(ctx, trap);
        }
    }
}

// Try to handle fast interrupts (non-volatile registers are not saved in ctx)
#[no_mangle]
extern "C" fn handle_interrupt_fast(cause: usize, ctx: &mut Context) -> bool {
    match cause {
        0x8000000000000003 => {
            ipi::process_ipi();
        }
        0x8000000000000007 => {
            unsafe {
                // Mask machine timer interrupt
                asm!("csrc mie, {}", in(reg) 1 << 7, options(nomem, nostack));
                // Propagate to S-Mode
                asm!("csrs mip, {}", in(reg) 1 << 5, options(nomem, nostack));
            }
        }
        9 => {
            sbi::handle_sbi(ctx);
            // ECALL is 4 bytes
            ctx.pc += 4;
        }
        _ => return false,
    }
    true
}

// Handle slow interrupts
#[no_mangle]
extern "C" fn handle_interrupt(cause: usize, ctx: &mut Context) {
    let mpp = (ctx.mstatus >> 11) & 3;
    if mpp > 1 {
        panic!(
            "unexpected trap in machine mode: cause = {:x}, ctx = {:?}",
            cause, ctx
        );
    }

    match cause {
        2 => handle_illegal_insn(ctx),
        4 => {
            if let Err(trap) = misalign::handle_misaligned_read(ctx) {
                trace!(
                    "Error handling read misalign: {:x}, {:x}",
                    trap.cause,
                    trap.tval
                );
                delegate_interrupt(ctx, trap);
            }
        }
        6 => {
            if let Err(trap) = misalign::handle_misaligned_write(ctx) {
                trace!(
                    "Error handling write misalign: {:x}, {:x}",
                    trap.cause,
                    trap.tval
                );
                delegate_interrupt(ctx, trap);
            }
        }
        _ => {
            panic!("unhandled exception cause = {:x}, ctx = {:?}", cause, ctx);
        }
    }
}

fn indefinite_sleep() -> ! {
    unsafe {
        asm!("csrw mie, x0", options(nomem, nostack));
        loop {
            asm!("wfi", options(nomem, nostack));
        }
    }
}

#[no_mangle]
extern "C" fn abort() -> ! {
    ipi::run_on_hart(hart_mask::HartMask::new(usize::MAX, 0), &|| {
        indefinite_sleep()
    });
    unreachable!();
}
