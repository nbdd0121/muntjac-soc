use core::cell::RefCell;
use riscv::{Csr, Op};
use softfp::{self, F32, F64};

#[cfg(rv64f = "none")]
use super::memory::*;
use super::{Context, TrapInfo};

#[cfg(rv64f = "none")]
struct FpState {
    fpr: [u64; 32],
    fflags: u8,
    frm: u8,
    effective_frm: u8,
    touched: bool,
}

#[cfg(rv64f = "mem")]
struct FpState {
    effective_frm: u8,
}

hart_local! {
    #[cfg(rv64f = "none")]
    static FP_STATE: RefCell<FpState> = RefCell::new(FpState {
        fpr: [0; 32],
        fflags: 0,
        frm: 0,
        effective_frm: 0,
        touched: false,
    });
    #[cfg(rv64f = "mem")]
    static FP_STATE: RefCell<FpState> = RefCell::new(FpState {
        effective_frm: 0,
    });
}

macro_rules! trap {
    ($cause: expr, $tval: expr) => {
        return Err(TrapInfo {
            cause: $cause,
            tval: $tval,
        });
    };
}

#[cfg(rv64f = "none")]
pub fn read_csr(ctx: &mut Context, csr: Csr) -> Result<usize, TrapInfo> {
    if ctx.mstatus & 0x6000 == 0 {
        trap!(2, 0);
    }

    let state = FP_STATE.borrow();

    Ok(match csr {
        Csr::Fflags => state.fflags as usize,
        Csr::Frm => state.frm as usize,
        Csr::Fcsr => ((state.frm << 5) | state.fflags) as usize,
        _ => unreachable!(),
    })
}

#[cfg(rv64f = "none")]
pub fn write_csr(ctx: &mut Context, csr: Csr, value: usize) -> Result<(), TrapInfo> {
    if ctx.mstatus & 0x6000 == 0 {
        trap!(2, 0);
    }
    ctx.mstatus |= 0x6000;

    let mut state = FP_STATE.borrow_mut();

    match csr {
        Csr::Fflags => {
            state.fflags = value as u8 & 0b11111;
        }
        Csr::Frm => {
            state.frm = 4.min(value as u8 & 0b111);
        }
        Csr::Fcsr => {
            state.fflags = (value as u8) & 0b11111;
            state.frm = 4.min((value as u8 >> 5) & 0b111);
        }
        _ => unreachable!(),
    }
    Ok(())
}

#[cfg(rv64f = "none")]
fn get_frm() -> u8 {
    FP_STATE.borrow().frm
}

#[cfg(rv64f = "mem")]
fn get_frm() -> u8 {
    let ret: u32;
    unsafe {
        asm!("csrr {}, frm", lateout(reg) ret);
    }
    ret as u8
}

#[cfg(rv64f = "mem")]
extern "C" {
    fn get_fpr(idx: usize) -> u64;
    fn set_fpr(idx: usize, reg: u64);
}

#[cfg(rv64f = "none")]
unsafe fn get_fpr(idx: usize) -> u64 {
    if idx >= 32 {
        core::hint::unreachable_unchecked();
    }
    FP_STATE.borrow().fpr[idx]
}

#[cfg(rv64f = "none")]
unsafe fn set_fpr(idx: usize, reg: u64) {
    if idx >= 32 {
        core::hint::unreachable_unchecked();
    }
    let mut state = FP_STATE.borrow_mut();
    state.fpr[idx] = reg;
    state.touched = true;
}

fn get_rounding_mode() -> softfp::RoundingMode {
    unsafe { core::mem::transmute(FP_STATE.borrow().effective_frm as u32) }
}

#[cfg(rv64f = "none")]
fn set_exception_flags(flags: softfp::ExceptionFlags) {
    let mut state = FP_STATE.borrow_mut();
    state.fflags |= flags.bits() as u8;
    state.touched = true;
}

#[cfg(rv64f = "mem")]
fn set_exception_flags(flags: softfp::ExceptionFlags) {
    unsafe {
        asm!("csrs fflags, {}", in(reg) flags.bits());
    }
}

/// Initialise softfp environemnt
pub fn init_fp() {
    softfp::register_get_rounding_mode(get_rounding_mode);
    softfp::register_set_exception_flag(set_exception_flags);
}

pub fn is_fp(op: &Op) -> bool {
    match op {
        Op::Flw { .. }
        | Op::Fsw { .. }
        | Op::FaddS { .. }
        | Op::FsubS { .. }
        | Op::FmulS { .. }
        | Op::FdivS { .. }
        | Op::FsqrtS { .. }
        | Op::FsgnjS { .. }
        | Op::FsgnjnS { .. }
        | Op::FsgnjxS { .. }
        | Op::FminS { .. }
        | Op::FmaxS { .. }
        | Op::FcvtWS { .. }
        | Op::FcvtWuS { .. }
        | Op::FcvtLS { .. }
        | Op::FcvtLuS { .. }
        | Op::FmvXW { .. }
        | Op::FclassS { .. }
        | Op::FeqS { .. }
        | Op::FltS { .. }
        | Op::FleS { .. }
        | Op::FcvtSW { .. }
        | Op::FcvtSWu { .. }
        | Op::FcvtSL { .. }
        | Op::FcvtSLu { .. }
        | Op::FmvWX { .. }
        | Op::FmaddS { .. }
        | Op::FmsubS { .. }
        | Op::FnmsubS { .. }
        | Op::FnmaddS { .. }
        | Op::Fld { .. }
        | Op::Fsd { .. }
        | Op::FaddD { .. }
        | Op::FsubD { .. }
        | Op::FmulD { .. }
        | Op::FdivD { .. }
        | Op::FsqrtD { .. }
        | Op::FsgnjD { .. }
        | Op::FsgnjnD { .. }
        | Op::FsgnjxD { .. }
        | Op::FminD { .. }
        | Op::FmaxD { .. }
        | Op::FcvtSD { .. }
        | Op::FcvtDS { .. }
        | Op::FcvtWD { .. }
        | Op::FcvtWuD { .. }
        | Op::FcvtLD { .. }
        | Op::FcvtLuD { .. }
        | Op::FmvXD { .. }
        | Op::FclassD { .. }
        | Op::FeqD { .. }
        | Op::FltD { .. }
        | Op::FleD { .. }
        | Op::FcvtDW { .. }
        | Op::FcvtDWu { .. }
        | Op::FcvtDL { .. }
        | Op::FcvtDLu { .. }
        | Op::FmvDX { .. }
        | Op::FmaddD { .. }
        | Op::FmsubD { .. }
        | Op::FnmsubD { .. }
        | Op::FnmaddD { .. } => true,
        _ => false,
    }
}

pub fn step(ctx: &mut Context, op: &Op) -> Result<(), TrapInfo> {
    macro_rules! read_reg {
        ($rs: expr) => {{
            let rs = $rs as usize;
            if rs >= 32 {
                unsafe { core::hint::unreachable_unchecked() }
            }
            ctx.registers[rs]
        }};
    }
    macro_rules! read_64 {
        ($rs: expr) => {
            read_reg!($rs) as u64
        };
    }
    macro_rules! read_32 {
        ($rs: expr) => {
            read_reg!($rs) as u32
        };
    }
    macro_rules! write_reg {
        ($rd: expr, $expression:expr) => {{
            let rd = $rd as usize;
            let value: usize = $expression;
            if rd >= 32 {
                unsafe { core::hint::unreachable_unchecked() }
            }
            if rd != 0 {
                ctx.registers[rd] = value
            }
        }};
    }
    macro_rules! write_64 {
        ($rd: expr, $expression:expr) => {{
            let value: u64 = $expression;
            write_reg!($rd, value as usize)
        }};
    }
    macro_rules! write_32 {
        ($rd: expr, $expression:expr) => {{
            let value: u32 = $expression;
            write_reg!($rd, value as i32 as usize)
        }};
    }
    macro_rules! read_fs {
        ($rs: expr) => {{
            F32::new(unsafe { get_fpr($rs as usize) } as u32)
        }};
    }
    macro_rules! read_fd {
        ($rs: expr) => {{
            F64::new(unsafe { get_fpr($rs as usize) })
        }};
    }
    macro_rules! write_fs {
        ($frd: expr, $expression:expr) => {{
            let value: F32 = $expression;
            unsafe { set_fpr($frd as usize, value.0 as u64 | 0xffffffff00000000) };
        }};
    }
    macro_rules! write_fd {
        ($frd: expr, $expression:expr) => {{
            let value: F64 = $expression;
            unsafe { set_fpr($frd as usize, value.0) };
        }};
    }
    macro_rules! set_rm {
        ($rm: expr) => {{
            let mut state = FP_STATE.borrow_mut();
            state.effective_frm = if $rm == 0b111 { get_frm() >> 5 } else { $rm };
        }};
    }

    // Check that FS is enabled.
    if ctx.mstatus & 0x6000 == 0 {
        trap!(2, 0);
    }

    // Clear touched flag. We will use this flag to determine if any registers have been modified.
    #[cfg(rv64f = "none")]
    {
        let mut state = FP_STATE.borrow_mut();
        state.touched = false;
    }

    match *op {
        /* F-extension */
        #[cfg(rv64f = "none")]
        Op::Flw { frd, rs1, imm } => {
            let vaddr = read_reg!(rs1).wrapping_add(imm as usize);
            if vaddr & 3 != 0 {
                trap!(4, vaddr)
            }
            write_fs!(frd, F32::new(load_u32(vaddr)?));
        }
        #[cfg(rv64f = "none")]
        Op::Fsw { rs1, frs2, imm } => {
            let vaddr = read_reg!(rs1).wrapping_add(imm as usize);
            if vaddr & 3 != 0 {
                trap!(5, vaddr)
            }
            store_u32(vaddr, read_fs!(frs2).0)?;
        }
        Op::FaddS {
            frd,
            frs1,
            frs2,
            rm,
        } => {
            set_rm!(rm);
            write_fs!(frd, read_fs!(frs1) + read_fs!(frs2));
        }
        Op::FsubS {
            frd,
            frs1,
            frs2,
            rm,
        } => {
            set_rm!(rm);
            write_fs!(frd, read_fs!(frs1) - read_fs!(frs2));
        }
        Op::FmulS {
            frd,
            frs1,
            frs2,
            rm,
        } => {
            set_rm!(rm);
            write_fs!(frd, read_fs!(frs1) * read_fs!(frs2));
        }
        Op::FdivS {
            frd,
            frs1,
            frs2,
            rm,
        } => {
            set_rm!(rm);
            write_fs!(frd, read_fs!(frs1) / read_fs!(frs2));
        }
        Op::FsqrtS { frd, frs1, rm } => {
            set_rm!(rm);
            write_fs!(frd, read_fs!(frs1).square_root());
        }
        Op::FsgnjS { frd, frs1, frs2 } => {
            write_fs!(frd, read_fs!(frs1).copy_sign(read_fs!(frs2)))
        }
        Op::FsgnjnS { frd, frs1, frs2 } => {
            write_fs!(frd, read_fs!(frs1).copy_sign_negated(read_fs!(frs2)))
        }
        Op::FsgnjxS { frd, frs1, frs2 } => {
            write_fs!(frd, read_fs!(frs1).copy_sign_xored(read_fs!(frs2)))
        }
        Op::FminS { frd, frs1, frs2 } => {
            write_fs!(frd, F32::min(read_fs!(frs1), read_fs!(frs2)));
        }
        Op::FmaxS { frd, frs1, frs2 } => {
            write_fs!(frd, F32::max(read_fs!(frs1), read_fs!(frs2)));
        }
        Op::FcvtWS { rd, frs1, rm } => {
            set_rm!(rm);
            write_32!(rd, read_fs!(frs1).convert_to_sint::<u32>());
        }
        Op::FcvtWuS { rd, frs1, rm } => {
            set_rm!(rm);
            write_32!(rd, read_fs!(frs1).convert_to_uint::<u32>());
        }
        Op::FcvtLS { rd, frs1, rm } => {
            set_rm!(rm);
            write_64!(rd, read_fs!(frs1).convert_to_sint::<u64>());
        }
        Op::FcvtLuS { rd, frs1, rm } => {
            set_rm!(rm);
            write_64!(rd, read_fs!(frs1).convert_to_uint::<u64>());
        }
        Op::FmvXW { rd, frs1 } => {
            write_32!(rd, read_fs!(frs1).0);
        }
        Op::FclassS { rd, frs1 } => {
            write_reg!(rd, 1 << read_fs!(frs1).classify() as u32);
        }
        Op::FeqS { rd, frs1, frs2 } => {
            write_reg!(rd, (read_fs!(frs1) == read_fs!(frs2)) as usize)
        }
        Op::FltS { rd, frs1, frs2 } => {
            write_reg!(rd, (read_fs!(frs1) < read_fs!(frs2)) as usize);
        }
        Op::FleS { rd, frs1, frs2 } => {
            write_reg!(rd, (read_fs!(frs1) <= read_fs!(frs2)) as usize);
        }
        Op::FcvtSW { frd, rs1, rm } => {
            set_rm!(rm);
            write_fs!(frd, F32::convert_from_sint::<u32>(read_32!(rs1)));
        }
        Op::FcvtSWu { frd, rs1, rm } => {
            set_rm!(rm);
            write_fs!(frd, F32::convert_from_uint::<u32>(read_32!(rs1)));
        }
        Op::FcvtSL { frd, rs1, rm } => {
            set_rm!(rm);
            write_fs!(frd, F32::convert_from_sint::<u64>(read_64!(rs1)));
        }
        Op::FcvtSLu { frd, rs1, rm } => {
            set_rm!(rm);
            write_fs!(frd, F32::convert_from_uint::<u64>(read_64!(rs1)));
        }
        Op::FmvWX { frd, rs1 } => {
            write_fs!(frd, F32::new(read_32!(rs1)));
        }
        Op::FmaddS {
            frd,
            frs1,
            frs2,
            frs3,
            rm,
        } => {
            set_rm!(rm);
            write_fs!(
                frd,
                F32::fused_multiply_add(read_fs!(frs1), read_fs!(frs2), read_fs!(frs3))
            );
        }
        Op::FmsubS {
            frd,
            frs1,
            frs2,
            frs3,
            rm,
        } => {
            set_rm!(rm);
            write_fs!(
                frd,
                F32::fused_multiply_add(read_fs!(frs1), read_fs!(frs2), -read_fs!(frs3))
            );
        }
        Op::FnmsubS {
            frd,
            frs1,
            frs2,
            frs3,
            rm,
        } => {
            set_rm!(rm);
            write_fs!(
                frd,
                F32::fused_multiply_add(-read_fs!(frs1), read_fs!(frs2), read_fs!(frs3))
            );
        }
        Op::FnmaddS {
            frd,
            frs1,
            frs2,
            frs3,
            rm,
        } => {
            set_rm!(rm);
            write_fs!(
                frd,
                -F32::fused_multiply_add(read_fs!(frs1), read_fs!(frs2), read_fs!(frs3))
            );
        }

        /* D-extension */
        #[cfg(rv64f = "none")]
        Op::Fld { frd, rs1, imm } => {
            let vaddr = read_reg!(rs1).wrapping_add(imm as usize);
            if vaddr & 3 != 0 {
                trap!(4, vaddr)
            }
            write_fd!(frd, F64::new(load_u64(vaddr)?));
        }
        #[cfg(rv64f = "none")]
        Op::Fsd { rs1, frs2, imm } => {
            let vaddr = read_reg!(rs1).wrapping_add(imm as usize);
            if vaddr & 7 != 0 {
                trap!(5, vaddr)
            }
            store_u64(vaddr, read_fd!(frs2).0)?;
        }
        Op::FaddD {
            frd,
            frs1,
            frs2,
            rm,
        } => {
            set_rm!(rm);
            write_fd!(frd, read_fd!(frs1) + read_fd!(frs2));
        }
        Op::FsubD {
            frd,
            frs1,
            frs2,
            rm,
        } => {
            set_rm!(rm);
            write_fd!(frd, read_fd!(frs1) - read_fd!(frs2));
        }
        Op::FmulD {
            frd,
            frs1,
            frs2,
            rm,
        } => {
            set_rm!(rm);
            write_fd!(frd, read_fd!(frs1) * read_fd!(frs2));
        }
        Op::FdivD {
            frd,
            frs1,
            frs2,
            rm,
        } => {
            set_rm!(rm);
            write_fd!(frd, read_fd!(frs1) / read_fd!(frs2));
        }
        Op::FsqrtD { frd, frs1, rm } => {
            set_rm!(rm);
            write_fd!(frd, read_fd!(frs1).square_root());
        }
        Op::FsgnjD { frd, frs1, frs2 } => {
            write_fd!(frd, read_fd!(frs1).copy_sign(read_fd!(frs2)))
        }
        Op::FsgnjnD { frd, frs1, frs2 } => {
            write_fd!(frd, read_fd!(frs1).copy_sign_negated(read_fd!(frs2)))
        }
        Op::FsgnjxD { frd, frs1, frs2 } => {
            write_fd!(frd, read_fd!(frs1).copy_sign_xored(read_fd!(frs2)))
        }
        Op::FminD { frd, frs1, frs2 } => {
            write_fd!(frd, F64::min(read_fd!(frs1), read_fd!(frs2)));
        }
        Op::FmaxD { frd, frs1, frs2 } => {
            write_fd!(frd, F64::max(read_fd!(frs1), read_fd!(frs2)));
        }
        Op::FcvtSD { frd, frs1, rm } => {
            set_rm!(rm);
            write_fs!(frd, read_fd!(frs1).convert_format());
        }
        Op::FcvtDS { frd, frs1, .. } => {
            write_fd!(frd, read_fs!(frs1).convert_format());
        }
        Op::FcvtWD { rd, frs1, rm } => {
            set_rm!(rm);
            write_32!(rd, read_fd!(frs1).convert_to_sint::<u32>());
        }
        Op::FcvtWuD { rd, frs1, rm } => {
            set_rm!(rm);
            write_32!(rd, read_fd!(frs1).convert_to_uint::<u32>());
        }
        Op::FcvtLD { rd, frs1, rm } => {
            set_rm!(rm);
            write_64!(rd, read_fd!(frs1).convert_to_sint::<u64>());
        }
        Op::FcvtLuD { rd, frs1, rm } => {
            set_rm!(rm);
            write_64!(rd, read_fd!(frs1).convert_to_uint::<u64>());
        }
        Op::FmvXD { rd, frs1 } => {
            write_64!(rd, read_fd!(frs1).0);
        }
        Op::FclassD { rd, frs1 } => {
            write_reg!(rd, 1 << read_fd!(frs1).classify() as u32);
        }
        Op::FeqD { rd, frs1, frs2 } => {
            write_reg!(rd, (read_fd!(frs1) == read_fd!(frs2)) as usize)
        }
        Op::FltD { rd, frs1, frs2 } => {
            write_reg!(rd, (read_fd!(frs1) < read_fd!(frs2)) as usize);
        }
        Op::FleD { rd, frs1, frs2 } => {
            write_reg!(rd, (read_fd!(frs1) <= read_fd!(frs2)) as usize);
        }
        Op::FcvtDW { frd, rs1, rm } => {
            set_rm!(rm);
            write_fd!(frd, F64::convert_from_sint::<u32>(read_32!(rs1)));
        }
        Op::FcvtDWu { frd, rs1, rm } => {
            set_rm!(rm);
            write_fd!(frd, F64::convert_from_uint::<u32>(read_32!(rs1)));
        }
        Op::FcvtDL { frd, rs1, rm } => {
            set_rm!(rm);
            write_fd!(frd, F64::convert_from_sint::<u64>(read_64!(rs1)));
        }
        Op::FcvtDLu { frd, rs1, rm } => {
            set_rm!(rm);
            write_fd!(frd, F64::convert_from_uint::<u64>(read_64!(rs1)));
        }
        Op::FmvDX { frd, rs1 } => {
            write_fd!(frd, F64::new(read_64!(rs1)));
        }
        Op::FmaddD {
            frd,
            frs1,
            frs2,
            frs3,
            rm,
        } => {
            set_rm!(rm);
            write_fd!(
                frd,
                F64::fused_multiply_add(read_fd!(frs1), read_fd!(frs2), read_fd!(frs3))
            );
        }
        Op::FmsubD {
            frd,
            frs1,
            frs2,
            frs3,
            rm,
        } => {
            set_rm!(rm);
            write_fd!(
                frd,
                F64::fused_multiply_add(read_fd!(frs1), read_fd!(frs2), -read_fd!(frs3))
            );
        }
        Op::FnmsubD {
            frd,
            frs1,
            frs2,
            frs3,
            rm,
        } => {
            set_rm!(rm);
            write_fd!(
                frd,
                F64::fused_multiply_add(-read_fd!(frs1), read_fd!(frs2), read_fd!(frs3))
            );
        }
        Op::FnmaddD {
            frd,
            frs1,
            frs2,
            frs3,
            rm,
        } => {
            set_rm!(rm);
            write_fd!(
                frd,
                -F64::fused_multiply_add(read_fd!(frs1), read_fd!(frs2), read_fd!(frs3))
            );
        }
        _ => trap!(2, 0),
    }

    #[cfg(rv64f = "none")]
    {
        let mut state = FP_STATE.borrow_mut();
        if state.touched {
            ctx.mstatus |= 0x6000;
        }
    }

    Ok(())
}
