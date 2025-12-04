//
//  CFGBuilder.h
//  iSH - Control Flow Graph Builder
//
//  Builds CFG from disassembled functions
//

#import <Foundation/Foundation.h>

@class BasicBlock, ARM64InstructionDecoder;

NS_ASSUME_NONNULL_BEGIN

@interface CFGBuilder : NSObject

@property (nonatomic, strong) ARM64InstructionDecoder *decoder;
@property (nonatomic, strong) NSData *binaryData;
@property (nonatomic, assign) uint64_t baseAddress;

- (instancetype)initWithDecoder:(ARM64InstructionDecoder *)decoder
                     binaryData:(NSData *)data
                    baseAddress:(uint64_t)baseAddr;

// Build CFG for a function
- (nullable NSDictionary<NSNumber *, BasicBlock *> *)buildCFGForFunction:(uint64_t)startAddress
                                                              endAddress:(uint64_t)endAddress;

// Get entry block
- (nullable BasicBlock *)entryBlockFromCFG:(NSDictionary<NSNumber *, BasicBlock *> *)cfg;

// Get blocks in topological order (for code generation)
- (NSArray<BasicBlock *> *)topologicalSortOfCFG:(NSDictionary<NSNumber *, BasicBlock *> *)cfg;

// Detect loops
- (void)detectLoopsInCFG:(NSDictionary<NSNumber *, BasicBlock *> *)cfg;

@end

NS_ASSUME_NONNULL_END
