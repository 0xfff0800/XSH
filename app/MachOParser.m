//
//  MachOParser.m
//  iSH - Mach-O Binary Parser Implementation
//

#import "MachOParser.h"
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach-o/fat.h>

@implementation MachOSegment
@end

@implementation MachOSection
@end

@implementation MachOSymbol
@end

@implementation ObjCClassInfo
- (instancetype)init {
    if (self = [super init]) {
        _methods = [NSMutableArray array];
        _properties = [NSMutableArray array];
    }
    return self;
}
@end

@implementation ObjCMethodInfo
@end

@interface MachOParser ()
@property (nonatomic, strong) NSMutableArray<MachOSegment *> *mutableSegments;
@property (nonatomic, strong) NSMutableArray<MachOSection *> *mutableSections;
@property (nonatomic, strong) NSMutableArray<MachOSymbol *> *mutableSymbols;
@property (nonatomic, strong) NSMutableArray<ObjCClassInfo *> *mutableObjCClasses;
@property (nonatomic, strong) NSMutableArray<ObjCMethodInfo *> *mutableObjCMethods;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, MachOSymbol *> *mutableSymbolsByAddress;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *mutableStringsByAddress;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, ObjCMethodInfo *> *mutableMethodsByAddress;
@end

@implementation MachOParser

- (instancetype)initWithData:(NSData *)data baseAddress:(uint64_t)baseAddr {
    if (self = [super init]) {
        _binaryData = data;
        _baseAddress = baseAddr;
        _mutableSegments = [NSMutableArray array];
        _mutableSections = [NSMutableArray array];
        _mutableSymbols = [NSMutableArray array];
        _mutableObjCClasses = [NSMutableArray array];
        _mutableObjCMethods = [NSMutableArray array];
        _mutableSymbolsByAddress = [NSMutableDictionary dictionary];
        _mutableStringsByAddress = [NSMutableDictionary dictionary];
        _mutableMethodsByAddress = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSArray *)segments { return [self.mutableSegments copy]; }
- (NSArray *)sections { return [self.mutableSections copy]; }
- (NSArray *)symbols { return [self.mutableSymbols copy]; }
- (NSArray *)objcClasses { return [self.mutableObjCClasses copy]; }
- (NSArray *)objcMethods { return [self.mutableObjCMethods copy]; }
- (NSDictionary *)symbolsByAddress { return [self.mutableSymbolsByAddress copy]; }
- (NSDictionary *)stringsByAddress { return [self.mutableStringsByAddress copy]; }
- (NSDictionary *)methodsByAddress { return [self.mutableMethodsByAddress copy]; }

#pragma mark - Main Parsing

- (BOOL)parse {
    if (self.binaryData.length < sizeof(struct mach_header_64)) {
        NSLog(@"[MachOParser] File too small");
        return NO;
    }

    const uint8_t *bytes = self.binaryData.bytes;
    struct mach_header_64 *header = (struct mach_header_64 *)bytes;

    // Check magic
    if (header->magic != MH_MAGIC_64) {
        NSLog(@"[MachOParser] Not a 64-bit Mach-O (magic: 0x%x)", header->magic);
        return NO;
    }

    // Parse load commands
    const uint8_t *ptr = bytes + sizeof(struct mach_header_64);
    struct symtab_command *symtabCmd = NULL;

    for (uint32_t i = 0; i < header->ncmds; i++) {
        struct load_command *lc = (struct load_command *)ptr;

        switch (lc->cmd) {
            case LC_SEGMENT_64:
                [self parseSegment64:(struct segment_command_64 *)lc];
                break;

            case LC_SYMTAB:
                symtabCmd = (struct symtab_command *)lc;
                break;

            default:
                break;
        }

        ptr += lc->cmdsize;
    }

    // Parse symbol table after all segments
    if (symtabCmd) {
        [self parseSymbolTable:symtabCmd];
    }

    // Parse C strings
    [self parseCStrings];

    // Parse Objective-C metadata
    [self parseObjCMetadata];

    NSLog(@"[MachOParser] Parsed: %lu segments, %lu sections, %lu symbols, %lu ObjC classes",
          (unsigned long)self.mutableSegments.count,
          (unsigned long)self.mutableSections.count,
          (unsigned long)self.mutableSymbols.count,
          (unsigned long)self.mutableObjCClasses.count);

    return YES;
}

#pragma mark - Segment Parsing

- (void)parseSegment64:(struct segment_command_64 *)segCmd {
    MachOSegment *segment = [[MachOSegment alloc] init];
    segment.name = [NSString stringWithUTF8String:segCmd->segname];
    segment.vmaddr = segCmd->vmaddr;
    segment.vmsize = segCmd->vmsize;
    segment.fileoff = segCmd->fileoff;
    segment.filesize = segCmd->filesize;

    [self.mutableSegments addObject:segment];

    // Parse sections in this segment
    struct section_64 *sections = (struct section_64 *)((uint8_t *)segCmd + sizeof(struct segment_command_64));

    for (uint32_t i = 0; i < segCmd->nsects; i++) {
        struct section_64 *sect = &sections[i];

        MachOSection *section = [[MachOSection alloc] init];
        section.sectname = [NSString stringWithUTF8String:sect->sectname];
        section.segname = [NSString stringWithUTF8String:sect->segname];
        section.addr = sect->addr;
        section.size = sect->size;
        section.offset = sect->offset;

        // Extract section data
        if (sect->offset > 0 && sect->offset + sect->size <= self.binaryData.length) {
            section.data = [self.binaryData subdataWithRange:NSMakeRange(sect->offset, sect->size)];
        }

        [self.mutableSections addObject:section];
    }
}

#pragma mark - Symbol Table Parsing

- (void)parseSymbolTable:(struct symtab_command *)symtab {
    if (symtab->symoff == 0 || symtab->stroff == 0) {
        return;
    }

    const uint8_t *bytes = self.binaryData.bytes;

    // Bounds check
    if (symtab->symoff + symtab->nsyms * sizeof(struct nlist_64) > self.binaryData.length ||
        symtab->stroff + symtab->strsize > self.binaryData.length) {
        NSLog(@"[MachOParser] Symbol table out of bounds");
        return;
    }

    struct nlist_64 *symbols = (struct nlist_64 *)(bytes + symtab->symoff);
    const char *stringTable = (const char *)(bytes + symtab->stroff);

    for (uint32_t i = 0; i < symtab->nsyms; i++) {
        struct nlist_64 *sym = &symbols[i];

        // Skip if no name
        if (sym->n_un.n_strx == 0 || sym->n_un.n_strx >= symtab->strsize) {
            continue;
        }

        const char *namePtr = stringTable + sym->n_un.n_strx;
        NSString *name = @(namePtr);

        MachOSymbol *symbol = [[MachOSymbol alloc] init];
        symbol.name = name;
        symbol.address = sym->n_value;
        symbol.type = sym->n_type;
        symbol.isExternal = (sym->n_type & N_EXT) != 0;

        // Determine if it's a function
        uint8_t nType = sym->n_type & N_TYPE;
        symbol.isFunction = (nType == N_SECT) && ![name hasPrefix:@"_OBJC_"];

        [self.mutableSymbols addObject:symbol];

        if (symbol.address > 0) {
            self.mutableSymbolsByAddress[@(symbol.address)] = symbol;
        }
    }
}

#pragma mark - String Parsing

- (void)parseCStrings {
    MachOSection *cstringSection = [self sectionNamed:@"__cstring"];
    if (!cstringSection || !cstringSection.data) {
        return;
    }

    const char *bytes = cstringSection.data.bytes;
    NSUInteger length = cstringSection.data.length;
    NSUInteger offset = 0;

    while (offset < length) {
        const char *str = bytes + offset;
        NSUInteger strLen = strnlen(str, length - offset);

        if (strLen > 0 && strLen < length - offset) {
            NSString *string = @(str);
            uint64_t address = cstringSection.addr + offset;

            self.mutableStringsByAddress[@(address)] = string;
        }

        offset += strLen + 1;  // Move past null terminator
    }
}

#pragma mark - Objective-C Metadata Parsing

- (void)parseObjCMetadata {
    // Parse __objc_classlist
    MachOSection *classListSection = [self sectionNamed:@"__objc_classlist"];
    if (!classListSection || !classListSection.data) {
        return;
    }

    const uint64_t *classPointers = (const uint64_t *)classListSection.data.bytes;
    NSUInteger numClasses = classListSection.data.length / sizeof(uint64_t);

    for (NSUInteger i = 0; i < numClasses; i++) {
        uint64_t classPtr = classPointers[i];
        [self parseObjCClass:classPtr];
    }

    // Parse __objc_methname for method names
    MachOSection *methnameSection = [self sectionNamed:@"__objc_methname"];
    if (methnameSection && methnameSection.data) {
        const char *bytes = methnameSection.data.bytes;
        NSUInteger length = methnameSection.data.length;
        NSUInteger offset = 0;

        while (offset < length) {
            const char *str = bytes + offset;
            NSUInteger strLen = strnlen(str, length - offset);

            if (strLen > 0 && strLen < length - offset) {
                uint64_t address = methnameSection.addr + offset;
                self.mutableStringsByAddress[@(address)] = @(str);
            }

            offset += strLen + 1;
        }
    }
}

- (void)parseObjCClass:(uint64_t)classAddr {
    // Read class_t structure
    uint64_t fileOffset = [self fileOffsetForVirtualAddress:classAddr];
    if (fileOffset == 0 || fileOffset + 40 > self.binaryData.length) {
        return;
    }

    const uint8_t *bytes = self.binaryData.bytes;
    const uint64_t *classData = (const uint64_t *)(bytes + fileOffset);

    // class_t structure:
    // uint64_t isa;
    // uint64_t superclass;
    // uint64_t cache;
    // uint64_t vtable;
    // uint64_t data_NEVER_USE;  // Points to class_ro_t

    uint64_t classROPtr = classData[4];
    uint64_t roOffset = [self fileOffsetForVirtualAddress:classROPtr];

    if (roOffset == 0 || roOffset + 80 > self.binaryData.length) {
        return;
    }

    // class_ro_t structure
    const uint8_t *roData = bytes + roOffset;
    const uint64_t *roFields = (const uint64_t *)roData;

    // uint32_t flags;
    // uint32_t instanceStart;
    // uint32_t instanceSize;
    // uint32_t reserved;
    // uint64_t ivarLayout;
    // uint64_t name;  // at offset 24

    uint64_t namePtr = roFields[3];  // name at offset 24 / 8 = index 3
    NSString *className = [self stringAtAddress:namePtr];

    if (className) {
        ObjCClassInfo *classInfo = [[ObjCClassInfo alloc] init];
        classInfo.className = className;
        classInfo.address = classAddr;

        [self.mutableObjCClasses addObject:classInfo];

        // Parse methods (baseMethods at offset 32)
        uint64_t methodListPtr = roFields[4];
        if (methodListPtr > 0) {
            [self parseObjCMethodList:methodListPtr forClass:className];
        }
    }
}

- (void)parseObjCMethodList:(uint64_t)methodListAddr forClass:(NSString *)className {
    uint64_t fileOffset = [self fileOffsetForVirtualAddress:methodListAddr];
    if (fileOffset == 0 || fileOffset + 8 > self.binaryData.length) {
        return;
    }

    const uint8_t *bytes = self.binaryData.bytes;
    const uint32_t *methodListHeader = (const uint32_t *)(bytes + fileOffset);

    // method_list_t:
    // uint32_t entsize;
    // uint32_t count;

    uint32_t entsize = methodListHeader[0] & 0xFFFF;
    uint32_t count = methodListHeader[1];

    if (count > 1000 || entsize < 24) {  // Sanity check
        return;
    }

    const uint8_t *methodsData = bytes + fileOffset + 8;

    for (uint32_t i = 0; i < count; i++) {
        const uint64_t *method = (const uint64_t *)(methodsData + i * entsize);

        // method_t:
        // uint64_t name;
        // uint64_t types;
        // uint64_t imp;

        uint64_t namePtr = method[0];
        uint64_t impPtr = method[2];

        NSString *methodName = [self stringAtAddress:namePtr];
        if (methodName) {
            ObjCMethodInfo *methodInfo = [[ObjCMethodInfo alloc] init];
            methodInfo.className = className;
            methodInfo.methodName = methodName;
            methodInfo.implementation = impPtr;
            methodInfo.isClassMethod = NO;  // TODO: detect class vs instance

            [self.mutableObjCMethods addObject:methodInfo];

            if (impPtr > 0) {
                self.mutableMethodsByAddress[@(impPtr)] = methodInfo;
            }
        }
    }
}

#pragma mark - Queries

- (MachOSymbol *)symbolAtAddress:(uint64_t)address {
    return self.mutableSymbolsByAddress[@(address)];
}

- (NSString *)stringAtAddress:(uint64_t)address {
    return self.mutableStringsByAddress[@(address)];
}

- (ObjCMethodInfo *)objcMethodAtAddress:(uint64_t)address {
    return self.mutableMethodsByAddress[@(address)];
}

- (MachOSection *)sectionContainingAddress:(uint64_t)address {
    for (MachOSection *section in self.mutableSections) {
        if (address >= section.addr && address < section.addr + section.size) {
            return section;
        }
    }
    return nil;
}

- (MachOSection *)sectionNamed:(NSString *)name {
    for (MachOSection *section in self.mutableSections) {
        if ([section.sectname isEqualToString:name]) {
            return section;
        }
    }
    return nil;
}

#pragma mark - Address Conversion

- (uint64_t)fileOffsetForVirtualAddress:(uint64_t)vmaddr {
    for (MachOSegment *segment in self.mutableSegments) {
        if (vmaddr >= segment.vmaddr && vmaddr < segment.vmaddr + segment.vmsize) {
            uint64_t offset = vmaddr - segment.vmaddr;
            return segment.fileoff + offset;
        }
    }
    return 0;
}

- (uint64_t)virtualAddressForFileOffset:(uint64_t)fileoff {
    for (MachOSegment *segment in self.mutableSegments) {
        if (fileoff >= segment.fileoff && fileoff < segment.fileoff + segment.filesize) {
            uint64_t offset = fileoff - segment.fileoff;
            return segment.vmaddr + offset;
        }
    }
    return 0;
}

@end
