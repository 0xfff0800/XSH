//
//  CodeEditorViewController.m
//  iSH
//
//  XSH Code Editor with Syntax Highlighting
//

#import "CodeEditorViewController.h"

@interface CodeEditorViewController () <UITextViewDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UITextView *lineNumberView;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@property (nonatomic, strong) UIBarButtonItem *cancelButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSString *originalContent;
@property (nonatomic, assign) BOOL hasUnsavedChanges;

// Syntax highlighting
@property (nonatomic, strong) NSDictionary *syntaxColors;
@property (nonatomic, strong) NSArray *keywords;
@property (nonatomic, strong) NSTimer *highlightTimer;

@end

@implementation CodeEditorViewController

- (instancetype)initWithFilePath:(NSString *)filePath {
    self = [super init];
    if (self) {
        _filePath = filePath;
        _language = [self detectLanguageFromPath:filePath];
        [self loadFile];
    }
    return self;
}

- (instancetype)initWithContent:(NSString *)content language:(CodeLanguage)language {
    self = [super init];
    if (self) {
        _originalContent = content ?: @"";
        _language = language;
    }
    return self;
}

- (instancetype)initWithContent:(NSString *)content language:(CodeLanguage)language filename:(NSString *)filename {
    self = [self initWithContent:content language:language];
    if (self) {
        _filename = filename;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self setupToolbar];
    [self setupEditor];
    [self setupLineNumbers];
    [self setupSyntaxColors];
    [self setupKeywords];

    // Initial syntax highlighting
    [self applySyntaxHighlighting];
}

- (void)setupToolbar {
    self.toolbar = [[UIToolbar alloc] init];
    self.toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.toolbar];

    // Cancel button
    self.cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                       target:self
                                                                       action:@selector(cancelTapped)];

    // Save button
    self.saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                     target:self
                                                                     action:@selector(saveTapped)];
    self.saveButton.tintColor = [UIColor systemBlueColor];

    // Status label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.text = self.filePath ? [self.filePath lastPathComponent] : @"New File";
    UIBarButtonItem *statusItem = [[UIBarButtonItem alloc] initWithCustomView:self.statusLabel];

    // Flexible space
    UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                               target:nil
                                                                               action:nil];

    // Language button
    UIBarButtonItem *langButton = [[UIBarButtonItem alloc] initWithTitle:[self languageName]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(showLanguageOptions)];

    self.toolbar.items = @[self.cancelButton, flexSpace, statusItem, flexSpace, langButton, flexSpace, self.saveButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.toolbar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (void)setupEditor {
    // Main text view
    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.delegate = self;
    self.textView.font = [UIFont fontWithName:@"Menlo" size:14];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    self.textView.textColor = [UIColor whiteColor];
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.smartQuotesType = UITextSmartQuotesTypeNo;
    self.textView.smartDashesType = UITextSmartDashesTypeNo;
    self.textView.keyboardAppearance = UIKeyboardAppearanceDark;
    self.textView.text = self.originalContent;
    self.textView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    [self.view addSubview:self.textView];

    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:self.toolbar.bottomAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupLineNumbers {
    // Line number view
    self.lineNumberView = [[UITextView alloc] init];
    self.lineNumberView.translatesAutoresizingMaskIntoConstraints = NO;
    self.lineNumberView.font = [UIFont fontWithName:@"Menlo" size:14];
    self.lineNumberView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    self.lineNumberView.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.lineNumberView.textAlignment = NSTextAlignmentRight;
    self.lineNumberView.editable = NO;
    self.lineNumberView.selectable = NO;
    self.lineNumberView.scrollEnabled = NO;
    self.lineNumberView.textContainerInset = UIEdgeInsetsMake(8, 4, 8, 4);
    [self.view addSubview:self.lineNumberView];

    [NSLayoutConstraint activateConstraints:@[
        [self.lineNumberView.topAnchor constraintEqualToAnchor:self.toolbar.bottomAnchor],
        [self.lineNumberView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.lineNumberView.widthAnchor constraintEqualToConstant:40],
        [self.lineNumberView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [self updateLineNumbers];
}

- (void)setupSyntaxColors {
    self.syntaxColors = @{
        @"keyword": [UIColor colorWithRed:1.0 green:0.4 blue:0.8 alpha:1.0],     // Pink
        @"string": [UIColor colorWithRed:1.0 green:0.8 blue:0.4 alpha:1.0],      // Yellow
        @"comment": [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0],     // Gray
        @"number": [UIColor colorWithRed:0.6 green:0.8 blue:1.0 alpha:1.0],      // Light blue
        @"function": [UIColor colorWithRed:0.4 green:1.0 blue:0.8 alpha:1.0],    // Cyan
        @"operator": [UIColor colorWithRed:1.0 green:0.6 blue:0.4 alpha:1.0],    // Orange
    };
}

- (void)setupKeywords {
    switch (self.language) {
        case CodeLanguagePython:
            self.keywords = @[@"def", @"class", @"if", @"elif", @"else", @"for", @"while",
                            @"import", @"from", @"return", @"try", @"except", @"finally",
                            @"with", @"as", @"pass", @"break", @"continue", @"lambda",
                            @"True", @"False", @"None", @"and", @"or", @"not", @"in",
                            @"is", @"print", @"range", @"len", @"str", @"int", @"float"];
            break;

        case CodeLanguageBash:
            self.keywords = @[@"if", @"then", @"else", @"elif", @"fi", @"case", @"esac",
                            @"for", @"while", @"do", @"done", @"function", @"return",
                            @"exit", @"break", @"continue", @"echo", @"read", @"cd",
                            @"ls", @"cat", @"grep", @"sed", @"awk", @"local", @"export"];
            break;

        case CodeLanguageJavaScript:
            self.keywords = @[@"function", @"var", @"let", @"const", @"if", @"else",
                            @"for", @"while", @"do", @"switch", @"case", @"break",
                            @"continue", @"return", @"try", @"catch", @"finally",
                            @"class", @"extends", @"new", @"this", @"super", @"async",
                            @"await", @"true", @"false", @"null", @"undefined"];
            break;

        case CodeLanguageC:
            self.keywords = @[@"int", @"char", @"float", @"double", @"void", @"struct",
                            @"if", @"else", @"for", @"while", @"do", @"switch", @"case",
                            @"break", @"continue", @"return", @"typedef", @"sizeof",
                            @"include", @"define", @"ifdef", @"ifndef", @"endif"];
            break;

        default:
            self.keywords = @[];
            break;
    }
}

- (void)textViewDidChange:(UITextView *)textView {
    self.hasUnsavedChanges = ![self.textView.text isEqualToString:self.originalContent];
    [self updateLineNumbers];

    // Debounced syntax highlighting
    [self.highlightTimer invalidate];
    self.highlightTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                           target:self
                                                         selector:@selector(applySyntaxHighlighting)
                                                         userInfo:nil
                                                          repeats:NO];
}

- (void)updateLineNumbers {
    NSString *text = self.textView.text;
    NSInteger lineCount = [[text componentsSeparatedByString:@"\n"] count];

    NSMutableString *lineNumbers = [NSMutableString string];
    for (NSInteger i = 1; i <= lineCount; i++) {
        [lineNumbers appendFormat:@"%ld\n", (long)i];
    }

    self.lineNumberView.text = lineNumbers;
}

- (void)applySyntaxHighlighting {
    if (self.language == CodeLanguagePlainText || self.keywords.count == 0) {
        return;
    }

    NSString *text = self.textView.text;
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:text];

    // Default attributes
    [attributedText addAttribute:NSFontAttributeName
                           value:[UIFont fontWithName:@"Menlo" size:14]
                           range:NSMakeRange(0, text.length)];
    [attributedText addAttribute:NSForegroundColorAttributeName
                           value:[UIColor whiteColor]
                           range:NSMakeRange(0, text.length)];

    // Highlight keywords
    for (NSString *keyword in self.keywords) {
        NSString *pattern = [NSString stringWithFormat:@"\\b%@\\b", keyword];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                               options:0
                                                                                 error:nil];
        [regex enumerateMatchesInString:text
                                options:0
                                  range:NSMakeRange(0, text.length)
                             usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
            [attributedText addAttribute:NSForegroundColorAttributeName
                                   value:self.syntaxColors[@"keyword"]
                                   range:match.range];
        }];
    }

    // Highlight strings
    [self highlightPattern:@"\"([^\"]*)\"" withColor:self.syntaxColors[@"string"] inText:attributedText];
    [self highlightPattern:@"'([^']*)'" withColor:self.syntaxColors[@"string"] inText:attributedText];

    // Highlight comments
    if (self.language == CodeLanguagePython) {
        [self highlightPattern:@"#.*$" withColor:self.syntaxColors[@"comment"] inText:attributedText];
    } else if (self.language == CodeLanguageBash) {
        [self highlightPattern:@"#.*$" withColor:self.syntaxColors[@"comment"] inText:attributedText];
    } else if (self.language == CodeLanguageJavaScript || self.language == CodeLanguageC) {
        [self highlightPattern:@"//.*$" withColor:self.syntaxColors[@"comment"] inText:attributedText];
        [self highlightPattern:@"/\\*.*?\\*/" withColor:self.syntaxColors[@"comment"] inText:attributedText];
    }

    // Highlight numbers
    [self highlightPattern:@"\\b\\d+\\.?\\d*\\b" withColor:self.syntaxColors[@"number"] inText:attributedText];

    // Preserve cursor position
    NSRange selectedRange = self.textView.selectedRange;
    self.textView.attributedText = attributedText;
    self.textView.selectedRange = selectedRange;
}

- (void)highlightPattern:(NSString *)pattern withColor:(UIColor *)color inText:(NSMutableAttributedString *)text {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:NSRegularExpressionAnchorsMatchLines
                                                                             error:nil];
    [regex enumerateMatchesInString:text.string
                            options:0
                              range:NSMakeRange(0, text.length)
                         usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        [text addAttribute:NSForegroundColorAttributeName
                     value:color
                     range:match.range];
    }];
}

- (void)cancelTapped {
    if (self.hasUnsavedChanges) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Unsaved Changes"
                                                                       message:@"You have unsaved changes. Discard them?"
                                                                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"Discard"
                                                 style:UIAlertActionStyleDestructive
                                               handler:^(UIAlertAction *action) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                 style:UIAlertActionStyleCancel
                                               handler:nil]];

        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)saveTapped {
    NSString *content = self.textView.text;

    if (self.filePath) {
        // Save to existing file
        [self saveToFile:content];

        self.originalContent = content;
        self.hasUnsavedChanges = NO;

        [self showSuccess:@"Saved"];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    } else if (self.filename && self.filename.length > 0) {
        // Show file picker to save new file
        [self showFilePicker:content];
    } else if (self.onSave) {
        // Fallback to onSave callback
        self.onSave(content);

        self.originalContent = content;
        self.hasUnsavedChanges = NO;

        [self showSuccess:@"Saved"];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    }
}

- (void)saveToFile:(NSString *)content {
    NSError *error = nil;
    [content writeToFile:self.filePath
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:&error];

    if (error) {
        [self showError:[NSString stringWithFormat:@"Failed to save: %@", error.localizedDescription]];
    }
}

- (void)loadFile {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:self.filePath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];

    if (error) {
        content = @"";
        [self showError:[NSString stringWithFormat:@"Failed to load: %@", error.localizedDescription]];
    }

    self.originalContent = content;
}

- (void)showLanguageOptions {
    UIAlertController *options = [UIAlertController alertControllerWithTitle:@"Select Language"
                                                                     message:nil
                                                              preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *languages = @[
        @[@"Auto-detect", @(CodeLanguageAuto)],
        @[@"Python", @(CodeLanguagePython)],
        @[@"Bash/Shell", @(CodeLanguageBash)],
        @[@"JavaScript", @(CodeLanguageJavaScript)],
        @[@"C/C++", @(CodeLanguageC)],
        @[@"HTML", @(CodeLanguageHTML)],
        @[@"JSON", @(CodeLanguageJSON)],
        @[@"Markdown", @(CodeLanguageMarkdown)],
        @[@"Plain Text", @(CodeLanguagePlainText)]
    ];

    for (NSArray *lang in languages) {
        NSString *name = lang[0];
        CodeLanguage langEnum = [lang[1] integerValue];

        [options addAction:[UIAlertAction actionWithTitle:name
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            self.language = langEnum;
            [self setupKeywords];
            [self applySyntaxHighlighting];
            [self.toolbar setItems:@[self.cancelButton,
                                   [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                                   [[UIBarButtonItem alloc] initWithCustomView:self.statusLabel],
                                   [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                                   [[UIBarButtonItem alloc] initWithTitle:[self languageName] style:UIBarButtonItemStylePlain target:self action:@selector(showLanguageOptions)],
                                   [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                                   self.saveButton]];
        }]];
    }

    [options addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];

    // For iPad
    if (options.popoverPresentationController) {
        options.popoverPresentationController.barButtonItem = self.toolbar.items[4];
    }

    [self presentViewController:options animated:YES completion:nil];
}

- (CodeLanguage)detectLanguageFromPath:(NSString *)path {
    NSString *ext = [[path pathExtension] lowercaseString];

    if ([ext isEqualToString:@"py"]) return CodeLanguagePython;
    if ([ext isEqualToString:@"sh"] || [ext isEqualToString:@"bash"]) return CodeLanguageBash;
    if ([ext isEqualToString:@"js"]) return CodeLanguageJavaScript;
    if ([ext isEqualToString:@"c"] || [ext isEqualToString:@"h"] || [ext isEqualToString:@"cpp"]) return CodeLanguageC;
    if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) return CodeLanguageHTML;
    if ([ext isEqualToString:@"json"]) return CodeLanguageJSON;
    if ([ext isEqualToString:@"md"] || [ext isEqualToString:@"markdown"]) return CodeLanguageMarkdown;

    return CodeLanguagePlainText;
}

- (NSString *)languageName {
    switch (self.language) {
        case CodeLanguageAuto: return @"Auto";
        case CodeLanguagePython: return @"Python";
        case CodeLanguageBash: return @"Bash";
        case CodeLanguageJavaScript: return @"JS";
        case CodeLanguageC: return @"C/C++";
        case CodeLanguageHTML: return @"HTML";
        case CodeLanguageJSON: return @"JSON";
        case CodeLanguageMarkdown: return @"Markdown";
        case CodeLanguagePlainText: return @"Text";
    }
}

- (void)showSuccess:(NSString *)message {
    self.statusLabel.text = message;
    self.statusLabel.textColor = [UIColor systemGreenColor];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.statusLabel.text = self.filePath ? [self.filePath lastPathComponent] : @"New File";
        self.statusLabel.textColor = [UIColor secondaryLabelColor];
    });
}

- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - File Picker

- (void)showFilePicker:(NSString *)content {
    if (@available(iOS 14.0, *)) {
        // Create temporary file
        NSString *tempDir = NSTemporaryDirectory();
        NSString *tempPath = [tempDir stringByAppendingPathComponent:self.filename];

        NSError *writeError = nil;
        [content writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];

        if (writeError) {
            [self showError:@"Failed to prepare file for saving"];
            return;
        }

        NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[tempURL]];
        picker.delegate = self;
        picker.modalPresentationStyle = UIModalPresentationFormSheet;

        NSLog(@"📝 Presenting document picker for file: %@", self.filename);
        [self presentViewController:picker animated:YES completion:nil];
    } else {
        [self showError:@"File picker requires iOS 14 or later"];
    }
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) {
        NSURL *selectedURL = urls[0];
        NSLog(@"✅ File saved to: %@", selectedURL.path);

        self.originalContent = self.textView.text;
        self.hasUnsavedChanges = NO;

        [self showSuccess:@"Saved"];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"📝 File save cancelled");
}

@end
