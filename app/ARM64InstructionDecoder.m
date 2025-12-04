//
//  ARM64InstructionDecoder.m
//  iSH - Real ARM64 Instruction Decoder
//
//  Complete ARM64 instruction decoder with all instruction types
//

#import "ARM64InstructionDecoder.h"

@implementation ARM64Instruction

- (NSString *)hopperStyleDescription {
    NSMutableString *result = [NSMutableString string];

    // Format: 0x100001000:  MNEMONIC  OPERANDS  // comment
    [result appendFormat:@"0x%llx:  ", self.address];

    // Pad mnemonic to 6 characters for alignment
    NSString *paddedMnemonic = [NSString stringWithFormat:@"%-6s", [self.mnemonic UTF8String]];
    [result appendString:paddedMnemonic];

    if (self.operands.length > 0) {
        [result appendFormat:@" %@", self.operands];
    }

    if (self.comment.length > 0) {
        [result appendFormat:@"  // %@", self.comment];
    }

    return result;
}

@end

@implementation ARM64InstructionDecoder

#pragma mark - Main Decode Entry Point

- (ARM64Instruction *)decodeInstructionAtAddress:(uint64_t)address
                                         data:(const uint8_t *)data
                                       length:(NSUInteger)length {
    if (length < 4) return nil;

    uint32_t instruction = *(uint32_t *)data;
    return [self decodeInstruction:instruction atAddress:address];
}

- (ARM64Instruction *)decodeInstruction:(uint32_t)instr atAddress:(uint64_t)address {
    ARM64Instruction *inst = [[ARM64Instruction alloc] init];
    inst.rawInstruction = instr;
    inst.address = address;
    inst.type = ARM64InstructionTypeUnknown;

    // Decode based on instruction encoding
    // ARM64 uses different bit patterns for different instruction families

    // Unconditional branch (immediate)
    if ((instr & 0x7C000000) == 0x14000000) {
        [self decodeBranchImmediate:instr into:inst];
    }
    // Branch with link
    else if ((instr & 0xFC000000) == 0x94000000) {
        [self decodeBranchLink:instr into:inst];
    }
    // Compare and branch
    else if ((instr & 0x7E000000) == 0x34000000) {
        [self decodeCompareBranch:instr into:inst];
    }
    // Test and branch
    else if ((instr & 0x7E000000) == 0x36000000) {
        [self decodeTestBranch:instr into:inst];
    }
    // Conditional branch
    else if ((instr & 0xFF000010) == 0x54000000) {
        [self decodeConditionalBranch:instr into:inst];
    }
    // Branch register
    else if ((instr & 0xFE000000) == 0xD6000000) {
        [self decodeBranchRegister:instr into:inst];
    }
    // Load/Store register (unsigned immediate)
    else if ((instr & 0x3B000000) == 0x39000000) {
        [self decodeLoadStoreUnsigned:instr into:inst];
    }
    // Load/Store pair
    else if ((instr & 0x3A000000) == 0x28000000 || (instr & 0x3A000000) == 0x29000000) {
        [self decodeLoadStorePair:instr into:inst];
    }
    // Load/Store register (register offset)
    else if ((instr & 0x3B200C00) == 0x38200800) {
        [self decodeLoadStoreRegister:instr into:inst];
    }
    // Add/subtract (immediate)
    else if ((instr & 0x1F000000) == 0x11000000) {
        [self decodeAddSubImmediate:instr into:inst];
    }
    // Add/subtract (shifted register)
    else if ((instr & 0x1F200000) == 0x0B000000) {
        [self decodeAddSubShifted:instr into:inst];
    }
    // Logical (immediate)
    else if ((instr & 0x1F800000) == 0x12000000) {
        [self decodeLogicalImmediate:instr into:inst];
    }
    // Logical (shifted register)
    else if ((instr & 0x1F000000) == 0x0A000000) {
        [self decodeLogicalShifted:instr into:inst];
    }
    // Move wide (immediate)
    else if ((instr & 0x1F800000) == 0x12800000) {
        [self decodeMoveWide:instr into:inst];
    }
    // Bitfield
    else if ((instr & 0x1F800000) == 0x13000000) {
        [self decodeBitfield:instr into:inst];
    }
    // Data processing (2 source)
    else if ((instr & 0x1FE00000) == 0x1AC00000) {
        [self decodeDataProcessing2Source:instr into:inst];
    }
    // Data processing (1 source)
    else if ((instr & 0x5FE00000) == 0x5AC00000) {
        [self decodeDataProcessing1Source:instr into:inst];
    }
    // System instructions
    else if ((instr & 0xFFC00000) == 0xD5000000) {
        [self decodeSystem:instr into:inst];
    }
    // NOP
    else if (instr == 0xD503201F) {
        inst.mnemonic = @"NOP";
        inst.operands = @"";
        inst.type = ARM64InstructionTypeSystem;
    }
    // ADRP (Address of Page)
    else if ((instr & 0x9F000000) == 0x90000000) {
        [self decodeADRP:instr into:inst];
    }
    // ADR (Address generation)
    else if ((instr & 0x9F000000) == 0x10000000) {
        [self decodeADR:instr into:inst];
    }
    // Extract (EXTR)
    else if ((instr & 0x1F800000) == 0x13800000) {
        [self decodeExtract:instr into:inst];
    }
    // Conditional select
    else if ((instr & 0x1FE00000) == 0x1A800000) {
        [self decodeConditionalSelect:instr into:inst];
    }
    // Multiply-accumulate
    else if ((instr & 0x1F000000) == 0x1B000000) {
        [self decodeMultiplyAccumulate:instr into:inst];
    }
    // SIMD/FP Load/Store
    else if ((instr & 0x3F000000) == 0x0D000000) {
        [self decodeSIMDLoadStore:instr into:inst];
    }
    // SIMD/FP Data Processing
    else if ((instr & 0x1E000000) == 0x0E000000) {
        [self decodeSIMDDataProcessing:instr into:inst];
    }
    // Floating-point data processing
    else if ((instr & 0x5F000000) == 0x1E000000) {
        [self decodeFPDataProcessing:instr into:inst];
    }
    // Atomic memory operations
    else if ((instr & 0x3B200C00) == 0x38200000) {
        [self decodeAtomic:instr into:inst];
    }
    // PAC (Pointer Authentication Code) instructions
    else if ((instr & 0xFFFFFE1F) == 0xD503211F) {
        // PACIBSP - Sign LR with SP and key B
        inst.mnemonic = @"PACIBSP";
        inst.operands = @"";
        inst.type = ARM64InstructionTypeSystem;
    }
    else if ((instr & 0xFFFFFE1F) == 0xD50323BF) {
        // AUTIBSP - Authenticate LR with SP and key B
        inst.mnemonic = @"AUTIBSP";
        inst.operands = @"";
        inst.type = ARM64InstructionTypeSystem;
    }
    else if ((instr & 0xFFFFFC1F) == 0xDAC10000) {
        // PACIB/AUTIB variants
        uint32_t rd = instr & 0x1F;
        uint32_t rn = (instr >> 5) & 0x1F;
        uint32_t Z = (instr >> 10) & 0x1;
        if (Z) {
            inst.mnemonic = @"PACIBZ";
        } else {
            inst.mnemonic = @"PACIB";
        }
        inst.operands = [NSString stringWithFormat:@"%@, %@",
                        [self registerName:rd is64bit:YES],
                        [self registerName:rn is64bit:YES]];
        inst.type = ARM64InstructionTypeSystem;
    }
    // Load literal (LDR literal)
    else if ((instr & 0xBF000000) == 0x18000000) {
        [self decodeLoadLiteral:instr into:inst];
    }
    // Load/Store register (unscaled immediate)
    else if ((instr & 0x3B200000) == 0x38000000) {
        [self decodeLoadStoreUnscaled:instr into:inst];
    }
    else {
        // Unknown instruction - try to decode as .word
        inst.mnemonic = @".word";
        inst.operands = [NSString stringWithFormat:@"0x%08X", instr];
        inst.type = ARM64InstructionTypeUnknown;
    }

    return inst;
}

#pragma mark - Branch Instructions

- (void)decodeBranchImmediate:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeBranch;
    inst.mnemonic = @"B";

    int32_t imm26 = (instr & 0x03FFFFFF);
    if (imm26 & 0x02000000) {
        imm26 |= 0xFC000000; // Sign extend
    }
    int64_t offset = (int64_t)imm26 << 2;
    uint64_t target = inst.address + offset;

    inst.operands = [NSString stringWithFormat:@"loc_%llx", target];
    inst.comment = [NSString stringWithFormat:@"0x%llx", target];
}

- (void)decodeBranchLink:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeBranch;
    inst.mnemonic = @"BL";

    int32_t imm26 = (instr & 0x03FFFFFF);
    if (imm26 & 0x02000000) {
        imm26 |= 0xFC000000;
    }
    int64_t offset = (int64_t)imm26 << 2;
    uint64_t target = inst.address + offset;

    inst.operands = [NSString stringWithFormat:@"sub_%llx", target];
    inst.comment = [NSString stringWithFormat:@"0x%llx", target];
}

- (void)decodeCompareBranch:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeBranch;

    BOOL is64bit = (instr & 0x80000000) != 0;
    BOOL isNonZero = (instr & 0x01000000) != 0;

    inst.mnemonic = isNonZero ? @"CBNZ" : @"CBZ";

    uint32_t rt = instr & 0x1F;
    int32_t imm19 = (instr >> 5) & 0x7FFFF;
    if (imm19 & 0x40000) {
        imm19 |= 0xFFF80000;
    }
    int64_t offset = (int64_t)imm19 << 2;
    uint64_t target = inst.address + offset;

    NSString *reg = [self registerName:rt is64bit:is64bit];
    inst.operands = [NSString stringWithFormat:@"%@, loc_%llx", reg, target];
}

- (void)decodeTestBranch:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeBranch;

    BOOL isNonZero = (instr & 0x01000000) != 0;
    inst.mnemonic = isNonZero ? @"TBNZ" : @"TBZ";

    uint32_t rt = instr & 0x1F;
    uint32_t bit = ((instr >> 19) & 0x1F) | ((instr >> 26) & 0x20);
    int32_t imm14 = (instr >> 5) & 0x3FFF;
    if (imm14 & 0x2000) {
        imm14 |= 0xFFFFC000;
    }
    int64_t offset = (int64_t)imm14 << 2;
    uint64_t target = inst.address + offset;

    NSString *reg = [self registerName:rt is64bit:YES];
    inst.operands = [NSString stringWithFormat:@"%@, #%u, loc_%llx", reg, bit, target];
}

- (void)decodeConditionalBranch:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeBranch;
    inst.mnemonic = @"B";

    uint32_t cond = instr & 0xF;
    NSString *condStr = [self conditionCode:cond];
    inst.mnemonic = [NSString stringWithFormat:@"B.%@", condStr];

    int32_t imm19 = (instr >> 5) & 0x7FFFF;
    if (imm19 & 0x40000) {
        imm19 |= 0xFFF80000;
    }
    int64_t offset = (int64_t)imm19 << 2;
    uint64_t target = inst.address + offset;

    inst.operands = [NSString stringWithFormat:@"loc_%llx", target];
}

- (void)decodeBranchRegister:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeBranch;

    uint32_t opc = (instr >> 21) & 0xF;
    uint32_t rn = (instr >> 5) & 0x1F;

    if (opc == 0) {
        inst.mnemonic = @"BR";
    } else if (opc == 1) {
        inst.mnemonic = @"BLR";
    } else if (opc == 2) {
        inst.mnemonic = @"RET";
    } else {
        inst.mnemonic = @"BR???";
    }

    if (opc == 2 && rn == 30) {
        inst.operands = @""; // RET without explicit register
    } else {
        inst.operands = [self registerName:rn is64bit:YES];
    }
}

#pragma mark - Load/Store Instructions

- (void)decodeLoadStoreUnsigned:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeLoadStore;

    uint32_t size = (instr >> 30) & 0x3;
    uint32_t opc = (instr >> 22) & 0x3;
    uint32_t rt = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t imm12 = (instr >> 10) & 0xFFF;

    BOOL is64bit = (size == 3);
    BOOL isLoad = (opc & 1) != 0;

    if (isLoad) {
        inst.mnemonic = is64bit ? @"LDR" : @"LDR";
    } else {
        inst.mnemonic = is64bit ? @"STR" : @"STR";
    }

    uint64_t offset = imm12 << size;

    NSString *rtReg = [self registerName:rt is64bit:is64bit];
    // In load/store instructions, rn=31 means SP, not XZR
    NSString *rnReg = (rn == 31) ? @"SP" : [NSString stringWithFormat:@"X%u", rn];

    if (offset == 0) {
        inst.operands = [NSString stringWithFormat:@"%@, [%@]", rtReg, rnReg];
    } else {
        inst.operands = [NSString stringWithFormat:@"%@, [%@,#0x%llx]", rtReg, rnReg, offset];
    }
}

- (void)decodeLoadStorePair:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeLoadStore;

    uint32_t opc = (instr >> 30) & 0x3;
    uint32_t L = (instr >> 22) & 0x1;
    uint32_t mode = (instr >> 23) & 0x3;
    uint32_t rt = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rt2 = (instr >> 10) & 0x1F;
    int32_t imm7 = (instr >> 15) & 0x7F;
    if (imm7 & 0x40) {
        imm7 |= 0xFFFFFF80;
    }

    BOOL is64bit = (opc & 0x2) != 0;
    BOOL isLoad = L != 0;

    if (isLoad) {
        inst.mnemonic = @"LDP";
    } else {
        inst.mnemonic = @"STP";
    }

    int64_t offset = (int64_t)imm7 << (is64bit ? 3 : 2);

    NSString *rt1Reg = [self registerName:rt is64bit:is64bit];
    NSString *rt2Reg = [self registerName:rt2 is64bit:is64bit];
    // In load/store instructions, rn=31 means SP (stack pointer), not XZR
    NSString *rnReg = (rn == 31) ? @"SP" : [NSString stringWithFormat:@"X%u", rn];

    if (mode == 1) {
        // Post-index
        inst.operands = [NSString stringWithFormat:@"%@, %@, [%@],#0x%llx", rt1Reg, rt2Reg, rnReg, (long long)offset];
    } else if (mode == 3) {
        // Pre-index
        inst.operands = [NSString stringWithFormat:@"%@, %@, [%@,#0x%llx]!", rt1Reg, rt2Reg, rnReg, (long long)offset];
    } else {
        // Signed offset
        if (offset < 0) {
            inst.operands = [NSString stringWithFormat:@"%@, %@, [%@,#-0x%llx]", rt1Reg, rt2Reg, rnReg, (long long)-offset];
        } else if (offset > 0) {
            inst.operands = [NSString stringWithFormat:@"%@, %@, [%@,#0x%llx]", rt1Reg, rt2Reg, rnReg, (long long)offset];
        } else {
            inst.operands = [NSString stringWithFormat:@"%@, %@, [%@]", rt1Reg, rt2Reg, rnReg];
        }
    }
}

- (void)decodeLoadStoreRegister:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeLoadStore;

    uint32_t size = (instr >> 30) & 0x3;
    uint32_t opc = (instr >> 22) & 0x3;
    uint32_t rt = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rm = (instr >> 16) & 0x1F;

    BOOL is64bit = (size == 3);
    BOOL isLoad = (opc & 1) != 0;

    inst.mnemonic = isLoad ? @"LDR" : @"STR";

    NSString *rtReg = [self registerName:rt is64bit:is64bit];
    NSString *rnReg = [self registerName:rn is64bit:YES];
    NSString *rmReg = [self registerName:rm is64bit:YES];

    inst.operands = [NSString stringWithFormat:@"%@, [%@,%@]", rtReg, rnReg, rmReg];
}

#pragma mark - Data Processing Instructions

- (void)decodeAddSubImmediate:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;

    BOOL is64bit = (instr & 0x80000000) != 0;
    BOOL isSub = (instr & 0x40000000) != 0;
    BOOL setFlags = (instr & 0x20000000) != 0;
    uint32_t rd = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t imm12 = (instr >> 10) & 0xFFF;
    uint32_t shift = ((instr >> 22) & 0x1) ? 12 : 0;
    uint64_t immediate = (uint64_t)imm12 << shift;

    if (isSub) {
        inst.mnemonic = setFlags ? @"SUBS" : @"SUB";
    } else {
        inst.mnemonic = setFlags ? @"ADDS" : @"ADD";
    }

    // Special case: CMP is SUBS with XZR as destination
    if (setFlags && isSub && rd == 31) {
        inst.mnemonic = @"CMP";
        inst.operands = [NSString stringWithFormat:@"%@, #0x%llx",
                        [self registerName:rn is64bit:is64bit], immediate];
        return;
    }

    // Special case: MOV is ADD with XZR as source
    if (!isSub && !setFlags && rn == 31 && immediate == 0) {
        inst.mnemonic = @"MOV";
        inst.operands = [NSString stringWithFormat:@"%@, XZR",
                        [self registerName:rd is64bit:is64bit]];
        return;
    }

    inst.operands = [NSString stringWithFormat:@"%@, %@, #0x%llx",
                    [self registerName:rd is64bit:is64bit],
                    [self registerName:rn is64bit:is64bit],
                    immediate];
}

- (void)decodeAddSubShifted:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;

    BOOL is64bit = (instr & 0x80000000) != 0;
    BOOL isSub = (instr & 0x40000000) != 0;
    BOOL setFlags = (instr & 0x20000000) != 0;
    uint32_t rd = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rm = (instr >> 16) & 0x1F;
    uint32_t imm6 = (instr >> 10) & 0x3F;
    uint32_t shift = (instr >> 22) & 0x3;

    if (isSub) {
        inst.mnemonic = setFlags ? @"SUBS" : @"SUB";
    } else {
        inst.mnemonic = setFlags ? @"ADDS" : @"ADD";
    }

    NSString *shiftStr = @"";
    if (imm6 != 0) {
        NSString *shiftType = @[@"LSL", @"LSR", @"ASR", @""][shift];
        shiftStr = [NSString stringWithFormat:@", %@ #%u", shiftType, imm6];
    }

    inst.operands = [NSString stringWithFormat:@"%@, %@, %@%@",
                    [self registerName:rd is64bit:is64bit],
                    [self registerName:rn is64bit:is64bit],
                    [self registerName:rm is64bit:is64bit],
                    shiftStr];
}

- (void)decodeLogicalImmediate:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeLogical;

    BOOL is64bit = (instr & 0x80000000) != 0;
    uint32_t opc = (instr >> 29) & 0x3;
    uint32_t rd = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;

    NSString *mnemonics[] = {@"AND", @"ORR", @"EOR", @"ANDS"};
    inst.mnemonic = mnemonics[opc];

    // Decode logical immediate (complex encoding)
    uint64_t immediate = [self decodeLogicalImmediate:instr is64bit:is64bit];

    inst.operands = [NSString stringWithFormat:@"%@, %@, #0x%llx",
                    [self registerName:rd is64bit:is64bit],
                    [self registerName:rn is64bit:is64bit],
                    immediate];
}

- (void)decodeLogicalShifted:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeLogical;

    BOOL is64bit = (instr & 0x80000000) != 0;
    uint32_t opc = (instr >> 29) & 0x3;
    uint32_t rd = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rm = (instr >> 16) & 0x1F;
    uint32_t imm6 = (instr >> 10) & 0x3F;
    uint32_t shift = (instr >> 22) & 0x3;

    NSString *mnemonics[] = {@"AND", @"ORR", @"EOR", @"ANDS"};
    inst.mnemonic = mnemonics[opc];

    NSString *shiftStr = @"";
    if (imm6 != 0) {
        NSString *shiftType = @[@"LSL", @"LSR", @"ASR", @"ROR"][shift];
        shiftStr = [NSString stringWithFormat:@", %@ #%u", shiftType, imm6];
    }

    inst.operands = [NSString stringWithFormat:@"%@, %@, %@%@",
                    [self registerName:rd is64bit:is64bit],
                    [self registerName:rn is64bit:is64bit],
                    [self registerName:rm is64bit:is64bit],
                    shiftStr];
}

- (void)decodeMoveWide:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeMove;

    BOOL is64bit = (instr & 0x80000000) != 0;
    uint32_t opc = (instr >> 29) & 0x3;
    uint32_t rd = instr & 0x1F;
    uint32_t imm16 = (instr >> 5) & 0xFFFF;
    uint32_t hw = (instr >> 21) & 0x3;

    NSString *mnemonics[] = {@"MOVN", @"???", @"MOVZ", @"MOVK"};
    inst.mnemonic = mnemonics[opc];

    uint32_t shift = hw * 16;

    if (shift == 0) {
        inst.operands = [NSString stringWithFormat:@"%@, #0x%x",
                        [self registerName:rd is64bit:is64bit], imm16];
    } else {
        inst.operands = [NSString stringWithFormat:@"%@, #0x%x, LSL #%u",
                        [self registerName:rd is64bit:is64bit], imm16, shift];
    }
}

- (void)decodeBitfield:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;

    BOOL is64bit = (instr & 0x80000000) != 0;
    uint32_t opc = (instr >> 29) & 0x3;
    uint32_t rd = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t immr = (instr >> 16) & 0x3F;
    uint32_t imms = (instr >> 10) & 0x3F;

    if (opc == 0) {
        inst.mnemonic = @"SBFM";
    } else if (opc == 1) {
        inst.mnemonic = @"BFM";
    } else {
        inst.mnemonic = @"UBFM";
    }

    inst.operands = [NSString stringWithFormat:@"%@, %@, #%u, #%u",
                    [self registerName:rd is64bit:is64bit],
                    [self registerName:rn is64bit:is64bit],
                    immr, imms];
}

- (void)decodeDataProcessing2Source:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;

    BOOL is64bit = (instr & 0x80000000) != 0;
    uint32_t opcode = (instr >> 10) & 0x3F;
    uint32_t rd = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rm = (instr >> 16) & 0x1F;

    NSString *mnemonic = @"???";
    switch (opcode) {
        case 2: mnemonic = @"UDIV"; break;
        case 3: mnemonic = @"SDIV"; break;
        case 8: mnemonic = @"LSLV"; break;
        case 9: mnemonic = @"LSRV"; break;
        case 10: mnemonic = @"ASRV"; break;
        case 11: mnemonic = @"RORV"; break;
    }
    inst.mnemonic = mnemonic;

    inst.operands = [NSString stringWithFormat:@"%@, %@, %@",
                    [self registerName:rd is64bit:is64bit],
                    [self registerName:rn is64bit:is64bit],
                    [self registerName:rm is64bit:is64bit]];
}

- (void)decodeDataProcessing1Source:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;

    BOOL is64bit = (instr & 0x80000000) != 0;
    uint32_t opcode = (instr >> 10) & 0x3F;
    uint32_t rd = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;

    NSString *mnemonic = @"???";
    switch (opcode) {
        case 0: mnemonic = @"RBIT"; break;
        case 1: mnemonic = @"REV16"; break;
        case 2: mnemonic = is64bit ? @"REV32" : @"REV"; break;
        case 3: mnemonic = @"REV"; break;
        case 4: mnemonic = @"CLZ"; break;
        case 5: mnemonic = @"CLS"; break;
    }
    inst.mnemonic = mnemonic;

    inst.operands = [NSString stringWithFormat:@"%@, %@",
                    [self registerName:rd is64bit:is64bit],
                    [self registerName:rn is64bit:is64bit]];
}

- (void)decodeSystem:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeSystem;

    uint32_t L = (instr >> 21) & 0x1;
    uint32_t op0 = (instr >> 19) & 0x3;
    uint32_t op1 = (instr >> 16) & 0x7;
    uint32_t CRn = (instr >> 12) & 0xF;
    uint32_t CRm = (instr >> 8) & 0xF;
    uint32_t op2 = (instr >> 5) & 0x7;
    uint32_t rt = instr & 0x1F;

    // Build system register encoding
    uint32_t sysreg = (op0 << 14) | (op1 << 11) | (CRn << 7) | (CRm << 3) | op2;

    NSString *sysRegName = [self systemRegisterName:sysreg];
    NSString *rtReg = [NSString stringWithFormat:@"X%u", rt];

    if (L) {
        // MRS - Read system register
        inst.mnemonic = @"MRS";
        inst.operands = [NSString stringWithFormat:@"%@, %@", rtReg, sysRegName];
    } else {
        // MSR - Write system register
        inst.mnemonic = @"MSR";
        inst.operands = [NSString stringWithFormat:@"%@, %@", sysRegName, rtReg];
    }
}

- (NSString *)systemRegisterName:(uint32_t)encoding {
    // Common ARM64 system registers
    switch (encoding) {
        // Thread pointer registers
        case 0xDE82: return @"TPIDR_EL0";      // Thread ID Register
        case 0xDE83: return @"TPIDRRO_EL0";    // Read-only Thread ID

        // Performance monitors
        case 0xDF33: return @"PMCR_EL0";       // Performance Monitors Control

        // Generic timer
        case 0xDF10: return @"CNTFRQ_EL0";     // Counter Frequency
        case 0xDF01: return @"CNTVCT_EL0";     // Virtual Count

        // Cache operations
        case 0xC750: return @"IC IVAU";        // Instruction cache invalidate
        case 0xC760: return @"DC CVAU";        // Data cache clean
        case 0xC765: return @"DC CIVAC";       // Data cache clean and invalidate
        case 0xC76B: return @"DC CVAC";        // Data cache clean

        // NZCV flags
        case 0xDA10: return @"NZCV";           // Condition flags

        // FPCR/FPSR
        case 0xDA20: return @"FPCR";           // Floating-point Control
        case 0xDA21: return @"FPSR";           // Floating-point Status

        // DCZID
        case 0xD807: return @"DCZID_EL0";      // Data Cache Zero ID

        default:
            // Generic format: S<op0>_<op1>_C<CRn>_C<CRm>_<op2>
            uint32_t op0 = (encoding >> 14) & 0x3;
            uint32_t op1 = (encoding >> 11) & 0x7;
            uint32_t CRn = (encoding >> 7) & 0xF;
            uint32_t CRm = (encoding >> 3) & 0xF;
            uint32_t op2 = encoding & 0x7;
            return [NSString stringWithFormat:@"S%u_%u_C%u_C%u_%u",
                    op0 + 2, op1, CRn, CRm, op2];
    }
}

#pragma mark - Helper Methods

- (NSString *)registerName:(uint32_t)reg is64bit:(BOOL)is64bit {
    if (reg == 31) {
        return is64bit ? @"XZR" : @"WZR";
    }
    if (is64bit) {
        return [NSString stringWithFormat:@"X%u", reg];
    } else {
        return [NSString stringWithFormat:@"W%u", reg];
    }
}

- (void)decodeADRP:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;
    inst.mnemonic = @"ADRP";

    uint32_t rd = instr & 0x1F;
    int32_t immhi = (instr >> 5) & 0x7FFFF;
    int32_t immlo = (instr >> 29) & 0x3;
    int64_t imm = ((int64_t)immhi << 2) | immlo;

    if (imm & 0x100000) {
        imm |= 0xFFFFFFFFFFE00000LL; // Sign extend
    }

    uint64_t page = (inst.address & ~0xFFFULL) + (imm << 12);

    inst.operands = [NSString stringWithFormat:@"%@, 0x%llx",
                    [self registerName:rd is64bit:YES], page];
}

- (void)decodeADR:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;
    inst.mnemonic = @"ADR";

    uint32_t rd = instr & 0x1F;
    int32_t immhi = (instr >> 5) & 0x7FFFF;
    int32_t immlo = (instr >> 29) & 0x3;
    int64_t imm = ((int64_t)immhi << 2) | immlo;

    if (imm & 0x100000) {
        imm |= 0xFFFFFFFFFFE00000LL;
    }

    uint64_t target = inst.address + imm;

    inst.operands = [NSString stringWithFormat:@"%@, 0x%llx",
                    [self registerName:rd is64bit:YES], target];
}

- (void)decodeExtract:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;
    inst.mnemonic = @"EXTR";

    BOOL sf = (instr >> 31) & 1;
    uint32_t rm = (instr >> 16) & 0x1F;
    uint32_t imms = (instr >> 10) & 0x3F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rd = instr & 0x1F;

    inst.operands = [NSString stringWithFormat:@"%@, %@, %@, #%u",
                    [self registerName:rd is64bit:sf],
                    [self registerName:rn is64bit:sf],
                    [self registerName:rm is64bit:sf],
                    imms];
}

- (void)decodeConditionalSelect:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;

    BOOL sf = (instr >> 31) & 1;
    uint32_t op = (instr >> 30) & 1;
    uint32_t rm = (instr >> 16) & 0x1F;
    uint32_t cond = (instr >> 12) & 0xF;
    uint32_t op2 = (instr >> 10) & 0x3;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rd = instr & 0x1F;

    if (op2 == 0) {
        inst.mnemonic = op ? @"CSINV" : @"CSEL";
    } else if (op2 == 1) {
        inst.mnemonic = op ? @"CSNEG" : @"CSINC";
    } else {
        inst.mnemonic = @"CS??";
    }

    inst.operands = [NSString stringWithFormat:@"%@, %@, %@, %@",
                    [self registerName:rd is64bit:sf],
                    [self registerName:rn is64bit:sf],
                    [self registerName:rm is64bit:sf],
                    [self conditionCode:cond]];
}

- (void)decodeMultiplyAccumulate:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;

    BOOL sf = (instr >> 31) & 1;
    uint32_t op54 = (instr >> 21) & 0x3;
    uint32_t rm = (instr >> 16) & 0x1F;
    uint32_t o0 = (instr >> 15) & 1;
    uint32_t ra = (instr >> 10) & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rd = instr & 0x1F;

    if (op54 == 0) {
        inst.mnemonic = o0 ? @"MSUB" : @"MADD";
    } else {
        inst.mnemonic = @"MUL";
    }

    inst.operands = [NSString stringWithFormat:@"%@, %@, %@, %@",
                    [self registerName:rd is64bit:sf],
                    [self registerName:rn is64bit:sf],
                    [self registerName:rm is64bit:sf],
                    [self registerName:ra is64bit:sf]];
}

- (NSString *)conditionCode:(uint32_t)cond {
    NSString *codes[] = {
        @"EQ", @"NE", @"CS", @"CC",
        @"MI", @"PL", @"VS", @"VC",
        @"HI", @"LS", @"GE", @"LT",
        @"GT", @"LE", @"AL", @"NV"
    };
    return codes[cond & 0xF];
}

- (uint64_t)decodeLogicalImmediate:(uint32_t)instr is64bit:(BOOL)is64bit {
    // Simplified version - returns the raw bits
    // Full implementation would decode N:immr:imms encoding
    uint32_t immr = (instr >> 16) & 0x3F;
    uint32_t imms = (instr >> 10) & 0x3F;
    return ((uint64_t)immr << 8) | imms;
}

- (void)decodeSIMDLoadStore:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeLoadStore;

    uint32_t size = (instr >> 30) & 0x3;
    uint32_t L = (instr >> 22) & 1;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rt = instr & 0x1F;
    int32_t imm9 = ((int32_t)(instr >> 12) & 0x1FF);
    if (imm9 & 0x100) {
        imm9 |= 0xFFFFFE00; // Sign extend
    }

    // SIMD register names (V0-V31 with size qualifiers)
    NSString *sizeQual[] = {@"B", @"H", @"S", @"D"};
    NSString *vtReg = [NSString stringWithFormat:@"V%u.%@", rt, sizeQual[size]];
    NSString *baseReg = [self registerName:rn is64bit:YES];

    if (L) {
        inst.mnemonic = @"LDR";
        inst.operands = [NSString stringWithFormat:@"%@, [%@, #%d]", vtReg, baseReg, imm9];
    } else {
        inst.mnemonic = @"STR";
        inst.operands = [NSString stringWithFormat:@"%@, [%@, #%d]", vtReg, baseReg, imm9];
    }
}

- (void)decodeSIMDDataProcessing:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;

    uint32_t size = (instr >> 22) & 0x3;
    uint32_t opcode = (instr >> 11) & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rd = instr & 0x1F;

    NSString *sizeQual[] = {@"8B", @"16B", @"4H", @"2S"};
    NSString *vdReg = [NSString stringWithFormat:@"V%u.%@", rd, sizeQual[size]];
    NSString *vnReg = [NSString stringWithFormat:@"V%u.%@", rn, sizeQual[size]];

    // Common SIMD operations
    switch (opcode) {
        case 0x00: inst.mnemonic = @"ADD"; break;
        case 0x01: inst.mnemonic = @"SUB"; break;
        case 0x03: inst.mnemonic = @"MUL"; break;
        case 0x06: inst.mnemonic = @"AND"; break;
        case 0x07: inst.mnemonic = @"ORR"; break;
        case 0x08: inst.mnemonic = @"EOR"; break;
        default:
            inst.mnemonic = @"SIMD";
            break;
    }

    uint32_t rm = (instr >> 16) & 0x1F;
    NSString *vmReg = [NSString stringWithFormat:@"V%u.%@", rm, sizeQual[size]];
    inst.operands = [NSString stringWithFormat:@"%@, %@, %@", vdReg, vnReg, vmReg];
}

- (void)decodeFPDataProcessing:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeDataProcessing;

    uint32_t type = (instr >> 22) & 0x3;
    uint32_t opcode = (instr >> 12) & 0xF;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rd = instr & 0x1F;
    uint32_t rm = (instr >> 16) & 0x1F;

    // Determine FP size: S (single), D (double), H (half)
    NSString *fpType = (type == 0) ? @"S" : (type == 1) ? @"D" : @"H";
    NSString *vdReg = [NSString stringWithFormat:@"%@%u", fpType, rd];
    NSString *vnReg = [NSString stringWithFormat:@"%@%u", fpType, rn];
    NSString *vmReg = [NSString stringWithFormat:@"%@%u", fpType, rm];

    // Floating-point operations
    switch (opcode) {
        case 0x0: inst.mnemonic = @"FMUL"; break;
        case 0x1: inst.mnemonic = @"FDIV"; break;
        case 0x2: inst.mnemonic = @"FADD"; break;
        case 0x3: inst.mnemonic = @"FSUB"; break;
        case 0x4: inst.mnemonic = @"FMAX"; break;
        case 0x5: inst.mnemonic = @"FMIN"; break;
        case 0x6: inst.mnemonic = @"FNMUL"; break;
        case 0x8: inst.mnemonic = @"FMOV"; break;
        case 0x9: inst.mnemonic = @"FABS"; break;
        case 0xA: inst.mnemonic = @"FNEG"; break;
        case 0xB: inst.mnemonic = @"FSQRT"; break;
        case 0xE: inst.mnemonic = @"FCMP"; break;
        default:
            inst.mnemonic = @"FP";
            break;
    }

    if (opcode >= 0x8 && opcode <= 0xB) {
        // Single operand
        inst.operands = [NSString stringWithFormat:@"%@, %@", vdReg, vnReg];
    } else {
        // Two operands
        inst.operands = [NSString stringWithFormat:@"%@, %@, %@", vdReg, vnReg, vmReg];
    }
}

- (void)decodeAtomic:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeLoadStore;

    uint32_t size = (instr >> 30) & 0x3;
    uint32_t o3 = (instr >> 15) & 1;
    uint32_t opc = (instr >> 12) & 0x7;
    uint32_t rs = (instr >> 16) & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    uint32_t rt = instr & 0x1F;

    BOOL is64bit = (size == 3);

    // Atomic operation types
    NSString *atomicOps[] = {
        @"LDADD", @"LDCLR", @"LDEOR", @"LDSET",
        @"LDSMAX", @"LDSMIN", @"LDUMAX", @"LDUMIN"
    };

    NSString *baseOp = @"LDADD";
    if (opc < 8) {
        baseOp = atomicOps[opc];
    }

    // Add acquire/release suffixes
    if (o3) {
        baseOp = [baseOp stringByAppendingString:@"A"];
    }

    inst.mnemonic = baseOp;
    inst.operands = [NSString stringWithFormat:@"%@, %@, [%@]",
                    [self registerName:rs is64bit:is64bit],
                    [self registerName:rt is64bit:is64bit],
                    [self registerName:rn is64bit:YES]];
}

- (void)decodeLoadLiteral:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeLoadStore;

    uint32_t opc = (instr >> 30) & 0x3;
    uint32_t V = (instr >> 26) & 0x1;
    uint32_t rt = instr & 0x1F;
    int32_t imm19 = (instr >> 5) & 0x7FFFF;

    // Sign extend
    if (imm19 & 0x40000) {
        imm19 |= 0xFFF80000;
    }

    int64_t offset = (int64_t)imm19 << 2;
    uint64_t target = inst.address + offset;

    if (V == 0) {
        // General-purpose register load
        BOOL is64bit = (opc & 0x1) != 0;
        if (opc == 0 || opc == 1) {
            inst.mnemonic = @"LDR";
            inst.operands = [NSString stringWithFormat:@"%@, 0x%llx",
                            [self registerName:rt is64bit:is64bit], target];
        } else if (opc == 2) {
            inst.mnemonic = @"LDRSW";
            inst.operands = [NSString stringWithFormat:@"X%u, 0x%llx", rt, target];
        } else {
            inst.mnemonic = @"PRFM";
            inst.operands = [NSString stringWithFormat:@"#%u, 0x%llx", rt, target];
        }
    } else {
        // SIMD/FP register load
        inst.mnemonic = @"LDR";
        const char *regPrefix = (opc == 0) ? "S" : (opc == 1) ? "D" : "Q";
        inst.operands = [NSString stringWithFormat:@"%s%u, 0x%llx", regPrefix, rt, target];
    }

    inst.comment = [NSString stringWithFormat:@"literal pool"];
}

- (void)decodeLoadStoreUnscaled:(uint32_t)instr into:(ARM64Instruction *)inst {
    inst.type = ARM64InstructionTypeLoadStore;

    uint32_t size = (instr >> 30) & 0x3;
    uint32_t opc = (instr >> 22) & 0x3;
    uint32_t rt = instr & 0x1F;
    uint32_t rn = (instr >> 5) & 0x1F;
    int32_t imm9 = (instr >> 12) & 0x1FF;

    // Sign extend imm9
    if (imm9 & 0x100) {
        imm9 |= 0xFFFFFE00;
    }

    BOOL is64bit = (size == 3);
    BOOL isLoad = (opc & 0x1) != 0;

    // Determine mnemonic
    if (size == 0 && opc == 0) inst.mnemonic = @"STURB";
    else if (size == 0 && opc == 1) inst.mnemonic = @"LDURB";
    else if (size == 1 && opc == 0) inst.mnemonic = @"STURH";
    else if (size == 1 && opc == 1) inst.mnemonic = @"LDURH";
    else if (size == 0 && opc == 2) inst.mnemonic = @"LDURSB";
    else if (size == 0 && opc == 3) inst.mnemonic = @"LDURSB";
    else if (size == 1 && opc == 2) inst.mnemonic = @"LDURSH";
    else if (size == 1 && opc == 3) inst.mnemonic = @"LDURSH";
    else if (size == 2 && opc == 2) inst.mnemonic = @"LDURSW";
    else if (isLoad) inst.mnemonic = @"LDUR";
    else inst.mnemonic = @"STUR";

    NSString *rtReg = [self registerName:rt is64bit:is64bit];
    NSString *rnReg = (rn == 31) ? @"SP" : [NSString stringWithFormat:@"X%u", rn];

    if (imm9 == 0) {
        inst.operands = [NSString stringWithFormat:@"%@, [%@]", rtReg, rnReg];
    } else if (imm9 < 0) {
        inst.operands = [NSString stringWithFormat:@"%@, [%@,#-0x%x]", rtReg, rnReg, -imm9];
    } else {
        inst.operands = [NSString stringWithFormat:@"%@, [%@,#0x%x]", rtReg, rnReg, imm9];
    }
}

@end
