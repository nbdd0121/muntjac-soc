use super::TrapInfo;

pub fn load_u16_exec(addr: usize) -> u16 {
    let mut err: usize = 0;
    let mut ret: u16;
    unsafe {
        asm!(
            "li t0, (1 << 17) | (1 << 19)
            csrs mstatus, t0
            .option push
            .option norvc
            lh {}, ({})
            .option pop
            csrc mstatus, t0",
            out(reg) ret,
            in(reg) addr,
            inout("a0") err,
            out("t0") _,
        );
    }
    assert_eq!(err, 0);
    ret
}

pub fn load_u32(addr: usize) -> Result<u32, TrapInfo> {
    let mut err: usize = 0;
    let mut ret: u32;
    unsafe {
        asm!(
            "li t0, 1 << 17
            csrs mstatus, t0
            .option push
            .option norvc
            lw {}, ({})
            .option pop
            csrc mstatus, t0",
            out(reg) ret,
            in(reg) addr,
            inout("a0") err,
            out("t0") _,
        );
    }
    if err != 0 {
        Err(TrapInfo {
            cause: 13,
            tval: addr,
        })
    } else {
        Ok(ret)
    }
}

pub fn load_u64(addr: usize) -> Result<u64, TrapInfo> {
    let mut err: usize = 0;
    let mut ret: u64;
    unsafe {
        asm!(
            "li t0, 1 << 17
            csrs mstatus, t0
            .option push
            .option norvc
            ld {}, ({})
            .option pop
            csrc mstatus, t0",
            out(reg) ret,
            in(reg) addr,
            inout("a0") err,
            out("t0") _,
        );
    }
    if err != 0 {
        Err(TrapInfo {
            cause: 13,
            tval: addr,
        })
    } else {
        Ok(ret)
    }
}

pub fn load_usize(addr: usize) -> Result<usize, TrapInfo> {
    Ok(load_u64(addr)? as _)
}

pub fn store_u32(addr: usize, value: u32) -> Result<(), TrapInfo> {
    let mut err: usize = 0;
    unsafe {
        asm!(
            "li t0, 1 << 17
            csrs mstatus, t0
            .option push
            .option norvc
            sw {}, ({})
            .option pop
            csrc mstatus, t0",
            in(reg) value,
            in(reg) addr,
            inout("a0") err,
            out("t0") _,
        );
    }
    if err != 0 {
        Err(TrapInfo {
            cause: 15,
            tval: addr,
        })
    } else {
        Ok(())
    }
}

pub fn store_u64(addr: usize, value: u64) -> Result<(), TrapInfo> {
    let mut err: usize = 0;
    unsafe {
        asm!(
            "li t0, 1 << 17
            csrs mstatus, t0
            .option push
            .option norvc
            sd {}, ({})
            .option pop
            csrc mstatus, t0",
            in(reg) value,
            in(reg) addr,
            inout("a0") err,
            out("t0") _,
        );
    }
    if err != 0 {
        Err(TrapInfo {
            cause: 15,
            tval: addr,
        })
    } else {
        Ok(())
    }
}

pub fn load(buf: &mut [u8], addr: usize) -> Result<(), TrapInfo> {
    if buf.is_empty() {
        return Ok(());
    }

    let mut err: usize = 0;
    unsafe {
        asm!(
            "li t0, 1 << 17
        1:
            csrs mstatus, t0
            .option push
            .option norvc
            lb {tmp}, ({src})
            .option pop
            csrc mstatus, t0
            sb {tmp}, ({dst})
            bnez a0, 2f
            addi {src}, {src}, 1
            addi {dst}, {dst}, 1
            addi {size}, {size}, -1
            bnez {size}, 1b
        2:",
            src = inout(reg) addr => _,
            dst = inout(reg) buf.as_mut_ptr() => _,
            size = inout(reg) buf.len() => _,
            tmp = out(reg) _,
            inout("a0") err,
        );
    }

    if err != 0 {
        let tval = unsafe {
            let v: usize;
            asm!("csrr {}, mtval", out(reg) v, options(nomem, nostack));
            v
        };
        Err(TrapInfo { cause: 13, tval })
    } else {
        Ok(())
    }
}

pub fn store(addr: usize, buf: &[u8]) -> Result<(), TrapInfo> {
    if buf.is_empty() {
        return Ok(());
    }

    let mut err: usize = 0;
    unsafe {
        asm!(
            "li t0, 1 << 17
        1:
            lb {tmp}, ({src})
            csrs mstatus, t0
            .option push
            .option norvc
            sb {tmp}, ({dst})
            .option pop
            csrc mstatus, t0
            bnez a0, 2f
            addi {src}, {src}, 1
            addi {dst}, {dst}, 1
            addi {size}, {size}, -1
            bnez {size}, 1b
        2:",
            src = inout(reg) buf.as_ptr() => _,
            dst = inout(reg) addr => _,
            size = inout(reg) buf.len() => _,
            tmp = out(reg) _,
            inout("a0") err,
        );
    }

    if err != 0 {
        let tval = unsafe {
            let v: usize;
            asm!("csrr {}, mtval", out(reg) v, options(nomem, nostack));
            v
        };
        Err(TrapInfo { cause: 15, tval })
    } else {
        Ok(())
    }
}
