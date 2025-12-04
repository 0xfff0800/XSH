//
//  FunctionAnalyzer.h
//  iSH - Function Detection and Analysis
//
//  Detects function boundaries, analyzes call graphs, and tracks cross-references
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ARM64InstructionDecoder;

@interface DetectedFunction : NSObject

@property (nonatomic, assign) uint64_t startAddress;
@property (nonatomic, assign) uint64_t endAddress;
@property (nonatomic, strong, nullable) NSString *name;
@property (nonatomic, assign) NSUInteger instructionCount;
@property (nonatomic, assign) BOOL isObjCMethod;
@property (nonatomic, strong, nullable) NSString *objcClassName;
@property (nonatomic, strong, nullable) NSString *objcMethodName;

// Call information
@property (nonatomic, strong) NSMutableArray<NSNumber *> *callsTo;      // Addresses this function calls
@property (nonatomic, strong) NSMutableArray<NSNumber *> *calledFrom;   // Addresses that call this function

// String references
@property (nonatomic, strong) NSMutableArray<NSString *> *stringRefs;

// Computed properties
@property (nonatomic, readonly) NSUInteger size;
@property (nonatomic, readonly) NSString *displayName;

@end

@interface CrossReference : NSObject

@property (nonatomic, assign) uint64_t fromAddress;
@property (nonatomic, assign) uint64_t toAddress;
@property (nonatomic, strong) NSString *type;  // "call", "jump", "data", "string"
@property (nonatomic, strong, nullable) NSString *context;

@end

@class MachOParser;

@interface FunctionAnalyzer : NSObject

@property (nonatomic, strong) NSData *binaryData;
@property (nonatomic, assign) uint64_t baseAddress;
@property (nonatomic, strong) ARM64InstructionDecoder *decoder;
@property (nonatomic, weak, nullable) MachOParser *machOParser;  // For symbol-based function detection

// Results
@property (nonatomic, strong, readonly) NSArray<DetectedFunction *> *functions;
@property (nonatomic, strong, readonly) NSArray<CrossReference *> *crossReferences;
@property (nonatomic, strong, readonly) NSDictionary<NSNumber *, DetectedFunction *> *functionMap;

- (instancetype)initWithBinaryData:(NSData *)data baseAddress:(uint64_t)baseAddr;
- (instancetype)initWithBinaryData:(NSData *)data baseAddress:(uint64_t)baseAddr machOParser:(nullable MachOParser *)parser;

// Analysis
- (void)analyze;
- (void)analyzeWithProgressBlock:(void (^ _Nullable)(float progress, NSString *message))progressBlock;
- (void)analyzeFunctionsInSection:(NSRange)section;
- (void)buildCrossReferences;

// Queries
- (nullable DetectedFunction *)functionAtAddress:(uint64_t)address;
- (NSArray<DetectedFunction *> *)functionsCallingAddress:(uint64_t)address;
- (NSArray<DetectedFunction *> *)functionsCalledByAddress:(uint64_t)address;
- (NSArray<CrossReference *> *)xrefsToAddress:(uint64_t)address;
- (NSArray<CrossReference *> *)xrefsFromAddress:(uint64_t)address;

// ObjC Integration
- (void)linkObjCMethod:(NSString *)methodName
             className:(NSString *)className
             toAddress:(uint64_t)address;

@end

NS_ASSUME_NONNULL_END
