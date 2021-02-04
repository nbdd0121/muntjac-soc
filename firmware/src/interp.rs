use riscv::{Csr, Op};

#[cfg(not(rv64f = "full"))]
use super::fp;
use super::Context;
use super::TrapInfo;

macro_rules! trap {
    ($cause: expr, $tval: expr) => {
        return Err(TrapInfo {
            cause: $cause,
            tval: $tval,
        });
    };
}

/// Perform a CSR read on a context.
fn read_csr(ctx: &mut Context, csr: Csr) -> Result<usize, TrapInfo> {
    Ok(match csr {
        Csr::Time => super::timer::time_u64() as usize,
        #[cfg(rv64f = "none")]
        Csr::Fflags | Csr::Frm | Csr::Fcsr => return fp::read_csr(ctx, csr),
        _ => trap!(2, 0),
    })
}

fn write_csr(ctx: &mut Context, csr: Csr, value: usize) -> Result<(), TrapInfo> {
    match csr {
        #[cfg(rv64f = "none")]
        Csr::Fflags | Csr::Frm | Csr::Fcsr => return fp::write_csr(ctx, csr, value),
        _ => trap!(2, 0),
    }
    Ok(())
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

    match *op {
        /* CSR */
        Op::Csrrw { rd, rs1, csr } => {
            let result = if rd != 0 { read_csr(ctx, csr)? } else { 0 };
            write_csr(ctx, csr, read_reg!(rs1))?;
            write_reg!(rd, result);
        }
        Op::Csrrs { rd, rs1, csr } => {
            let result = read_csr(ctx, csr)?;
            if rs1 != 0 {
                write_csr(ctx, csr, result | read_reg!(rs1))?
            }
            write_reg!(rd, result);
        }
        Op::Csrrc { rd, rs1, csr } => {
            let result = read_csr(ctx, csr)?;
            if rs1 != 0 {
                write_csr(ctx, csr, result & !read_reg!(rs1))?
            }
            write_reg!(rd, result);
        }
        Op::Csrrwi { rd, imm, csr } => {
            let result = if rd != 0 { read_csr(ctx, csr)? } else { 0 };
            write_csr(ctx, csr, imm as usize)?;
            write_reg!(rd, result);
        }
        Op::Csrrsi { rd, imm, csr } => {
            let result = read_csr(ctx, csr)?;
            if imm != 0 {
                write_csr(ctx, csr, result | imm as usize)?
            }
            write_reg!(rd, result);
        }
        Op::Csrrci { rd, imm, csr } => {
            let result = read_csr(ctx, csr)?;
            if imm != 0 {
                write_csr(ctx, csr, result & !imm as usize)?
            }
            write_reg!(rd, result);
        }

        _ => {
            #[cfg(not(rv64f = "full"))]
            if fp::is_fp(op) {
                return fp::step(ctx, op);
            }
            trap!(2, 0);
        }
    }

    Ok(())
}
