use core::arch::asm;
use core::cell::Cell;
use core::cell::RefCell;
use riscv::{Csr, Op};
use softfp::{self, F32, F64};

#[cfg(feature = "fp-none")]
use super::memory::*;
use super::{Context, TrapInfo};

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FpMode {
    None,
    Mem,
    Full,
}

impl FpMode {
    // Detect the floating point support of the current hart.
    fn detect() -> Self {
        unsafe {
            let mode: u8;
            asm!(
                ".option push",
                ".attribute arch, \"rv64gc\"",
                // Enable float point registers
                "li {tmp}, 0x6000",
                "csrs mstatus, {tmp}",
                // Backup interrupt handler
                "csrr {tmp}, mtvec",
                "la {tmp2}, 1f",
                // Setup temporary interrupt handler for feature detection
                "csrw mtvec, {tmp2}",
                // Load dummy value to f0. If this fails, then we are in RV64FNone mode
                "li {out}, 0",
                "fld f0, (sp)",
                // Test an fp operation. If this fails, then we are in RV64FMem mode.
                "li {out}, 1",
                "fadd.d f0, f0, f0",
                // If all succeeded, then we are in RV64FFull mode.
                "li {out}, 2",
                // Interrupt handler must be aligned
                ".balign 4, 1",
                "1: csrw mtvec, {tmp}",
                ".option pop",
                tmp = out(reg) _,
                tmp2 = out(reg) _,
                out = lateout(reg) mode,
                // f0 is clobbered
                out("f0") _,
            );
            match mode {
                0 => FpMode::None,
                1 => FpMode::Mem,
                2 => FpMode::Full,
                _ => core::hint::unreachable_unchecked(),
            }
        }
    }
}

trait FpState {
    fn read_rm(&self) -> u8;
    fn write_rm(&mut self, value: u8);

    fn read_flags(&self) -> u8;
    fn write_flags(&mut self, value: u8);

    fn set_flags(&mut self, value: u8) {
        self.write_flags(self.read_flags() | value);
    }

    unsafe fn read_fpr(&self, idx: usize) -> u64;
    unsafe fn write_fpr(&mut self, idx: usize, value: u64);
}

#[cfg(feature = "fp-none")]
struct FpStateNone {
    fpr: [u64; 32],
    fflags: u8,
    frm: u8,
}

#[cfg(feature = "fp-mem")]
struct FpStateMem;

#[cfg(feature = "fp-none")]
impl FpState for FpStateNone {
    fn read_rm(&self) -> u8 {
        self.frm
    }

    fn write_rm(&mut self, value: u8) {
        self.frm = value;
    }

    fn read_flags(&self) -> u8 {
        self.fflags
    }

    fn write_flags(&mut self, value: u8) {
        self.fflags = value;
    }

    unsafe fn read_fpr(&self, idx: usize) -> u64 {
        if idx >= 32 {
            core::hint::unreachable_unchecked();
        }
        self.fpr[idx]
    }

    unsafe fn write_fpr(&mut self, idx: usize, value: u64) {
        if idx >= 32 {
            core::hint::unreachable_unchecked();
        }
        self.fpr[idx] = value;
    }
}

#[cfg(feature = "fp-mem")]
impl FpState for FpStateMem {
    fn read_rm(&self) -> u8 {
        let ret: u32;
        unsafe {
            asm!("csrr {}, frm", lateout(reg) ret);
        }
        ret as u8
    }

    fn write_rm(&mut self, value: u8) {
        unsafe {
            asm!("csrw frm, {}", in(reg) value);
        }
    }

    fn read_flags(&self) -> u8 {
        let ret: u32;
        unsafe {
            asm!("csrr {}, fflags", lateout(reg) ret);
        }
        ret as u8
    }

    fn write_flags(&mut self, value: u8) {
        unsafe {
            asm!("csrw fflags, {}", in(reg) value);
        }
    }

    fn set_flags(&mut self, value: u8) {
        unsafe {
            asm!("csrs fflags, {}", in(reg) value);
        }
    }

    unsafe fn read_fpr(&self, idx: usize) -> u64 {
        let mut out = 0u64;
        macro_rules! r {
            ($reg:tt) => {
                asm!(
                    ".option push",
                    ".attribute arch, \"rv64gc\"",
                    concat!("fsd f", $reg, ", ({})"),
                    ".option pop",
                    in(reg) &mut out,
                    options(nostack)
                )
            }
        }
        match idx {
            0 => r!(0),
            1 => r!(1),
            2 => r!(2),
            3 => r!(3),
            4 => r!(4),
            5 => r!(5),
            6 => r!(6),
            7 => r!(7),
            8 => r!(8),
            9 => r!(9),
            10 => r!(10),
            11 => r!(11),
            12 => r!(12),
            13 => r!(13),
            14 => r!(14),
            15 => r!(15),
            16 => r!(16),
            17 => r!(17),
            18 => r!(18),
            19 => r!(19),
            20 => r!(20),
            21 => r!(21),
            22 => r!(22),
            23 => r!(23),
            24 => r!(24),
            25 => r!(25),
            26 => r!(26),
            27 => r!(27),
            28 => r!(28),
            29 => r!(29),
            30 => r!(30),
            31 => r!(31),
            _ => core::hint::unreachable_unchecked(),
        }
        out
    }

    unsafe fn write_fpr(&mut self, idx: usize, value: u64) {
        macro_rules! w {
            ($reg:tt) => {
                asm!(
                    ".option push",
                    ".attribute arch, \"rv64gc\"",
                    concat!("fld f", $reg, ", ({})"),
                    ".option pop",
                    in(reg) &value,
                    options(nostack)
                )
            }
        }

        match idx {
            0 => w!(0),
            1 => w!(1),
            2 => w!(2),
            3 => w!(3),
            4 => w!(4),
            5 => w!(5),
            6 => w!(6),
            7 => w!(7),
            8 => w!(8),
            9 => w!(9),
            10 => w!(10),
            11 => w!(11),
            12 => w!(12),
            13 => w!(13),
            14 => w!(14),
            15 => w!(15),
            16 => w!(16),
            17 => w!(17),
            18 => w!(18),
            19 => w!(19),
            20 => w!(20),
            21 => w!(21),
            22 => w!(22),
            23 => w!(23),
            24 => w!(24),
            25 => w!(25),
            26 => w!(26),
            27 => w!(27),
            28 => w!(28),
            29 => w!(29),
            30 => w!(30),
            31 => w!(31),
            _ => core::hint::unreachable_unchecked(),
        }
    }
}

#[thread_local]
static FP_MODE: Cell<FpMode> = Cell::new(FpMode::None);

#[cfg(feature = "fp-mem")]
#[thread_local]
static EFFECTIVE_FRM: Cell<u8> = Cell::new(0);
#[cfg(feature = "fp-mem")]
#[thread_local]
static TRIGGERED_FLAGS: Cell<u8> = Cell::new(0);

#[cfg(feature = "fp-none")]
#[thread_local]
static FP_STATE_NONE: RefCell<FpStateNone> = RefCell::new(FpStateNone {
    fpr: [0; 32],
    fflags: 0,
    frm: 0,
});

#[cfg(feature = "fp-mem")]
#[thread_local]
static FP_STATE_MEM: RefCell<FpStateMem> = RefCell::new(FpStateMem);

macro_rules! trap {
    ($cause: expr, $tval: expr) => {
        return Err(TrapInfo {
            cause: $cause,
            tval: $tval,
        })
    };
}

#[cfg(feature = "fp-mem")]
fn borrow_state<'a>() -> core::cell::Ref<'a, dyn FpState> {
    let p: core::cell::Ref<'_, dyn FpState> = match FP_MODE.get() {
        #[cfg(feature = "fp-none")]
        FpMode::None => FP_STATE_NONE.borrow(),
        _ => FP_STATE_MEM.borrow(),
    };
    unsafe { core::mem::transmute(p) }
}

#[cfg(feature = "fp-mem")]
fn borrow_state_mut<'a>() -> core::cell::RefMut<'a, dyn FpState> {
    let p: core::cell::RefMut<'_, dyn FpState> = match FP_MODE.get() {
        #[cfg(feature = "fp-none")]
        FpMode::None => FP_STATE_NONE.borrow_mut(),
        _ => FP_STATE_MEM.borrow_mut(),
    };
    unsafe { core::mem::transmute(p) }
}

#[cfg(feature = "fp-mem")]
pub fn read_csr(ctx: &mut Context, csr: Csr) -> Result<usize, TrapInfo> {
    if ctx.mstatus & 0x6000 == 0 {
        trap!(2, 0);
    }

    let state = borrow_state();

    Ok(match csr {
        Csr::Fflags => state.read_flags() as usize,
        Csr::Frm => state.read_rm() as usize,
        Csr::Fcsr => ((state.read_rm() << 5) | state.read_flags()) as usize,
        _ => unreachable!(),
    })
}

#[cfg(feature = "fp-mem")]
pub fn write_csr(ctx: &mut Context, csr: Csr, value: usize) -> Result<(), TrapInfo> {
    if ctx.mstatus & 0x6000 == 0 {
        trap!(2, 0);
    }
    ctx.mstatus |= 0x6000;

    let mut state = borrow_state_mut();

    match csr {
        Csr::Fflags => {
            state.write_flags(value as u8 & 0b11111);
        }
        Csr::Frm => {
            state.write_rm(4.min(value as u8 & 0b111));
        }
        Csr::Fcsr => {
            state.write_flags((value as u8) & 0b11111);
            state.write_rm(4.min((value as u8 >> 5) & 0b111));
        }
        _ => unreachable!(),
    }
    Ok(())
}

#[cfg(feature = "fp-mem")]
#[no_mangle]
fn softfp_get_rounding_mode() -> softfp::RoundingMode {
    unsafe { core::mem::transmute(EFFECTIVE_FRM.get() as u32) }
}

#[cfg(feature = "fp-mem")]
#[no_mangle]
fn softfp_set_exception_flags(flags: softfp::ExceptionFlags) {
    TRIGGERED_FLAGS.set(TRIGGERED_FLAGS.get() | flags.bits() as u8);
}

pub fn init_fp() {
    let mode = FpMode::detect();
    info!("Core {} FP mode = {:?}", crate::hartid(), mode);
    match mode {
        FpMode::None => assert!(
            cfg!(feature = "fp-none"),
            "Full FP emulation is not enabled"
        ),
        FpMode::Mem => assert!(cfg!(feature = "fp-mem"), "FP emulation is not enabled"),
        _ => (),
    }
    FP_MODE.set(mode);
}

#[cfg(feature = "fp-mem")]
pub fn is_fp(op: &Op) -> bool {
    if FP_MODE.get() == FpMode::Full {
        return false;
    }
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

#[cfg(feature = "fp-mem")]
pub fn step(ctx: &mut Context, op: &Op) -> Result<(), TrapInfo> {
    // Check that FS is enabled.
    if ctx.mstatus & 0x6000 == 0 {
        trap!(2, 0);
    }

    // Clear flags.
    TRIGGERED_FLAGS.set(0);

    let mut touched = false;
    let mut state = borrow_state_mut();

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
            F32::new(unsafe { state.read_fpr($rs as usize) } as u32)
        }};
    }
    macro_rules! read_fd {
        ($rs: expr) => {{
            F64::new(unsafe { state.read_fpr($rs as usize) })
        }};
    }
    macro_rules! write_fs {
        ($frd: expr, $expression:expr) => {{
            let value: F32 = $expression;
            unsafe { state.write_fpr($frd as usize, value.0 as u64 | 0xffffffff00000000) };
            touched = true;
        }};
    }
    macro_rules! write_fd {
        ($frd: expr, $expression:expr) => {{
            let value: F64 = $expression;
            unsafe { state.write_fpr($frd as usize, value.0) };
            touched = true;
        }};
    }
    macro_rules! set_rm {
        ($rm: expr) => {
            EFFECTIVE_FRM.set(if $rm == 0b111 { state.read_rm() } else { $rm });
        };
    }

    match *op {
        /* F-extension */
        #[cfg(feature = "fp-none")]
        Op::Flw { frd, rs1, imm } => {
            let vaddr = read_reg!(rs1).wrapping_add(imm as usize);
            if vaddr & 3 != 0 {
                trap!(4, vaddr)
            }
            write_fs!(frd, F32::new(load_u32(vaddr)?));
        }
        #[cfg(feature = "fp-none")]
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
        #[cfg(feature = "fp-none")]
        Op::Fld { frd, rs1, imm } => {
            let vaddr = read_reg!(rs1).wrapping_add(imm as usize);
            if vaddr & 3 != 0 {
                trap!(4, vaddr)
            }
            write_fd!(frd, F64::new(load_u64(vaddr)?));
        }
        #[cfg(feature = "fp-none")]
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

    let triggered_flags = TRIGGERED_FLAGS.get();
    if triggered_flags != 0 {
        state.set_flags(triggered_flags);
        touched = true;
    }

    if touched {
        ctx.mstatus |= 0x6000;
    }

    Ok(())
}
