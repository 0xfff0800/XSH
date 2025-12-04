//
//  CFGGenerator.h
//  iSH - Control Flow Graph Generator
//
//  Generates CFG like Hopper Disassembler with Graphviz visualization
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DetectedFunction, ARM64Instruction;

// Edge types for control flow
typedef NS_ENUM(NSInteger, CFGEdgeType) {
    CFGEdgeTypeFallthrough,      // Green - natural flow
    CFGEdgeTypeConditionalTrue,  // Red - branch taken
    CFGEdgeTypeConditionalFalse, // Red - branch not taken
    CFGEdgeTypeUnconditional,    // Red - unconditional jump
    CFGEdgeTypeCall,             // Blue - function call
};

// Block types
typedef NS_ENUM(NSInteger, CFGBlockType) {
    CFGBlockTypeEntry,           // Function entry point
    CFGBlockTypeNormal,          // Regular basic block
    CFGBlockTypeConditional,     // Ends with conditional branch
    CFGBlockTypeUnconditional,   // Ends with unconditional branch
    CFGBlockTypeReturn,          // Ends with return
};

// Basic Block
@interface CFGBasicBlock : NSObject

@property (nonatomic, assign) uint64_t startAddress;
@property (nonatomic, assign) uint64_t endAddress;
@property (nonatomic, strong) NSArray<ARM64Instruction *> *instructions;
@property (nonatomic, assign) CFGBlockType blockType;

- (NSString *)blockID;
- (NSString *)dotLabel;

@end

// Control Flow Edge
@interface CFGEdge : NSObject

@property (nonatomic, strong) CFGBasicBlock *fromBlock;
@property (nonatomic, strong) CFGBasicBlock *toBlock;
@property (nonatomic, assign) CFGEdgeType edgeType;

@end

// Control Flow Graph
@interface ControlFlowGraph : NSObject

@property (nonatomic, strong) NSString *functionName;
@property (nonatomic, assign) uint64_t startAddress;
@property (nonatomic, strong) NSMutableArray<CFGBasicBlock *> *blocks;
@property (nonatomic, strong) NSMutableArray<CFGEdge *> *edges;

- (instancetype)initWithFunctionName:(NSString *)name startAddress:(uint64_t)address;

- (void)addBlock:(CFGBasicBlock *)block;
- (void)addEdge:(CFGEdge *)edge;
- (CFGBasicBlock *)getBlockAtAddress:(uint64_t)address;

// Generate Graphviz DOT format
- (NSString *)generateDOT;
- (void)saveDOTToFile:(NSString *)path;

// Generate image directly (requires Graphviz installed)
- (BOOL)generatePNGToFile:(NSString *)path;

// Statistics
- (NSDictionary *)statistics;

@end

// CFG Builder
@interface CFGBuilder : NSObject

@property (nonatomic, strong) NSArray<ARM64Instruction *> *instructions;
@property (nonatomic, strong) NSString *functionName;
@property (nonatomic, assign) uint64_t startAddress;
@property (nonatomic, strong, nullable) ControlFlowGraph *cfg;

- (instancetype)initWithInstructions:(NSArray<ARM64Instruction *> *)instructions
                        functionName:(NSString *)name;

- (ControlFlowGraph *)build;

@end

NS_ASSUME_NONNULL_END
