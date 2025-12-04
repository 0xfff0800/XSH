//
//  LazyDisassembler.h
//  iSH - Lazy/On-Demand Disassembly System
//
//  High-performance disassembler for large binaries (like Hopper)
//  Features:
//  - Memory mapping (لا يحمل كل الملف في الذاكرة)
//  - Lazy loading (يفكك عند الطلب فقط)
//  - Caching (يحفظ النتائج)
//  - Background processing
//

#import <Foundation/Foundation.h>
#import "ARM64InstructionDecoder.h"

NS_ASSUME_NONNULL_BEGIN

// Forward declaration
@class DetectedFunction;

// Cache entry for disassembled code
@interface DisassemblyCache : NSObject
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, strong) NSArray<ARM64Instruction *> *instructions;
@property (nonatomic, assign) NSTimeInterval lastAccess;
@end

// Lazy Disassembler - يفكك عند الطلب فقط
@interface LazyDisassembler : NSObject

// Binary data (memory mapped)
@property (nonatomic, strong) NSData *binaryData;
@property (nonatomic, assign) uint64_t baseAddress;

// Decoder
@property (nonatomic, strong) ARM64InstructionDecoder *decoder;

// Cache settings
@property (nonatomic, assign) NSUInteger maxCacheSize;  // Max cached blocks
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, DisassemblyCache *> *cache;

// Statistics
@property (nonatomic, assign) NSUInteger cacheHits;
@property (nonatomic, assign) NSUInteger cacheMisses;

// Initialize
- (instancetype)initWithBinaryData:(NSData *)data baseAddress:(uint64_t)baseAddress;
- (instancetype)initWithFileURL:(NSURL *)fileURL baseAddress:(uint64_t)baseAddress;

// Disassemble on-demand (يفكك فقط ما تحتاجه)
- (ARM64Instruction * _Nullable)disassembleInstructionAtAddress:(uint64_t)address;
- (NSArray<ARM64Instruction *> *)disassembleRange:(NSRange)range startAddress:(uint64_t)startAddress;
- (NSArray<ARM64Instruction *> *)disassembleFunction:(DetectedFunction *)function;

// Quick analysis (بدون تفكيك كامل)
- (NSArray<NSNumber *> *)findFunctionStarts;  // يبحث عن بدايات الدوال فقط
- (NSArray<NSString *> *)extractStringsQuick; // يستخرج النصوص بسرعة

// Cache management
- (void)clearCache;
- (void)evictOldEntries;  // يحذف العناصر القديمة
- (NSDictionary *)cacheStatistics;

@end

NS_ASSUME_NONNULL_END
