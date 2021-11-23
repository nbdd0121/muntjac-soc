use super::memory;
use super::{Context, TrapInfo};

use riscv::Op;

fn load_instruction(pc: usize) -> (u32, Op) {
    let bits_lo = memory::load_u16_exec(pc).unwrap();
    let (bits, insn) = if bits_lo & 3 != 3 {
        (bits_lo as u32, riscv::decode_compressed(bits_lo))
    } else {
        let bits = bits_lo as u32 | ((memory::load_u16_exec(pc + 2).unwrap() as u32) << 16);
        (bits, riscv::decode(bits))
    };
    (bits, insn)
}

pub fn handle_misaligned_read(ctx: &mut Context) -> Result<(), TrapInfo> {
    let addr;
    unsafe {
        asm!("csrr {}, mtval", lateout(reg) addr, options(nomem, nostack));
    }
    let (bits, insn) = load_instruction(ctx.pc);

    match insn {
        Op::Lh { rd, .. } => {
            let mut bytes = [0; 2];
            memory::load(&mut bytes, addr)?;
            ctx.registers[rd as usize] = i16::from_le_bytes(bytes) as usize;
        }
        Op::Lw { rd, .. } => {
            let mut bytes = [0; 4];
            memory::load(&mut bytes, addr)?;
            ctx.registers[rd as usize] = i32::from_le_bytes(bytes) as usize;
        }
        Op::Ld { rd, .. } => {
            let mut bytes = [0; 8];
            memory::load(&mut bytes, addr)?;
            ctx.registers[rd as usize] = u64::from_le_bytes(bytes) as usize;
        }
        Op::Lhu { rd, .. } => {
            let mut bytes = [0; 2];
            memory::load(&mut bytes, addr)?;
            ctx.registers[rd as usize] = u16::from_le_bytes(bytes) as usize;
        }
        Op::Lwu { rd, .. } => {
            let mut bytes = [0; 4];
            memory::load(&mut bytes, addr)?;
            ctx.registers[rd as usize] = u32::from_le_bytes(bytes) as usize;
        }
        _ => panic!("unexpected misaligned read: {}", insn),
    }

    ctx.pc += if bits & 3 == 3 { 4 } else { 2 };
    Ok(())
}

pub fn handle_misaligned_write(ctx: &mut Context) -> Result<(), TrapInfo> {
    let addr;
    unsafe {
        asm!("csrr {}, mtval", lateout(reg) addr, options(nomem, nostack));
    }
    let (bits, insn) = load_instruction(ctx.pc);

    match insn {
        Op::Sh { rs2, .. } => {
            let bytes = (ctx.registers[rs2 as usize] as u16).to_le_bytes();
            memory::store(addr, &bytes)?;
        }
        Op::Sw { rs2, .. } => {
            let bytes = (ctx.registers[rs2 as usize] as u32).to_le_bytes();
            memory::store(addr, &bytes)?;
        }
        Op::Sd { rs2, .. } => {
            let bytes = ctx.registers[rs2 as usize].to_le_bytes();
            memory::store(addr, &bytes)?;
        }
        _ => {
            return Err(TrapInfo {
                cause: 6,
                tval: addr,
            })
        }
    }

    ctx.pc += if bits & 3 == 3 { 4 } else { 2 };
    Ok(())
}
