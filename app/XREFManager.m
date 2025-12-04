//
//  XREFManager.m
//  iSH - Cross-Reference Manager Implementation
//

#import "XREFManager.h"
#import "FunctionAnalyzer.h"

@implementation XREF

- (NSString *)displayName {
    return [NSString stringWithFormat:@"sub_%llx+%llu", self.fromAddress, self.offset];
}

- (NSString *)typeSymbol {
    switch (self.type) {
        case XREFTypeCall:
            return @"→";  // Call
        case XREFTypeJump:
            return @"⇒";  // Jump
        case XREFTypeDataRead:
            return @"◀";  // Load
        case XREFTypeDataWrite:
            return @"▶";  // Store
        case XREFTypeStringRef:
            return @"📝"; // String
        case XREFTypeCodeRef:
            return @"⚡"; // Code ref
        default:
            return @"•";
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ XREF: 0x%llx %@ 0x%llx (%@)>",
            [self typeSymbol],
            self.fromAddress,
            self.type == XREFTypeCall ? @"calls" : @"refs",
            self.toAddress,
            self.instruction ?: @""];
}

@end

@implementation XREFManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _incomingRefs = [NSMutableDictionary dictionary];
        _outgoingRefs = [NSMutableDictionary dictionary];
        _navigationHistory = [NSMutableArray array];
        _currentHistoryIndex = -1;
    }
    return self;
}

#pragma mark - Add XREFs

- (void)addXREF:(XREF *)xref {
    // Add to incoming refs (target → sources)
    NSNumber *toKey = @(xref.toAddress);
    if (!self.incomingRefs[toKey]) {
        self.incomingRefs[toKey] = [NSMutableArray array];
    }
    [self.incomingRefs[toKey] addObject:xref];

    // Add to outgoing refs (source → targets)
    NSNumber *fromKey = @(xref.fromAddress);
    if (!self.outgoingRefs[fromKey]) {
        self.outgoingRefs[fromKey] = [NSMutableArray array];
    }
    [self.outgoingRefs[fromKey] addObject:xref];
}

- (void)addXREFFrom:(uint64_t)from
                 to:(uint64_t)to
               type:(XREFType)type
        instruction:(NSString *)instruction
             offset:(uint64_t)offset {
    XREF *xref = [[XREF alloc] init];
    xref.fromAddress = from;
    xref.toAddress = to;
    xref.type = type;
    xref.instruction = instruction;
    xref.offset = offset;

    [self addXREF:xref];
}

#pragma mark - Query XREFs

- (NSArray<XREF *> *)getIncomingXREFs:(uint64_t)address {
    NSNumber *key = @(address);
    return self.incomingRefs[key] ?: @[];
}

- (NSArray<XREF *> *)getOutgoingXREFs:(uint64_t)address {
    NSNumber *key = @(address);
    return self.outgoingRefs[key] ?: @[];
}

#pragma mark - Navigation (Back/Forward Stack)

- (void)navigateTo:(uint64_t)address {
    // Remove any forward history (we're branching to a new path)
    if (self.currentHistoryIndex < (NSInteger)self.navigationHistory.count - 1) {
        NSRange rangeToRemove = NSMakeRange(self.currentHistoryIndex + 1,
                                           self.navigationHistory.count - self.currentHistoryIndex - 1);
        [self.navigationHistory removeObjectsInRange:rangeToRemove];
    }

    // Add new address
    [self.navigationHistory addObject:@(address)];
    self.currentHistoryIndex = (NSInteger)self.navigationHistory.count - 1;
}

- (BOOL)canGoBack {
    return self.currentHistoryIndex > 0;
}

- (BOOL)canGoForward {
    return self.currentHistoryIndex < (NSInteger)self.navigationHistory.count - 1;
}

- (uint64_t)goBack {
    if (![self canGoBack]) {
        return 0;
    }

    self.currentHistoryIndex--;
    return [self.navigationHistory[self.currentHistoryIndex] unsignedLongLongValue];
}

- (uint64_t)goForward {
    if (![self canGoForward]) {
        return 0;
    }

    self.currentHistoryIndex++;
    return [self.navigationHistory[self.currentHistoryIndex] unsignedLongLongValue];
}

#pragma mark - Statistics

- (NSUInteger)totalXREFCount {
    NSUInteger total = 0;
    for (NSArray *refs in self.incomingRefs.allValues) {
        total += refs.count;
    }
    return total;
}

- (NSDictionary<NSString *, NSNumber *> *)statistics {
    NSUInteger calls = 0, jumps = 0, dataReads = 0, dataWrites = 0, stringRefs = 0, codeRefs = 0;

    for (NSArray<XREF *> *refs in self.incomingRefs.allValues) {
        for (XREF *xref in refs) {
            switch (xref.type) {
                case XREFTypeCall:      calls++;      break;
                case XREFTypeJump:      jumps++;      break;
                case XREFTypeDataRead:  dataReads++;  break;
                case XREFTypeDataWrite: dataWrites++; break;
                case XREFTypeStringRef: stringRefs++; break;
                case XREFTypeCodeRef:   codeRefs++;   break;
            }
        }
    }

    return @{
        @"calls": @(calls),
        @"jumps": @(jumps),
        @"dataReads": @(dataReads),
        @"dataWrites": @(dataWrites),
        @"stringRefs": @(stringRefs),
        @"codeRefs": @(codeRefs),
        @"total": @(self.totalXREFCount)
    };
}

#pragma mark - Clear

- (void)clear {
    [self.incomingRefs removeAllObjects];
    [self.outgoingRefs removeAllObjects];
    [self.navigationHistory removeAllObjects];
    self.currentHistoryIndex = -1;
}

@end
