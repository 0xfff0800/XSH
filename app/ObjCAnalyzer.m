//
//  ObjCAnalyzer.m
//  iSH - Real Objective-C Runtime Analyzer Implementation
//

#import "ObjCAnalyzer.h"
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

// Objective-C Runtime Structures (64-bit)
struct objc_class_64 {
    uint64_t isa;
    uint64_t superclass;
    uint64_t cache;
    uint64_t vtable;
    uint64_t data;
};

struct objc_class_ro_64 {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
    uint32_t reserved;
    uint64_t ivarLayout;
    uint64_t name;
    uint64_t baseMethods;
    uint64_t baseProtocols;
    uint64_t ivars;
    uint64_t weakIvarLayout;
    uint64_t baseProperties;
};

struct objc_method_64 {
    uint64_t name;      // SEL
    uint64_t types;     // const char *
    uint64_t imp;       // IMP
};

struct objc_method_list_64 {
    uint32_t entsize;
    uint32_t count;
    // followed by objc_method_64 entries
};

struct objc_property_64 {
    uint64_t name;
    uint64_t attributes;
};

struct objc_property_list_64 {
    uint32_t entsize;
    uint32_t count;
    // followed by objc_property_64 entries
};

struct objc_ivar_64 {
    uint64_t offset;    // uint32_t *
    uint64_t name;      // const char *
    uint64_t type;      // const char *
    uint32_t alignment;
    uint32_t size;
};

struct objc_ivar_list_64 {
    uint32_t entsize;
    uint32_t count;
    // followed by objc_ivar_64 entries
};

struct objc_protocol_64 {
    uint64_t isa;
    uint64_t name;
    uint64_t protocols;
    uint64_t instanceMethods;
    uint64_t classMethods;
    uint64_t optionalInstanceMethods;
    uint64_t optionalClassMethods;
    uint64_t instanceProperties;
};

struct objc_category_64 {
    uint64_t name;
    uint64_t cls;
    uint64_t instanceMethods;
    uint64_t classMethods;
    uint64_t protocols;
    uint64_t instanceProperties;
};

@implementation ObjCMethod
@end

@implementation ObjCProperty
@end

@implementation ObjCIvar
@end

@implementation ObjCClass
- (instancetype)init {
    if (self = [super init]) {
        _instanceMethods = [NSMutableArray array];
        _classMethods = [NSMutableArray array];
        _properties = [NSMutableArray array];
        _ivars = [NSMutableArray array];
        _protocols = [NSMutableArray array];
    }
    return self;
}
@end

@implementation ObjCProtocol
- (instancetype)init {
    if (self = [super init]) {
        _requiredMethods = [NSMutableArray array];
        _optionalMethods = [NSMutableArray array];
    }
    return self;
}
@end

@implementation ObjCCategory
- (instancetype)init {
    if (self = [super init]) {
        _instanceMethods = [NSMutableArray array];
        _classMethods = [NSMutableArray array];
    }
    return self;
}
@end

@interface ObjCAnalyzer ()
@property (nonatomic, strong) NSData *binaryData;
@property (nonatomic, assign) uint64_t baseAddress;
@property (nonatomic, assign) uint64_t slide;
@property (nonatomic, strong) NSMutableArray<ObjCClass *> *mutableClasses;
@property (nonatomic, strong) NSMutableArray<ObjCProtocol *> *mutableProtocols;
@property (nonatomic, strong) NSMutableArray<ObjCCategory *> *mutableCategories;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ObjCClass *> *mutableClassMap;

// Section information
@property (nonatomic, assign) uint64_t classListOffset;
@property (nonatomic, assign) uint64_t classListSize;
@property (nonatomic, assign) uint64_t catListOffset;
@property (nonatomic, assign) uint64_t catListSize;
@property (nonatomic, assign) uint64_t protoListOffset;
@property (nonatomic, assign) uint64_t protoListSize;
@end

@implementation ObjCAnalyzer

- (instancetype)initWithBinaryData:(NSData *)data baseAddress:(uint64_t)baseAddr {
    if (self = [super init]) {
        _binaryData = data;
        _baseAddress = baseAddr;
        _slide = 0;
        _mutableClasses = [NSMutableArray array];
        _mutableProtocols = [NSMutableArray array];
        _mutableCategories = [NSMutableArray array];
        _mutableClassMap = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)analyze {
    if (!self.binaryData || self.binaryData.length < sizeof(struct mach_header_64)) {
        return;
    }

    // Parse Mach-O header and find __objc sections
    [self parseMachOHeader];

    // Parse classes
    if (self.classListOffset > 0) {
        [self parseClassList];
    }

    // Parse categories
    if (self.catListOffset > 0) {
        [self parseCategoryList];
    }

    // Parse protocols
    if (self.protoListOffset > 0) {
        [self parseProtocolList];
    }
}

- (void)parseMachOHeader {
    const uint8_t *bytes = self.binaryData.bytes;
    struct mach_header_64 *header = (struct mach_header_64 *)bytes;

    if (header->magic != MH_MAGIC_64) {
        return; // Not 64-bit Mach-O
    }

    // Parse load commands to find segments and sections
    uint64_t offset = sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (offset + sizeof(struct load_command) > self.binaryData.length) break;

        struct load_command *cmd = (struct load_command *)(bytes + offset);

        if (cmd->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)(bytes + offset);

            // Look for __DATA or __DATA_CONST segments
            if (strncmp(seg->segname, "__DATA", 6) == 0) {
                [self parseDataSegment:seg];
            }
        }

        offset += cmd->cmdsize;
    }
}

- (void)parseDataSegment:(struct segment_command_64 *)segment {
    const uint8_t *bytes = self.binaryData.bytes;
    uint64_t sectionOffset = (uint64_t)segment - (uint64_t)bytes + sizeof(struct segment_command_64);

    for (uint32_t i = 0; i < segment->nsects; i++) {
        if (sectionOffset + sizeof(struct section_64) > self.binaryData.length) break;

        struct section_64 *section = (struct section_64 *)(bytes + sectionOffset);

        // __objc_classlist
        if (strncmp(section->sectname, "__objc_classlist", 16) == 0) {
            self.classListOffset = section->offset;
            self.classListSize = section->size;
        }
        // __objc_catlist
        else if (strncmp(section->sectname, "__objc_catlist", 14) == 0) {
            self.catListOffset = section->offset;
            self.catListSize = section->size;
        }
        // __objc_protolist
        else if (strncmp(section->sectname, "__objc_protolist", 16) == 0) {
            self.protoListOffset = section->offset;
            self.protoListSize = section->size;
        }

        sectionOffset += sizeof(struct section_64);
    }
}

- (void)parseClassList {
    uint64_t count = self.classListSize / 8; // 8 bytes per pointer (64-bit)

    for (uint64_t i = 0; i < count; i++) {
        uint64_t classPointerOffset = self.classListOffset + (i * 8);
        if (classPointerOffset + 8 > self.binaryData.length) break;

        uint64_t classPointer = [self read64BitAtOffset:classPointerOffset];
        if (classPointer == 0) continue;

        ObjCClass *cls = [self parseClassAtPointer:classPointer];
        if (cls) {
            [self.mutableClasses addObject:cls];
            self.mutableClassMap[cls.className] = cls;
        }
    }
}

- (ObjCClass *)parseClassAtPointer:(uint64_t)pointer {
    uint64_t offset = [self pointerToFileOffset:pointer];
    if (offset == 0 || offset + sizeof(struct objc_class_64) > self.binaryData.length) {
        return nil;
    }

    ObjCClass *cls = [[ObjCClass alloc] init];
    cls.classAddress = pointer;

    struct objc_class_64 classStruct;
    [self.binaryData getBytes:&classStruct range:NSMakeRange(offset, sizeof(classStruct))];

    // Get class data
    uint64_t dataOffset = [self pointerToFileOffset:classStruct.data & ~0x7]; // Clear low bits (flags)
    if (dataOffset == 0 || dataOffset + sizeof(struct objc_class_ro_64) > self.binaryData.length) {
        return nil;
    }

    struct objc_class_ro_64 roData;
    [self.binaryData getBytes:&roData range:NSMakeRange(dataOffset, sizeof(roData))];

    // Read class name
    cls.className = [self readStringAtPointer:roData.name] ?: @"<Unknown>";
    cls.instanceSize = roData.instanceSize;

    // Read superclass name
    if (classStruct.superclass != 0) {
        cls.superClassName = [self getClassNameAtPointer:classStruct.superclass];
    }

    // Parse methods
    if (roData.baseMethods != 0) {
        [self parseMethods:roData.baseMethods intoArray:cls.instanceMethods isClassMethod:NO];
    }

    // Parse class methods (from metaclass)
    uint64_t metaclassOffset = [self pointerToFileOffset:classStruct.isa];
    if (metaclassOffset > 0) {
        [self parseClassMethodsFromMetaclass:metaclassOffset intoArray:cls.classMethods];
    }

    // Parse properties
    if (roData.baseProperties != 0) {
        [self parseProperties:roData.baseProperties intoArray:cls.properties];
    }

    // Parse ivars
    if (roData.ivars != 0) {
        [self parseIvars:roData.ivars intoArray:cls.ivars];
    }

    return cls;
}

- (void)parseMethods:(uint64_t)methodListPointer intoArray:(NSMutableArray<ObjCMethod *> *)methods isClassMethod:(BOOL)isClassMethod {
    uint64_t offset = [self pointerToFileOffset:methodListPointer];
    if (offset == 0 || offset + sizeof(struct objc_method_list_64) > self.binaryData.length) {
        return;
    }

    struct objc_method_list_64 methodList;
    [self.binaryData getBytes:&methodList range:NSMakeRange(offset, sizeof(methodList))];

    uint64_t methodsOffset = offset + sizeof(struct objc_method_list_64);

    for (uint32_t i = 0; i < methodList.count; i++) {
        if (methodsOffset + sizeof(struct objc_method_64) > self.binaryData.length) break;

        struct objc_method_64 method;
        [self.binaryData getBytes:&method range:NSMakeRange(methodsOffset, sizeof(method))];

        ObjCMethod *objcMethod = [[ObjCMethod alloc] init];
        objcMethod.name = [self readStringAtPointer:method.name] ?: @"<unknown>";
        objcMethod.signature = [self readStringAtPointer:method.types] ?: @"";
        objcMethod.implementation = method.imp;
        objcMethod.isClassMethod = isClassMethod;

        [methods addObject:objcMethod];

        methodsOffset += sizeof(struct objc_method_64);
    }
}

- (void)parseClassMethodsFromMetaclass:(uint64_t)metaclassOffset intoArray:(NSMutableArray<ObjCMethod *> *)methods {
    if (metaclassOffset + sizeof(struct objc_class_64) > self.binaryData.length) {
        return;
    }

    struct objc_class_64 metaclass;
    [self.binaryData getBytes:&metaclass range:NSMakeRange(metaclassOffset, sizeof(metaclass))];

    uint64_t dataOffset = [self pointerToFileOffset:metaclass.data & ~0x7];
    if (dataOffset == 0 || dataOffset + sizeof(struct objc_class_ro_64) > self.binaryData.length) {
        return;
    }

    struct objc_class_ro_64 roData;
    [self.binaryData getBytes:&roData range:NSMakeRange(dataOffset, sizeof(roData))];

    if (roData.baseMethods != 0) {
        [self parseMethods:roData.baseMethods intoArray:methods isClassMethod:YES];
    }
}

- (void)parseProperties:(uint64_t)propertyListPointer intoArray:(NSMutableArray<ObjCProperty *> *)properties {
    uint64_t offset = [self pointerToFileOffset:propertyListPointer];
    if (offset == 0 || offset + sizeof(struct objc_property_list_64) > self.binaryData.length) {
        return;
    }

    struct objc_property_list_64 propList;
    [self.binaryData getBytes:&propList range:NSMakeRange(offset, sizeof(propList))];

    uint64_t propsOffset = offset + sizeof(struct objc_property_list_64);

    for (uint32_t i = 0; i < propList.count; i++) {
        if (propsOffset + sizeof(struct objc_property_64) > self.binaryData.length) break;

        struct objc_property_64 prop;
        [self.binaryData getBytes:&prop range:NSMakeRange(propsOffset, sizeof(prop))];

        ObjCProperty *objcProp = [[ObjCProperty alloc] init];
        objcProp.name = [self readStringAtPointer:prop.name] ?: @"<unknown>";
        objcProp.attributes = [self readStringAtPointer:prop.attributes] ?: @"";

        [properties addObject:objcProp];

        propsOffset += sizeof(struct objc_property_64);
    }
}

- (void)parseIvars:(uint64_t)ivarListPointer intoArray:(NSMutableArray<ObjCIvar *> *)ivars {
    uint64_t offset = [self pointerToFileOffset:ivarListPointer];
    if (offset == 0 || offset + sizeof(struct objc_ivar_list_64) > self.binaryData.length) {
        return;
    }

    struct objc_ivar_list_64 ivarList;
    [self.binaryData getBytes:&ivarList range:NSMakeRange(offset, sizeof(ivarList))];

    uint64_t ivarsOffset = offset + sizeof(struct objc_ivar_list_64);

    for (uint32_t i = 0; i < ivarList.count; i++) {
        if (ivarsOffset + sizeof(struct objc_ivar_64) > self.binaryData.length) break;

        struct objc_ivar_64 ivar;
        [self.binaryData getBytes:&ivar range:NSMakeRange(ivarsOffset, sizeof(ivar))];

        ObjCIvar *objcIvar = [[ObjCIvar alloc] init];
        objcIvar.name = [self readStringAtPointer:ivar.name] ?: @"<unknown>";
        objcIvar.type = [self readStringAtPointer:ivar.type] ?: @"?";

        [ivars addObject:objcIvar];

        ivarsOffset += sizeof(struct objc_ivar_64);
    }
}

- (void)parseCategoryList {
    // Similar to parseClassList but for categories
    uint64_t count = self.catListSize / 8;

    for (uint64_t i = 0; i < count; i++) {
        uint64_t catPointerOffset = self.catListOffset + (i * 8);
        if (catPointerOffset + 8 > self.binaryData.length) break;

        uint64_t catPointer = [self read64BitAtOffset:catPointerOffset];
        if (catPointer == 0) continue;

        ObjCCategory *category = [self parseCategoryAtPointer:catPointer];
        if (category) {
            [self.mutableCategories addObject:category];
        }
    }
}

- (ObjCCategory *)parseCategoryAtPointer:(uint64_t)pointer {
    uint64_t offset = [self pointerToFileOffset:pointer];
    if (offset == 0 || offset + sizeof(struct objc_category_64) > self.binaryData.length) {
        return nil;
    }

    struct objc_category_64 catStruct;
    [self.binaryData getBytes:&catStruct range:NSMakeRange(offset, sizeof(catStruct))];

    ObjCCategory *category = [[ObjCCategory alloc] init];
    category.name = [self readStringAtPointer:catStruct.name] ?: @"<Unknown>";
    category.className = [self getClassNameAtPointer:catStruct.cls] ?: @"<Unknown>";

    if (catStruct.instanceMethods != 0) {
        [self parseMethods:catStruct.instanceMethods intoArray:category.instanceMethods isClassMethod:NO];
    }

    if (catStruct.classMethods != 0) {
        [self parseMethods:catStruct.classMethods intoArray:category.classMethods isClassMethod:YES];
    }

    return category;
}

- (void)parseProtocolList {
    // Similar implementation for protocols
    uint64_t count = self.protoListSize / 8;

    for (uint64_t i = 0; i < count; i++) {
        uint64_t protoPointerOffset = self.protoListOffset + (i * 8);
        if (protoPointerOffset + 8 > self.binaryData.length) break;

        uint64_t protoPointer = [self read64BitAtOffset:protoPointerOffset];
        if (protoPointer == 0) continue;

        ObjCProtocol *protocol = [self parseProtocolAtPointer:protoPointer];
        if (protocol) {
            [self.mutableProtocols addObject:protocol];
        }
    }
}

- (ObjCProtocol *)parseProtocolAtPointer:(uint64_t)pointer {
    uint64_t offset = [self pointerToFileOffset:pointer];
    if (offset == 0 || offset + sizeof(struct objc_protocol_64) > self.binaryData.length) {
        return nil;
    }

    struct objc_protocol_64 protoStruct;
    [self.binaryData getBytes:&protoStruct range:NSMakeRange(offset, sizeof(protoStruct))];

    ObjCProtocol *protocol = [[ObjCProtocol alloc] init];
    protocol.name = [self readStringAtPointer:protoStruct.name] ?: @"<Unknown>";

    if (protoStruct.instanceMethods != 0) {
        [self parseMethods:protoStruct.instanceMethods intoArray:protocol.requiredMethods isClassMethod:NO];
    }

    return protocol;
}

#pragma mark - Helper Methods

- (uint64_t)pointerToFileOffset:(uint64_t)pointer {
    // Simple implementation - assumes ASLR slide
    // In real implementation, need to map VM address to file offset using segment info
    if (pointer < self.baseAddress) {
        return 0;
    }
    uint64_t offset = pointer - self.baseAddress;
    if (offset >= self.binaryData.length) {
        return 0;
    }
    return offset;
}

- (uint64_t)read64BitAtOffset:(uint64_t)offset {
    if (offset + 8 > self.binaryData.length) {
        return 0;
    }
    uint64_t value = 0;
    [self.binaryData getBytes:&value range:NSMakeRange(offset, 8)];
    return value;
}

- (NSString *)readStringAtPointer:(uint64_t)pointer {
    uint64_t offset = [self pointerToFileOffset:pointer];
    if (offset == 0 || offset >= self.binaryData.length) {
        return nil;
    }

    const char *bytes = (const char *)self.binaryData.bytes + offset;
    size_t maxLen = self.binaryData.length - offset;

    // Find null terminator
    size_t len = strnlen(bytes, maxLen);
    if (len == 0 || len >= maxLen) {
        return nil;
    }

    return [[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
}

- (NSString *)getClassNameAtPointer:(uint64_t)pointer {
    uint64_t offset = [self pointerToFileOffset:pointer];
    if (offset == 0 || offset + sizeof(struct objc_class_64) > self.binaryData.length) {
        return nil;
    }

    struct objc_class_64 classStruct;
    [self.binaryData getBytes:&classStruct range:NSMakeRange(offset, sizeof(classStruct))];

    uint64_t dataOffset = [self pointerToFileOffset:classStruct.data & ~0x7];
    if (dataOffset == 0 || dataOffset + sizeof(struct objc_class_ro_64) > self.binaryData.length) {
        return nil;
    }

    struct objc_class_ro_64 roData;
    [self.binaryData getBytes:&roData range:NSMakeRange(dataOffset, sizeof(roData))];

    return [self readStringAtPointer:roData.name];
}

#pragma mark - Search

- (NSArray<ObjCClass *> *)searchClassesByName:(NSString *)query {
    if (!query || query.length == 0) {
        return self.mutableClasses;
    }

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"className CONTAINS[cd] %@", query];
    return [self.mutableClasses filteredArrayUsingPredicate:predicate];
}

- (NSArray<ObjCMethod *> *)searchMethodsByName:(NSString *)query {
    NSMutableArray *results = [NSMutableArray array];

    for (ObjCClass *cls in self.mutableClasses) {
        for (ObjCMethod *method in cls.instanceMethods) {
            if ([method.name rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [results addObject:method];
            }
        }
        for (ObjCMethod *method in cls.classMethods) {
            if ([method.name rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [results addObject:method];
            }
        }
    }

    return results;
}

#pragma mark - Properties

- (NSArray<ObjCClass *> *)classes {
    return [self.mutableClasses copy];
}

- (NSArray<ObjCProtocol *> *)protocols {
    return [self.mutableProtocols copy];
}

- (NSArray<ObjCCategory *> *)categories {
    return [self.mutableCategories copy];
}

- (NSDictionary<NSString *, ObjCClass *> *)classMap {
    return [self.mutableClassMap copy];
}

@end
