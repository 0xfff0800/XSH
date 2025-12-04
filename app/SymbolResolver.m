//
//  SymbolResolver.m
//  iSH - Symbol Resolution Implementation
//

#import "SymbolResolver.h"
#import "MachOParser.h"

@implementation ResolvedAddress
@end

@implementation SymbolResolver

- (instancetype)initWithParser:(MachOParser *)parser {
    if (self = [super init]) {
        _parser = parser;
    }
    return self;
}

#pragma mark - Main Resolution

- (ResolvedAddress *)resolveAddress:(uint64_t)address {
    ResolvedAddress *resolved = [[ResolvedAddress alloc] init];
    resolved.address = address;
    resolved.type = ResolvedTypeUnknown;

    // 1. Check for function symbol
    MachOSymbol *symbol = [self.parser symbolAtAddress:address];
    if (symbol && symbol.isFunction) {
        resolved.type = ResolvedTypeFunction;
        resolved.name = symbol.name;
        return resolved;
    }

    // 2. Check for Objective-C method
    ObjCMethodInfo *method = [self.parser objcMethodAtAddress:address];
    if (method) {
        resolved.type = ResolvedTypeObjCMethod;
        resolved.className = method.className;
        resolved.methodName = method.methodName;
        resolved.name = [NSString stringWithFormat:@"-[%@ %@]", method.className, method.methodName];
        return resolved;
    }

    // 3. Check for string
    NSString *string = [self.parser stringAtAddress:address];
    if (string) {
        resolved.type = ResolvedTypeString;
        resolved.name = string;
        resolved.comment = [NSString stringWithFormat:@"\"%@\"", [self escapeString:string]];
        return resolved;
    }

    // 4. Check for any symbol (even non-function)
    if (symbol) {
        resolved.type = ResolvedTypeData;
        resolved.name = symbol.name;
        return resolved;
    }

    // 5. Generate default name
    resolved.name = [NSString stringWithFormat:@"sub_%llx", address];
    return resolved;
}

#pragma mark - Specific Queries

- (NSString *)functionNameAtAddress:(uint64_t)address {
    MachOSymbol *symbol = [self.parser symbolAtAddress:address];
    if (symbol && symbol.isFunction) {
        return symbol.name;
    }

    ObjCMethodInfo *method = [self.parser objcMethodAtAddress:address];
    if (method) {
        return [NSString stringWithFormat:@"-[%@ %@]", method.className, method.methodName];
    }

    return [NSString stringWithFormat:@"sub_%llx", address];
}

- (NSString *)stringAtAddress:(uint64_t)address {
    return [self.parser stringAtAddress:address];
}

- (NSString *)objcMethodAtAddress:(uint64_t)address {
    ObjCMethodInfo *method = [self.parser objcMethodAtAddress:address];
    if (method) {
        return [NSString stringWithFormat:@"-[%@ %@]", method.className, method.methodName];
    }
    return nil;
}

- (NSString *)formatAddress:(uint64_t)address {
    ResolvedAddress *resolved = [self resolveAddress:address];
    return resolved.name;
}

- (NSString *)commentForAddress:(uint64_t)address {
    ResolvedAddress *resolved = [self resolveAddress:address];

    switch (resolved.type) {
        case ResolvedTypeString:
            return resolved.comment;

        case ResolvedTypeFunction:
        case ResolvedTypeObjCMethod:
            return resolved.name;

        case ResolvedTypeData:
            return [NSString stringWithFormat:@"&%@", resolved.name];

        default:
            return nil;
    }
}

#pragma mark - Helpers

- (NSString *)escapeString:(NSString *)str {
    if (str.length > 50) {
        str = [[str substringToIndex:47] stringByAppendingString:@"..."];
    }

    // Escape special characters
    str = [str stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    str = [str stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];
    str = [str stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

    return str;
}

@end
