//
//  StackFrameTracker.m
//  iSH - Stack Frame Tracking Implementation
//

#import "StackFrameTracker.h"
#import "ARM64InstructionDecoder.h"

@implementation StackVariable
// Properties are auto-synthesized
@end

@interface StackFrameTracker ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, StackVariable *> *stackSlots;
@property (nonatomic, assign) int64_t currentSPOffset;
@property (nonatomic, assign) int64_t currentFPOffset;
@property (nonatomic, assign) int64_t detectedFrameSize;
@property (nonatomic, assign) BOOL hasFramePointer;
@property (nonatomic, assign) PrologueType detectedPrologueType;
@end

@implementation StackFrameTracker

- (instancetype)init {
    if (self = [super init]) {
        _stackSlots = [NSMutableDictionary dictionary];
        [self reset];
    }
    return self;
}

- (void)reset {
    [self.stackSlots removeAllObjects];
    _currentSPOffset = 0;
    _currentFPOffset = 0;
    _detectedFrameSize = 0;
    _hasFramePointer = NO;
    _detectedPrologueType = PrologueTypeNone;
}

- (int64_t)frameSize { return _detectedFrameSize; }
- (int64_t)spOffset { return _currentSPOffset; }
- (int64_t)fpOffset { return _currentFPOffset; }
- (BOOL)hasFP { return _hasFramePointer; }
- (PrologueType)prologueType { return _detectedPrologueType; }

- (NSArray<StackVariable *> *)variables {
    return [self.stackSlots.allValues sortedArrayUsingComparator:^NSComparisonResult(StackVariable *a, StackVariable *b) {
        if (a.offset < b.offset) return NSOrderedAscending;
        if (a.offset > b.offset) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

#pragma mark - Prologue Detection

- (BOOL)detectPrologueAtInstructions:(NSArray<ARM64Instruction *> *)instructions {
    if (instructions.count < 2) {
        return NO;
    }

    ARM64Instruction *inst0 = instructions[0];
    ARM64Instruction *inst1 = instructions.count > 1 ? instructions[1] : nil;
    ARM64Instruction *inst2 = instructions.count > 2 ? instructions[2] : nil;

    // Pattern 1: Compact - STP FP,LR,[SP,#-n]!
    if ([inst0.mnemonic isEqualToString:@"STP"] &&
        [inst0.operands containsString:@"X29"] &&
        [inst0.operands containsString:@"X30"] &&
        [inst0.operands containsString:@"]!"]) {

        int64_t frameSize = [self extractImmediateFromOperands:inst0.operands];
        if (frameSize < 0) {
            _detectedFrameSize = -frameSize;
            _hasFramePointer = YES;
            _detectedPrologueType = PrologueTypeCompact;

            // Add saved registers
            [self addSavedRegister:@"X29" offset:0];
            [self addSavedRegister:@"X30" offset:8];

            return YES;
        }
    }

    // Pattern 2: Standard - SUB SP,SP,#n
    if ([inst0.mnemonic isEqualToString:@"SUB"] &&
        [inst0.operands hasPrefix:@"SP, SP"]) {

        int64_t frameSize = [self extractImmediateFromOperands:inst0.operands];
        if (frameSize > 0) {
            _detectedFrameSize = frameSize;
            _currentSPOffset = -frameSize;

            // Check for STP FP,LR
            if (inst1 && [inst1.mnemonic isEqualToString:@"STP"] &&
                [inst1.operands containsString:@"X29"] &&
                [inst1.operands containsString:@"X30"]) {
                _hasFramePointer = YES;
                _detectedPrologueType = PrologueTypeStandard;

                // Extract offset
                int64_t stpOffset = [self extractImmediateFromOperands:inst1.operands];
                [self addSavedRegister:@"X29" offset:stpOffset];
                [self addSavedRegister:@"X30" offset:stpOffset + 8];
            } else {
                _detectedPrologueType = PrologueTypeLeaf;
            }

            return YES;
        }
    }

    return NO;
}

#pragma mark - Instruction Processing

- (void)processInstruction:(ARM64Instruction *)inst {
    NSString *mnemonic = inst.mnemonic;
    NSString *operands = inst.operands;

    // Track SP modifications
    if ([mnemonic isEqualToString:@"SUB"] && [operands hasPrefix:@"SP, SP"]) {
        int64_t imm = [self extractImmediateFromOperands:operands];
        _currentSPOffset -= imm;
    }
    else if ([mnemonic isEqualToString:@"ADD"] && [operands hasPrefix:@"SP, SP"]) {
        int64_t imm = [self extractImmediateFromOperands:operands];
        _currentSPOffset += imm;
    }

    // Track FP setup
    else if ([mnemonic isEqualToString:@"MOV"] && [operands hasPrefix:@"X29, SP"]) {
        _currentFPOffset = _currentSPOffset;
        _hasFramePointer = YES;
    }
    else if ([mnemonic isEqualToString:@"ADD"] && [operands hasPrefix:@"X29, SP"]) {
        int64_t imm = [self extractImmediateFromOperands:operands];
        _currentFPOffset = _currentSPOffset + imm;
        _hasFramePointer = YES;
    }

    // Track stores to stack
    else if ([mnemonic isEqualToString:@"STR"] || [mnemonic isEqualToString:@"STP"]) {
        [self processStoreInstruction:inst];
    }
}

- (void)processStoreInstruction:(ARM64Instruction *)inst {
    // Extract base register and offset from "[SP,#0x10]" or "[X29,#-0x8]"
    NSString *operands = inst.operands;

    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"\\[(SP|X29),#(-?0x[0-9a-fA-F]+|\\-?\\d+)\\]"
        options:0 error:nil];

    NSTextCheckingResult *match = [regex firstMatchInString:operands
                                                    options:0
                                                      range:NSMakeRange(0, operands.length)];

    if (match && match.numberOfRanges >= 3) {
        NSString *baseReg = [operands substringWithRange:[match rangeAtIndex:1]];
        NSString *offsetStr = [operands substringWithRange:[match rangeAtIndex:2]];

        int64_t offset = [self parseInteger:offsetStr];
        BOOL isFP = [baseReg isEqualToString:@"X29"];

        // Create variable if not exists
        NSNumber *key = @(offset);
        if (!self.stackSlots[key]) {
            StackVariable *var = [[StackVariable alloc] init];
            var.offset = offset;
            var.name = [self generateVariableName:offset fromFP:isFP];
            var.size = 8;  // Default
            var.isSavedRegister = NO;

            self.stackSlots[key] = var;
        }
    }
}

#pragma mark - Queries

- (NSString *)variableAtOffset:(int64_t)offset fromFP:(BOOL)fromFP {
    StackVariable *var = self.stackSlots[@(offset)];
    if (var) {
        return var.name;
    }

    return [self generateVariableName:offset fromFP:fromFP];
}

- (NSString *)variableForOperand:(NSString *)operand {
    // Parse "[SP,#0x10]" or "[X29,#-0x8]"
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"\\[(SP|X29),#(-?0x[0-9a-fA-F]+|\\-?\\d+)\\]"
        options:0 error:nil];

    NSTextCheckingResult *match = [regex firstMatchInString:operand
                                                    options:0
                                                      range:NSMakeRange(0, operand.length)];

    if (match && match.numberOfRanges >= 3) {
        NSString *baseReg = [operand substringWithRange:[match rangeAtIndex:1]];
        NSString *offsetStr = [operand substringWithRange:[match rangeAtIndex:2]];

        int64_t offset = [self parseInteger:offsetStr];
        BOOL isFP = [baseReg isEqualToString:@"X29"];

        return [self variableAtOffset:offset fromFP:isFP];
    }

    return nil;
}

#pragma mark - Helpers

- (void)addSavedRegister:(NSString *)regName offset:(int64_t)offset {
    StackVariable *var = [[StackVariable alloc] init];
    var.offset = offset;
    var.name = [NSString stringWithFormat:@"saved_%@", regName];
    var.size = 8;
    var.isSavedRegister = YES;

    self.stackSlots[@(offset)] = var;
}

- (NSString *)generateVariableName:(int64_t)offset fromFP:(BOOL)fromFP {
    if (offset >= 0) {
        // Positive offsets are arguments (in parent's frame)
        return [NSString stringWithFormat:@"arg_%llx", (long long)offset];
    } else {
        // Negative offsets are local variables
        return [NSString stringWithFormat:@"var_%llx", (long long)-offset];
    }
}

- (int64_t)extractImmediateFromOperands:(NSString *)operands {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"#(-?0x[0-9a-fA-F]+|-?\\d+)"
        options:0 error:nil];

    NSTextCheckingResult *match = [regex firstMatchInString:operands
                                                    options:0
                                                      range:NSMakeRange(0, operands.length)];

    if (match) {
        NSString *immStr = [operands substringWithRange:[match rangeAtIndex:1]];
        return [self parseInteger:immStr];
    }

    return 0;
}

- (int64_t)parseInteger:(NSString *)str {
    if ([str hasPrefix:@"0x"] || [str hasPrefix:@"-0x"]) {
        BOOL negative = [str hasPrefix:@"-"];
        NSString *hexPart = negative ? [str substringFromIndex:3] : [str substringFromIndex:2];
        unsigned long long value = strtoull([hexPart UTF8String], NULL, 16);
        return negative ? -(int64_t)value : (int64_t)value;
    } else {
        return (int64_t)[str longLongValue];
    }
}

@end
