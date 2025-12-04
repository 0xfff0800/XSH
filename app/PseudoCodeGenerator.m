//
//  PseudoCodeGenerator.m
//  iSH - Pseudo-Code Generator
//
//  Converts ARM64 assembly to C-like pseudo-code
//

#import "PseudoCodeGenerator.h"
#import "ARM64InstructionDecoder.h"
#import "FunctionAnalyzer.h"
#import "SymbolResolver.h"
#import "CFGBuilder.h"
#import "StackFrameTracker.h"

@interface PseudoCodeGenerator ()
@property (nonatomic, strong) ARM64InstructionDecoder *decoder;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *registerMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *variableTypes; // var → type
@property (nonatomic, assign) NSInteger variableCounter;
@property (nonatomic, assign) NSInteger stringVarCounter;
@property (nonatomic, assign) NSInteger ptrVarCounter;
@end

@implementation PseudoCodeGenerator

- (instancetype)init {
    self = [super init];
    if (self) {
        _decoder = [[ARM64InstructionDecoder alloc] init];
        _registerMap = [NSMutableDictionary dictionary];
        _variableTypes = [NSMutableDictionary dictionary];
        _variableCounter = 0;
        _stringVarCounter = 0;
        _ptrVarCounter = 0;
    }
    return self;
}

- (NSString *)generatePseudoCodeForFunction:(DetectedFunction *)function
                                 binaryData:(NSData *)binaryData
                                baseAddress:(uint64_t)baseAddress {

    NSMutableString *pseudoCode = [NSMutableString string];

    // Function signature
    if (function.isObjCMethod) {
        [pseudoCode appendFormat:@"// Objective-C Method: -[%@ %@]\n", function.objcClassName, function.objcMethodName];
    }

    [pseudoCode appendFormat:@"void %@(", [self sanitizeFunctionName:function.displayName]];

    // Parameters (X0-X7 are argument registers in ARM64)
    [pseudoCode appendString:@"void* arg0, void* arg1, void* arg2"];
    [pseudoCode appendString:@") {\n"];

    // Reset register mapping and type tracking
    [self.registerMap removeAllObjects];
    [self.variableTypes removeAllObjects];
    self.variableCounter = 0;
    self.stringVarCounter = 0;
    self.ptrVarCounter = 0;

    // Local variables
    NSMutableSet *declaredVars = [NSMutableSet set];
    [pseudoCode appendString:@"    // Local variables\n"];

    // Process instructions
    if (binaryData && function.startAddress >= baseAddress) {
        uint64_t offset = function.startAddress - baseAddress;
        const uint8_t *bytes = (const uint8_t *)[binaryData bytes];

        NSMutableString *bodyCode = [NSMutableString string];

        for (uint64_t addr = function.startAddress; addr < function.endAddress; addr += 4) {
            if (offset + (addr - function.startAddress) + 4 <= binaryData.length) {
                const uint8_t *instrBytes = bytes + offset + (addr - function.startAddress);
                ARM64Instruction *inst = [self.decoder decodeInstructionAtAddress:addr
                                                                            data:instrBytes
                                                                          length:4];

                NSString *pseudoLine = [self convertInstructionToPseudoCode:inst
                                                              declaredVars:declaredVars];
                if (pseudoLine) {
                    [bodyCode appendFormat:@"    %@\n", pseudoLine];
                }
            }
        }

        // Declare variables that were used (with correct types)
        for (NSString *var in declaredVars) {
            NSString *varType = self.variableTypes[var];

            if ([varType isEqualToString:@"const char*"]) {
                [pseudoCode appendFormat:@"    const char *%@;\n", var];
            } else if ([varType isEqualToString:@"void*"]) {
                [pseudoCode appendFormat:@"    void *%@;\n", var];
            } else {
                // Default: int64_t for numeric variables
                [pseudoCode appendFormat:@"    int64_t %@;\n", var];
            }
        }
        [pseudoCode appendString:@"\n"];

        [pseudoCode appendString:bodyCode];
    }

    [pseudoCode appendString:@"}\n"];

    return pseudoCode;
}

- (NSString *)generatePseudoCodeForRange:(NSRange)range
                              binaryData:(NSData *)binaryData
                             baseAddress:(uint64_t)baseAddress {
    // Simplified version
    return @"// Pseudo-code generation for range";
}

- (NSString *)convertInstructionToPseudoCode:(ARM64Instruction *)inst
                               declaredVars:(NSMutableSet *)declaredVars {

    if (!inst) return nil;

    NSString *mnemonic = inst.mnemonic;
    NSString *operands = inst.operands;

    // Skip NOP
    if ([mnemonic isEqualToString:@"NOP"]) {
        return nil;
    }

    // Return statement
    if ([mnemonic isEqualToString:@"RET"]) {
        return @"return;";
    }

    // Branch with link (function call)
    if ([mnemonic isEqualToString:@"BL"]) {
        // Try to resolve function name using SymbolResolver
        NSString *functionCall = operands;

        if (self.symbolResolver && inst.comment) {
            // Extract address from comment (e.g., "→ 0x100001234")
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"0x([0-9a-fA-F]+)"
                                                                                   options:0
                                                                                     error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:inst.comment
                                                            options:0
                                                              range:NSMakeRange(0, inst.comment.length)];
            if (match) {
                NSString *hexStr = [inst.comment substringWithRange:[match rangeAtIndex:1]];
                uint64_t targetAddr = strtoull([hexStr UTF8String], NULL, 16);

                NSString *funcName = [self.symbolResolver functionNameAtAddress:targetAddr];
                if (funcName) {
                    functionCall = funcName;
                }
            }
        }

        return [NSString stringWithFormat:@"%@();", functionCall];
    }

    // Branch register (indirect call)
    if ([mnemonic isEqualToString:@"BLR"]) {
        return @"(*funcPtr)();";
    }

    // Conditional branch
    if ([mnemonic hasPrefix:@"B."]) {
        NSString *condition = [mnemonic substringFromIndex:2];
        return [NSString stringWithFormat:@"if (%@) goto %@;", [self conditionToC:condition], operands];
    }

    // Compare
    if ([mnemonic isEqualToString:@"CMP"]) {
        NSArray *ops = [operands componentsSeparatedByString:@", "];
        if (ops.count >= 2) {
            NSString *var1 = [self registerToVariable:ops[0] declaredVars:declaredVars];
            NSString *var2 = [self parseOperand:ops[1] declaredVars:declaredVars];
            return [NSString stringWithFormat:@"// compare %@ with %@", var1, var2];
        }
    }

    // Load
    if ([mnemonic isEqualToString:@"LDR"]) {
        NSArray *ops = [operands componentsSeparatedByString:@", "];
        if (ops.count >= 2) {
            NSString *dest = [self registerToVariable:ops[0] declaredVars:declaredVars];
            NSString *addr = [self parseMemoryAccess:ops[1] declaredVars:declaredVars];
            return [NSString stringWithFormat:@"%@ = *(%@);", dest, addr];
        }
    }

    // Store
    if ([mnemonic isEqualToString:@"STR"]) {
        NSArray *ops = [operands componentsSeparatedByString:@", "];
        if (ops.count >= 2) {
            NSString *src = [self registerToVariable:ops[0] declaredVars:declaredVars];
            NSString *addr = [self parseMemoryAccess:ops[1] declaredVars:declaredVars];
            return [NSString stringWithFormat:@"*(%@) = %@;", addr, src];
        }
    }

    // Add
    if ([mnemonic isEqualToString:@"ADD"] || [mnemonic isEqualToString:@"ADDS"]) {
        NSArray *ops = [operands componentsSeparatedByString:@", "];
        if (ops.count >= 3) {
            NSString *dest = [self registerToVariable:ops[0] declaredVars:declaredVars];
            NSString *src1 = [self registerToVariable:ops[1] declaredVars:declaredVars];
            NSString *src2 = [self parseOperand:ops[2] declaredVars:declaredVars];
            return [NSString stringWithFormat:@"%@ = %@ + %@;", dest, src1, src2];
        }
    }

    // Subtract
    if ([mnemonic isEqualToString:@"SUB"] || [mnemonic isEqualToString:@"SUBS"]) {
        NSArray *ops = [operands componentsSeparatedByString:@", "];
        if (ops.count >= 3) {
            NSString *dest = [self registerToVariable:ops[0] declaredVars:declaredVars];
            NSString *src1 = [self registerToVariable:ops[1] declaredVars:declaredVars];
            NSString *src2 = [self parseOperand:ops[2] declaredVars:declaredVars];
            return [NSString stringWithFormat:@"%@ = %@ - %@;", dest, src1, src2];
        }
    }

    // Move
    if ([mnemonic isEqualToString:@"MOV"] || [mnemonic isEqualToString:@"MOVZ"] || [mnemonic isEqualToString:@"MOVK"]) {
        NSArray *ops = [operands componentsSeparatedByString:@", "];
        if (ops.count >= 2) {
            NSString *dest = [self registerToVariable:ops[0] declaredVars:declaredVars];
            NSString *src = [self parseOperand:ops[1] declaredVars:declaredVars];
            return [NSString stringWithFormat:@"%@ = %@;", dest, src];
        }
    }

    // ADRP - Address of Page (load string address)
    if ([mnemonic isEqualToString:@"ADRP"] || [mnemonic isEqualToString:@"ADR"]) {
        NSArray *ops = [operands componentsSeparatedByString:@", "];
        if (ops.count >= 2) {
            NSString *regName = [ops[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *addrStr = ops[1];

            // Extract address: "#0x100001234" -> 0x100001234
            if ([addrStr hasPrefix:@"#"]) {
                addrStr = [addrStr substringFromIndex:1];
            }

            uint64_t address = strtoull([addrStr UTF8String], NULL, 16);

            // Check if this address points to a string
            NSString *stringLiteral = [self resolveStringAtAddress:address];
            if (stringLiteral) {
                // Create a NEW string variable (not reusing register mapping)
                NSString *stringVar = [NSString stringWithFormat:@"str_%ld", (long)self.stringVarCounter++];

                // Mark this register as holding a string
                self.registerMap[regName] = stringVar;
                self.variableTypes[stringVar] = @"const char*";

                [declaredVars addObject:stringVar];

                // Return with string literal
                return [NSString stringWithFormat:@"%@ = \"%@\";  // %@", stringVar, stringLiteral, addrStr];
            } else {
                // Regular address - create pointer variable
                NSString *ptrVar = [NSString stringWithFormat:@"ptr_%ld", (long)self.ptrVarCounter++];

                self.registerMap[regName] = ptrVar;
                self.variableTypes[ptrVar] = @"void*";

                [declaredVars addObject:ptrVar];

                return [NSString stringWithFormat:@"%@ = %@;", ptrVar, addrStr];
            }
        }
    }

    // Default: comment with assembly
    return [NSString stringWithFormat:@"// %@ %@", mnemonic, operands];
}

// Resolve string at a given address using the string map or SymbolResolver
- (NSString *)resolveStringAtAddress:(uint64_t)address {
    // First try SymbolResolver (new architecture)
    if (self.symbolResolver) {
        NSString *resolved = [self.symbolResolver stringAtAddress:address];
        if (resolved) {
            return resolved;
        }
    }

    // Fallback to old string map
    if (!self.stringMap) return nil;

    // Exact match
    NSString *exactMatch = self.stringMap[@(address)];
    if (exactMatch) {
        return exactMatch;
    }

    // Check within 4KB page (ADRP loads page-aligned addresses)
    for (NSNumber *key in self.stringMap) {
        uint64_t strAddr = [key unsignedLongLongValue];

        // If within same 4KB page
        if ((address & ~0xFFF) == (strAddr & ~0xFFF)) {
            return self.stringMap[key];
        }
    }

    return nil;
}

// Build string map from binary data
- (void)buildStringMapFromBinaryData:(NSData *)binaryData baseAddress:(uint64_t)baseAddress {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];

    if (!binaryData) {
        self.stringMap = map;
        return;
    }

    const uint8_t *bytes = (const uint8_t *)[binaryData bytes];
    NSUInteger length = binaryData.length;

    // Scan for null-terminated strings
    NSMutableData *currentStringData = [NSMutableData data];
    NSUInteger stringStart = 0;
    BOOL inString = NO;

    for (NSUInteger i = 0; i < length; i++) {
        uint8_t c = bytes[i];

        // Check if printable or UTF-8
        BOOL isPrintable = (c >= 32 && c < 127) || (c >= 0x80);

        if (isPrintable && c != 0x7F) {
            if (!inString) {
                stringStart = i;
                inString = YES;
                [currentStringData setLength:0];
            }
            [currentStringData appendBytes:&c length:1];
        } else if (c == 0 && inString) {
            // Null terminator - end of string
            if (currentStringData.length >= 4) {
                NSString *str = [[NSString alloc] initWithData:currentStringData encoding:NSUTF8StringEncoding];

                if (str && str.length >= 3) {
                    uint64_t stringAddress = baseAddress + stringStart;

                    // Escape quotes in string
                    str = [str stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

                    // Truncate very long strings
                    if (str.length > 100) {
                        str = [[str substringToIndex:97] stringByAppendingString:@"..."];
                    }

                    map[@(stringAddress)] = str;
                }
            }

            inString = NO;
            [currentStringData setLength:0];
        } else {
            inString = NO;
            [currentStringData setLength:0];
        }
    }

    self.stringMap = [map copy];

    NSLog(@"String Map built: %lu strings found", (unsigned long)map.count);
}

- (NSString *)registerToVariable:(NSString *)reg declaredVars:(NSMutableSet *)declaredVars {
    reg = [reg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    // Check if already mapped
    NSString *var = self.registerMap[reg];
    if (var) {
        return var;
    }

    // Special registers
    if ([reg isEqualToString:@"X0"] || [reg isEqualToString:@"W0"]) {
        var = @"arg0";
    } else if ([reg isEqualToString:@"X1"] || [reg isEqualToString:@"W1"]) {
        var = @"arg1";
    } else if ([reg isEqualToString:@"X2"] || [reg isEqualToString:@"W2"]) {
        var = @"arg2";
    } else if ([reg isEqualToString:@"SP"]) {
        return @"stack_ptr";
    } else if ([reg isEqualToString:@"XZR"] || [reg isEqualToString:@"WZR"]) {
        return @"0";
    } else {
        var = [NSString stringWithFormat:@"var_%ld", (long)self.variableCounter++];
    }

    self.registerMap[reg] = var;
    [declaredVars addObject:var];

    return var;
}

- (NSString *)parseOperand:(NSString *)operand declaredVars:(NSMutableSet *)declaredVars {
    operand = [operand stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    // Immediate value
    if ([operand hasPrefix:@"#"]) {
        return [operand substringFromIndex:1];
    }

    // Register
    if ([operand hasPrefix:@"X"] || [operand hasPrefix:@"W"]) {
        return [self registerToVariable:operand declaredVars:declaredVars];
    }

    return operand;
}

- (NSString *)parseMemoryAccess:(NSString *)memAccess declaredVars:(NSMutableSet *)declaredVars {
    // [X0, #0x10] -> (arg0 + 0x10)
    if ([memAccess hasPrefix:@"["] && [memAccess hasSuffix:@"]"]) {
        NSString *inner = [memAccess substringWithRange:NSMakeRange(1, memAccess.length - 2)];
        NSArray *parts = [inner componentsSeparatedByString:@","];

        if (parts.count == 1) {
            NSString *base = [self registerToVariable:parts[0] declaredVars:declaredVars];
            return base;
        } else if (parts.count >= 2) {
            NSString *base = [self registerToVariable:parts[0] declaredVars:declaredVars];
            NSString *offset = [self parseOperand:parts[1] declaredVars:declaredVars];
            return [NSString stringWithFormat:@"(%@ + %@)", base, offset];
        }
    }

    return memAccess;
}

- (NSString *)conditionToC:(NSString *)condition {
    NSDictionary *map = @{
        @"EQ": @"equal",
        @"NE": @"not_equal",
        @"GT": @"greater",
        @"LT": @"less",
        @"GE": @"greater_equal",
        @"LE": @"less_equal",
    };

    return map[condition] ?: condition;
}

- (NSString *)sanitizeFunctionName:(NSString *)name {
    // Remove special characters for C function name
    name = [name stringByReplacingOccurrencesOfString:@"-[" withString:@""];
    name = [name stringByReplacingOccurrencesOfString:@"]" withString:@""];
    name = [name stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    name = [name stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    return name;
}

@end
