//
//  CFGGenerator.m
//  iSH - Control Flow Graph Generator Implementation
//

#import "CFGGenerator.h"
#import "ARM64InstructionDecoder.h"

@implementation CFGBasicBlock

- (NSString *)blockID {
    return [NSString stringWithFormat:@"block_%llx", self.startAddress];
}

- (NSString *)dotLabel {
    NSMutableString *label = [NSMutableString string];
    for (ARM64Instruction *instr in self.instructions) {
        [label appendFormat:@"0x%llx: %@ %@\\n",
         instr.address, instr.mnemonic, instr.operands ?: @""];
    }
    return label;
}

@end

@implementation CFGEdge
@end

@implementation ControlFlowGraph

- (instancetype)initWithFunctionName:(NSString *)name startAddress:(uint64_t)address {
    self = [super init];
    if (self) {
        _functionName = name;
        _startAddress = address;
        _blocks = [NSMutableArray array];
        _edges = [NSMutableArray array];
    }
    return self;
}

- (void)addBlock:(CFGBasicBlock *)block {
    [self.blocks addObject:block];
}

- (void)addEdge:(CFGEdge *)edge {
    [self.edges addObject:edge];
}

- (CFGBasicBlock *)getBlockAtAddress:(uint64_t)address {
    for (CFGBasicBlock *block in self.blocks) {
        if (address >= block.startAddress && address <= block.endAddress) {
            return block;
        }
    }
    return nil;
}

- (NSString *)generateDOT {
    NSMutableString *dot = [NSMutableString string];

    [dot appendFormat:@"digraph \"%@\" {\n", self.functionName];
    [dot appendString:@"    rankdir=TB;\n"];
    [dot appendString:@"    node [shape=box, style=filled, fontname=\"Courier New\"];\n\n"];

    // Add nodes (basic blocks)
    for (CFGBasicBlock *block in self.blocks) {
        NSString *color;
        switch (block.blockType) {
            case CFGBlockTypeEntry:
                color = @"lightblue";
                break;
            case CFGBlockTypeReturn:
                color = @"lightcoral";
                break;
            case CFGBlockTypeConditional:
                color = @"lightyellow";
                break;
            default:
                color = @"lightgray";
                break;
        }

        [dot appendFormat:@"    %@ [label=\"%@\", fillcolor=%@];\n",
         [block blockID], [block dotLabel], color];
    }

    [dot appendString:@"\n"];

    // Add edges
    for (CFGEdge *edge in self.edges) {
        NSString *color;
        NSString *style;
        NSString *label = @"";

        switch (edge.edgeType) {
            case CFGEdgeTypeFallthrough:
                color = @"green";
                style = @"solid";
                break;

            case CFGEdgeTypeConditionalTrue:
                color = @"red";
                style = @"solid";
                label = @"T";
                break;

            case CFGEdgeTypeConditionalFalse:
                color = @"red";
                style = @"solid";
                label = @"F";
                break;

            case CFGEdgeTypeUnconditional:
                color = @"red";
                style = @"bold";
                break;

            case CFGEdgeTypeCall:
                color = @"blue";
                style = @"dashed";
                label = @"call";
                break;
        }

        if (label.length > 0) {
            [dot appendFormat:@"    %@ -> %@ [color=%@, style=%@, label=\"%@\"];\n",
             [edge.fromBlock blockID], [edge.toBlock blockID], color, style, label];
        } else {
            [dot appendFormat:@"    %@ -> %@ [color=%@, style=%@];\n",
             [edge.fromBlock blockID], [edge.toBlock blockID], color, style];
        }
    }

    [dot appendString:@"}\n"];
    return dot;
}

- (void)saveDOTToFile:(NSString *)path {
    NSString *dot = [self generateDOT];
    NSError *error = nil;
    [dot writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];

    if (error) {
        NSLog(@"❌ Failed to save DOT file: %@", error);
    } else {
        NSLog(@"✅ Saved CFG to %@", path);
        NSLog(@"   To visualize: dot -Tpng %@ -o %@",
              path, [path stringByReplacingOccurrencesOfString:@".dot" withString:@".png"]);
    }
}

- (BOOL)generatePNGToFile:(NSString *)path {
    // First save DOT file
    NSString *dotPath = [path stringByReplacingOccurrencesOfString:@".png" withString:@".dot"];
    [self saveDOTToFile:dotPath];

    // Run Graphviz to generate PNG
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/local/bin/dot";
    task.arguments = @[@"-Tpng", dotPath, @"-o", path];

    @try {
        [task launch];
        [task waitUntilExit];

        if (task.terminationStatus == 0) {
            NSLog(@"✅ Generated PNG: %@", path);
            return YES;
        } else {
            NSLog(@"⚠️ Graphviz failed. Install with: brew install graphviz");
            return NO;
        }
    } @catch (NSException *e) {
        NSLog(@"⚠️ Graphviz not found. Install with: brew install graphviz");
        return NO;
    }
}

- (NSDictionary *)statistics {
    NSInteger fallthrough = 0, conditional = 0, unconditional = 0, calls = 0;

    for (CFGEdge *edge in self.edges) {
        switch (edge.edgeType) {
            case CFGEdgeTypeFallthrough:
                fallthrough++;
                break;
            case CFGEdgeTypeConditionalTrue:
            case CFGEdgeTypeConditionalFalse:
                conditional++;
                break;
            case CFGEdgeTypeUnconditional:
                unconditional++;
                break;
            case CFGEdgeTypeCall:
                calls++;
                break;
        }
    }

    return @{
        @"blocks": @(self.blocks.count),
        @"edges": @(self.edges.count),
        @"fallthrough": @(fallthrough),
        @"conditional": @(conditional),
        @"unconditional": @(unconditional),
        @"calls": @(calls)
    };
}

@end

@implementation CFGBuilder {
    NSMutableDictionary<NSNumber *, ARM64Instruction *> *_instrMap;
}

- (instancetype)initWithInstructions:(NSArray<ARM64Instruction *> *)instructions
                        functionName:(NSString *)name {
    self = [super init];
    if (self) {
        _instructions = instructions;
        _functionName = name;
        _startAddress = instructions.firstObject.address;

        // Build instruction map
        _instrMap = [NSMutableDictionary dictionary];
        for (ARM64Instruction *instr in instructions) {
            _instrMap[@(instr.address)] = instr;
        }
    }
    return self;
}

- (ControlFlowGraph *)build {
    NSLog(@"Building CFG for %@ at 0x%llx", self.functionName, self.startAddress);

    self.cfg = [[ControlFlowGraph alloc] initWithFunctionName:self.functionName
                                                  startAddress:self.startAddress];

    // Step 1: Find basic block boundaries
    NSSet *blockStarts = [self findBlockStarts];

    // Step 2: Create basic blocks
    NSArray<CFGBasicBlock *> *blocks = [self createBasicBlocks:blockStarts];

    // Step 3: Build edges
    [self buildEdges:blocks];

    NSDictionary *stats = [self.cfg statistics];
    NSLog(@"✅ CFG complete: %@ blocks, %@ edges", stats[@"blocks"], stats[@"edges"]);

    return self.cfg;
}

- (NSSet *)findBlockStarts {
    NSMutableSet *blockStarts = [NSMutableSet setWithObject:@(self.startAddress)];

    for (ARM64Instruction *instr in self.instructions) {
        // Block starts after any branch or return
        if ([self isBranch:instr] || [self isReturn:instr]) {
            uint64_t nextAddr = instr.address + 4;
            if (_instrMap[@(nextAddr)]) {
                [blockStarts addObject:@(nextAddr)];
            }
        }

        // Block starts at branch target
        if ([self isBranch:instr]) {
            uint64_t target = [self getBranchTarget:instr];
            if (target != 0 && _instrMap[@(target)]) {
                [blockStarts addObject:@(target)];
            }
        }
    }

    return blockStarts;
}

- (NSArray<CFGBasicBlock *> *)createBasicBlocks:(NSSet *)blockStarts {
    NSArray *sortedStarts = [[blockStarts allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<CFGBasicBlock *> *blocks = [NSMutableArray array];

    for (NSInteger i = 0; i < sortedStarts.count; i++) {
        uint64_t start = [sortedStarts[i] unsignedLongLongValue];

        // Find end of this block
        uint64_t end;
        if (i + 1 < sortedStarts.count) {
            end = [sortedStarts[i + 1] unsignedLongLongValue] - 4;
        } else {
            end = self.instructions.lastObject.address;
        }

        // Collect instructions in this block
        NSMutableArray<ARM64Instruction *> *blockInstrs = [NSMutableArray array];
        uint64_t addr = start;
        while (addr <= end && _instrMap[@(addr)]) {
            [blockInstrs addObject:_instrMap[@(addr)]];
            addr += 4;
        }

        if (blockInstrs.count == 0) continue;

        // Determine block type
        ARM64Instruction *lastInstr = blockInstrs.lastObject;
        CFGBlockType blockType;

        if (start == self.startAddress) {
            blockType = CFGBlockTypeEntry;
        } else if ([self isReturn:lastInstr]) {
            blockType = CFGBlockTypeReturn;
        } else if ([self isConditionalBranch:lastInstr]) {
            blockType = CFGBlockTypeConditional;
        } else if ([self isUnconditionalBranch:lastInstr]) {
            blockType = CFGBlockTypeUnconditional;
        } else {
            blockType = CFGBlockTypeNormal;
        }

        CFGBasicBlock *block = [[CFGBasicBlock alloc] init];
        block.startAddress = start;
        block.endAddress = blockInstrs.lastObject.address;
        block.instructions = blockInstrs;
        block.blockType = blockType;

        [blocks addObject:block];
        [self.cfg addBlock:block];
    }

    return blocks;
}

- (void)buildEdges:(NSArray<CFGBasicBlock *> *)blocks {
    for (CFGBasicBlock *block in blocks) {
        ARM64Instruction *lastInstr = block.instructions.lastObject;
        uint64_t nextAddr = lastInstr.address + 4;

        // Conditional branch: add both taken and fallthrough edges
        if ([self isConditionalBranch:lastInstr]) {
            // Branch taken (red)
            uint64_t target = [self getBranchTarget:lastInstr];
            if (target != 0) {
                CFGBasicBlock *targetBlock = [self.cfg getBlockAtAddress:target];
                if (targetBlock) {
                    CFGEdge *edge = [[CFGEdge alloc] init];
                    edge.fromBlock = block;
                    edge.toBlock = targetBlock;
                    edge.edgeType = CFGEdgeTypeConditionalTrue;
                    [self.cfg addEdge:edge];
                }
            }

            // Fallthrough (red - false branch)
            if (_instrMap[@(nextAddr)]) {
                CFGBasicBlock *fallthrough = [self.cfg getBlockAtAddress:nextAddr];
                if (fallthrough) {
                    CFGEdge *edge = [[CFGEdge alloc] init];
                    edge.fromBlock = block;
                    edge.toBlock = fallthrough;
                    edge.edgeType = CFGEdgeTypeConditionalFalse;
                    [self.cfg addEdge:edge];
                }
            }
        }
        // Unconditional branch
        else if ([self isUnconditionalBranch:lastInstr]) {
            uint64_t target = [self getBranchTarget:lastInstr];
            if (target != 0) {
                CFGBasicBlock *targetBlock = [self.cfg getBlockAtAddress:target];
                if (targetBlock) {
                    CFGEdge *edge = [[CFGEdge alloc] init];
                    edge.fromBlock = block;
                    edge.toBlock = targetBlock;
                    edge.edgeType = CFGEdgeTypeUnconditional;
                    [self.cfg addEdge:edge];
                }
            }
        }
        // Function call
        else if ([self isCall:lastInstr]) {
            // Just add fallthrough
            if (_instrMap[@(nextAddr)]) {
                CFGBasicBlock *fallthrough = [self.cfg getBlockAtAddress:nextAddr];
                if (fallthrough) {
                    CFGEdge *edge = [[CFGEdge alloc] init];
                    edge.fromBlock = block;
                    edge.toBlock = fallthrough;
                    edge.edgeType = CFGEdgeTypeFallthrough;
                    [self.cfg addEdge:edge];
                }
            }
        }
        // Return: no outgoing edges
        else if ([self isReturn:lastInstr]) {
            // Terminal block
        }
        // Normal instruction: fallthrough
        else {
            if (_instrMap[@(nextAddr)]) {
                CFGBasicBlock *fallthrough = [self.cfg getBlockAtAddress:nextAddr];
                if (fallthrough) {
                    CFGEdge *edge = [[CFGEdge alloc] init];
                    edge.fromBlock = block;
                    edge.toBlock = fallthrough;
                    edge.edgeType = CFGEdgeTypeFallthrough;
                    [self.cfg addEdge:edge];
                }
            }
        }
    }
}

#pragma mark - Helper Methods

- (BOOL)isBranch:(ARM64Instruction *)instr {
    NSString *m = instr.mnemonic.uppercaseString;
    return [m isEqualToString:@"B"] || [m isEqualToString:@"BR"] ||
           [m isEqualToString:@"BL"] || [m isEqualToString:@"BLR"] ||
           [m hasPrefix:@"B."] || [m hasPrefix:@"CB"] || [m hasPrefix:@"TB"];
}

- (BOOL)isConditionalBranch:(ARM64Instruction *)instr {
    NSString *m = instr.mnemonic.uppercaseString;
    return [m hasPrefix:@"B."] || [m hasPrefix:@"CB"] || [m hasPrefix:@"TB"];
}

- (BOOL)isUnconditionalBranch:(ARM64Instruction *)instr {
    NSString *m = instr.mnemonic.uppercaseString;
    return [m isEqualToString:@"B"] || [m isEqualToString:@"BR"];
}

- (BOOL)isCall:(ARM64Instruction *)instr {
    NSString *m = instr.mnemonic.uppercaseString;
    return [m isEqualToString:@"BL"] || [m isEqualToString:@"BLR"];
}

- (BOOL)isReturn:(ARM64Instruction *)instr {
    return [instr.mnemonic.uppercaseString isEqualToString:@"RET"];
}

- (uint64_t)getBranchTarget:(ARM64Instruction *)instr {
    // Extract target address from operands
    NSString *operands = instr.operands;
    if (!operands) return 0;

    // Look for hex address (0x...)
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"0x([0-9a-fA-F]+)"
                                                                           options:0
                                                                             error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:operands
                                                     options:0
                                                       range:NSMakeRange(0, operands.length)];

    if (match && match.numberOfRanges > 1) {
        NSString *hexStr = [operands substringWithRange:[match rangeAtIndex:1]];
        unsigned long long addr = 0;
        NSScanner *scanner = [NSScanner scannerWithString:hexStr];
        [scanner scanHexLongLong:&addr];
        return (uint64_t)addr;
    }

    return 0;
}

@end
