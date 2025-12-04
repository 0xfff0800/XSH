//
//  PseudoCodeGenerator.h
//  iSH - Pseudo-Code Generator (Decompiler)
//
//  Converts ARM64 assembly to readable pseudo-C code
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ARM64Instruction, DetectedFunction, SymbolResolver, CFGBuilder, StackFrameTracker;

@interface PseudoCodeGenerator : NSObject

// String map for resolving addresses to string literals
@property (nonatomic, strong) NSDictionary<NSNumber *, NSString *> *stringMap;

// New architecture components
@property (nonatomic, weak, nullable) SymbolResolver *symbolResolver;
@property (nonatomic, weak, nullable) CFGBuilder *cfgBuilder;

// Generate pseudo-code for a function
- (NSString *)generatePseudoCodeForFunction:(DetectedFunction *)function
                                 binaryData:(NSData *)binaryData
                                baseAddress:(uint64_t)baseAddress;

// Generate pseudo-code for a range of instructions
- (NSString *)generatePseudoCodeForRange:(NSRange)range
                              binaryData:(NSData *)binaryData
                             baseAddress:(uint64_t)baseAddress;

// Build string map from binary data
- (void)buildStringMapFromBinaryData:(NSData *)binaryData baseAddress:(uint64_t)baseAddress;

@end

NS_ASSUME_NONNULL_END
