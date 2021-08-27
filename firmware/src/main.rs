#![no_std]
#![no_main]
#![feature(asm)]
#![feature(default_alloc_error_handler)]
#![feature(core_intrinsics)]

#[macro_use]
extern crate alloc;
#[macro_use]
extern crate log;
extern crate unwind;
extern crate compiler_builtins_local;

#[macro_use]
mod util;
#[macro_use]
mod fmt;

mod block;
mod fs;
mod hart_mask;
mod io;
mod iomem;
mod net;
mod panic;

#[allow(unused)]
mod memtest;

#[cfg(not(rv64f = "full"))]
mod fp;

#[allow(unused)]
mod address;
mod allocator;
#[allow(unused)]
mod elf;
#[allow(unused)]
mod interp;
#[allow(unused)]
mod ipi;
#[allow(unused)]
mod memory;
#[allow(unused)]
mod misalign;
#[allow(unused)]
mod sbi;
#[allow(unused)]
mod timer;
#[allow(unused)]
mod uart;

#[allow(unused)]
mod config {
    const MAX_HART: usize = 4;
}

use self::ipi::hart_count;

#[repr(C)]
pub struct Context {
    registers: [usize; 32],
    pc: usize,
    mstatus: usize,
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

#[no_mangle]
extern "C" fn main(boot: bool) -> usize {
    let hartid = hartid();

    if boot {
        uart::uart_init();
        fmt::logger_init();

        #[cfg(not(rv64f = "full"))]
        fp::init_fp();

        // Set baud to 230,400 8N1
        // 18.432M / (16 * 230,400) = 5
        uart::uart_set_mode(uart::Config {
            divisor: 5,
            lcr: 0b11,
        });

        println!("Booting...");

        // Probe number of harts available
        ipi::probe_hart_count();

        // memtest::memtest(unsafe {
        //     core::slice::from_raw_parts_mut(0x40000000 as *mut usize, 0x07e00000 / 8)
        // });

        if true {
            allocator::scoped_with_memory(
                unsafe { core::slice::from_raw_parts_mut(0x44000000 as *mut u8, 0x03e00000) },
                || {
                    let elf_file = if false {
                        let time = timer::time();
                        let vec = net::load_kernel();
                        let elapsed = timer::time() - time;
                        println!("Elapsed: {:?}", elapsed);
                        vec
                    } else {
                        use alloc::sync::Arc;

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
                    };
                    let kernel_size = unsafe { elf::load_elf(&elf_file, 0x40000000) };
                },
            );
        }

        // loop {
        //     unsafe { asm!(""); }
        //     memtest::memtest(unsafe { core::slice::from_raw_parts_mut(0x44000000 as *mut usize, 0x03e00000/8) });
        // }

        println!("Control transfer to kernel");

        // Wake up secondary processors
        for i in 1..hart_count() {
            ipi::set_msip(i, true);
        }
    } else {
        // Booting process will invoke IPI, clear it.
        ipi::process_ipi();
    }

    println!("Core {} up", hartid);

    include_bytes!(concat!(env!("OUT_DIR"), "/device_tree.dtb")).as_ptr() as usize
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
    let bits_lo = memory::load_u16_exec(ctx.pc);
    let (bits, insn) = if bits_lo & 3 != 3 {
        (bits_lo as u32, riscv::decode_compressed(bits_lo))
    } else {
        let bits = bits_lo as u32 | ((memory::load_u16_exec(ctx.pc + 2) as u32) << 16);
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

fn dump_context(ctx: &Context) {
    for i in 1..32 {
        println!("x{} = {:x}", i, ctx.registers[i]);
    }
    println!("pc = {:x}", ctx.pc);
    println!("mstatus = {:x}", ctx.mstatus);
}

#[allow(unused)]
unsafe fn debug(addr: usize) {
    let satp: usize;
    asm!("csrr {}, satp", out(reg) satp, options(nomem, nostack));
    println!("SATP = 0x{:x}", satp);

    if satp as i64 > 0 {
        return;
    }

    let root_page_table = ((satp & ((1 << 44) - 1)) << 12) as *const u64;
    let l1_ptr = root_page_table.add((addr >> 30) & 0x1FF);
    let l1 = *l1_ptr;
    println!("L1({:?}) = 0x{:x}", l1_ptr, l1);
    if (l1 & 1) == 0 || l1 & 14 != 0 {
        return;
    }

    let l1_page_table = ((l1 << 2) & !0xFFF) as *const u64;
    let l2_ptr = l1_page_table.add((addr >> 21) & 0x1FF);
    let l2 = *l2_ptr;
    println!("L2({:?}) = 0x{:x}", l2_ptr, l2);
    if (l2 & 1) == 0 || l2 & 14 != 0 {
        return;
    }

    let l2_page_table = ((l2 << 2) & !0xFFF) as *const u64;
    let l3_ptr = l2_page_table.add((addr >> 12) & 0x1FF);
    let l3 = *l3_ptr;
    println!("L3({:?}) = 0x{:x}", l3_ptr, l3);
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
        /*  0x800000000000000b => {
            let addr = 0xffffffe0000321bc;
            unsafe { debug(addr) };
        }*/
        9 => {
            sbi::handle_sbi(ctx);
            // ECALL is 4 bytes
            ctx.pc += 4;
        }
        // Page fault. We can only get these in memory::*.
        13 | 15 => {
            let mpp = (ctx.mstatus >> 11) & 3;
            if mpp == 3 {
                // Set a0 to 1 to signal a fault and skip over the wrong load
                ctx.registers[10] = 1;
                ctx.pc += 4;

                let tval = unsafe {
                    let v: usize;
                    asm!("csrr {}, mtval", out(reg) v, options(nomem, nostack));
                    v
                };
                println!("Page fault at {:x}", tval);
            } else {
                let tval = unsafe {
                    let v: usize;
                    asm!("csrr {}, mtval", out(reg) v, options(nomem, nostack));
                    v
                };
                let mstatus = unsafe {
                    let v: usize;
                    asm!("csrr {}, mstatus", out(reg) v, options(nomem, nostack));
                    v
                };
                println!(
                    "cause={:x}, pc = {:x}, tval = {:x}, mstatus = {:x}",
                    cause, ctx.pc, tval, mstatus
                );
                delegate_interrupt(ctx, TrapInfo { cause, tval });
            }
        }
        0xC => {
            let tval = unsafe {
                let v: usize;
                asm!("csrr {}, mtval", out(reg) v, options(nomem, nostack));
                v
            };
            let mstatus = unsafe {
                let v: usize;
                asm!("csrr {}, mstatus", out(reg) v, options(nomem, nostack));
                v
            };
            println!(
                "cause={:x}, pc = {:x}, tval = {:x}, mstatus = {:x}",
                cause, ctx.pc, tval, mstatus
            );
            delegate_interrupt(ctx, TrapInfo { cause: 0xC, tval });
        }
        _ => return false,
    }
    true
}

// Handle slow interrupts
#[no_mangle]
extern "C" fn handle_interrupt(cause: usize, ctx: &mut Context) {
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
            dump_context(ctx);
            panic!("unhandled exception cause {:x}", cause);
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
    ipi::run_on_hart(hart_mask::HartMask::new(usize::MAX, 0), &|| indefinite_sleep());
    unreachable!();
}
