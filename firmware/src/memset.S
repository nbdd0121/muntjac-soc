.global memset
.balign 16, 1
.type memset, @function
memset:
    /* Save for return value */
    mv   t6, a0

    /*
     * Register allocation for code below:
     * a0 - start of unfilled dst
     * t0 - end of unfilled dst
     */
    add  t0, a0, a2

    /*
     * Use bytewise fill if too small.
     *
     * This threshold must be at least 16 to ensure at least one wordwise fill
     * is performed. This will save at least 7 iterations of bytewise fill,
     * which pays off the fixed overhead.
     */
    li   a3, 16
    bltu a2, a3, .Lbyte_fill_tail

    /*
     * Bytewise fill first to align a0 to word boundary.
     */
    addi a2, a0, 7
    andi a2, a2, ~7
    beq  a0, a2, 2f
1:
    sb   a1, 0(a0)
    addi a0, a0, 1
    bne  a0, a2, 1b
2:

    /* Broadcast value into all bytes */
    andi a1, a1, 0xff
    slli a3, a1, 8
    or   a1, a3, a1
    slli a3, a1, 16
    or   a1, a3, a1
    slli a3, a1, 32
    or   a1, a3, a1

    /* Align the end pointer to word boundary */
    andi a2, t0, ~7

    /* Calculate the offset into the loop */
    sub  a3, a2, a0
    neg  a3, a3
    andi a3, a3, 32*8-1

    /* Offset the excessive increment in first iteration */
    sub  a0, a0, a3

    /* Jump into the loop by offset */
    la   a4, 1f
    srli a5, a3, 2
    add  a4, a4, a5
    jr   a4

1:
    c.sd a1,  0*8(a0)
    c.sd a1,  1*8(a0)
    c.sd a1,  2*8(a0)
    c.sd a1,  3*8(a0)
    c.sd a1,  4*8(a0)
    c.sd a1,  5*8(a0)
    c.sd a1,  6*8(a0)
    c.sd a1,  7*8(a0)
    c.sd a1,  8*8(a0)
    c.sd a1,  9*8(a0)
    c.sd a1, 10*8(a0)
    c.sd a1, 11*8(a0)
    c.sd a1, 12*8(a0)
    c.sd a1, 13*8(a0)
    c.sd a1, 14*8(a0)
    c.sd a1, 15*8(a0)
    c.sd a1, 16*8(a0)
    c.sd a1, 17*8(a0)
    c.sd a1, 18*8(a0)
    c.sd a1, 19*8(a0)
    c.sd a1, 20*8(a0)
    c.sd a1, 21*8(a0)
    c.sd a1, 22*8(a0)
    c.sd a1, 23*8(a0)
    c.sd a1, 24*8(a0)
    c.sd a1, 25*8(a0)
    c.sd a1, 26*8(a0)
    c.sd a1, 27*8(a0)
    c.sd a1, 28*8(a0)
    c.sd a1, 29*8(a0)
    c.sd a1, 30*8(a0)
    c.sd a1, 31*8(a0)
    addi a0, a0, 32*8
    bltu a0, a2, 1b

.Lbyte_fill_tail:
    /*
     * Bytewise fill anything left.
     */
    beq  a0, t0, 2f
1:
    sb   a1, 0(a0)
    addi a0, a0, 1
    bne  a0, t0, 1b
2:

    mv   a0, t6
    ret
.size memset, . - memset
