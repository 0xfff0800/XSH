//
//  FunctionAnalyzer.m
//  iSH - Function Detection and Analysis
//
//  Complete function analyzer with prologue/epilogue detection and XREF tracking
//

#import "FunctionAnalyzer.h"
#import "ARM64InstructionDecoder.h"
#import "MachOParser.h"

@implementation DetectedFunction

- (NSUInteger)size {
    return (NSUInteger)(self.endAddress - self.startAddress);
}

- (NSString *)displayName {
    if (self.name) {
        return self.name;
    }
    if (self.isObjCMethod && self.objcClassName && self.objcMethodName) {
        return [NSString stringWithFormat:@"-[%@ %@]", self.objcClassName, self.objcMethodName];
    }
    return [NSString stringWithFormat:@"sub_%llx", self.startAddress];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _callsTo = [NSMutableArray array];
        _calledFrom = [NSMutableArray array];
        _stringRefs = [NSMutableArray array];
    }
    return self;
}

@end

@implementation CrossReference
@end

@interface FunctionAnalyzer ()
@property (nonatomic, strong) NSMutableArray<DetectedFunction *> *mutableFunctions;
@property (nonatomic, strong) NSMutableArray<CrossReference *> *mutableXRefs;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, DetectedFunction *> *mutableFunctionMap;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *analyzedAddresses;
@end

@implementation FunctionAnalyzer

- (instancetype)initWithBinaryData:(NSData *)data baseAddress:(uint64_t)baseAddr {
    return [self initWithBinaryData:data baseAddress:baseAddr machOParser:nil];
}

- (instancetype)initWithBinaryData:(NSData *)data baseAddress:(uint64_t)baseAddr machOParser:(MachOParser *)parser {
    self = [super init];
    if (self) {
        _binaryData = data;
        _baseAddress = baseAddr;
        _machOParser = parser;
        _decoder = [[ARM64InstructionDecoder alloc] init];
        _mutableFunctions = [NSMutableArray array];
        _mutableXRefs = [NSMutableArray array];
        _mutableFunctionMap = [NSMutableDictionary dictionary];
        _analyzedAddresses = [NSMutableSet set];
    }
    return self;
}

- (NSArray<DetectedFunction *> *)functions {
    return [self.mutableFunctions copy];
}

- (NSArray<CrossReference *> *)crossReferences {
    return [self.mutableXRefs copy];
}

- (NSDictionary<NSNumber *, DetectedFunction *> *)functionMap {
    return [self.mutableFunctionMap copy];
}

#pragma mark - Main Analysis

- (void)analyze {
    [self analyzeWithProgressBlock:nil];
}

- (void)analyzeWithProgressBlock:(void (^)(float progress, NSString *message))progressBlock {
    // Phase 1: Use MachO symbol table for initial function list (if available)
    if (self.machOParser && self.machOParser.symbols.count > 0) {
        if (progressBlock) {
            progressBlock(0.1, [NSString stringWithFormat:@"Loading %lu symbols from Mach-O...",
                              (unsigned long)self.machOParser.symbols.count]);
        }

        NSUInteger functionCount = 0;
        for (MachOSymbol *symbol in self.machOParser.symbols) {
            if (symbol.isFunction && symbol.address >= self.baseAddress) {
                DetectedFunction *func = [[DetectedFunction alloc] init];
                func.startAddress = symbol.address;
                func.name = symbol.name;

                // Mark as analyzed to avoid duplicate detection
                [self.analyzedAddresses addObject:@(symbol.address)];
                [self.mutableFunctions addObject:func];
                [self.mutableFunctionMap setObject:func forKey:@(symbol.address)];
                functionCount++;
            }
        }

        if (progressBlock) {
            progressBlock(0.15, [NSString stringWithFormat:@"Loaded %lu functions from symbols",
                              (unsigned long)functionCount]);
        }
    }

    // Phase 2: Analyze the entire binary with progress reporting (for functions without symbols)
    NSUInteger totalBytes = self.binaryData.length;
    NSUInteger processedBytes = 0;

    // For large files, analyze in chunks
    NSUInteger chunkSize = 10 * 1024 * 1024; // 10MB chunks
    BOOL isLargeFile = (totalBytes > 50 * 1024 * 1024); // >50MB = large

    if (isLargeFile) {
        NSLog(@"Large file detected (%.2f MB) - using chunked analysis", totalBytes / 1024.0 / 1024.0);

        // Process in chunks
        for (NSUInteger offset = 0; offset < totalBytes; offset += chunkSize) {
            NSUInteger remainingBytes = totalBytes - offset;
            NSUInteger currentChunkSize = MIN(chunkSize, remainingBytes);

            NSRange chunkRange = NSMakeRange(offset, currentChunkSize);
            [self analyzeFunctionsInSection:chunkRange];

            processedBytes += currentChunkSize;
            float progress = (float)processedBytes / (float)totalBytes;

            if (progressBlock) {
                NSString *message = [NSString stringWithFormat:@"Analyzing functions... %.0f%% (%lu/%lu MB)",
                                    progress * 100,
                                    processedBytes / (1024 * 1024),
                                    totalBytes / (1024 * 1024)];
                progressBlock(progress, message);
            }
        }
    } else {
        // Small file - analyze all at once
        NSRange fullRange = NSMakeRange(0, totalBytes);
        [self analyzeFunctionsInSection:fullRange];

        if (progressBlock) {
            progressBlock(1.0, @"Function analysis complete");
        }
    }

    // Build cross-references after all functions are detected
    if (progressBlock) {
        progressBlock(0.9, @"Building cross-references...");
    }

    [self buildCrossReferences];

    if (progressBlock) {
        progressBlock(1.0, [NSString stringWithFormat:@"Complete! Found %lu functions", (unsigned long)self.mutableFunctions.count]);
    }

    NSLog(@"Function Analysis Complete: Found %lu functions", (unsigned long)self.mutableFunctions.count);
}

- (void)analyzeFunctionsInSection:(NSRange)section {
    const uint8_t *bytes = (const uint8_t *)[self.binaryData bytes];

    // Scan through the section looking for function prologues
    for (NSUInteger offset = section.location; offset < section.location + section.length - 4; offset += 4) {
        uint64_t address = self.baseAddress + offset;

        // Skip if already analyzed
        if ([self.analyzedAddresses containsObject:@(address)]) {
            continue;
        }

        // Check for function prologue
        if ([self isFunctionPrologueAtOffset:offset]) {
            DetectedFunction *function = [self analyzeFunctionAtOffset:offset];
            if (function) {
                [self.mutableFunctions addObject:function];
                [self.mutableFunctionMap setObject:function forKey:@(function.startAddress)];

                // Mark all addresses in this function as analyzed
                for (uint64_t addr = function.startAddress; addr < function.endAddress; addr += 4) {
                    [self.analyzedAddresses addObject:@(addr)];
                }
            }
        }
    }
}

#pragma mark - Function Detection

- (BOOL)isFunctionPrologueAtOffset:(NSUInteger)offset {
    if (offset + 8 > self.binaryData.length) {
        return NO;
    }

    const uint8_t *bytes = (const uint8_t *)[self.binaryData bytes];
    uint32_t instr1 = *(uint32_t *)(bytes + offset);
    uint32_t instr2 = *(uint32_t *)(bytes + offset + 4);

    // Common ARM64 function prologues:

    // 1. STP X29, X30, [SP, #-0x??]!  (0xA9BF??FD pattern)
    //    Saves frame pointer (X29) and link register (X30)
    if ((instr1 & 0xFFC003E0) == 0xA9800000) {
        uint32_t rt = instr1 & 0x1F;
        uint32_t rt2 = (instr1 >> 10) & 0x1F;
        if (rt == 29 && rt2 == 30) {  // X29, X30
            return YES;
        }
    }

    // 2. SUB SP, SP, #0x??  (0xD10??3FF or 0xD14??3FF)
    //    Allocates stack space
    if ((instr1 & 0xFF8003FF) == 0xD10003FF || (instr1 & 0xFF8003FF) == 0xD14003FF) {
        return YES;
    }

    // 3. STP X??, X??, [SP, #-0x??]! followed by STP X29, X30
    if ((instr1 & 0xFFC00000) == 0xA9800000 && (instr2 & 0xFFC003E0) == 0xA9800000) {
        uint32_t rt2_1 = instr2 & 0x1F;
        uint32_t rt2_2 = (instr2 >> 10) & 0x1F;
        if (rt2_1 == 29 && rt2_2 == 30) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)isFunctionEpilogueAtOffset:(NSUInteger)offset {
    if (offset + 4 > self.binaryData.length) {
        return NO;
    }

    const uint8_t *bytes = (const uint8_t *)[self.binaryData bytes];
    uint32_t instr = *(uint32_t *)(bytes + offset);

    // RET instruction (0xD65F03C0)
    if (instr == 0xD65F03C0) {
        return YES;
    }

    // RET X?? (0xD65F0000 | (rn << 5))
    if ((instr & 0xFFFFFC1F) == 0xD65F0000) {
        return YES;
    }

    return NO;
}

- (nullable DetectedFunction *)analyzeFunctionAtOffset:(NSUInteger)startOffset {
    DetectedFunction *function = [[DetectedFunction alloc] init];
    function.startAddress = self.baseAddress + startOffset;

    const uint8_t *bytes = (const uint8_t *)[self.binaryData bytes];
    NSUInteger currentOffset = startOffset;
    NSUInteger instructionCount = 0;

    // Scan forward until we find a RET or reach max function size
    NSUInteger maxFunctionSize = 0x10000;  // 64KB max
    BOOL foundEnd = NO;

    while (currentOffset < self.binaryData.length - 4 &&
           (currentOffset - startOffset) < maxFunctionSize) {

        uint64_t currentAddress = self.baseAddress + currentOffset;
        uint32_t instr = *(uint32_t *)(bytes + currentOffset);

        instructionCount++;

        // Check for function epilogue (RET)
        if ([self isFunctionEpilogueAtOffset:currentOffset]) {
            function.endAddress = currentAddress + 4;
            foundEnd = YES;
            break;
        }

        // Check for unconditional branch that might end the function
        if ((instr & 0xFC000000) == 0x14000000) {  // B instruction
            // This might be a tail call
            function.endAddress = currentAddress + 4;
            foundEnd = YES;
            break;
        }

        // Analyze instruction for calls and references
        [self analyzeInstructionForReferences:instr
                                    atAddress:currentAddress
                                   inFunction:function];

        currentOffset += 4;
    }

    if (!foundEnd) {
        function.endAddress = self.baseAddress + currentOffset;
    }

    function.instructionCount = instructionCount;

    // Validate function (must be at least 1 instruction)
    if (function.instructionCount == 0) {
        return nil;
    }

    return function;
}

#pragma mark - Reference Analysis

- (void)analyzeInstructionForReferences:(uint32_t)instr
                              atAddress:(uint64_t)address
                             inFunction:(DetectedFunction *)function {

    // BL (Branch with Link) - function call
    if ((instr & 0xFC000000) == 0x94000000) {
        int32_t imm26 = (instr & 0x03FFFFFF);
        if (imm26 & 0x02000000) {
            imm26 |= 0xFC000000;  // Sign extend
        }
        int64_t offset = (int64_t)imm26 << 2;
        uint64_t targetAddress = address + offset;

        [function.callsTo addObject:@(targetAddress)];
    }

    // BLR (Branch with Link Register) - indirect call
    else if ((instr & 0xFFFFFC1F) == 0xD63F0000) {
        // Indirect call - can't determine target statically
    }

    // ADRP + ADD/LDR pattern for loading addresses (common for string refs)
    else if ((instr & 0x9F000000) == 0x90000000) {  // ADRP
        // This loads a page address - often followed by ADD or LDR for full address
        // We'll handle this in a more complete implementation
    }
}

- (void)buildCrossReferences {
    // Build reverse call graph and create XREF entries

    // First, build calledFrom relationships
    for (DetectedFunction *function in self.mutableFunctions) {
        for (NSNumber *targetAddr in function.callsTo) {
            uint64_t target = [targetAddr unsignedLongLongValue];
            DetectedFunction *targetFunc = [self functionAtAddress:target];

            if (targetFunc) {
                [targetFunc.calledFrom addObject:@(function.startAddress)];
            }

            // Create XREF entry
            CrossReference *xref = [[CrossReference alloc] init];
            xref.fromAddress = function.startAddress;
            xref.toAddress = target;
            xref.type = @"call";
            xref.context = [NSString stringWithFormat:@"%@ → %@",
                          function.displayName,
                          targetFunc ? targetFunc.displayName : [NSString stringWithFormat:@"sub_%llx", target]];
            [self.mutableXRefs addObject:xref];
        }
    }
}

#pragma mark - Queries

- (nullable DetectedFunction *)functionAtAddress:(uint64_t)address {
    // Try exact match first
    DetectedFunction *exactMatch = self.mutableFunctionMap[@(address)];
    if (exactMatch) {
        return exactMatch;
    }

    // Check if address is within any function
    for (DetectedFunction *function in self.mutableFunctions) {
        if (address >= function.startAddress && address < function.endAddress) {
            return function;
        }
    }

    return nil;
}

- (NSArray<DetectedFunction *> *)functionsCallingAddress:(uint64_t)address {
    NSMutableArray *result = [NSMutableArray array];

    for (DetectedFunction *function in self.mutableFunctions) {
        if ([function.callsTo containsObject:@(address)]) {
            [result addObject:function];
        }
    }

    return result;
}

- (NSArray<DetectedFunction *> *)functionsCalledByAddress:(uint64_t)address {
    NSMutableArray *result = [NSMutableArray array];

    DetectedFunction *function = [self functionAtAddress:address];
    if (function) {
        for (NSNumber *targetAddr in function.callsTo) {
            DetectedFunction *targetFunc = [self functionAtAddress:[targetAddr unsignedLongLongValue]];
            if (targetFunc) {
                [result addObject:targetFunc];
            }
        }
    }

    return result;
}

- (NSArray<CrossReference *> *)xrefsToAddress:(uint64_t)address {
    NSMutableArray *result = [NSMutableArray array];

    for (CrossReference *xref in self.mutableXRefs) {
        if (xref.toAddress == address) {
            [result addObject:xref];
        }
    }

    return result;
}

- (NSArray<CrossReference *> *)xrefsFromAddress:(uint64_t)address {
    NSMutableArray *result = [NSMutableArray array];

    for (CrossReference *xref in self.mutableXRefs) {
        if (xref.fromAddress == address) {
            [result addObject:xref];
        }
    }

    return result;
}

#pragma mark - ObjC Integration

- (void)linkObjCMethod:(NSString *)methodName
             className:(NSString *)className
             toAddress:(uint64_t)address {

    DetectedFunction *function = [self functionAtAddress:address];
    if (function) {
        function.isObjCMethod = YES;
        function.objcClassName = className;
        function.objcMethodName = methodName;
        function.name = [NSString stringWithFormat:@"-[%@ %@]", className, methodName];
    }
}

@end
