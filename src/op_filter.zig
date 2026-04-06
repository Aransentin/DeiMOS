const std = @import("std");
const config = @import("config.zig");
const instructions = @import("instructions.zig");

pub fn run(range: []const u8) bool {
    if (range.len < 2) return false;

    const insmap = instructions.instructionmap;
    const ins = instructions.instructions;

    var op_n: usize = 0;
    var op_mem: [config.max_length]u8 = undefined;

    var i: usize = 0;
    while (i < range.len) {
        op_mem[op_n] = range[i];
        op_n += 1;
        i += insmap[range[i]].size();
    }

    const ops = op_mem[0..op_n];
    if (ops.len < 2) return false;

    const l2o = ops[ops.len - 2 ..];

    // Idempotent ops
    const idemp = [_]u8{ ins.tax.op, ins.txa.op, ins.tay.op, ins.tya.op, ins.tsx.op, ins.txs.op, ins.clc.op, ins.clv.op, ins.sec.op };
    for (idemp) |op| {
        if (l2o[0] == op and l2o[1] == op) return true;
    }

    // loading things into the same register multiple times
    const load_a = [_]u8{ ins.lda_imm.op, ins.lda_zp.op, ins.txa.op, ins.tya.op };
    for (load_a) |op0| {
        if (l2o[0] == op0) {
            for (load_a) |op1| if (l2o[1] == op1) return true;
            break;
        }
    }

    const load_x = [_]u8{ ins.ldx_imm.op, ins.ldx_zp.op, ins.tax.op };
    for (load_x) |op0| {
        if (l2o[0] == op0) {
            for (load_x) |op1| if (l2o[1] == op1) return true;
            break;
        }
    }

    const load_y = [_]u8{ ins.ldy_imm.op, ins.ldy_zp.op, ins.tay.op };
    for (load_y) |op0| {
        if (l2o[0] == op0) {
            for (load_y) |op1| if (l2o[1] == op1) return true;
            break;
        }
    }

    return false;
}
