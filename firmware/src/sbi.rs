use core::arch::asm;

use super::memory;
use super::Context;
use crate::hart_mask::HartMask;

#[allow(dead_code)]
#[repr(isize)]
enum SbiError {
    Failed = -1,
    NotSupported = -2,
    InvalidParam = -3,
    Denied = -4,
    InvalidAddress = -5,
    AlreadyAvailable = -6,
}

type SbiResult = Result<isize, SbiError>;

const EXTENSION_TIMER: isize = 0x54494D45;
const EXTENSION_IPI: isize = 0x735049;
const EXTENSION_RFENCE: isize = 0x52464E43;
const EXTENSION_RESET: isize = 0x53525354;

fn load_mask(addr: usize) -> usize {
    if addr == 0 {
        core::usize::MAX
    } else {
        memory::load_usize(addr).unwrap()
    }
}

fn sbi_get_spec_version() -> SbiResult {
    // Version 0.2
    Ok(0 << 24 | 2)
}

fn sbi_probe_extension(extension_id: isize) -> SbiResult {
    match extension_id {
        EXTENSION_TIMER => Ok(1),
        EXTENSION_IPI => Ok(1),
        EXTENSION_RFENCE => Ok(1),
        EXTENSION_RESET => Ok(1),
        _ => Ok(0),
    }
}

fn sbi_get_mvendorid() -> SbiResult {
    Ok(0)
}

fn sbi_get_marchid() -> SbiResult {
    Ok(0)
}

fn sbi_get_mimpid() -> SbiResult {
    Ok(0)
}

fn sbi_set_timer(time: u64) -> SbiResult {
    unsafe {
        // Unmask machine timer interrupt
        asm!("csrs mie, {}", in(reg) 1 << 7, options(nomem, nostack));
        // Clear supervisor timer interrupt
        asm!("csrc mip, {}", in(reg) 1 << 5, options(nomem, nostack));
        super::timer::set_timer_u64(super::hartid(), time as u64);
    }
    Ok(0)
}

fn sbi_send_ipi(mask: HartMask) -> SbiResult {
    super::ipi::run_on_hart(mask, &|| {
        unsafe { asm!("csrsi mip, 2", options(nomem, nostack)) };
    });
    Ok(0)
}

fn sbi_remote_fence_i(mask: HartMask) -> SbiResult {
    super::ipi::run_on_hart_wait(mask, &|| {
        unsafe { asm!("fence.i", options(nomem, nostack)) };
    });
    Ok(0)
}

fn sbi_remote_sfence_vma(mask: HartMask, start_addr: usize, size: usize) -> SbiResult {
    super::ipi::run_on_hart_wait(mask, &|| unsafe {
        if size == 4096 {
            asm!("sfence.vma {}", in(reg) start_addr, options(nomem, nostack));
        } else {
            asm!("sfence.vma", options(nomem, nostack));
        }
    });
    Ok(0)
}

fn sbi_remote_sfence_vma_asid(
    mask: HartMask,
    start_addr: usize,
    size: usize,
    asid: usize,
) -> SbiResult {
    super::ipi::run_on_hart_wait(mask, &|| unsafe {
        if size == 4096 {
            asm!("sfence.vma {}, {}", in(reg) start_addr, in(reg) asid, options(nomem, nostack));
        } else {
            asm!("sfence.vma x0, {}", in(reg) asid, options(nomem, nostack));
        }
    });
    Ok(0)
}

fn sbi_system_reset(reset_type: usize, _reset_reason: usize) -> SbiResult {
    match reset_type {
        0 => panic!("shutdown"),
        1 => panic!("cold reboot"),
        2 => panic!("warm reboot"),
        _ => Err(SbiError::InvalidParam),
    }
}

fn handle_sbi_nonlegacy(ctx: &mut Context) -> SbiResult {
    match ctx.registers[17] as isize {
        0x10 => match ctx.registers[16] {
            0 => sbi_get_spec_version(),
            3 => sbi_probe_extension(ctx.registers[10] as isize),
            4 => sbi_get_mvendorid(),
            5 => sbi_get_marchid(),
            6 => sbi_get_mimpid(),
            _ => Err(SbiError::NotSupported),
        },
        EXTENSION_TIMER => match ctx.registers[16] {
            0 => sbi_set_timer(ctx.registers[10] as u64),
            _ => Err(SbiError::NotSupported),
        },
        EXTENSION_IPI => match ctx.registers[16] {
            0 => sbi_send_ipi(HartMask {
                mask: ctx.registers[10],
                mask_base: ctx.registers[11],
            }),
            _ => Err(SbiError::NotSupported),
        },
        EXTENSION_RFENCE => match ctx.registers[16] {
            0 => sbi_remote_fence_i(HartMask {
                mask: ctx.registers[10],
                mask_base: ctx.registers[11],
            }),
            1 => sbi_remote_sfence_vma(
                HartMask {
                    mask: ctx.registers[10],
                    mask_base: ctx.registers[11],
                },
                ctx.registers[12],
                ctx.registers[13],
            ),
            2 => sbi_remote_sfence_vma_asid(
                HartMask {
                    mask: ctx.registers[10],
                    mask_base: ctx.registers[11],
                },
                ctx.registers[12],
                ctx.registers[13],
                ctx.registers[14],
            ),
            _ => Err(SbiError::NotSupported),
        },
        EXTENSION_RESET => match ctx.registers[16] {
            0 => sbi_system_reset(ctx.registers[10], ctx.registers[11]),
            _ => Err(SbiError::NotSupported),
        },
        _ => Err(SbiError::NotSupported),
    }
}

fn handle_sbi_legacy(ctx: &mut Context) -> SbiResult {
    match ctx.registers[17] {
        0 => sbi_set_timer(ctx.registers[10] as u64),
        1 => {
            // putchar
            super::uart::uart_send_byte(ctx.registers[10] as u8);
            Ok(0)
        }
        2 => {
            // getchar
            match super::uart::uart_try_recv_byte() {
                None => Err(SbiError::Failed),
                Some(v) => Ok(v as isize),
            }
        }
        3 => {
            unsafe { asm!("csrci mip, 2", options(nomem, nostack)) };
            Ok(0)
        }
        4 => {
            let mask = load_mask(ctx.registers[10]);
            sbi_send_ipi(HartMask { mask, mask_base: 0 })
        }
        5 => {
            let mask = load_mask(ctx.registers[10]);
            sbi_remote_fence_i(HartMask { mask, mask_base: 0 })
        }
        6 => {
            let mask = load_mask(ctx.registers[10]);
            sbi_remote_sfence_vma(
                HartMask { mask, mask_base: 0 },
                ctx.registers[11],
                ctx.registers[12],
            )
        }
        7 => {
            let mask = load_mask(ctx.registers[10]);
            sbi_remote_sfence_vma_asid(
                HartMask { mask, mask_base: 0 },
                ctx.registers[11],
                ctx.registers[12],
                ctx.registers[13],
            )
        }
        8 => sbi_system_reset(0, 0),
        _ => Err(SbiError::NotSupported),
    }
}

pub fn handle_sbi(ctx: &mut Context) {
    match ctx.registers[17] {
        0x00..=0x0F => match handle_sbi_legacy(ctx) {
            Ok(v) => ctx.registers[10] = v as usize,
            Err(v) => ctx.registers[10] = v as isize as usize,
        },
        _ => match handle_sbi_nonlegacy(ctx) {
            Ok(v) => {
                ctx.registers[10] = 0;
                ctx.registers[11] = v as usize;
            }
            Err(v) => {
                ctx.registers[10] = v as isize as usize;
            }
        },
    }
}
