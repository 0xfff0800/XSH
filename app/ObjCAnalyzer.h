//
//  ObjCAnalyzer.h
//  iSH - Real Objective-C Runtime Analyzer
//
//  Parses Objective-C classes, methods, properties from Mach-O binaries
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCMethod : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *signature;
@property (nonatomic, assign) uint64_t implementation;
@property (nonatomic, assign) BOOL isClassMethod;
@end

@interface ObjCProperty : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *attributes;
@end

@interface ObjCIvar : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, assign) uint32_t offset;
@end

@interface ObjCClass : NSObject
@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong, nullable) NSString *superClassName;
@property (nonatomic, strong) NSMutableArray<ObjCMethod *> *instanceMethods;
@property (nonatomic, strong) NSMutableArray<ObjCMethod *> *classMethods;
@property (nonatomic, strong) NSMutableArray<ObjCProperty *> *properties;
@property (nonatomic, strong) NSMutableArray<ObjCIvar *> *ivars;
@property (nonatomic, strong) NSMutableArray<NSString *> *protocols;
@property (nonatomic, assign) uint64_t classAddress;
@property (nonatomic, assign) uint32_t instanceSize;
@end

@interface ObjCProtocol : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSMutableArray<ObjCMethod *> *requiredMethods;
@property (nonatomic, strong) NSMutableArray<ObjCMethod *> *optionalMethods;
@end

@interface ObjCCategory : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong) NSMutableArray<ObjCMethod *> *instanceMethods;
@property (nonatomic, strong) NSMutableArray<ObjCMethod *> *classMethods;
@end

@interface ObjCAnalyzer : NSObject

- (instancetype)initWithBinaryData:(NSData *)data baseAddress:(uint64_t)baseAddr;

// Main analysis
- (void)analyze;

// Results
@property (nonatomic, strong, readonly) NSArray<ObjCClass *> *classes;
@property (nonatomic, strong, readonly) NSArray<ObjCProtocol *> *protocols;
@property (nonatomic, strong, readonly) NSArray<ObjCCategory *> *categories;
@property (nonatomic, strong, readonly) NSDictionary<NSString *, ObjCClass *> *classMap;

// Search
- (NSArray<ObjCClass *> *)searchClassesByName:(NSString *)query;
- (NSArray<ObjCMethod *> *)searchMethodsByName:(NSString *)query;

@end

NS_ASSUME_NONNULL_END
