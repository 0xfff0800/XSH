//
//  SyntaxHighlighter.m
//  iSH - Syntax Highlighting Implementation
//
//  Beautiful syntax highlighting like Hopper/IDA
//

#import "SyntaxHighlighter.h"

@implementation SyntaxHighlighter

- (instancetype)initWithColorScheme:(SyntaxColorScheme)scheme {
    self = [super init];
    if (self) {
        _colorScheme = scheme;
        _font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        [self applyColorScheme:scheme];
    }
    return self;
}

#pragma mark - Color Schemes

- (void)applyColorScheme:(SyntaxColorScheme)scheme {
    _colorScheme = scheme;

    switch (scheme) {
        case SyntaxColorSchemeDark:
            [self applyDarkTheme];
            break;

        case SyntaxColorSchemeLight:
            [self applyLightTheme];
            break;

        case SyntaxColorSchemeMonokai:
            [self applyMonokaiTheme];
            break;

        case SyntaxColorSchemeSolarized:
            [self applySolarizedTheme];
            break;
    }
}

- (void)applyDarkTheme {
    // Dark theme - like Hopper's default
    self.backgroundColor = [UIColor colorWithRed:0.14 green:0.14 blue:0.14 alpha:1.0];
    self.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1.0];

    self.keywordColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.6 alpha:1.0];      // Pink
    self.typeColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];         // Light blue
    self.stringColor = [UIColor colorWithRed:0.9 green:0.8 blue:0.4 alpha:1.0];       // Yellow
    self.numberColor = [UIColor colorWithRed:0.7 green:0.9 blue:0.7 alpha:1.0];       // Light green
    self.commentColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0];      // Gray
    self.functionColor = [UIColor colorWithRed:0.5 green:0.9 blue:0.5 alpha:1.0];     // Green
    self.variableColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];     // White
    self.operatorColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.4 alpha:1.0];     // Orange
    self.addressColor = [UIColor colorWithRed:0.8 green:0.6 blue:1.0 alpha:1.0];      // Purple
    self.instructionColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.5 alpha:1.0];  // Light red
    self.registerColor = [UIColor colorWithRed:0.5 green:0.8 blue:1.0 alpha:1.0];     // Cyan
}

- (void)applyLightTheme {
    // Light theme
    self.backgroundColor = [UIColor whiteColor];
    self.textColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0];

    self.keywordColor = [UIColor colorWithRed:0.8 green:0.0 blue:0.4 alpha:1.0];      // Dark pink
    self.typeColor = [UIColor colorWithRed:0.0 green:0.4 blue:0.8 alpha:1.0];         // Blue
    self.stringColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.0 alpha:1.0];       // Orange
    self.numberColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.0 alpha:1.0];       // Green
    self.commentColor = [UIColor colorWithRed:0.6 green:0.6 blue:0.6 alpha:1.0];      // Gray
    self.functionColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1.0];     // Dark green
    self.variableColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];     // Dark gray
    self.operatorColor = [UIColor colorWithRed:0.6 green:0.3 blue:0.0 alpha:1.0];     // Brown
    self.addressColor = [UIColor colorWithRed:0.5 green:0.0 blue:0.8 alpha:1.0];      // Purple
    self.instructionColor = [UIColor colorWithRed:0.8 green:0.0 blue:0.0 alpha:1.0];  // Red
    self.registerColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.8 alpha:1.0];     // Blue
}

- (void)applyMonokaiTheme {
    // Monokai theme - popular with developers
    self.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.14 alpha:1.0];
    self.textColor = [UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0];

    self.keywordColor = [UIColor colorWithRed:0.98 green:0.15 blue:0.45 alpha:1.0];   // Pink
    self.typeColor = [UIColor colorWithRed:0.4 green:0.85 blue:0.94 alpha:1.0];       // Cyan
    self.stringColor = [UIColor colorWithRed:0.9 green:0.86 blue:0.45 alpha:1.0];     // Yellow
    self.numberColor = [UIColor colorWithRed:0.68 green:0.51 blue:1.0 alpha:1.0];     // Purple
    self.commentColor = [UIColor colorWithRed:0.46 green:0.45 blue:0.48 alpha:1.0];   // Gray
    self.functionColor = [UIColor colorWithRed:0.65 green:0.89 blue:0.18 alpha:1.0];  // Green
    self.variableColor = [UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0];  // White
    self.operatorColor = [UIColor colorWithRed:0.98 green:0.15 blue:0.45 alpha:1.0];  // Pink
    self.addressColor = [UIColor colorWithRed:0.68 green:0.51 blue:1.0 alpha:1.0];    // Purple
    self.instructionColor = [UIColor colorWithRed:0.98 green:0.15 blue:0.45 alpha:1.0]; // Pink
    self.registerColor = [UIColor colorWithRed:0.4 green:0.85 blue:0.94 alpha:1.0];   // Cyan
}

- (void)applySolarizedTheme {
    // Solarized Dark
    self.backgroundColor = [UIColor colorWithRed:0.0 green:0.17 blue:0.21 alpha:1.0];
    self.textColor = [UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0];

    self.keywordColor = [UIColor colorWithRed:0.71 green:0.54 blue:0.0 alpha:1.0];    // Yellow
    self.typeColor = [UIColor colorWithRed:0.27 green:0.66 blue:0.84 alpha:1.0];      // Blue
    self.stringColor = [UIColor colorWithRed:0.16 green:0.63 blue:0.6 alpha:1.0];     // Cyan
    self.numberColor = [UIColor colorWithRed:0.83 green:0.21 blue:0.51 alpha:1.0];    // Magenta
    self.commentColor = [UIColor colorWithRed:0.36 green:0.43 blue:0.44 alpha:1.0];   // Gray
    self.functionColor = [UIColor colorWithRed:0.52 green:0.6 blue:0.0 alpha:1.0];    // Green
    self.variableColor = [UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0];  // Base text
    self.operatorColor = [UIColor colorWithRed:0.71 green:0.54 blue:0.0 alpha:1.0];   // Yellow
    self.addressColor = [UIColor colorWithRed:0.42 green:0.44 blue:0.77 alpha:1.0];   // Violet
    self.instructionColor = [UIColor colorWithRed:0.86 green:0.2 blue:0.18 alpha:1.0]; // Red
    self.registerColor = [UIColor colorWithRed:0.27 green:0.66 blue:0.84 alpha:1.0];  // Blue
}

#pragma mark - Highlight Pseudo-Code

- (NSAttributedString *)highlightPseudoCode:(NSString *)code {
    if (!code || code.length == 0) {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:code];

    // Apply default styling
    [result addAttribute:NSForegroundColorAttributeName
                   value:self.textColor
                   range:NSMakeRange(0, code.length)];
    [result addAttribute:NSFontAttributeName
                   value:self.font
                   range:NSMakeRange(0, code.length)];

    // 1. Comments (highest priority - color everything after //)
    [self applyPattern:@"//.*$"
                 color:self.commentColor
              toString:result
               options:NSRegularExpressionAnchorsMatchLines];

    // 2. String literals
    [self applyPattern:@"\"[^\"]*\""
                 color:self.stringColor
              toString:result
               options:0];

    // 3. Numbers (hex, decimal, float)
    [self applyPattern:@"\\b0x[0-9a-fA-F]+\\b|\\b[0-9]+\\.[0-9]+\\b|\\b[0-9]+\\b"
                 color:self.numberColor
              toString:result
               options:0];

    // 4. Keywords
    NSString *keywords = @"\\b(if|else|return|void|const|struct|typedef|enum|for|while|break|continue|switch|case|default|goto)\\b";
    [self applyPattern:keywords
                 color:self.keywordColor
              toString:result
               options:0];

    // 5. Types
    NSString *types = @"\\b(int64_t|uint64_t|int32_t|uint32_t|int16_t|uint16_t|int8_t|uint8_t|char|void\\s*\\*|const\\s+char\\s*\\*)\\b";
    [self applyPattern:types
                 color:self.typeColor
              toString:result
               options:0];

    // 6. Function names (word followed by parenthesis)
    [self applyPattern:@"\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\("
                 color:self.functionColor
              toString:result
               options:0
              groupIndex:1];

    // 7. Variables (var_0, str_0, ptr_0, etc.)
    [self applyPattern:@"\\b(var|str|ptr|arg|ret)_[0-9]+\\b"
                 color:self.variableColor
              toString:result
               options:0];

    // 8. Addresses (0x...)
    [self applyPattern:@"\\b0x[0-9a-fA-F]{8,}\\b"
                 color:self.addressColor
              toString:result
               options:0];

    // 9. Operators
    NSString *operators = @"(\\+\\+|--|==|!=|<=|>=|&&|\\|\\||->|\\+|-|\\*|/|%|=|<|>|&|\\||\\^|!|~)";
    [self applyPattern:operators
                 color:self.operatorColor
              toString:result
               options:0];

    return result;
}

#pragma mark - Highlight Assembly

- (NSAttributedString *)highlightAssembly:(NSString *)assembly {
    if (!assembly || assembly.length == 0) {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:assembly];

    // Apply default styling
    [result addAttribute:NSForegroundColorAttributeName
                   value:self.textColor
                   range:NSMakeRange(0, assembly.length)];
    [result addAttribute:NSFontAttributeName
                   value:self.font
                   range:NSMakeRange(0, assembly.length)];

    // 1. Comments
    [self applyPattern:@"//.*$|;.*$"
                 color:self.commentColor
              toString:result
               options:NSRegularExpressionAnchorsMatchLines];

    // 2. Addresses (at start of line or standalone)
    [self applyPattern:@"^\\s*0x[0-9a-fA-F]+\\b|\\b0x[0-9a-fA-F]{8,}\\b"
                 color:self.addressColor
              toString:result
               options:NSRegularExpressionAnchorsMatchLines];

    // 3. ARM64 Instructions
    NSString *instructions = @"\\b(ADRP|ADR|LDR|LDRB|LDRH|LDRSW|STR|STRB|STRH|"
                            @"ADD|SUB|MUL|UDIV|SDIV|AND|ORR|EOR|LSL|LSR|ASR|"
                            @"MOV|MOVK|MOVZ|MOVN|"
                            @"B|BL|BR|BLR|RET|CBZ|CBNZ|TBZ|TBNZ|"
                            @"CMP|CMN|TST|CCMP|CCMN|CSEL|CSET|CINC|"
                            @"STP|LDP|NOP|BRK|HLT|MSR|MRS)\\b";
    [self applyPattern:instructions
                 color:self.instructionColor
              toString:result
               options:NSRegularExpressionCaseInsensitive];

    // 4. Registers
    NSString *registers = @"\\b(X[0-9]|X1[0-9]|X2[0-9]|X30|"
                         @"W[0-9]|W1[0-9]|W2[0-9]|W30|"
                         @"SP|LR|PC|FP|XZR|WZR|"
                         @"V[0-9]|V1[0-9]|V2[0-9]|V3[0-1])\\b";
    [self applyPattern:registers
                 color:self.registerColor
              toString:result
               options:NSRegularExpressionCaseInsensitive];

    // 5. Numbers (immediate values)
    [self applyPattern:@"#0x[0-9a-fA-F]+|#-?[0-9]+"
                 color:self.numberColor
              toString:result
               options:0];

    // 6. String literals in assembly comments
    [self applyPattern:@"\"[^\"]*\""
                 color:self.stringColor
              toString:result
               options:0];

    return result;
}

- (NSAttributedString *)highlightAssemblyLine:(NSString *)line {
    if (!line || line.length == 0) {
        return [[NSAttributedString alloc] initWithString:@"" attributes:@{}];
    }

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc]
                                         initWithString:line
                                         attributes:@{
                                             NSForegroundColorAttributeName: self.textColor,
                                             NSFontAttributeName: self.font
                                         }];

    // 1. Addresses (0x100001234)
    [self applyPattern:@"0x[0-9a-fA-F]+"
                 color:self.addressColor
              toString:result
               options:0];

    // 2. ARM64 Instructions (ADRP, LDR, STR, MOV, BL, etc.)
    [self applyPattern:@"\\b(ADRP|LDR|LDRB|LDRH|LDRSB|LDRSH|LDRSW|STR|STRB|STRH|MOV|MOVZ|MOVK|MOVN|ADD|SUB|MUL|SDIV|UDIV|AND|ORR|EOR|LSL|LSR|ASR|ROR|CMP|CMN|TST|B|BL|BR|BLR|RET|CBZ|CBNZ|TBZ|TBNZ|B\\.EQ|B\\.NE|B\\.CS|B\\.CC|B\\.MI|B\\.PL|B\\.VS|B\\.VC|B\\.HI|B\\.LS|B\\.GE|B\\.LT|B\\.GT|B\\.LE|B\\.AL|STP|LDP|STUR|LDUR|NOP|SVC|BRK|AUTIBSP|AUTIBZ)\\b"
                 color:self.instructionColor
              toString:result
               options:0];

    // 3. Registers (X0-X30, W0-W30, SP, LR, XZR, WZR)
    [self applyPattern:@"\\b([XW]([0-9]|1[0-9]|2[0-9]|30)|SP|LR|FP|[XW]ZR|PC)\\b"
                 color:self.registerColor
              toString:result
               options:0];

    // 4. Immediate values (#0x123, #42, #-5)
    [self applyPattern:@"#-?0x[0-9a-fA-F]+"
                 color:self.numberColor
              toString:result
               options:0];

    [self applyPattern:@"#-?\\d+"
                 color:self.numberColor
              toString:result
               options:0];

    // 5. Comments (// ...)
    [self applyPattern:@"//.*$"
                 color:self.commentColor
              toString:result
               options:0];

    // 6. Function names (sub_..., loc_..., _objc_...)
    [self applyPattern:@"\\b(sub_[0-9a-fA-F]+|loc_[0-9a-fA-F]+|_objc_\\w+|_[A-Za-z_][A-Za-z0-9_]*)\\b"
                 color:self.functionColor
              toString:result
               options:0];

    return result;
}

#pragma mark - Helper Methods

- (void)applyPattern:(NSString *)pattern
               color:(UIColor *)color
            toString:(NSMutableAttributedString *)attrString
             options:(NSRegularExpressionOptions)options {
    [self applyPattern:pattern color:color toString:attrString options:options groupIndex:0];
}

- (void)applyPattern:(NSString *)pattern
               color:(UIColor *)color
            toString:(NSMutableAttributedString *)attrString
             options:(NSRegularExpressionOptions)options
          groupIndex:(NSInteger)groupIndex {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:options
                                                                             error:&error];
    if (error) {
        NSLog(@"Regex error: %@", error);
        return;
    }

    NSString *string = attrString.string;
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:string
                                                              options:0
                                                                range:NSMakeRange(0, string.length)];

    for (NSTextCheckingResult *match in matches) {
        NSRange rangeToColor = groupIndex > 0 && groupIndex < (NSInteger)match.numberOfRanges
                                ? [match rangeAtIndex:groupIndex]
                                : match.range;

        if (rangeToColor.location != NSNotFound) {
            [attrString addAttribute:NSForegroundColorAttributeName
                               value:color
                               range:rangeToColor];
        }
    }
}

@end
