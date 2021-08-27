use super::TrapInfo;

fn load_u16_with_flag(addr: usize, flag: usize) -> Result<u16, TrapInfo> {
    let mut err: usize;
    let mut out: u16;
    unsafe {
        asm!(
            "la {mtvec}, 1f
            csrrw {mtvec}, mtvec, {mtvec}
            j 2f
            .balign 4,1
        1:
            li {err}, 1
            j 3f
        2:
            csrs mstatus, {mstatus_flag}
            lhu {out}, ({addr})
            li {err}, 0
        3:
            csrc mstatus, {mstatus_flag}
            csrw mtvec, {mtvec}",
            addr = in(reg) addr,
            out = out(reg) out,
            mtvec = out(reg) _,
            err = out(reg) err,
            mstatus_flag = in(reg) 1 << 17 | flag,
        );
    }

    if err != 0 {
        let cause: usize;
        let tval: usize;
        unsafe {
            asm!("csrr {}, mcause
                  csrr {}, mtval", out(reg) cause, out(reg) tval, options(nomem, nostack));
        };
        Err(TrapInfo { cause, tval })
    } else {
        Ok(out)
    }
}

fn load_u32_with_flag(addr: usize, flag: usize) -> Result<u32, TrapInfo> {
    let mut err: usize;
    let mut out: u32;
    unsafe {
        asm!(
            "la {mtvec}, 1f
            csrrw {mtvec}, mtvec, {mtvec}
            j 2f
            .balign 4,1
        1:
            li {err}, 1
            j 3f
        2:
            csrs mstatus, {mstatus_flag}
            lw {out}, ({addr})
            li {err}, 0
        3:
            csrc mstatus, {mstatus_flag}
            csrw mtvec, {mtvec}",
            addr = in(reg) addr,
            out = out(reg) out,
            mtvec = out(reg) _,
            err = out(reg) err,
            mstatus_flag = in(reg) 1 << 17 | flag,
        );
    }

    if err != 0 {
        let cause: usize;
        let tval: usize;
        unsafe {
            asm!("csrr {}, mcause
                  csrr {}, mtval", out(reg) cause, out(reg) tval, options(nomem, nostack));
        };
        Err(TrapInfo { cause, tval })
    } else {
        Ok(out)
    }
}

fn load_u64_with_flag(addr: usize, flag: usize) -> Result<u64, TrapInfo> {
    let mut err: usize;
    let mut out: u64;
    unsafe {
        asm!(
            "la {mtvec}, 1f
            csrrw {mtvec}, mtvec, {mtvec}
            j 2f
            .balign 4,1
        1:
            li {err}, 1
            j 3f
        2:
            csrs mstatus, {mstatus_flag}
            ld {out}, ({addr})
            li {err}, 0
        3:
            csrc mstatus, {mstatus_flag}
            csrw mtvec, {mtvec}",
            addr = in(reg) addr,
            out = out(reg) out,
            mtvec = out(reg) _,
            err = out(reg) err,
            mstatus_flag = in(reg) 1 << 17 | flag,
        );
    }

    if err != 0 {
        let cause: usize;
        let tval: usize;
        unsafe {
            asm!("csrr {}, mcause
                  csrr {}, mtval", out(reg) cause, out(reg) tval, options(nomem, nostack));
        };
        Err(TrapInfo { cause, tval })
    } else {
        Ok(out)
    }
}

fn load_with_flag(buf: &mut [u8], addr: usize, flag: usize) -> Result<(), TrapInfo> {
    if buf.is_empty() {
        return Ok(());
    }

    let err: usize;
    unsafe {
        asm!(
            "la {mtvec}, 1f
            csrrw {mtvec}, mtvec, {mtvec}
            j 2f
            .balign 4,1
        1:
            csrc mstatus, {mstatus_flag}
            li {err}, 1
            j 3f
        2:
            csrs mstatus, {mstatus_flag}
            lb {tmp}, ({src})
            csrc mstatus, {mstatus_flag}
            sb {tmp}, ({dst})
            addi {src}, {src}, 1
            addi {dst}, {dst}, 1
            blt {dst}, {dst_limit}, 2b
            li {err}, 0
        3:
            csrw mtvec, {mtvec}",
            src = inout(reg) addr => _,
            dst = inout(reg) buf.as_mut_ptr() => _,
            dst_limit = in(reg) buf.as_mut_ptr().add(buf.len()),
            tmp = out(reg) _,
            mtvec = out(reg) _,
            err = lateout(reg) err,
            mstatus_flag = in(reg) 1 << 17 | flag,
        );
    }

    if err != 0 {
        let cause: usize;
        let tval: usize;
        unsafe {
            asm!("csrr {}, mcause
                  csrr {}, mtval", out(reg) cause, out(reg) tval, options(nomem, nostack));
        };
        Err(TrapInfo { cause, tval })
    } else {
        Ok(())
    }
}

pub fn load_u16_exec(addr: usize) -> Result<u16, TrapInfo> {
    load_u16_with_flag(addr, 1 << 19)
}

pub fn load_u32(addr: usize) -> Result<u32, TrapInfo> {
    load_u32_with_flag(addr, 0)
}

pub fn load_u64(addr: usize) -> Result<u64, TrapInfo> {
    load_u64_with_flag(addr, 0)
}

pub fn load_usize(addr: usize) -> Result<usize, TrapInfo> {
    Ok(load_u64(addr)? as _)
}

pub fn load(buf: &mut [u8], addr: usize) -> Result<(), TrapInfo> {
    load_with_flag(buf, addr, 0)
}

pub fn store_u32(addr: usize, value: u32) -> Result<(), TrapInfo> {
    let err: usize;
    unsafe {
        asm!(
            "la {mtvec}, 1f
            csrrw {mtvec}, mtvec, {mtvec}
            j 2f
            .balign 4,1
        1:
            li {err}, 1
            j 3f
        2:
            csrs mstatus, {mstatus_flag}
            sw {val}, ({addr})
            li {err}, 0
        3:
            csrc mstatus, {mstatus_flag}
            csrw mtvec, {mtvec}",
            addr = in(reg) addr,
            val = in(reg) value,
            mtvec = out(reg) _,
            err = out(reg) err,
            mstatus_flag = in(reg) 1 << 17,
        );
    }

    if err != 0 {
        let cause: usize;
        let tval: usize;
        unsafe {
            asm!("csrr {}, mcause
                  csrr {}, mtval", out(reg) cause, out(reg) tval, options(nomem, nostack));
        };
        Err(TrapInfo { cause, tval })
    } else {
        Ok(())
    }
}

pub fn store_u64(addr: usize, value: u64) -> Result<(), TrapInfo> {
    let err: usize;
    unsafe {
        asm!(
            "la {mtvec}, 1f
            csrrw {mtvec}, mtvec, {mtvec}
            j 2f
            .balign 4,1
        1:
            li {err}, 1
            j 3f
        2:
            csrs mstatus, {mstatus_flag}
            sd {val}, ({addr})
            li {err}, 0
        3:
            csrc mstatus, {mstatus_flag}
            csrw mtvec, {mtvec}",
            addr = in(reg) addr,
            val = in(reg) value,
            mtvec = out(reg) _,
            err = out(reg) err,
            mstatus_flag = in(reg) 1 << 17,
        );
    }

    if err != 0 {
        let cause: usize;
        let tval: usize;
        unsafe {
            asm!("csrr {}, mcause
                  csrr {}, mtval", out(reg) cause, out(reg) tval, options(nomem, nostack));
        };
        Err(TrapInfo { cause, tval })
    } else {
        Ok(())
    }
}

pub fn store(addr: usize, buf: &[u8]) -> Result<(), TrapInfo> {
    if buf.is_empty() {
        return Ok(());
    }

    let err: usize;
    unsafe {
        asm!(
            "la {mtvec}, 1f
            csrrw {mtvec}, mtvec, {mtvec}
            j 2f
            .balign 4,1
        1:
            csrc mstatus, {mstatus_flag}
            li {err}, 1
            j 3f
        2:
            lb {tmp}, ({src})
            csrs mstatus, {mstatus_flag}
            sb {tmp}, ({dst})
            csrc mstatus, {mstatus_flag}
            addi {src}, {src}, 1
            addi {dst}, {dst}, 1
            blt {dst}, {dst_limit}, 2b
            li {err}, 0
        3:
            csrw mtvec, {mtvec}",
            src = inout(reg) buf.as_ptr() => _,
            dst = inout(reg) addr => _,
            dst_limit = in(reg) addr + buf.len(),
            tmp = out(reg) _,
            mtvec = out(reg) _,
            err = lateout(reg) err,
            mstatus_flag = in(reg) 1 << 17,
        );
    }

    if err != 0 {
        let cause: usize;
        let tval: usize;
        unsafe {
            asm!("csrr {}, mcause
                  csrr {}, mtval", out(reg) cause, out(reg) tval, options(nomem, nostack));
        };
        Err(TrapInfo { cause, tval })
    } else {
        Ok(())
    }
}
