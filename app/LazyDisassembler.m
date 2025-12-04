//
//  LazyDisassembler.m
//  iSH - Lazy/On-Demand Disassembly Implementation
//

#import "LazyDisassembler.h"
#import "FunctionAnalyzer.h"  // For DetectedFunction
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

@implementation DisassemblyCache
@end

@implementation LazyDisassembler

- (instancetype)initWithBinaryData:(NSData *)data baseAddress:(uint64_t)baseAddress {
    if (self = [super init]) {
        _binaryData = data;
        _baseAddress = baseAddress;
        _decoder = [[ARM64InstructionDecoder alloc] init];
        _cache = [NSMutableDictionary dictionary];
        _maxCacheSize = 1000;  // Cache up to 1000 blocks
        _cacheHits = 0;
        _cacheMisses = 0;
    }
    return self;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL baseAddress:(uint64_t)baseAddress {
    if (self = [super init]) {
        // Use memory mapping for large files
        NSError *error = nil;
        _binaryData = [NSData dataWithContentsOfURL:fileURL
                                            options:NSDataReadingMappedIfSafe
                                              error:&error];

        if (!_binaryData) {
            NSLog(@"Failed to map file: %@", error);
            return nil;
        }

        _baseAddress = baseAddress;
        _decoder = [[ARM64InstructionDecoder alloc] init];
        _cache = [NSMutableDictionary dictionary];
        _maxCacheSize = 1000;
        _cacheHits = 0;
        _cacheMisses = 0;
    }
    return self;
}

#pragma mark - On-Demand Disassembly

- (ARM64Instruction *)disassembleInstructionAtAddress:(uint64_t)address {
    if (address < self.baseAddress) return nil;

    uint64_t offset = address - self.baseAddress;
    if (offset + 4 > self.binaryData.length) return nil;

    const uint8_t *bytes = (const uint8_t *)[self.binaryData bytes];
    const uint8_t *instrBytes = bytes + offset;

    return [self.decoder decodeInstructionAtAddress:address
                                               data:instrBytes
                                             length:4];
}

- (NSArray<ARM64Instruction *> *)disassembleRange:(NSRange)range startAddress:(uint64_t)startAddress {
    // Check cache first
    NSNumber *cacheKey = @(startAddress);
    DisassemblyCache *cached = self.cache[cacheKey];

    if (cached) {
        cached.lastAccess = [NSDate timeIntervalSinceReferenceDate];
        self.cacheHits++;
        return cached.instructions;
    }

    self.cacheMisses++;

    // Disassemble
    NSMutableArray<ARM64Instruction *> *instructions = [NSMutableArray array];

    if (range.location + range.length > self.binaryData.length) {
        return instructions;
    }

    const uint8_t *bytes = (const uint8_t *)[self.binaryData bytes];

    for (NSUInteger i = 0; i < range.length; i += 4) {
        uint64_t addr = startAddress + i;
        const uint8_t *instrBytes = bytes + range.location + i;

        ARM64Instruction *inst = [self.decoder decodeInstructionAtAddress:addr
                                                                     data:instrBytes
                                                                   length:4];
        if (inst) {
            [instructions addObject:inst];
        }
    }

    // Cache result
    DisassemblyCache *cacheEntry = [[DisassemblyCache alloc] init];
    cacheEntry.address = startAddress;
    cacheEntry.instructions = [instructions copy];
    cacheEntry.lastAccess = [NSDate timeIntervalSinceReferenceDate];

    self.cache[cacheKey] = cacheEntry;

    // Evict old entries if cache is too large
    if (self.cache.count > self.maxCacheSize) {
        [self evictOldEntries];
    }

    return instructions;
}

- (NSArray<ARM64Instruction *> *)disassembleFunction:(DetectedFunction *)function {
    if (function.startAddress < self.baseAddress) return @[];

    uint64_t offset = function.startAddress - self.baseAddress;
    NSUInteger length = MIN(function.size, 4096);  // Limit to 4KB per function

    NSRange range = NSMakeRange(offset, length);
    return [self disassembleRange:range startAddress:function.startAddress];
}

#pragma mark - Quick Analysis (بدون تفكيك كامل)

- (NSArray<NSNumber *> *)findFunctionStarts {
    // البحث السريع عن بدايات الدوال بدون تفكيك كامل
    NSMutableArray<NSNumber *> *functionStarts = [NSMutableArray array];

    const uint8_t *bytes = (const uint8_t *)[self.binaryData bytes];
    NSUInteger length = self.binaryData.length;

    // نبحث عن patterns شائعة لبداية الدوال ARM64:
    // STP X29, X30, [SP, #-xxx]! - Function prologue
    // SUB SP, SP, #xxx            - Stack allocation

    for (NSUInteger i = 0; i < length - 4; i += 4) {
        uint32_t instruction = *(uint32_t *)(bytes + i);

        // Check for STP X29, X30 (frame pointer setup)
        // Pattern: 0xA9Bxxxxx (STP with pre-index)
        if ((instruction & 0xFFC00000) == 0xA9800000) {
            uint64_t address = self.baseAddress + i;
            [functionStarts addObject:@(address)];
        }

        // Also check for SUB SP, SP pattern
        // Pattern: 0xD10xxxxx
        else if ((instruction & 0xFF800000) == 0xD1000000) {
            // Check if previous instruction was also a function start pattern
            if (i >= 4) {
                uint32_t prevInstr = *(uint32_t *)(bytes + i - 4);
                if ((prevInstr & 0xFFC00000) != 0xA9800000) {
                    uint64_t address = self.baseAddress + i;
                    [functionStarts addObject:@(address)];
                }
            }
        }
    }

    return functionStarts;
}

- (NSArray<NSString *> *)extractStringsQuick {
    // استخراج سريع للنصوص بدون معالجة كاملة
    NSMutableArray<NSString *> *strings = [NSMutableArray array];

    const char *bytes = (const char *)[self.binaryData bytes];
    NSUInteger length = self.binaryData.length;

    NSMutableString *currentString = nil;
    NSUInteger stringStart = 0;

    for (NSUInteger i = 0; i < length; i++) {
        char c = bytes[i];

        // Start of potential string
        if (c >= 32 && c <= 126) {  // Printable ASCII
            if (!currentString) {
                currentString = [NSMutableString string];
                stringStart = i;
            }
            [currentString appendFormat:@"%c", c];
        }
        // End of string
        else if (c == 0 && currentString) {
            // Only keep strings >= 4 characters
            if (currentString.length >= 4) {
                [strings addObject:[currentString copy]];
            }
            currentString = nil;

            // Limit results to avoid memory issues
            if (strings.count >= 50000) break;
        }
        // Invalid character
        else {
            currentString = nil;
        }
    }

    return strings;
}

#pragma mark - Cache Management

- (void)clearCache {
    [self.cache removeAllObjects];
    self.cacheHits = 0;
    self.cacheMisses = 0;
}

- (void)evictOldEntries {
    // Remove oldest 20% of cache entries
    NSUInteger entriesToRemove = self.cache.count / 5;

    // Sort by last access time
    NSArray *sortedKeys = [self.cache keysSortedByValueUsingComparator:^NSComparisonResult(DisassemblyCache *obj1, DisassemblyCache *obj2) {
        if (obj1.lastAccess < obj2.lastAccess) return NSOrderedAscending;
        if (obj1.lastAccess > obj2.lastAccess) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    // Remove oldest entries
    for (NSUInteger i = 0; i < entriesToRemove && i < sortedKeys.count; i++) {
        [self.cache removeObjectForKey:sortedKeys[i]];
    }
}

- (NSDictionary *)cacheStatistics {
    NSUInteger totalRequests = self.cacheHits + self.cacheMisses;
    double hitRate = totalRequests > 0 ? (double)self.cacheHits / totalRequests : 0.0;

    return @{
        @"cacheSize": @(self.cache.count),
        @"maxCacheSize": @(self.maxCacheSize),
        @"cacheHits": @(self.cacheHits),
        @"cacheMisses": @(self.cacheMisses),
        @"hitRate": @(hitRate * 100.0)  // Percentage
    };
}

@end
