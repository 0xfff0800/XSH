//
//  StackFrameTracker.h
//  iSH - Stack Frame Analysis and Tracking
//
//  Simulates SP/FP registers and tracks stack variables
//

#import <Foundation/Foundation.h>

@class ARM64Instruction;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PrologueType) {
    PrologueTypeNone,
    PrologueTypeStandard,      // SUB SP + STP FP,LR + ADD FP
    PrologueTypeCompact,       // STP FP,LR,[SP,#-n]! + MOV FP,SP
    PrologueTypeLeaf,          // SUB SP only (no frame pointer)
};

@interface StackVariable : NSObject
@property (nonatomic, assign) int64_t offset;      // Offset from FP or SP
@property (nonatomic, strong) NSString *name;      // var_0, arg_0, etc.
@property (nonatomic, assign) NSUInteger size;     // 1, 2, 4, 8 bytes
@property (nonatomic, assign) BOOL isSavedRegister;  // Saved X29, X30, etc.
@end

@interface StackFrameTracker : NSObject

// Frame info
@property (nonatomic, assign, readonly) int64_t frameSize;
@property (nonatomic, assign, readonly) int64_t spOffset;       // Current SP relative to entry
@property (nonatomic, assign, readonly) int64_t fpOffset;       // Current FP relative to entry
@property (nonatomic, assign, readonly) BOOL hasFP;             // Uses frame pointer
@property (nonatomic, assign, readonly) PrologueType prologueType;

// Variables
@property (nonatomic, strong, readonly) NSArray<StackVariable *> *variables;

// Analysis
- (void)processInstruction:(ARM64Instruction *)inst;
- (void)reset;

// Queries
- (nullable NSString *)variableAtOffset:(int64_t)offset fromFP:(BOOL)fromFP;
- (nullable NSString *)variableForOperand:(NSString *)operand;  // "[SP,#0x10]" -> "var_10"

// Detection (call before processing instructions)
- (BOOL)detectPrologueAtInstructions:(NSArray<ARM64Instruction *> *)instructions;

@end

NS_ASSUME_NONNULL_END
