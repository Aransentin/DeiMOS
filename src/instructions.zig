pub const InstructionMode = enum {
    accumulator,
    absolute,
    absolute_x,
    absolute_y,
    immediate,
    implied,
    indirect,
    indirect_x,
    indirect_y,
    relative,
    zeropage,
    zeropage_x,
    zeropage_y,
};

pub const Instruction = struct {
    name: []const u8,
    mode: InstructionMode,
    op: u8,
    unofficial: bool = false,
    implemented: bool = false,
    jam: bool = false,
    nop: bool = false,
    unstable: bool = false,
    readmem: bool = false,
    writemem: bool = false,

    pub fn size(self: Instruction) u8 {
        return switch (self.mode) {
            .accumulator, .implied => 1,
            .immediate, .relative, .indirect_x, .indirect_y, .zeropage, .zeropage_x, .zeropage_y => 2,
            else => 3,
        };
    }
};

pub const instructions: struct {

    // Transfer Instructions

    tax: Instruction = .{
        .name = "TAX",
        .mode = .implied,
        .op = 0xAA,
        .implemented = true,
    },

    txa: Instruction = .{
        .name = "TXA",
        .mode = .implied,
        .op = 0x8A,
        .implemented = true,
    },

    tay: Instruction = .{
        .name = "TAY",
        .mode = .implied,
        .op = 0xA8,
        .implemented = true,
    },

    tya: Instruction = .{
        .name = "TYA",
        .mode = .implied,
        .op = 0x98,
        .implemented = true,
    },

    tsx: Instruction = .{
        .name = "TSX",
        .mode = .implied,
        .op = 0xBA,
        .implemented = true,
    },

    txs: Instruction = .{
        .name = "TXS",
        .mode = .implied,
        .op = 0x9A,
        .implemented = true,
    },

    lda_imm: Instruction = .{
        .name = "LDA",
        .mode = .immediate,
        .op = 0xA9,
        .implemented = true,
    },

    lda_zp: Instruction = .{
        .name = "LDA",
        .mode = .zeropage,
        .op = 0xA5,
        .readmem = true,
        .implemented = true,
    },

    lda_zpx: Instruction = .{
        .name = "LDA",
        .mode = .zeropage_x,
        .op = 0xB5,
        .readmem = true,
    },

    lda_abs: Instruction = .{
        .name = "LDA",
        .mode = .absolute,
        .op = 0xAD,
        .readmem = true,
    },

    lda_absx: Instruction = .{
        .name = "LDA",
        .mode = .absolute_x,
        .op = 0xBD,
        .readmem = true,
    },

    lda_absy: Instruction = .{
        .name = "LDA",
        .mode = .absolute_y,
        .op = 0xB9,
        .readmem = true,
    },

    lda_indx: Instruction = .{
        .name = "LDA",
        .mode = .indirect_y,
        .op = 0xA1,
        .readmem = true,
    },

    lda_indy: Instruction = .{
        .name = "LDA",
        .mode = .indirect_x,
        .op = 0xB1,
        .readmem = true,
    },

    ldx_imm: Instruction = .{
        .name = "LDX",
        .mode = .immediate,
        .op = 0xA2,
        .implemented = true,
    },

    ldx_zp: Instruction = .{
        .name = "LDX",
        .mode = .zeropage,
        .op = 0xA6,
        .readmem = true,
        .implemented = true,
    },

    ldx_zpy: Instruction = .{
        .name = "LDX",
        .mode = .zeropage_y,
        .op = 0xB6,
        .readmem = true,
        .implemented = true,
    },

    ldx_abs: Instruction = .{
        .name = "LDX",
        .mode = .absolute,
        .op = 0xAE,
        .readmem = true,
    },

    ldx_absy: Instruction = .{
        .name = "LDX",
        .mode = .absolute_y,
        .op = 0xBE,
        .readmem = true,
        .implemented = true,
    },

    ldy_imm: Instruction = .{
        .name = "LDY",
        .mode = .immediate,
        .op = 0xA0,
        .implemented = true,
    },

    ldy_zp: Instruction = .{
        .name = "LDY",
        .mode = .zeropage,
        .op = 0xA4,
        .readmem = true,
        .implemented = true,
    },

    ldy_zpx: Instruction = .{
        .name = "LDY",
        .mode = .zeropage_x,
        .op = 0xB4,
        .readmem = true,
    },

    ldy_abs: Instruction = .{
        .name = "LDY",
        .mode = .absolute,
        .op = 0xAC,
        .readmem = true,
    },

    ldy_absx: Instruction = .{
        .name = "LDY",
        .mode = .absolute_x,
        .op = 0xBC,
        .readmem = true,
    },

    sta_zp: Instruction = .{
        .name = "STA",
        .mode = .zeropage,
        .op = 0x85,
        .writemem = true,
        .implemented = true,
    },

    sta_zpx: Instruction = .{
        .name = "STA",
        .mode = .zeropage_x,
        .op = 0x95,
        .writemem = true,
    },

    sta_abs: Instruction = .{
        .name = "STA",
        .mode = .absolute,
        .op = 0x8D,
        .writemem = true,
    },

    sta_absx: Instruction = .{
        .name = "STA",
        .mode = .absolute_x,
        .op = 0x9D,
        .writemem = true,
    },

    sta_absy: Instruction = .{
        .name = "STA",
        .mode = .absolute_y,
        .op = 0x99,
        .writemem = true,
    },

    sta_indx: Instruction = .{
        .name = "STA",
        .mode = .indirect_x,
        .op = 0x81,
        .writemem = true,
    },

    sta_indy: Instruction = .{
        .name = "STA",
        .mode = .indirect_y,
        .op = 0x91,
        .writemem = true,
    },

    stx_zp: Instruction = .{
        .name = "STX",
        .mode = .zeropage,
        .op = 0x86,
        .writemem = true,
        .implemented = true,
    },

    stx_zpy: Instruction = .{
        .name = "STX",
        .mode = .zeropage_y,
        .op = 0x96,
        .writemem = true,
        .implemented = true,
    },

    stx_abs: Instruction = .{
        .name = "STX",
        .mode = .absolute,
        .op = 0x8E,
        .writemem = true,
    },

    sty_zp: Instruction = .{
        .name = "STY",
        .mode = .zeropage,
        .op = 0x84,
        .writemem = true,
        .implemented = true,
    },

    sty_zpx: Instruction = .{
        .name = "STY",
        .mode = .zeropage_x,
        .op = 0x94,
        .writemem = true,
    },

    sty_absolute: Instruction = .{
        .name = "STY",
        .mode = .absolute,
        .op = 0x8C,
        .writemem = true,
    },

    // Stack Instructions

    pha: Instruction = .{
        .name = "PHA",
        .mode = .implied,
        .op = 0x48,
    },

    php: Instruction = .{
        .name = "PHP",
        .mode = .implied,
        .op = 0x08,
    },

    pla: Instruction = .{
        .name = "PLA",
        .mode = .implied,
        .op = 0x68,
    },

    plp: Instruction = .{
        .name = "PLP",
        .mode = .implied,
        .op = 0x28,
    },

    // Decrements & Increments

    inx: Instruction = .{
        .name = "INX",
        .mode = .implied,
        .op = 0xE8,
        .implemented = true,
    },

    dex: Instruction = .{
        .name = "DEX",
        .mode = .implied,
        .op = 0xCA,
        .implemented = true,
    },

    iny: Instruction = .{
        .name = "INY",
        .mode = .implied,
        .op = 0xC8,
        .implemented = true,
    },

    dey: Instruction = .{
        .name = "DEY",
        .mode = .implied,
        .op = 0x88,
        .implemented = true,
    },

    inc_zp: Instruction = .{
        .name = "INC",
        .mode = .zeropage,
        .op = 0xE6,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    inc_zpx: Instruction = .{
        .name = "INC",
        .mode = .zeropage_x,
        .op = 0xF6,
        .readmem = true,
        .writemem = true,
    },

    inc_abs: Instruction = .{
        .name = "INC",
        .mode = .absolute,
        .op = 0xEE,
        .readmem = true,
        .writemem = true,
    },

    inc_absx: Instruction = .{
        .name = "INC",
        .mode = .absolute_x,
        .op = 0xFE,
        .readmem = true,
        .writemem = true,
    },

    dec_zp: Instruction = .{
        .name = "DEC",
        .mode = .zeropage,
        .op = 0xC6,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    dec_zpx: Instruction = .{
        .name = "DEC",
        .mode = .zeropage_x,
        .op = 0xD6,
        .readmem = true,
        .writemem = true,
    },

    dec_abs: Instruction = .{
        .name = "DEC",
        .mode = .absolute,
        .op = 0xCE,
        .readmem = true,
        .writemem = true,
    },

    dec_absx: Instruction = .{
        .name = "DEC",
        .mode = .absolute_x,
        .op = 0xDE,
        .readmem = true,
        .writemem = true,
    },

    // Arithmetic Operations

    adc_imm: Instruction = .{
        .name = "ADC",
        .mode = .immediate,
        .op = 0x69,
        .implemented = true,
    },

    adc_zp: Instruction = .{
        .name = "ADC",
        .mode = .zeropage,
        .op = 0x65,
        .readmem = true,
        .implemented = true,
    },

    adc_zpx: Instruction = .{
        .name = "ADC",
        .mode = .zeropage_x,
        .op = 0x75,
        .readmem = true,
    },

    adc_abs: Instruction = .{
        .name = "ADC",
        .mode = .absolute,
        .op = 0x6D,
        .readmem = true,
    },

    adc_absx: Instruction = .{
        .name = "ADC",
        .mode = .absolute_x,
        .op = 0x7D,
        .readmem = true,
    },

    adc_absy: Instruction = .{
        .name = "ADC",
        .mode = .absolute_y,
        .op = 0x79,
        .readmem = true,
    },

    adc_indx: Instruction = .{
        .name = "ADC",
        .mode = .indirect_x,
        .op = 0x61,
        .readmem = true,
    },

    adc_indy: Instruction = .{
        .name = "ADC",
        .mode = .indirect_y,
        .op = 0x71,
        .readmem = true,
    },

    sbc_imm: Instruction = .{
        .name = "SBC",
        .mode = .immediate,
        .op = 0xE9,
        .implemented = true,
    },

    sbc_zp: Instruction = .{
        .name = "SBC",
        .mode = .zeropage,
        .op = 0xE5,
        .readmem = true,
        .implemented = true,
    },

    sbc_zpx: Instruction = .{
        .name = "SBC",
        .mode = .zeropage_x,
        .op = 0xF5,
        .readmem = true,
    },

    sbc_abs: Instruction = .{
        .name = "SBC",
        .mode = .absolute,
        .op = 0xED,
        .readmem = true,
    },

    sbc_absx: Instruction = .{
        .name = "SBC",
        .mode = .absolute_x,
        .op = 0xFD,
        .readmem = true,
    },

    sbc_absy: Instruction = .{
        .name = "SBC",
        .mode = .absolute_y,
        .op = 0xF9,
        .readmem = true,
    },

    sbc_indx: Instruction = .{
        .name = "SBC",
        .mode = .indirect_x,
        .op = 0xE1,
        .readmem = true,
    },

    sbc_indy: Instruction = .{
        .name = "SBC",
        .mode = .indirect_y,
        .op = 0xF1,
        .readmem = true,
    },

    // Logical Operations

    and_imm: Instruction = .{
        .name = "AND",
        .mode = .immediate,
        .op = 0x29,
        .implemented = true,
    },

    and_zp: Instruction = .{
        .name = "AND",
        .mode = .zeropage,
        .op = 0x25,
        .readmem = true,
        .implemented = true,
    },

    and_zpx: Instruction = .{
        .name = "AND",
        .mode = .zeropage_x,
        .op = 0x35,
        .readmem = true,
    },

    and_abs: Instruction = .{
        .name = "AND",
        .mode = .absolute,
        .op = 0x2D,
        .readmem = true,
    },

    and_absx: Instruction = .{
        .name = "AND",
        .mode = .absolute_x,
        .op = 0x3D,
        .readmem = true,
    },

    and_absy: Instruction = .{
        .name = "AND",
        .mode = .absolute_y,
        .op = 0x39,
        .readmem = true,
    },

    and_indx: Instruction = .{
        .name = "AND",
        .mode = .indirect_x,
        .op = 0x21,
        .readmem = true,
    },

    and_indy: Instruction = .{
        .name = "AND",
        .mode = .indirect_y,
        .op = 0x31,
        .readmem = true,
    },

    eor_imm: Instruction = .{
        .name = "EOR",
        .mode = .immediate,
        .op = 0x49,
        .implemented = true,
    },

    eor_zp: Instruction = .{
        .name = "EOR",
        .mode = .zeropage,
        .op = 0x45,
        .readmem = true,
        .implemented = true,
    },

    eor_zpx: Instruction = .{
        .name = "EOR",
        .mode = .zeropage_x,
        .op = 0x55,
        .readmem = true,
    },

    eor_abs: Instruction = .{
        .name = "EOR",
        .mode = .absolute,
        .op = 0x4D,
        .readmem = true,
    },

    eor_absx: Instruction = .{
        .name = "EOR",
        .mode = .absolute_x,
        .op = 0x5D,
        .readmem = true,
    },

    eor_absy: Instruction = .{
        .name = "EOR",
        .mode = .absolute_y,
        .op = 0x59,
        .readmem = true,
    },

    eor_indx: Instruction = .{
        .name = "EOR",
        .mode = .indirect_x,
        .op = 0x41,
        .readmem = true,
    },

    eor_indy: Instruction = .{
        .name = "EOR",
        .mode = .indirect_y,
        .op = 0x51,
        .readmem = true,
    },

    ora_imm: Instruction = .{
        .name = "ORA",
        .mode = .immediate,
        .op = 0x09,
        .implemented = true,
    },

    ora_zp: Instruction = .{
        .name = "ORA",
        .mode = .zeropage,
        .op = 0x05,
        .readmem = true,
        .implemented = true,
    },

    ora_zpx: Instruction = .{
        .name = "ORA",
        .mode = .zeropage_x,
        .op = 0x15,
        .readmem = true,
    },

    ora_abs: Instruction = .{
        .name = "ORA",
        .mode = .absolute,
        .op = 0x0D,
        .readmem = true,
    },

    ora_absx: Instruction = .{
        .name = "ORA",
        .mode = .absolute_x,
        .op = 0x1D,
        .readmem = true,
    },

    ora_absy: Instruction = .{
        .name = "ORA",
        .mode = .absolute_y,
        .op = 0x19,
        .readmem = true,
    },

    ora_indx: Instruction = .{
        .name = "ORA",
        .mode = .indirect_x,
        .op = 0x01,
        .readmem = true,
    },

    ora_indy: Instruction = .{
        .name = "ORA",
        .mode = .indirect_y,
        .op = 0x11,
        .readmem = true,
    },

    // Shift & Rotate Instructions

    asl: Instruction = .{
        .name = "ASL",
        .mode = .accumulator,
        .op = 0x0A,
        .implemented = true,
    },

    asl_zp: Instruction = .{
        .name = "ASL",
        .mode = .zeropage,
        .op = 0x06,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    asl_zpx: Instruction = .{
        .name = "ASL",
        .mode = .zeropage_x,
        .op = 0x16,
        .readmem = true,
        .writemem = true,
    },

    asl_abs: Instruction = .{
        .name = "ASL",
        .mode = .absolute,
        .op = 0x0E,
        .readmem = true,
        .writemem = true,
    },

    asl_absx: Instruction = .{
        .name = "ASL",
        .mode = .absolute_x,
        .op = 0x1E,
        .readmem = true,
        .writemem = true,
    },

    lsr: Instruction = .{
        .name = "LSR",
        .mode = .accumulator,
        .op = 0x4A,
        .implemented = true,
    },

    lsr_zp: Instruction = .{
        .name = "LSR",
        .mode = .zeropage,
        .op = 0x46,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    lsr_zpx: Instruction = .{
        .name = "LSR",
        .mode = .zeropage_x,
        .op = 0x56,
        .readmem = true,
        .writemem = true,
    },

    lsr_abs: Instruction = .{
        .name = "LSR",
        .mode = .absolute,
        .op = 0x4E,
        .readmem = true,
        .writemem = true,
    },

    lsr_absx: Instruction = .{
        .name = "LSR",
        .mode = .absolute_x,
        .op = 0x5E,
        .readmem = true,
        .writemem = true,
    },

    rol: Instruction = .{
        .name = "ROL",
        .mode = .accumulator,
        .op = 0x2A,
        .implemented = true,
    },

    rol_zp: Instruction = .{
        .name = "ROL",
        .mode = .zeropage,
        .op = 0x26,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    rol_zpx: Instruction = .{
        .name = "ROL",
        .mode = .zeropage_x,
        .op = 0x36,
        .readmem = true,
        .writemem = true,
    },

    rol_abs: Instruction = .{
        .name = "ROL",
        .mode = .absolute,
        .op = 0x2E,
        .readmem = true,
        .writemem = true,
    },

    rol_absx: Instruction = .{
        .name = "ROL",
        .mode = .absolute_x,
        .op = 0x3E,
        .readmem = true,
        .writemem = true,
    },

    ror: Instruction = .{
        .name = "ROR",
        .mode = .accumulator,
        .op = 0x6A,
        .implemented = true,
    },

    ror_zp: Instruction = .{
        .name = "ROR",
        .mode = .zeropage,
        .op = 0x66,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    ror_zpx: Instruction = .{
        .name = "ROR",
        .mode = .zeropage_x,
        .op = 0x76,
        .readmem = true,
        .writemem = true,
    },

    ror_abs: Instruction = .{
        .name = "ROR",
        .mode = .absolute,
        .op = 0x6E,
        .readmem = true,
        .writemem = true,
    },

    ror_absx: Instruction = .{
        .name = "ROR",
        .mode = .absolute_x,
        .op = 0x7E,
        .readmem = true,
        .writemem = true,
    },

    // Flag Instructions

    clc: Instruction = .{
        .name = "CLC",
        .mode = .implied,
        .op = 0x18,
        .implemented = true,
    },

    cld: Instruction = .{
        .name = "CLD",
        .mode = .implied,
        .op = 0xD8,
        .implemented = true,
    },

    cli: Instruction = .{
        .name = "CLI",
        .mode = .implied,
        .op = 0x58,
        .implemented = true,
    },

    clv: Instruction = .{
        .name = "CLV",
        .mode = .implied,
        .op = 0xB8,
        .implemented = true,
    },

    sec: Instruction = .{
        .name = "SEC",
        .mode = .implied,
        .op = 0x38,
        .implemented = true,
    },

    sed: Instruction = .{
        .name = "SED",
        .mode = .implied,
        .op = 0xF8,
        .implemented = true,
    },

    sei: Instruction = .{
        .name = "SEI",
        .mode = .implied,
        .op = 0x78,
        .implemented = true,
    },

    // Comparisons

    cmp_imm: Instruction = .{
        .name = "CMP",
        .mode = .immediate,
        .op = 0xC9,
        .implemented = true,
    },

    cmp_zp: Instruction = .{
        .name = "CMP",
        .mode = .zeropage,
        .op = 0xC5,
        .readmem = true,
        .implemented = true,
    },

    cmp_zpx: Instruction = .{
        .name = "CMP",
        .mode = .zeropage_x,
        .op = 0xD5,
        .readmem = true,
    },

    cmp_abs: Instruction = .{
        .name = "CMP",
        .mode = .absolute,
        .op = 0xCD,
        .readmem = true,
    },

    cmp_absx: Instruction = .{
        .name = "CMP",
        .mode = .absolute_x,
        .op = 0xDD,
        .readmem = true,
    },

    cmp_absy: Instruction = .{
        .name = "CMP",
        .mode = .absolute_y,
        .op = 0xD9,
        .readmem = true,
    },

    cmp_indx: Instruction = .{
        .name = "CMP",
        .mode = .indirect_x,
        .op = 0xC1,
        .readmem = true,
    },

    cmp_indy: Instruction = .{
        .name = "CMP",
        .mode = .indirect_y,
        .op = 0xD1,
        .readmem = true,
    },

    cpx_imm: Instruction = .{
        .name = "CPX",
        .mode = .immediate,
        .op = 0xE0,
        .implemented = true,
    },

    cpx_zp: Instruction = .{
        .name = "CPX",
        .mode = .zeropage,
        .op = 0xE4,
        .readmem = true,
        .implemented = true,
    },

    cpx_abs: Instruction = .{
        .name = "CPX",
        .mode = .absolute,
        .op = 0xEC,
        .readmem = true,
    },

    cpy_imm: Instruction = .{
        .name = "CPY",
        .mode = .immediate,
        .op = 0xC0,
        .readmem = true,
        .implemented = true,
    },

    cpy_zp: Instruction = .{
        .name = "CPY",
        .mode = .zeropage,
        .op = 0xC4,
        .readmem = true,
        .implemented = true,
    },

    cpy_abs: Instruction = .{
        .name = "CPY",
        .mode = .absolute,
        .op = 0xCC,
        .readmem = true,
    },

    // Conditional Branch Instructions

    bcc: Instruction = .{
        .name = "BCC",
        .mode = .relative,
        .op = 0x90,
        .implemented = true,
    },

    bcs: Instruction = .{
        .name = "BCS",
        .mode = .relative,
        .op = 0xB0,
        .implemented = true,
    },

    beq: Instruction = .{
        .name = "BEQ",
        .mode = .relative,
        .op = 0xF0,
        .implemented = true,
    },

    bmi: Instruction = .{
        .name = "BMI",
        .mode = .relative,
        .op = 0x30,
        .implemented = true,
    },

    bne: Instruction = .{
        .name = "BNE",
        .mode = .relative,
        .op = 0xD0,
        .implemented = true,
    },

    bpl: Instruction = .{
        .name = "BPL",
        .mode = .relative,
        .op = 0x10,
        .implemented = true,
    },

    bvc: Instruction = .{
        .name = "BVC",
        .mode = .relative,
        .op = 0x50,
        .implemented = true,
    },

    bvs: Instruction = .{
        .name = "BVS",
        .mode = .relative,
        .op = 0x70,
        .implemented = true,
    },

    // Jumps & Subroutines

    jmp: Instruction = .{
        .name = "JMP",
        .mode = .absolute,
        .op = 0x4C,
    },

    jmp_ind: Instruction = .{
        .name = "JMP",
        .mode = .indirect,
        .op = 0x6C,
    },

    jsr: Instruction = .{
        .name = "JSR",
        .mode = .absolute,
        .op = 0x20,
    },

    rts: Instruction = .{
        .name = "RTS",
        .mode = .implied,
        .op = 0x60,
    },

    // Interrupts

    brk: Instruction = .{
        .name = "BRK",
        .mode = .implied,
        .op = 0x00,
        .jam = true,
    },

    rti: Instruction = .{
        .name = "RTI",
        .mode = .implied,
        .op = 0x40,
    },

    // Misc

    bit_zp: Instruction = .{
        .name = "BIT",
        .mode = .zeropage,
        .op = 0x24,
        .readmem = true,
        .implemented = true,
    },

    bit_abs: Instruction = .{
        .name = "BIT",
        .mode = .absolute,
        .op = 0x2C,
        .readmem = true,
    },

    nop: Instruction = .{
        .name = "NOP",
        .mode = .implied,
        .op = 0xEA,
        .nop = true,
    },

    // Unofficial

    alr_imm: Instruction = .{
        .name = "ALR",
        .mode = .immediate,
        .op = 0x4B,
        .unofficial = true,
        .implemented = true,
    },

    anc_imm: Instruction = .{
        .name = "ANC",
        .mode = .immediate,
        .op = 0x0B,
        .unofficial = true,
        .implemented = true,
    },

    anc_imm_2: Instruction = .{
        .name = "ANC",
        .mode = .immediate,
        .op = 0x2B,
        .unofficial = true,
        .implemented = true,
    },

    ane_imm: Instruction = .{
        .name = "ANE",
        .mode = .immediate,
        .op = 0x8B,
        .unofficial = true,
        .unstable = true,
    },

    arr_imm: Instruction = .{
        .name = "ARR",
        .mode = .immediate,
        .op = 0x6B,
        .unofficial = true,
        .implemented = true,
    },

    dcp_zp: Instruction = .{
        .name = "DCP",
        .mode = .zeropage,
        .op = 0xC7,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    dcp_zpx: Instruction = .{
        .name = "DCP",
        .mode = .zeropage_x,
        .op = 0xD7,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    dcp_abs: Instruction = .{
        .name = "DCP",
        .mode = .absolute,
        .op = 0xCF,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    dcp_absx: Instruction = .{
        .name = "DCP",
        .mode = .absolute_x,
        .op = 0xDF,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    dcp_absy: Instruction = .{
        .name = "DCP",
        .mode = .absolute_y,
        .op = 0xDB,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    dcp_indx: Instruction = .{
        .name = "DCP",
        .mode = .indirect_x,
        .op = 0xC3,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    dcp_indy: Instruction = .{
        .name = "DCP",
        .mode = .indirect_y,
        .op = 0xD3,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    isc_zp: Instruction = .{
        .name = "ISC",
        .mode = .zeropage,
        .op = 0xE7,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    isc_zpx: Instruction = .{
        .name = "ISC",
        .mode = .zeropage_x,
        .op = 0xF7,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    isc_abs: Instruction = .{
        .name = "ISC",
        .mode = .absolute,
        .op = 0xEF,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    isc_absx: Instruction = .{
        .name = "ISC",
        .mode = .absolute_x,
        .op = 0xFF,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    isc_absy: Instruction = .{
        .name = "ISC",
        .mode = .absolute_y,
        .op = 0xFB,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    isc_indx: Instruction = .{
        .name = "ISC",
        .mode = .indirect_x,
        .op = 0xE3,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    isc_indy: Instruction = .{
        .name = "ISC",
        .mode = .indirect_y,
        .op = 0xF3,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    las_absx: Instruction = .{
        .name = "LAS",
        .mode = .absolute_x,
        .op = 0xBB,
        .unofficial = true,
        .readmem = true,
    },

    lax_zp: Instruction = .{
        .name = "LAX",
        .mode = .zeropage,
        .op = 0xA7,
        .unofficial = true,
        .readmem = true,
        .implemented = true,
    },

    lax_zpy: Instruction = .{
        .name = "LAX",
        .mode = .zeropage_y,
        .op = 0xB7,
        .unofficial = true,
        .readmem = true,
        .implemented = true,
    },

    lax_abs: Instruction = .{
        .name = "LAX",
        .mode = .absolute,
        .op = 0xAF,
        .unofficial = true,
        .readmem = true,
        .implemented = true,
    },

    lax_absy: Instruction = .{
        .name = "LAX",
        .mode = .absolute_y,
        .op = 0xBF,
        .unofficial = true,
        .readmem = true,
    },

    lax_indx: Instruction = .{
        .name = "LAX",
        .mode = .indirect_x,
        .op = 0xA3,
        .unofficial = true,
        .readmem = true,
    },

    lax_indy: Instruction = .{
        .name = "LAX",
        .mode = .indirect_y,
        .op = 0xB3,
        .unofficial = true,
        .readmem = true,
    },

    lxa: Instruction = .{
        .name = "LXA",
        .mode = .immediate,
        .op = 0xAB,
        .unofficial = true,
        .unstable = true,
        .implemented = true,
    },

    rla_zp: Instruction = .{
        .name = "RLA",
        .mode = .zeropage,
        .op = 0x27,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    rla_zpx: Instruction = .{
        .name = "RLA",
        .mode = .zeropage_x,
        .op = 0x37,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    rla_abs: Instruction = .{
        .name = "RLA",
        .mode = .absolute,
        .op = 0x2F,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    rla_absx: Instruction = .{
        .name = "RLA",
        .mode = .absolute_x,
        .op = 0x3F,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    rla_absy: Instruction = .{
        .name = "RLA",
        .mode = .absolute_y,
        .op = 0x3B,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    rla_indx: Instruction = .{
        .name = "RLA",
        .mode = .indirect_x,
        .op = 0x23,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    rla_indy: Instruction = .{
        .name = "RLA",
        .mode = .indirect_y,
        .op = 0x33,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    // RRA

    rra_zp: Instruction = .{
        .name = "RRA",
        .mode = .zeropage,
        .op = 0x67,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    rra_zpx: Instruction = .{
        .name = "RRA",
        .mode = .zeropage_x,
        .op = 0x77,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    rra_abs: Instruction = .{
        .name = "RRA",
        .mode = .absolute,
        .op = 0x6F,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    rra_absx: Instruction = .{
        .name = "RRA",
        .mode = .absolute_x,
        .op = 0x7F,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    rra_absy: Instruction = .{
        .name = "RRA",
        .mode = .absolute_y,
        .op = 0x7B,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    rra_indx: Instruction = .{
        .name = "RRA",
        .mode = .indirect_x,
        .op = 0x63,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    rra_indy: Instruction = .{
        .name = "RRA",
        .mode = .indirect_y,
        .op = 0x73,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    // SAX

    sax_zp: Instruction = .{
        .name = "SAX",
        .mode = .zeropage,
        .op = 0x87,
        .unofficial = true,
        .writemem = true,
        .implemented = true,
    },

    sax_zpy: Instruction = .{
        .name = "SAX",
        .mode = .zeropage_y,
        .op = 0x97,
        .unofficial = true,
        .writemem = true,
        .implemented = true,
    },

    sax_abs: Instruction = .{
        .name = "SAX",
        .mode = .absolute,
        .op = 0x8F,
        .unofficial = true,
        .writemem = true,
    },

    sax_indx: Instruction = .{
        .name = "SAX",
        .mode = .indirect_x,
        .op = 0x83,
        .unofficial = true,
        .writemem = true,
    },

    sbx_imm: Instruction = .{
        .name = "SBX",
        .mode = .immediate,
        .op = 0xCB,
        .unofficial = true,
        .implemented = true,
    },

    sha_absy: Instruction = .{
        .name = "SHA",
        .mode = .absolute_y,
        .op = 0x9F,
        .unofficial = true,
        .unstable = true,
        .writemem = true,
    },

    sha_indy: Instruction = .{
        .name = "SHA",
        .mode = .indirect_y,
        .op = 0x93,
        .unofficial = true,
        .unstable = true,
        .writemem = true,
    },

    shx_absy: Instruction = .{
        .name = "SHX",
        .mode = .absolute_y,
        .op = 0x9E,
        .unofficial = true,
        .unstable = true,
        .writemem = true,
    },

    shy_absx: Instruction = .{
        .name = "SHY",
        .mode = .absolute_x,
        .op = 0x9C,
        .unofficial = true,
        .unstable = true,
        .writemem = true,
    },

    slo_zp: Instruction = .{
        .name = "SLO",
        .mode = .zeropage,
        .op = 0x07,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    slo_zpx: Instruction = .{
        .name = "SLO",
        .mode = .zeropage_x,
        .op = 0x17,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    slo_abs: Instruction = .{
        .name = "SLO",
        .mode = .absolute,
        .op = 0x0F,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    slo_absx: Instruction = .{
        .name = "SLO",
        .mode = .absolute_x,
        .op = 0x1F,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    slo_absy: Instruction = .{
        .name = "SLO",
        .mode = .absolute_y,
        .op = 0x1B,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    slo_indx: Instruction = .{
        .name = "SLO",
        .mode = .indirect_x,
        .op = 0x03,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    slo_indy: Instruction = .{
        .name = "SLO",
        .mode = .indirect_y,
        .op = 0x13,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    sre_zp: Instruction = .{
        .name = "SRE",
        .mode = .zeropage,
        .op = 0x47,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
        .implemented = true,
    },

    sre_zpx: Instruction = .{
        .name = "SRE",
        .mode = .zeropage_x,
        .op = 0x57,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    sre_abs: Instruction = .{
        .name = "SRE",
        .mode = .absolute,
        .op = 0x4F,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    sre_absx: Instruction = .{
        .name = "SRE",
        .mode = .absolute_x,
        .op = 0x5F,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    sre_absy: Instruction = .{
        .name = "SRE",
        .mode = .absolute_y,
        .op = 0x5B,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    sre_indx: Instruction = .{
        .name = "SRE",
        .mode = .indirect_x,
        .op = 0x43,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    sre_indy: Instruction = .{
        .name = "SRE",
        .mode = .indirect_y,
        .op = 0x53,
        .unofficial = true,
        .readmem = true,
        .writemem = true,
    },

    tas_absy: Instruction = .{
        .name = "TAS",
        .mode = .absolute_y,
        .op = 0x9B,
        .unofficial = true,
        .unstable = true,
        .writemem = true,
    },

    sbc_imm_2: Instruction = .{
        .name = "SBC",
        .mode = .immediate,
        .op = 0xEB,
        .unofficial = true,
        .implemented = true,
    },

    nop_2: Instruction = .{
        .name = "NOP",
        .mode = .implied,
        .op = 0x1A,
        .unofficial = true,
        .nop = true,
    },

    nop_3: Instruction = .{
        .name = "NOP",
        .mode = .implied,
        .op = 0x3A,
        .unofficial = true,
        .nop = true,
    },

    nop_4: Instruction = .{
        .name = "NOP",
        .mode = .implied,
        .op = 0x5A,
        .unofficial = true,
        .nop = true,
    },

    nop_5: Instruction = .{
        .name = "NOP",
        .mode = .implied,
        .op = 0x7A,
        .unofficial = true,
        .nop = true,
    },

    nop_6: Instruction = .{
        .name = "NOP",
        .mode = .implied,
        .op = 0xDA,
        .unofficial = true,
        .nop = true,
    },

    nop_7: Instruction = .{
        .name = "NOP",
        .mode = .implied,
        .op = 0xFA,
        .unofficial = true,
        .nop = true,
    },

    nop_imm: Instruction = .{
        .name = "NOP",
        .mode = .immediate,
        .op = 0x80,
        .unofficial = true,
        .nop = true,
    },

    nop_imm_2: Instruction = .{
        .name = "NOP",
        .mode = .immediate,
        .op = 0x82,
        .unofficial = true,
        .nop = true,
    },

    nop_imm_3: Instruction = .{
        .name = "NOP",
        .mode = .immediate,
        .op = 0x89,
        .unofficial = true,
        .nop = true,
    },

    nop_imm_4: Instruction = .{
        .name = "NOP",
        .mode = .immediate,
        .op = 0xC2,
        .unofficial = true,
        .nop = true,
    },

    nop_imm_5: Instruction = .{
        .name = "NOP",
        .mode = .immediate,
        .op = 0xE2,
        .unofficial = true,
        .nop = true,
    },

    nop_zp: Instruction = .{
        .name = "NOP",
        .mode = .zeropage,
        .op = 0x04,
        .unofficial = true,
        .nop = true,
    },

    nop_zp_2: Instruction = .{
        .name = "NOP",
        .mode = .zeropage,
        .op = 0x44,
        .unofficial = true,
        .nop = true,
    },

    nop_zp_3: Instruction = .{
        .name = "NOP",
        .mode = .zeropage,
        .op = 0x64,
        .unofficial = true,
        .nop = true,
    },

    nop_zpx: Instruction = .{
        .name = "NOP",
        .mode = .zeropage_x,
        .op = 0x14,
        .unofficial = true,
        .nop = true,
    },

    nop_zpx_2: Instruction = .{
        .name = "NOP",
        .mode = .zeropage_x,
        .op = 0x34,
        .unofficial = true,
        .nop = true,
    },

    nop_zpx_3: Instruction = .{
        .name = "NOP",
        .mode = .zeropage_x,
        .op = 0x54,
        .unofficial = true,
        .nop = true,
    },

    nop_zpx_4: Instruction = .{
        .name = "NOP",
        .mode = .zeropage_x,
        .op = 0x74,
        .unofficial = true,
        .nop = true,
    },

    nop_zpx_5: Instruction = .{
        .name = "NOP",
        .mode = .zeropage_x,
        .op = 0xD4,
        .unofficial = true,
        .nop = true,
    },

    nop_zpx_6: Instruction = .{
        .name = "NOP",
        .mode = .zeropage_x,
        .op = 0xF4,
        .unofficial = true,
        .nop = true,
    },

    nop_abs: Instruction = .{
        .name = "NOP",
        .mode = .absolute,
        .op = 0x0C,
        .unofficial = true,
        .nop = true,
    },

    nop_absx: Instruction = .{
        .name = "NOP",
        .mode = .absolute_x,
        .op = 0x1C,
        .unofficial = true,
        .nop = true,
    },

    nop_absx_2: Instruction = .{
        .name = "NOP",
        .mode = .absolute_x,
        .op = 0x3C,
        .unofficial = true,
        .nop = true,
    },

    nop_absx_3: Instruction = .{
        .name = "NOP",
        .mode = .absolute_x,
        .op = 0x5C,
        .unofficial = true,
        .nop = true,
    },

    nop_absx_4: Instruction = .{
        .name = "NOP",
        .mode = .absolute_x,
        .op = 0x7C,
        .unofficial = true,
        .nop = true,
    },

    nop_absx_5: Instruction = .{
        .name = "NOP",
        .mode = .absolute_x,
        .op = 0xDC,
        .unofficial = true,
        .nop = true,
    },

    nop_absx_6: Instruction = .{
        .name = "NOP",
        .mode = .absolute_x,
        .op = 0xFC,
        .unofficial = true,
        .nop = true,
    },

    jam: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0x02,
        .unofficial = true,
        .jam = true,
    },

    jam_2: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0x12,
        .unofficial = true,
        .jam = true,
    },

    jam_3: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0x22,
        .unofficial = true,
        .jam = true,
    },

    jam_4: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0x32,
        .unofficial = true,
        .jam = true,
    },

    jam_5: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0x42,
        .unofficial = true,
        .jam = true,
    },

    jam_6: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0x52,
        .unofficial = true,
        .jam = true,
    },

    jam_7: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0x62,
        .unofficial = true,
        .jam = true,
    },

    jam_8: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0x72,
        .unofficial = true,
        .jam = true,
    },

    jam_9: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0x92,
        .unofficial = true,
        .jam = true,
    },

    jam_10: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0xB2,
        .unofficial = true,
        .jam = true,
    },

    jam_11: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0xD2,
        .unofficial = true,
        .jam = true,
    },

    jam_12: Instruction = .{
        .name = "JAM",
        .mode = .implied,
        .op = 0xF2,
        .unofficial = true,
        .jam = true,
    },
} = .{};

pub const instructionmap = blk: {
    var ops = [_]Instruction{.{ .name = "", .mode = .accumulator, .op = 0 }} ** 256;
    for (@typeInfo(@TypeOf(instructions)).@"struct".fields) |field| {
        const value = field.defaultValue().?;
        if (ops[value.op].op != 0) @compileError("Multiple instructions with same op");
        ops[value.op] = value;
    }
    for (ops[1..]) |op| if (op.op == 0) @compileError("Unassigned operation");

    break :blk ops;
};
