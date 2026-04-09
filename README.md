# DeiMOS
A MOS 6502 superoptimizer, capable of synthezising programs up to ~11 bytes.

An article explaining the design of the program is available [here](https://aransentin.github.io/deimos/).

## Usage

Specifying the task to be synthesized is done in __src/config.zig__.

First, modify the __test_generate__, __test_run__, and __test_verify__ functions as appropriate for your task. Also specify how many test cases there are; generally 256.

There are a few options as well on what code the superoptimizer should explore. Most of them should be self-explanatory. For example, if you feel the process is slow you might want to limit the amount of zero-page addresses and immediate values the program can utilize.

When this is done, build the program using __zig build__, preferably using __-Doptimize=ReleaseFast__ for obvious reasons.

By default, the program waits for "phobos" workers to connect to port 6502, so that it can distribute work to them. You may automatically spawn such workers as subprocesses, like so:

    ./zig-out/bin/deimos zig-out/bin/phobos 8

The above example will (in addition to the master process) automatically spawn 8 workers, which will die when the program exits.

By default, the superoptimizer tries to find an optimal popcnt(A) program. Run it and it should eventually print:

    info: Program found: bytes: 9, cycles (total): 15623, cycles (worst case): 68
    C000 A2    LDX #$FF
    C001 FF
    C002 E8    INX
    C003 0A    ASL A
    C004 B0    BCS $FC (C002)
    C005 FC
    C006 D0    BNE $FB (C003)
    C007 FB
    C008 8A    TXA
