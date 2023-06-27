#include "platform.h"

.section .text.start
.option arch, +zicsr
.globl _start
_start:
.type _start, @function
.option push
.option norelax
    # Initialise all registers to zero
    li x1, 0
    li x2, 0
    li x3, 0
    li x4, 0
    li x5, 0
    li x6, 0
    li x7, 0
    li x8, 0
    li x9, 0
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x14, 0
    li x15, 0
    li x16, 0
    li x17, 0
    li x18, 0
    li x19, 0
    li x20, 0
    li x21, 0
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    li x26, 0
    li x27, 0
    li x28, 0
    li x29, 0
    li x30, 0
    li x31, 0

    # Pick hart 0 to be the booting hart, send the rest to wait
    csrr s0, mhartid
    bnez s0, .secondary_start

    la  a0, __text_start
    la  a1, __text_start_phys
    la  a2, __bss_start_phys
    sub a2, a2, a1
    call memcpy_phys

    la  a0, __bss_start
    li  a1, 0
    la  a2, __BSS_END__
    sub a2, a2, a0
    call memset_phys

    j .relocated

.secondary_start:
    csrwi mie, 1 << 3
1:
    # Wait until MSIP to fire
    wfi
    csrr t0, mip
    andi t0, t0, 1 << 3
    beqz t0, 1b

    # Fallthrough to relocated

.relocated:
    # Setup the firmware stack and thread pointer
    # The stack pointer will grow down and thread pointer will grow up
    li sp, MEMORY_LIMIT
    slli t0, s0, 14
    sub sp, sp, t0

    la s1, __tdata_start
    la s2, __tdata_end
    la s3, __tbss_end

    # Subtract the size needed for TLS (aligned to 16 bytes)
    sub t0, s3, s1
    sub tp, sp, t0
    and tp, tp, ~15
    mv  sp, tp

    # Copy TDATA
    mv  a0, tp
    mv  a1, s1
    sub a2, s2, a1
    call memcpy

    # Clear TBSS
    sub a0, s2, s1
    add a0, a0, tp
    li  a1, 0
    sub a2, s3, s1
    call memset

    la gp, __global_pointer$
.option pop

    csrw mscratch, sp

    # Setup interrupt handler
    la t0, handler
    csrw mtvec, t0

    # Set a0 to the boot flag
    seqz a0, s0
    call main

    # a0 is the return value from main, i.e. FDT address
    mv a1, a0
    mv a0, s0

    # Delegate as much traps as possible to S-mode
    li t0, -1
    csrw mideleg, t0
    csrw mcounteren, t0
    # Delegate everything except
    # * Illegal instruction
    # * Load/store/AMO alignment fault
    # * Environment call from S-mode
    li t0, 0xB109
    csrw medeleg, t0

    # Enable MTI, MSI
    li t0, (1 << 11) | (1 << 3)
    csrw mie, t0

    # Switch to S-Mode
    li t0, MEMORY_BASE
    csrw mepc, t0
    li t0, 0x800
    csrw mstatus, t0
    mret
.size _start, .-_start

.section .text
.extern handle_interrupt
.balign 16, 1
.type handler, @function
handler:
    # Setup stack MSCRATCH
    csrrw sp, mscratch, sp

    # In case of a firmware re-entry we will have mscratch set to zero.
    beqz sp, 10f

    addi sp, sp, -256-16
    sd x3, 3 * 8(sp)
    sd x4, 4 * 8(sp)
.option push
.option norelax
    la gp, __global_pointer$
    addi tp, sp, 256+16
.option pop

11:
    # Save volatile GPRs
    sd x1, 1 * 8(sp)
    sd x5, 5 * 8(sp)
    sd x6, 6 * 8(sp)
    sd x7, 7 * 8(sp)
    sd x10, 10 * 8(sp)
    sd x11, 11 * 8(sp)
    sd x12, 12 * 8(sp)
    sd x13, 13 * 8(sp)
    sd x14, 14 * 8(sp)
    sd x15, 15 * 8(sp)
    sd x16, 16 * 8(sp)
    sd x17, 17 * 8(sp)
    sd x28, 28 * 8(sp)
    sd x29, 29 * 8(sp)
    sd x30, 30 * 8(sp)
    sd x31, 31 * 8(sp)

    # Set mscratch to zero, indicating we're already in M-mode so can use stack directly. Also save sp.
    csrrw t0, mscratch, x0
    sd t0, 2 * 8(sp)

    # Save MEPC
    csrr t0, mepc
    sd t0, 32 * 8(sp)

    # Save MSTATUS
    csrr t0, mstatus
    sd t0, 33 * 8(sp)

    csrr a0, mcause
    mv a1, sp
    call handle_interrupt_fast
    bnez a0, 1f

    # Save all other GPRs
    sd x0, 0 * 8(sp)
    sd x8, 8 * 8(sp)
    sd x9, 9 * 8(sp)
    sd x18, 18 * 8(sp)
    sd x19, 19 * 8(sp)
    sd x20, 20 * 8(sp)
    sd x21, 21 * 8(sp)
    sd x22, 22 * 8(sp)
    sd x23, 23 * 8(sp)
    sd x24, 24 * 8(sp)
    sd x25, 25 * 8(sp)
    sd x26, 26 * 8(sp)
    sd x27, 27 * 8(sp)

    csrr a0, mcause
    mv a1, sp
    call handle_interrupt

    # Restore non-volatile GPR, except SP, GP, TP
    ld x8, 8 * 8(sp)
    ld x9, 9 * 8(sp)
    ld x18, 18 * 8(sp)
    ld x19, 19 * 8(sp)
    ld x20, 20 * 8(sp)
    ld x21, 21 * 8(sp)
    ld x22, 22 * 8(sp)
    ld x23, 23 * 8(sp)
    ld x24, 24 * 8(sp)
    ld x25, 25 * 8(sp)
    ld x26, 26 * 8(sp)
    ld x27, 27 * 8(sp)

1:
    # Restore MEPC
    ld t0, 32 * 8(sp)
    csrw mepc, t0

    # Restore MSTATUS
    ld t0, 33 * 8(sp)
    csrw mstatus, t0

    # If mstatus.MPP is not M, reset mscratch
    li t1, 0x1000
    and t0, t0, t1
    bnez t0, 1f
    addi t0, sp, 256 + 16
    csrw mscratch, t0
1:

    # Restore volatile GPRs and GP, TP
    ld x1, 1 * 8(sp)
    ld x3, 3 * 8(sp)
    ld x4, 4 * 8(sp)
    ld x5, 5 * 8(sp)
    ld x6, 6 * 8(sp)
    ld x7, 7 * 8(sp)
    ld x10, 10 * 8(sp)
    ld x11, 11 * 8(sp)
    ld x12, 12 * 8(sp)
    ld x13, 13 * 8(sp)
    ld x14, 14 * 8(sp)
    ld x15, 15 * 8(sp)
    ld x16, 16 * 8(sp)
    ld x17, 17 * 8(sp)
    ld x28, 28 * 8(sp)
    ld x29, 29 * 8(sp)
    ld x30, 30 * 8(sp)
    ld x31, 31 * 8(sp)

    # Restore Stack
    ld sp, 2 * 8(sp)
    mret

# M-mode interrupt reentry
10:
    # Read out saved SP and reuse that.
    csrr sp, mscratch
    addi sp, sp, -256-16
    # GP and TP don't need to change,
    # but save them so restore code don't need to be aware.
    sd x3, 3 * 8(sp)
    sd x4, 4 * 8(sp)
    j 11b
.size handler, . - handler
