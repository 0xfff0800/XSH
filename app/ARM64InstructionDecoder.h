//
//  ARM64InstructionDecoder.h
//  iSH - Real ARM64 Instruction Decoder
//
//  Decodes ARM64 instructions with Hopper-like formatting
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ARM64InstructionType) {
    ARM64InstructionTypeUnknown,
    ARM64InstructionTypeBranch,        // B, BL, BR, BLR, RET, etc.
    ARM64InstructionTypeLoadStore,     // LDR, STR, LDP, STP
    ARM64InstructionTypeDataProcessing, // ADD, SUB, MUL, DIV
    ARM64InstructionTypeLogical,       // AND, ORR, EOR
    ARM64InstructionTypeShift,         // LSL, LSR, ASR, ROR
    ARM64InstructionTypeCompare,       // CMP, CMN, TST
    ARM64InstructionTypeMove,          // MOV, MOVZ, MOVK, MOVN
    ARM64InstructionTypeConditional,   // CSEL, CSET, etc.
    ARM64InstructionTypeSystem,        // MSR, MRS, etc.
};

@interface ARM64Instruction : NSObject

@property (nonatomic, assign) uint32_t rawInstruction;
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) ARM64InstructionType type;
@property (nonatomic, strong) NSString *mnemonic;
@property (nonatomic, strong) NSString *operands;
@property (nonatomic, strong, nullable) NSString *comment;

// Formatted output like Hopper
- (NSString *)hopperStyleDescription;

@end

@interface ARM64InstructionDecoder : NSObject

// Decode single instruction
- (ARM64Instruction *)decodeInstructionAtAddress:(uint64_t)address
                                         data:(const uint8_t *)data
                                       length:(NSUInteger)length;

// Decode instruction from 32-bit value
- (ARM64Instruction *)decodeInstruction:(uint32_t)instruction
                              atAddress:(uint64_t)address;

@end

NS_ASSUME_NONNULL_END
