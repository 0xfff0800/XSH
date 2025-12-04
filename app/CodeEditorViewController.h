//
//  CodeEditorViewController.h
//  iSH
//
//  XSH Code Editor with Syntax Highlighting
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CodeLanguage) {
    CodeLanguageAuto,       // Auto-detect from extension
    CodeLanguagePython,
    CodeLanguageBash,
    CodeLanguageJavaScript,
    CodeLanguageC,
    CodeLanguageHTML,
    CodeLanguageJSON,
    CodeLanguageMarkdown,
    CodeLanguagePlainText
};

@interface CodeEditorViewController : UIViewController

@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, strong) NSString *filename;  // Default filename for saving
@property (nonatomic, assign) CodeLanguage language;
@property (nonatomic, copy) void (^onSave)(NSString *content);

- (instancetype)initWithFilePath:(NSString *)filePath;
- (instancetype)initWithContent:(NSString *)content language:(CodeLanguage)language;
- (instancetype)initWithContent:(NSString *)content language:(CodeLanguage)language filename:(NSString *)filename;

@end

NS_ASSUME_NONNULL_END
