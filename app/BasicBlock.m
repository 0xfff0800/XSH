//
//  BasicBlock.m
//  iSH - Basic Block Implementation
//

#import "BasicBlock.h"
#import "ARM64InstructionDecoder.h"

@implementation BasicBlock

- (instancetype)init {
    if (self = [super init]) {
        _instructions = [NSMutableArray array];
        _successors = [NSMutableArray array];
        _predecessors = [NSMutableArray array];
        _type = BlockTypeNormal;
        _branchTarget = 0;
        _isLoopHeader = NO;
    }
    return self;
}

- (BOOL)containsAddress:(uint64_t)address {
    return address >= self.startAddress && address < self.endAddress;
}

- (NSUInteger)instructionCount {
    return self.instructions.count;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<BasicBlock 0x%llx-0x%llx (%lu instructions, %lu successors)>",
            self.startAddress, self.endAddress,
            (unsigned long)self.instructions.count,
            (unsigned long)self.successors.count];
}

@end
