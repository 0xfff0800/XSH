//
//  SymbolResolver.h
//  iSH - Symbol and Address Resolution
//
//  Resolves addresses to symbols, strings, class names, and method names
//

#import <Foundation/Foundation.h>

@class MachOParser;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ResolvedType) {
    ResolvedTypeUnknown,
    ResolvedTypeFunction,
    ResolvedTypeString,
    ResolvedTypeObjCMethod,
    ResolvedTypeObjCClass,
    ResolvedTypeObjCSelector,
    ResolvedTypeData,
};

@interface ResolvedAddress : NSObject

@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) ResolvedType type;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong, nullable) NSString *comment;

// For ObjC methods
@property (nonatomic, strong, nullable) NSString *className;
@property (nonatomic, strong, nullable) NSString *methodName;

@end

@interface SymbolResolver : NSObject

@property (nonatomic, weak, nullable) MachOParser *parser;

- (instancetype)initWithParser:(MachOParser *)parser;

// Main resolution
- (nullable ResolvedAddress *)resolveAddress:(uint64_t)address;

// Specific queries
- (nullable NSString *)functionNameAtAddress:(uint64_t)address;
- (nullable NSString *)stringAtAddress:(uint64_t)address;
- (nullable NSString *)objcMethodAtAddress:(uint64_t)address;
- (nullable NSString *)formatAddress:(uint64_t)address;

// Get comment for instruction operand
- (nullable NSString *)commentForAddress:(uint64_t)address;

@end

NS_ASSUME_NONNULL_END
