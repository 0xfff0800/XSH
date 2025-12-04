//
//  BasicBlock.h
//  iSH - Basic Block for Control Flow Graph
//
//  Represents a basic block: straight-line sequence of instructions
//

#import <Foundation/Foundation.h>

@class ARM64Instruction;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BlockType) {
    BlockTypeNormal,
    BlockTypeConditional,  // Ends with conditional branch
    BlockTypeUnconditional, // Ends with B
    BlockTypeReturn,       // Ends with RET
    BlockTypeCall,         // Contains BL
};

@interface BasicBlock : NSObject

@property (nonatomic, assign) uint64_t startAddress;
@property (nonatomic, assign) uint64_t endAddress;
@property (nonatomic, assign) BlockType type;

// Instructions in this block
@property (nonatomic, strong) NSMutableArray<ARM64Instruction *> *instructions;

// CFG edges
@property (nonatomic, strong) NSMutableArray<BasicBlock *> *successors;
@property (nonatomic, strong) NSMutableArray<BasicBlock *> *predecessors;

// Branch target (for conditional/unconditional blocks)
@property (nonatomic, assign) uint64_t branchTarget;

// For dominance and loop analysis
@property (nonatomic, weak, nullable) BasicBlock *immediateDominator;
@property (nonatomic, assign) BOOL isLoopHeader;

- (BOOL)containsAddress:(uint64_t)address;
- (NSUInteger)instructionCount;

@end

NS_ASSUME_NONNULL_END
