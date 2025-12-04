//
//  CFGBuilder.m
//  iSH - Control Flow Graph Builder Implementation
//

#import "CFGBuilder.h"
#import "BasicBlock.h"
#import "ARM64InstructionDecoder.h"

@implementation CFGBuilder

- (instancetype)initWithDecoder:(ARM64InstructionDecoder *)decoder
                     binaryData:(NSData *)data
                    baseAddress:(uint64_t)baseAddr {
    if (self = [super init]) {
        _decoder = decoder;
        _binaryData = data;
        _baseAddress = baseAddr;
    }
    return self;
}

#pragma mark - CFG Construction

- (NSDictionary<NSNumber *, BasicBlock *> *)buildCFGForFunction:(uint64_t)startAddress
                                                     endAddress:(uint64_t)endAddress {
    if (startAddress >= endAddress) {
        return nil;
    }

    // Step 1: Find all block boundaries (leaders)
    NSMutableSet<NSNumber *> *leaders = [NSMutableSet setWithObject:@(startAddress)];

    [self findBlockLeaders:leaders start:startAddress end:endAddress];

    // Step 2: Create basic blocks
    NSMutableDictionary<NSNumber *, BasicBlock *> *blocks = [NSMutableDictionary dictionary];

    NSArray *sortedLeaders = [[leaders allObjects] sortedArrayUsingSelector:@selector(compare:)];

    for (NSUInteger i = 0; i < sortedLeaders.count; i++) {
        uint64_t blockStart = [sortedLeaders[i] unsignedLongLongValue];
        uint64_t blockEnd = (i + 1 < sortedLeaders.count) ?
                            [sortedLeaders[i + 1] unsignedLongLongValue] :
                            endAddress;

        BasicBlock *block = [self createBasicBlock:blockStart end:blockEnd];
        if (block) {
            blocks[@(blockStart)] = block;
        }
    }

    // Step 3: Link blocks (build edges)
    [self linkBlocks:blocks];

    return [blocks copy];
}

- (void)findBlockLeaders:(NSMutableSet<NSNumber *> *)leaders
                   start:(uint64_t)startAddress
                     end:(uint64_t)endAddress {

    uint64_t addr = startAddress;

    while (addr < endAddress) {
        uint64_t offset = addr - self.baseAddress;
        if (offset + 4 > self.binaryData.length) break;

        const uint8_t *bytes = (const uint8_t *)[self.binaryData bytes];
        ARM64Instruction *inst = [self.decoder decodeInstructionAtAddress:addr
                                                                      data:bytes + offset
                                                                    length:4];

        if (!inst) {
            addr += 4;
            continue;
        }

        NSString *mnemonic = inst.mnemonic;

        // Branch instructions create new block after them
        if ([mnemonic hasPrefix:@"B"] || [mnemonic isEqualToString:@"RET"]) {
            // Next instruction is a leader (if not already added)
            if (addr + 4 < endAddress) {
                [leaders addObject:@(addr + 4)];
            }

            // Branch target is a leader
            if (inst.comment && [inst.comment rangeOfString:@"0x"].location != NSNotFound) {
                uint64_t target = [self extractAddressFromComment:inst.comment];
                if (target >= startAddress && target < endAddress) {
                    [leaders addObject:@(target)];
                }
            }
        }

        addr += 4;
    }
}

- (BasicBlock *)createBasicBlock:(uint64_t)start end:(uint64_t)end {
    BasicBlock *block = [[BasicBlock alloc] init];
    block.startAddress = start;
    block.endAddress = end;

    uint64_t addr = start;

    while (addr < end) {
        uint64_t offset = addr - self.baseAddress;
        if (offset + 4 > self.binaryData.length) break;

        const uint8_t *bytes = (const uint8_t *)[self.binaryData bytes];
        ARM64Instruction *inst = [self.decoder decodeInstructionAtAddress:addr
                                                                      data:bytes + offset
                                                                    length:4];

        if (inst) {
            [block.instructions addObject:inst];

            // Determine block type from last instruction
            if (addr + 4 >= end || addr + 4 >= block.endAddress) {
                [self determineBlockType:block fromInstruction:inst];
            }
        }

        addr += 4;
    }

    return block;
}

- (void)determineBlockType:(BasicBlock *)block fromInstruction:(ARM64Instruction *)inst {
    NSString *mnemonic = inst.mnemonic;

    if ([mnemonic isEqualToString:@"RET"] ||
        ([mnemonic isEqualToString:@"BR"] && [inst.operands containsString:@"X30"])) {
        block.type = BlockTypeReturn;
    }
    else if ([mnemonic isEqualToString:@"B"]) {
        block.type = BlockTypeUnconditional;
        block.branchTarget = [self extractAddressFromComment:inst.comment];
    }
    else if ([mnemonic hasPrefix:@"B."]) {  // B.EQ, B.NE, etc.
        block.type = BlockTypeConditional;
        block.branchTarget = [self extractAddressFromComment:inst.comment];
    }
    else if ([mnemonic isEqualToString:@"CBZ"] ||
             [mnemonic isEqualToString:@"CBNZ"] ||
             [mnemonic isEqualToString:@"TBZ"] ||
             [mnemonic isEqualToString:@"TBNZ"]) {
        block.type = BlockTypeConditional;
        block.branchTarget = [self extractAddressFromComment:inst.comment];
    }
    else if ([mnemonic isEqualToString:@"BL"]) {
        block.type = BlockTypeCall;
        // Fall through to next block
    }
    else {
        block.type = BlockTypeNormal;
    }
}

- (void)linkBlocks:(NSDictionary<NSNumber *, BasicBlock *> *)blocks {
    for (NSNumber *startNum in blocks) {
        BasicBlock *block = blocks[startNum];

        switch (block.type) {
            case BlockTypeNormal:
            case BlockTypeCall: {
                // Fall through to next block
                BasicBlock *nextBlock = blocks[@(block.endAddress)];
                if (nextBlock) {
                    [block.successors addObject:nextBlock];
                    [nextBlock.predecessors addObject:block];
                }
                break;
            }

            case BlockTypeConditional: {
                // Two successors: branch target and fall-through
                BasicBlock *branchBlock = blocks[@(block.branchTarget)];
                if (branchBlock) {
                    [block.successors addObject:branchBlock];
                    [branchBlock.predecessors addObject:block];
                }

                BasicBlock *fallThrough = blocks[@(block.endAddress)];
                if (fallThrough) {
                    [block.successors addObject:fallThrough];
                    [fallThrough.predecessors addObject:block];
                }
                break;
            }

            case BlockTypeUnconditional: {
                // One successor: branch target
                BasicBlock *branchBlock = blocks[@(block.branchTarget)];
                if (branchBlock) {
                    [block.successors addObject:branchBlock];
                    [branchBlock.predecessors addObject:block];
                }
                break;
            }

            case BlockTypeReturn:
                // No successors
                break;
        }
    }
}

#pragma mark - CFG Analysis

- (BasicBlock *)entryBlockFromCFG:(NSDictionary<NSNumber *, BasicBlock *> *)cfg {
    // Find block with lowest address
    uint64_t minAddr = UINT64_MAX;
    BasicBlock *entry = nil;

    for (NSNumber *addr in cfg) {
        uint64_t a = [addr unsignedLongLongValue];
        if (a < minAddr) {
            minAddr = a;
            entry = cfg[addr];
        }
    }

    return entry;
}

- (NSArray<BasicBlock *> *)topologicalSortOfCFG:(NSDictionary<NSNumber *, BasicBlock *> *)cfg {
    NSMutableArray<BasicBlock *> *sorted = [NSMutableArray array];
    NSMutableSet<BasicBlock *> *visited = [NSMutableSet set];

    BasicBlock *entry = [self entryBlockFromCFG:cfg];
    if (entry) {
        [self topologicalVisit:entry visited:visited sorted:sorted];
    }

    return sorted;
}

- (void)topologicalVisit:(BasicBlock *)block
                 visited:(NSMutableSet<BasicBlock *> *)visited
                  sorted:(NSMutableArray<BasicBlock *> *)sorted {

    if ([visited containsObject:block]) {
        return;
    }

    [visited addObject:block];

    // Visit successors first (post-order)
    for (BasicBlock *successor in block.successors) {
        [self topologicalVisit:successor visited:visited sorted:sorted];
    }

    // Add this block
    [sorted insertObject:block atIndex:0];  // Reverse post-order
}

- (void)detectLoopsInCFG:(NSDictionary<NSNumber *, BasicBlock *> *)cfg {
    // Simple back-edge detection
    // A back-edge is an edge from a block to one of its ancestors in DFS

    NSMutableSet<BasicBlock *> *visited = [NSMutableSet set];
    NSMutableSet<BasicBlock *> *inStack = [NSMutableSet set];

    BasicBlock *entry = [self entryBlockFromCFG:cfg];
    if (entry) {
        [self detectLoopsDFS:entry visited:visited inStack:inStack];
    }
}

- (void)detectLoopsDFS:(BasicBlock *)block
               visited:(NSMutableSet<BasicBlock *> *)visited
               inStack:(NSMutableSet<BasicBlock *> *)inStack {

    [visited addObject:block];
    [inStack addObject:block];

    for (BasicBlock *successor in block.successors) {
        if (![visited containsObject:successor]) {
            [self detectLoopsDFS:successor visited:visited inStack:inStack];
        }
        else if ([inStack containsObject:successor]) {
            // Back edge found - successor is loop header
            successor.isLoopHeader = YES;
        }
    }

    [inStack removeObject:block];
}

#pragma mark - Helpers

- (uint64_t)extractAddressFromComment:(NSString *)comment {
    if (!comment) return 0;

    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"0x([0-9a-fA-F]+)"
        options:0 error:nil];

    NSTextCheckingResult *match = [regex firstMatchInString:comment
                                                    options:0
                                                      range:NSMakeRange(0, comment.length)];

    if (match) {
        NSString *hexStr = [comment substringWithRange:[match rangeAtIndex:1]];
        return strtoull([hexStr UTF8String], NULL, 16);
    }

    return 0;
}

@end
