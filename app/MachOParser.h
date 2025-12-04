//
//  MachOParser.h
//  iSH - Mach-O Binary Parser
//
//  Parses Mach-O files to extract symbols, strings, and metadata
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Segment information
@interface MachOSegment : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) uint64_t vmaddr;
@property (nonatomic, assign) uint64_t vmsize;
@property (nonatomic, assign) uint64_t fileoff;
@property (nonatomic, assign) uint64_t filesize;
@end

// Section information
@interface MachOSection : NSObject
@property (nonatomic, strong) NSString *sectname;
@property (nonatomic, strong) NSString *segname;
@property (nonatomic, assign) uint64_t addr;
@property (nonatomic, assign) uint64_t size;
@property (nonatomic, assign) uint32_t offset;
@property (nonatomic, strong, nullable) NSData *data;
@end

// Symbol entry
@interface MachOSymbol : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) uint8_t type;
@property (nonatomic, assign) BOOL isExternal;
@property (nonatomic, assign) BOOL isFunction;
@end

// Objective-C Class
@interface ObjCClassInfo : NSObject
@property (nonatomic, strong) NSString *className;
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, strong, nullable) NSString *superClassName;
@property (nonatomic, strong) NSMutableArray<NSString *> *methods;
@property (nonatomic, strong) NSMutableArray<NSString *> *properties;
@end

// Objective-C Method
@interface ObjCMethodInfo : NSObject
@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong) NSString *methodName;
@property (nonatomic, assign) uint64_t implementation;
@property (nonatomic, assign) BOOL isClassMethod;
@end

@interface MachOParser : NSObject

@property (nonatomic, strong, readonly) NSData *binaryData;
@property (nonatomic, assign, readonly) uint64_t baseAddress;

// Parsed data
@property (nonatomic, strong, readonly) NSArray<MachOSegment *> *segments;
@property (nonatomic, strong, readonly) NSArray<MachOSection *> *sections;
@property (nonatomic, strong, readonly) NSArray<MachOSymbol *> *symbols;
@property (nonatomic, strong, readonly) NSArray<ObjCClassInfo *> *objcClasses;
@property (nonatomic, strong, readonly) NSArray<ObjCMethodInfo *> *objcMethods;

// Lookup tables (address -> object)
@property (nonatomic, strong, readonly) NSDictionary<NSNumber *, MachOSymbol *> *symbolsByAddress;
@property (nonatomic, strong, readonly) NSDictionary<NSNumber *, NSString *> *stringsByAddress;
@property (nonatomic, strong, readonly) NSDictionary<NSNumber *, ObjCMethodInfo *> *methodsByAddress;

- (instancetype)initWithData:(NSData *)data baseAddress:(uint64_t)baseAddr;

// Main parsing
- (BOOL)parse;

// Queries
- (nullable MachOSymbol *)symbolAtAddress:(uint64_t)address;
- (nullable NSString *)stringAtAddress:(uint64_t)address;
- (nullable ObjCMethodInfo *)objcMethodAtAddress:(uint64_t)address;
- (nullable MachOSection *)sectionContainingAddress:(uint64_t)address;
- (nullable MachOSection *)sectionNamed:(NSString *)name;

// Helpers
- (uint64_t)fileOffsetForVirtualAddress:(uint64_t)vmaddr;
- (uint64_t)virtualAddressForFileOffset:(uint64_t)fileoff;

@end

NS_ASSUME_NONNULL_END
