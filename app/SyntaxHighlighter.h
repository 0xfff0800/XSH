//
//  SyntaxHighlighter.h
//  iSH - Syntax Highlighting for Pseudo-Code & Assembly
//
//  Beautiful syntax highlighting like Hopper/IDA
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Color Scheme
typedef NS_ENUM(NSInteger, SyntaxColorScheme) {
    SyntaxColorSchemeDark,      // Dark theme (like Hopper)
    SyntaxColorSchemeLight,     // Light theme
    SyntaxColorSchemeMonokai,   // Monokai theme
    SyntaxColorSchemeSolarized, // Solarized Dark
};

@interface SyntaxHighlighter : NSObject

// Current color scheme
@property (nonatomic, assign) SyntaxColorScheme colorScheme;

// Colors for different elements (customizable)
@property (nonatomic, strong) UIColor *keywordColor;       // if, else, return, void
@property (nonatomic, strong) UIColor *typeColor;          // int64_t, const char*, void*
@property (nonatomic, strong) UIColor *stringColor;        // "string literals"
@property (nonatomic, strong) UIColor *numberColor;        // 0x123, 42, 0.5
@property (nonatomic, strong) UIColor *commentColor;       // // comments
@property (nonatomic, strong) UIColor *functionColor;      // function names
@property (nonatomic, strong) UIColor *variableColor;      // var_0, str_0, ptr_0
@property (nonatomic, strong) UIColor *operatorColor;      // +, -, *, =, ==
@property (nonatomic, strong) UIColor *addressColor;       // 0x100028420
@property (nonatomic, strong) UIColor *instructionColor;   // ADRP, LDR, STR (assembly)
@property (nonatomic, strong) UIColor *registerColor;      // X0, SP, LR (assembly)
@property (nonatomic, strong) UIColor *backgroundColor;    // Background
@property (nonatomic, strong) UIColor *textColor;          // Default text

// Font
@property (nonatomic, strong) UIFont *font;                // Menlo, Monaco, etc.

// Initialize with scheme
- (instancetype)initWithColorScheme:(SyntaxColorScheme)scheme;

// Highlight code
- (NSAttributedString *)highlightPseudoCode:(NSString *)code;
- (NSAttributedString *)highlightAssembly:(NSString *)assembly;
- (NSAttributedString *)highlightAssemblyLine:(NSString *)line;

// Apply scheme
- (void)applyColorScheme:(SyntaxColorScheme)scheme;

@end

NS_ASSUME_NONNULL_END
