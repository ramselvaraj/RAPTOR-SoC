# Zero-thread jobs with a GPU clock much faster than the CPU clock.
# Each completion must survive until CPU software observes sticky done.
    addi x5, x0, 1
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    add x5, x5, x5
    addi x2, x0, 32
    addi x12, x0, 1
    addi x14, x0, 2
    sw x0, 8(x5)
launch:
    sw x12, 0(x5)
poll:
    lw x13, 4(x5)
    and x13, x13, x14
    beq x13, x0, poll
    addi x2, x2, -1
    bne x2, x0, launch
    addi x22, x0, 123
halt:
    beq x0, x0, halt
