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

    info: Program found: bytes: 10, cycles (total): 21270, cycles (worst case): 94
    C000 38    SEC
    C001 6A    ROR A
    C002 85    STA $00
    C003 00
    C004 65    ADC $00
    C005 00
    C006 06    ASL $00
    C007 00
    C008 D0    BNE $FA (C004)
    C009 FA
