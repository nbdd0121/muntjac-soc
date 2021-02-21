.globl get_fpr
get_fpr:
.option push
.option norvc
    auipc a1, 0
    slli a0, a0, 3
    addi a0, a0, 20
    add a1, a1, a0
    jr a1
    .insn s STORE_FP, 3, x0, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x1, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x2, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x3, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x4, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x5, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x6, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x7, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x8, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x9, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x10, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x11, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x12, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x13, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x14, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x15, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x16, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x17, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x18, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x19, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x20, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x21, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x22, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x23, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x24, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x25, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x26, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x27, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x28, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x29, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x30, 0(sp)
    j 1f
    .insn s STORE_FP, 3, x31, 0(sp)
.option pop
1:
    ld a0, (sp)
    ret

.globl set_fpr
set_fpr:
.option push
.option norvc
    sd a1, (sp)
    auipc a1, 0
    slli a0, a0, 3
    addi a0, a0, 20
    add a1, a1, a0
    jr a1
    .insn i LOAD_FP, 3, x0, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x1, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x2, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x3, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x4, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x5, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x6, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x7, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x8, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x9, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x10, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x11, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x12, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x13, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x14, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x15, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x16, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x17, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x18, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x19, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x20, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x21, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x22, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x23, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x24, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x25, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x26, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x27, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x28, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x29, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x30, sp, 0
    j 1f
    .insn i LOAD_FP, 3, x31, sp, 0
.option pop
1:
    ret

