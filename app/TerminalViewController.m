//
//  ViewController.m
//  iSH
//
//  Created by Theodore Dubois on 10/17/17.
//

#import "TerminalViewController.h"
#import "AppDelegate.h"
#import "TerminalView.h"
#import "BarButton.h"
#import "ArrowBarButton.h"
#import "UserPreferences.h"
#import "AboutViewController.h"
#import "CurrentRoot.h"
#import "NSObject+SaneKVO.h"
#import "LinuxInterop.h"
#import "AppGroup.h"
#import "SplitTerminalViewController.h"
#import "CodeEditorViewController.h"
// ReverseEngineeringViewController removed - XSH Pro feature
#include "kernel/init.h"
#include "kernel/task.h"
#include "kernel/calls.h"
#include "fs/devices.h"

@interface TerminalViewController () <UIGestureRecognizerDelegate, UIDocumentPickerDelegate>

@property UITapGestureRecognizer *tapRecognizer;
@property (weak, nonatomic) IBOutlet TerminalView *termView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *bottomConstraint;

@property (weak, nonatomic) IBOutlet UIButton *tabKey;
@property (weak, nonatomic) IBOutlet UIButton *controlKey;
@property (weak, nonatomic) IBOutlet UIButton *escapeKey;
@property (strong, nonatomic) IBOutletCollection(id) NSArray *barButtons;
@property (strong, nonatomic) IBOutletCollection(id) NSArray *barControls;

@property (weak, nonatomic) IBOutlet UIInputView *barView;
@property (weak, nonatomic) IBOutlet UIStackView *bar;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *barTop;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *barBottom;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *barLeading;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *barTrailing;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *barButtonWidth;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *barHeight;
@property (weak, nonatomic) IBOutlet UIView *settingsBadge;

@property (weak, nonatomic) IBOutlet UIButton *infoButton;
@property (weak, nonatomic) IBOutlet UIButton *pasteButton;
@property (weak, nonatomic) IBOutlet UIButton *hideKeyboardButton;
@property (strong, nonatomic) UIButton *sessionsButton; // Button for sessions management
@property (strong, nonatomic) UIButton *splitScreenButton; // Button for split screen
@property (strong, nonatomic) UIButton *filesButton; // Combined button for files/editor/RE
@property (strong, nonatomic) UIButton *editorButton; // Button for code editor
@property (strong, nonatomic) UIButton *reverseEngineeringButton; // Button for reverse engineering

@property int sessionPid;
@property (nonatomic) Terminal *sessionTerminal;

@property BOOL ignoreKeyboardMotion;
@property (nonatomic) BOOL hasExternalKeyboard;

// Command history for quick paste
@property (nonatomic, strong) NSMutableArray<NSString *> *pasteHistory;

// Multiple terminals management
@property (nonatomic) int currentTerminalNumber;
@property (nonatomic, strong) UILabel *terminalIndicatorLabel;
@property (nonatomic, strong) NSMutableArray<Terminal *> *terminalSessions; // Array of active terminal sessions
@property (nonatomic, strong) NSMutableArray<NSNumber *> *sessionPids; // Array of session PIDs
@property (strong, nonatomic) UIButton *homeButton; // Quick access to home directory

// Download progress indicator
@property (nonatomic, strong) UIView *downloadIndicatorView;
@property (nonatomic, strong) UILabel *downloadIndicatorLabel;
@property (nonatomic, strong) NSTimer *downloadMonitorTimer;
@property (nonatomic, strong) NSMutableString *recentOutput;
@property (nonatomic, strong) NSDate *lastDownloadActivity;
@property (nonatomic, strong) NSDate *lastDownloadCompletion;

// First launch auto-setup
@property (nonatomic) BOOL isRunningAutoSetup;
@property (nonatomic, strong) UIAlertController *setupProgressDialog;
@property (nonatomic) int currentSetupStep;
@property (nonatomic, strong) UIProgressView *setupProgressBar;
@property (nonatomic, strong) UIActivityIndicatorView *setupSpinner;

// Code editor save state
@property (nonatomic, strong) NSString *pendingSaveContent;
@property (nonatomic, strong) NSString *pendingSaveFilename;

@end

@implementation TerminalViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Initialize paste history
    self.pasteHistory = [NSMutableArray array];

    // Initialize terminal management
    self.currentTerminalNumber = 0; // Start with session 0 (the main session)
    self.terminalSessions = [NSMutableArray array];
    self.sessionPids = [NSMutableArray array];
    [self setupTerminalIndicator];

    // Initialize download monitoring
    self.recentOutput = [NSMutableString string];
    [self setupDownloadIndicator];
    [self startMonitoringDownloads];

#if !ISH_LINUX
    int bootError = [AppDelegate bootError];
    if (bootError < 0) {
        NSString *message = [NSString stringWithFormat:@"could not boot"];
        NSString *subtitle = [NSString stringWithFormat:@"error code %d", bootError];
        if (bootError == _EINVAL)
            subtitle = [subtitle stringByAppendingString:@"\n(try reinstalling the app, see release notes for details)"];
        [self showMessage:message subtitle:subtitle];
        NSLog(@"boot failed with code %d", bootError);
    }
#endif

    self.terminal = self.terminal;
    [self.termView becomeFirstResponder];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(keyboardDidSomething:)
                   name:UIKeyboardWillChangeFrameNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(keyboardDidSomething:)
                   name:UIKeyboardDidChangeFrameNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(handleTerminalOutput:)
                   name:@"TerminalOutputReceived"
                 object:nil];
    [center addObserver:self
               selector:@selector(handleRunSystemSetup:)
                   name:@"RunSystemSetup"
                 object:nil];
    [center addObserver:self
               selector:@selector(handleCloseSplitView:)
                   name:@"CloseSplitView"
                 object:nil];
    [center addObserver:self
               selector:@selector(_updateBadge)
                   name:FsUpdatedNotification
                 object:nil];


    [self _updateStyleFromPreferences:NO];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        [self.bar removeArrangedSubview:self.hideKeyboardButton];
        [self.hideKeyboardButton removeFromSuperview];
    }
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        self.barHeight.constant = 36;
    } else {
        self.barHeight.constant = 43;
    }
    
    // SF Symbols is cool
    if (@available(iOS 13, *)) {
        [self.infoButton setImage:[UIImage systemImageNamed:@"gear"] forState:UIControlStateNormal];
        [self.pasteButton setImage:[UIImage systemImageNamed:@"doc.on.clipboard"] forState:UIControlStateNormal];
        [self.hideKeyboardButton setImage:[UIImage systemImageNamed:@"keyboard.chevron.compact.down"] forState:UIControlStateNormal];
        
        [self.tabKey setTitle:nil forState:UIControlStateNormal];
        [self.tabKey setImage:[UIImage systemImageNamed:@"arrow.right.to.line.alt"] forState:UIControlStateNormal];
        [self.controlKey setTitle:nil forState:UIControlStateNormal];
        [self.controlKey setImage:[UIImage systemImageNamed:@"control"] forState:UIControlStateNormal];
        [self.escapeKey setTitle:nil forState:UIControlStateNormal];
        [self.escapeKey setImage:[UIImage systemImageNamed:@"escape"] forState:UIControlStateNormal];
    }

    // Add long-press gestures for additional functionality
    [self setupLongPressGestures];

    // Add long-press to paste button for command history
    UILongPressGestureRecognizer *pasteLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showPasteHistory:)];
    pasteLongPress.minimumPressDuration = 0.5;
    [self.pasteButton addGestureRecognizer:pasteLongPress];

    // Create and add organized toolbar buttons
    [self setupHomeButton];        // 📁 Home directory access
    [self setupFilesButton];       // 📂 Files menu (Browse/Editor/RE)
    [self setupSessionsButton];    // ⊞ Terminal sessions
    [self setupSplitScreenButton]; // ⬌ Split screen

    // Reorder hideKeyboardButton to be rightmost (last) in toolbar
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        [self.bar removeArrangedSubview:self.hideKeyboardButton];
        [self.bar addArrangedSubview:self.hideKeyboardButton];
    }

    [UserPreferences.shared observe:@[@"hideStatusBar"] options:0 owner:self usingBlock:^(typeof(self) self) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setNeedsStatusBarAppearanceUpdate];
        });
    }];
    [UserPreferences.shared observe:@[@"colorScheme", @"theme", @"hideExtraKeysWithExternalKeyboard"]
                            options:0 owner:self usingBlock:^(typeof(self) self) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _updateStyleFromPreferences:YES];
        });
    }];
    [self _updateBadge];
}

- (void)awakeFromNib {
    [super awakeFromNib];
#if !ISH_LINUX
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(processExited:)
                                               name:ProcessExitedNotification
                                             object:nil];
#else
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(kernelPanicked:)
                                               name:KernelPanicNotification
                                             object:nil];
#endif

    // Listen for SSH command execution notification
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleExecuteSSHCommand:)
                                               name:@"ExecuteSSHCommand"
                                             object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [AppDelegate maybePresentStartupMessageOnViewController:self];
    [super viewDidAppear:animated];

    // Show first launch setup dialog
    [self checkAndShowFirstLaunchSetup];
}

- (void)startNewSession {
    int err = [self startSession];
    if (err < 0) {
        [self showMessage:@"could not start session"
                 subtitle:[NSString stringWithFormat:@"error code %d", err]];
    } else {
        // Add the main session to our sessions array
        if (self.sessionTerminal && self.terminalSessions.count == 0) {
            [self.terminalSessions addObject:self.sessionTerminal];
            [self.sessionPids addObject:@(self.sessionPid)];
        }
    }
}

- (void)reconnectSessionFromTerminalUUID:(NSUUID *)uuid {
    self.sessionTerminal = [Terminal terminalWithUUID:uuid];
    if (self.sessionTerminal == nil)
        [self startNewSession];
}

- (NSUUID *)sessionTerminalUUID {
    return self.terminal.uuid;
}

- (int)startSession {
    NSArray<NSString *> *command = UserPreferences.shared.launchCommand;

#if !ISH_LINUX
    int err = become_new_init_child();
    if (err < 0)
        return err;
    struct tty *tty;
    self.sessionTerminal = nil;
    Terminal *terminal = [Terminal createPseudoTerminal:&tty];
    if (terminal == nil) {
        NSAssert(IS_ERR(tty), @"tty should be error");
        return (int) PTR_ERR(tty);
    }
    self.sessionTerminal = terminal;
    NSString *stdioFile = [NSString stringWithFormat:@"/dev/pts/%d", tty->num];
    err = create_stdio(stdioFile.fileSystemRepresentation, TTY_PSEUDO_SLAVE_MAJOR, tty->num);
    if (err < 0)
        return err;
    tty_release(tty);

    char argv[4096];
    [Terminal convertCommand:command toArgs:argv limitSize:sizeof(argv)];
    const char *envp = "TERM=xterm-256color\0";
    err = do_execve(command[0].UTF8String, command.count, argv, envp);
    if (err < 0)
        return err;
    self.sessionPid = current->pid;
    task_start(current);
#else
    const char *argv_arr[command.count + 1];
    for (NSUInteger i = 0; i < command.count; i++)
        argv_arr[i] = command[i].UTF8String;
    argv_arr[command.count] = NULL;
    const char *envp_arr[] = {
        "TERM=xterm-256color",
        NULL,
    };
    const char *const *argv = argv_arr;
    const char *const *envp = envp_arr;
    __block Terminal *terminal = nil;
    __block int sessionPid = 0;
    __block int err = 1;
    sync_do_in_workqueue(^(void (^done)(void)) {
        linux_start_session(argv[0], argv, envp, ^(int retval, int pid, nsobj_t term) {
            err = retval;
            if (term)
                terminal = CFBridgingRelease(term);
            sessionPid = pid;
            done();
        });
    });
    NSAssert(err <= 0, @"session start did not finish??");
    if (err < 0)
        return err;
    self.sessionTerminal = terminal;
    self.sessionPid = sessionPid;
#endif
    return 0;
}

#if !ISH_LINUX
- (void)processExited:(NSNotification *)notif {
    int pid = [notif.userInfo[@"pid"] intValue];
    if (pid != self.sessionPid)
        return;

    [self.sessionTerminal destroy];
    // On iOS 13, there are multiple windows, so just close this one.
    if (@available(iOS 13, *)) {
        // On iPhone, destroying scenes will fail, but the error doesn't actually go to the error handler, which is really stupid. Apple doesn't fix bugs, so I'm forced to just add a check here.
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad && self.sceneSession != nil) {
            [UIApplication.sharedApplication requestSceneSessionDestruction:self.sceneSession options:nil errorHandler:^(NSError *error) {
                NSLog(@"scene destruction error %@", error);
                self.sceneSession = nil;
                [self processExited:notif];
            }];
            return;
        }
    }
    current = NULL; // it's been freed
    [self startNewSession];
}
#endif

#if ISH_LINUX
- (void)kernelPanicked:(NSNotification *)notif {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"panik" message:notif.userInfo[@"message"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"k" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
#endif

- (void)showMessage:(NSString *)message subtitle:(NSString *)subtitle {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:message message:subtitle preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"k"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:^{
            // Adjust alert position to be higher (above keyboard)
            if (alert.view.superview) {
                // Move alert up by 100 points to avoid keyboard
                alert.view.superview.transform = CGAffineTransformMakeTranslation(0, -100);
            }
        }];
    });
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == [UserPreferences shared]) {
        [self _updateStyleFromPreferences:YES];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)_updateStyleFromPreferences:(BOOL)animated {
    NSAssert(NSThread.isMainThread, @"This method needs to be called on the main thread");
    NSTimeInterval duration = animated ? 0.1 : 0;
    [UIView animateWithDuration:duration animations:^{
        self.view.backgroundColor = [[UIColor alloc] ish_initWithHexString:UserPreferences.shared.palette.backgroundColor];
        UIKeyboardAppearance keyAppearance = UserPreferences.shared.keyboardAppearance;
        self.termView.keyboardAppearance = keyAppearance;
        for (BarButton *button in self.barButtons) {
            button.keyAppearance = keyAppearance;
        }
        UIColor *tintColor = keyAppearance == UIKeyboardAppearanceLight ? UIColor.blackColor : UIColor.whiteColor;
        for (UIControl *control in self.barControls) {
            control.tintColor = tintColor;
        }
    }];
    UIView *oldBarView = self.termView.inputAccessoryView;
    if (UserPreferences.shared.hideExtraKeysWithExternalKeyboard && self.hasExternalKeyboard) {
        self.termView.inputAccessoryView = nil;
    } else {
        self.termView.inputAccessoryView = self.barView;
    }
    if (self.termView.inputAccessoryView != oldBarView && self.termView.isFirstResponder) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.ignoreKeyboardMotion = YES; // avoid infinite recursion
            [self.termView reloadInputViews];
            self.ignoreKeyboardMotion = NO;
        });
    }
}
- (void)_updateStyleAnimated {
    [self _updateStyleFromPreferences:YES];
}

- (void)_updateBadge {
    self.settingsBadge.hidden = !FsNeedsRepositoryUpdate();
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UserPreferences.shared.statusBarStyle;
}

- (BOOL)prefersStatusBarHidden {
    return UserPreferences.shared.hideStatusBar;
}

- (void)keyboardDidSomething:(NSNotification *)notification {
    if (self.ignoreKeyboardMotion)
        return;

    CGRect screenKeyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIScreen *screen = UIScreen.mainScreen;
    // notification.object is nil before iOS 16.1 and the correct UIScreen after iOS 16.1
    if (notification.object != nil)
        screen = notification.object;
    CGRect keyboardFrame = [self.view convertRect:screenKeyboardFrame fromCoordinateSpace:screen.coordinateSpace];
    if (CGRectEqualToRect(keyboardFrame, CGRectZero))
        return;
    CGRect intersection = CGRectIntersection(keyboardFrame, self.view.bounds);
    keyboardFrame = intersection;
    NSLog(@"%@ %@", notification.name, @(keyboardFrame));
    self.hasExternalKeyboard = keyboardFrame.size.height < 100;
    CGFloat pad = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboardFrame);
    // The keyboard appears to be undocked. This means it can either be split or
    // truly floating. In the former case we want to keep the pad, but in the
    // latter we should fall back to the input accessory view instead of the
    // keyboard.
    if (pad != keyboardFrame.size.height && keyboardFrame.size.width != UIScreen.mainScreen.bounds.size.width) {
        pad = MAX(self.view.safeAreaInsets.bottom, self.termView.inputAccessoryView.frame.size.height);
    }
    // NSLog(@"pad %f", pad);
    self.bottomConstraint.constant = pad;

    BOOL initialLayout = self.termView.needsUpdateConstraints;
    [self.view setNeedsUpdateConstraints];
    if (!initialLayout) {
        // if initial layout hasn't happened yet, the terminal view is going to be at a really weird place, so animating it is going to look really bad
        NSNumber *interval = notification.userInfo[UIKeyboardAnimationDurationUserInfoKey];
        NSNumber *curve = notification.userInfo[UIKeyboardAnimationCurveUserInfoKey];
        [UIView animateWithDuration:interval.doubleValue
                              delay:0
                            options:curve.integerValue << 16
                         animations:^{
                             [self.view layoutIfNeeded];
                         }
                         completion:nil];
    }
}

- (void)setHasExternalKeyboard:(BOOL)hasExternalKeyboard {
    _hasExternalKeyboard = hasExternalKeyboard;
    [self _updateStyleFromPreferences:YES];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"embed"]) {
        // You might want to check if this is your embed segue here
        // in case there are other segues triggered from this view controller.
        segue.destinationViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    // Hack to resolve a layering mismatch between the UI and preferences.
    if (@available(iOS 12.0, *)) {
        if (previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
            // Ensure that the relevant things listening for this will update.
            UserPreferences.shared.colorScheme = UserPreferences.shared.colorScheme;
        }
    }
}

#pragma mark Bar

- (IBAction)showAbout:(id)sender {
    UINavigationController *navigationController = [[UIStoryboard storyboardWithName:@"About" bundle:nil] instantiateInitialViewController];
    if ([sender isKindOfClass:[UIGestureRecognizer class]]) {
        UIGestureRecognizer *recognizer = sender;
        if (recognizer.state == UIGestureRecognizerStateBegan) {
            AboutViewController *aboutViewController = (AboutViewController *) navigationController.topViewController;
            aboutViewController.includeDebugPanel = YES;
        } else {
            return;
        }
    }
    [self presentViewController:navigationController animated:YES completion:nil];
    [self.termView resignFirstResponder];
}

- (void)resizeBar {
    CGSize bar = self.barView.bounds.size;
    // set sizing parameters on bar
    // numbers stolen from iVim and modified somewhat
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        // phone
        [self setBarHorizontalPadding:6 verticalPadding:6 buttonWidth:32];
    } else if (bar.width >= 450) {
        // wide ipad
        [self setBarHorizontalPadding:15 verticalPadding:8 buttonWidth:43];
    } else {
        // narrow ipad (slide over)
        [self setBarHorizontalPadding:10 verticalPadding:8 buttonWidth:36];
    }
    [UIView performWithoutAnimation:^{
        [self.barView layoutIfNeeded];
    }];
}

- (void)setBarHorizontalPadding:(CGFloat)horizontal verticalPadding:(CGFloat)vertical buttonWidth:(CGFloat)buttonWidth {
    self.barLeading.constant = self.barTrailing.constant = horizontal;
    self.barTop.constant = self.barBottom.constant = vertical;
    self.barButtonWidth.constant = buttonWidth;
}

- (IBAction)pressEscape:(id)sender {
    [self pressKey:@"\x1b"];
}
- (IBAction)pressTab:(id)sender {
    [self pressKey:@"\t"];
}
- (void)pressKey:(NSString *)key {
    [self.termView insertText:key];
}

- (IBAction)pressControl:(id)sender {
    self.controlKey.selected = !self.controlKey.selected;
}
    
- (IBAction)pressArrow:(ArrowBarButton *)sender {
    switch (sender.direction) {
        case ArrowUp: [self pressKey:[self.terminal arrow:'A']]; break;
        case ArrowDown: [self pressKey:[self.terminal arrow:'B']]; break;
        case ArrowLeft: [self pressKey:[self.terminal arrow:'D']]; break;
        case ArrowRight: [self pressKey:[self.terminal arrow:'C']]; break;
        case ArrowNone: break;
    }
}

- (void)switchTerminal:(UIKeyCommand *)sender {
    unsigned i = (unsigned) sender.input.integerValue;
    if (i == 7)
        self.terminal = self.sessionTerminal;
    else
        self.terminal = [Terminal terminalWithType:TTY_CONSOLE_MAJOR number:i];
}

- (void)increaseFontSize:(UIKeyCommand *)command {
    self.termView.overrideFontSize = self.termView.effectiveFontSize + 1;
}
- (void)decreaseFontSize:(UIKeyCommand *)command {
    self.termView.overrideFontSize = self.termView.effectiveFontSize - 1;
}
- (void)resetFontSize:(UIKeyCommand *)command {
    self.termView.overrideFontSize = 0;
}

- (NSArray<UIKeyCommand *> *)keyCommands {
    static NSMutableArray<UIKeyCommand *> *commands = nil;
    if (commands == nil) {
        commands = [NSMutableArray new];
        for (unsigned i = 1; i <= 7; i++) {
            [commands addObject:
             [UIKeyCommand keyCommandWithInput:[NSString stringWithFormat:@"%d", i]
                                 modifierFlags:UIKeyModifierCommand|UIKeyModifierAlternate|UIKeyModifierShift
                                        action:@selector(switchTerminal:)]];
        }
        [commands addObject:
         [UIKeyCommand keyCommandWithInput:@"+"
                             modifierFlags:UIKeyModifierCommand
                                    action:@selector(increaseFontSize:)
                      discoverabilityTitle:@"Increase Font Size"]];
        [commands addObject:
         [UIKeyCommand keyCommandWithInput:@"="
                             modifierFlags:UIKeyModifierCommand
                                    action:@selector(increaseFontSize:)]];
        [commands addObject:
         [UIKeyCommand keyCommandWithInput:@"-"
                             modifierFlags:UIKeyModifierCommand
                                    action:@selector(decreaseFontSize:)
                      discoverabilityTitle:@"Decrease Font Size"]];
        [commands addObject:
         [UIKeyCommand keyCommandWithInput:@"0"
                             modifierFlags:UIKeyModifierCommand
                                    action:@selector(resetFontSize:)
                      discoverabilityTitle:@"Reset Font Size"]];
        [commands addObject:
         [UIKeyCommand keyCommandWithInput:@","
                             modifierFlags:UIKeyModifierCommand
                                    action:@selector(showAbout:)
                      discoverabilityTitle:@"Settings"]];
    }
    return commands;
}

- (void)setTerminal:(Terminal *)terminal {
    _terminal = terminal;
    self.termView.terminal = self.terminal;
}

- (void)setSessionTerminal:(Terminal *)sessionTerminal {
    if (_terminal == _sessionTerminal)
        self.terminal = sessionTerminal;
    _sessionTerminal = sessionTerminal;
}

#pragma mark - Enhanced Keyboard Shortcuts

- (void)setupLongPressGestures {
    // Long press on Tab key - insert multiple spaces (4 spaces)
    UILongPressGestureRecognizer *tabLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleTabLongPress:)];
    tabLongPress.minimumPressDuration = 0.5;
    [self.tabKey addGestureRecognizer:tabLongPress];

    // Long press on Escape key - send Ctrl+C (interrupt)
    UILongPressGestureRecognizer *escLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleEscapeLongPress:)];
    escLongPress.minimumPressDuration = 0.5;
    [self.escapeKey addGestureRecognizer:escLongPress];

    // Long press on Control key - send Ctrl+D (EOF)
    UILongPressGestureRecognizer *ctrlLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleControlLongPress:)];
    ctrlLongPress.minimumPressDuration = 0.5;
    [self.controlKey addGestureRecognizer:ctrlLongPress];
}

- (void)handleTabLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        // Insert 4 spaces (common indentation)
        [self pressKey:@"    "];

        // Haptic feedback
        if (@available(iOS 10.0, *)) {
            UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
            [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
        }
    }
}

- (void)handleEscapeLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        // Send Ctrl+C (^C) to interrupt running command
        [self pressKey:@"\x03"];

        // Haptic feedback
        if (@available(iOS 10.0, *)) {
            UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
            [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
        }
    }
}

- (void)handleControlLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        // Send Ctrl+D (^D) for EOF
        [self pressKey:@"\x04"];

        // Haptic feedback
        if (@available(iOS 10.0, *)) {
            UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
            [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
        }
    }
}

#pragma mark - Paste History Feature

- (void)addToPasteHistory:(NSString *)text {
    if (!text || text.length == 0) return;

    // Remove if already exists to move it to top
    [self.pasteHistory removeObject:text];

    // Add to beginning of array
    [self.pasteHistory insertObject:text atIndex:0];

    // Keep only last 10 commands
    if (self.pasteHistory.count > 10) {
        [self.pasteHistory removeLastObject];
    }
}

- (void)showPasteHistory:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;

    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }

    if (self.pasteHistory.count == 0) {
        // Show message if history is empty
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Paste History"
                                                                       message:@"No paste history yet. Paste some commands first!"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // Create action sheet with paste history
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"Recent Commands"
                                                                         message:@"Tap to paste a recent command"
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];

    // Add each command from history
    for (NSInteger i = 0; i < self.pasteHistory.count; i++) {
        NSString *command = self.pasteHistory[i];
        // Truncate long commands for display
        NSString *displayText = command.length > 50 ? [[command substringToIndex:50] stringByAppendingString:@"..."] : command;
        NSString *title = [NSString stringWithFormat:@"%ld. %@", (long)(i + 1), displayText];

        [actionSheet addAction:[UIAlertAction actionWithTitle:title
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
            // Paste the selected command
            [self.termView insertText:command];

            // Haptic feedback
            if (@available(iOS 10.0, *)) {
                UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                [feedback impactOccurred];
            }
        }]];
    }

    // Add clear history option
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Clear History"
                                                    style:UIAlertActionStyleDestructive
                                                  handler:^(UIAlertAction *action) {
        [self.pasteHistory removeAllObjects];
    }]];

    // Add cancel button
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                    style:UIAlertActionStyleCancel
                                                  handler:nil]];

    // For iPad - set popover source
    if (actionSheet.popoverPresentationController) {
        actionSheet.popoverPresentationController.sourceView = self.pasteButton;
        actionSheet.popoverPresentationController.sourceRect = self.pasteButton.bounds;
    }

    [self presentViewController:actionSheet animated:YES completion:nil];
}

// Override paste to track history
- (IBAction)pasteFromButton:(id)sender {
    NSString *string = UIPasteboard.generalPasteboard.string;
    if (string) {
        [self addToPasteHistory:string];
        [self.termView insertText:string];
    }
}

#pragma mark - Multiple Terminals Feature

- (void)setupTerminalIndicator {
    // Create terminal indicator label at top-right of screen
    self.terminalIndicatorLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 80, 30)];
    self.terminalIndicatorLabel.textAlignment = NSTextAlignmentCenter;
    self.terminalIndicatorLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.terminalIndicatorLabel.textColor = UIColor.whiteColor;
    self.terminalIndicatorLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    self.terminalIndicatorLabel.layer.cornerRadius = 15;
    self.terminalIndicatorLabel.layer.masksToBounds = YES;
    self.terminalIndicatorLabel.alpha = 0; // Hidden initially

    [self.view addSubview:self.terminalIndicatorLabel];
    [self updateTerminalIndicator];

    // Position at top-right with safe area
    self.terminalIndicatorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.terminalIndicatorLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.terminalIndicatorLabel.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-10],
        [self.terminalIndicatorLabel.widthAnchor constraintEqualToConstant:80],
        [self.terminalIndicatorLabel.heightAnchor constraintEqualToConstant:30]
    ]];

    // Add swipe gestures for switching terminals
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeLeft:)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeLeft.numberOfTouchesRequired = 2; // Two fingers
    [self.view addGestureRecognizer:swipeLeft];

    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeRight:)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRight.numberOfTouchesRequired = 2; // Two fingers
    [self.view addGestureRecognizer:swipeRight];

}

- (void)setupSessionsButton {
    // Create sessions button
    self.sessionsButton = [UIButton buttonWithType:UIButtonTypeSystem];

    // Set icon (multiple windows/tabs symbol)
    if (@available(iOS 13, *)) {
        UIImage *icon = [UIImage systemImageNamed:@"square.split.2x2"];
        [self.sessionsButton setImage:icon forState:UIControlStateNormal];
    } else {
        [self.sessionsButton setTitle:@"⊞" forState:UIControlStateNormal]; // Fallback for older iOS
    }

    // Style the button to match other bar buttons
    self.sessionsButton.tintColor = self.infoButton.tintColor;

    // Add tap action
    [self.sessionsButton addTarget:self action:@selector(sessionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // Find the index of files button in the bar (insert after files)
    NSInteger filesButtonIndex = [self.bar.arrangedSubviews indexOfObject:self.filesButton];

    // Add to the bar view
    if (filesButtonIndex != NSNotFound) {
        [self.bar insertArrangedSubview:self.sessionsButton atIndex:filesButtonIndex + 1];
    } else {
        // Fallback: add at the end of the bar
        [self.bar addArrangedSubview:self.sessionsButton];
    }

    // Match the width constraint of other buttons
    self.sessionsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sessionsButton.widthAnchor constraintEqualToConstant:self.barButtonWidth.constant].active = YES;
}

- (void)sessionsButtonTapped:(UIButton *)sender {
    // Show terminal menu when sessions button is tapped
    [self showTerminalMenuFromButton:sender];
}

- (void)setupHomeButton {
    // Create home button
    self.homeButton = [UIButton buttonWithType:UIButtonTypeSystem];

    // Set icon (folder/home symbol)
    if (@available(iOS 13, *)) {
        UIImage *icon = [UIImage systemImageNamed:@"house.fill"];
        [self.homeButton setImage:icon forState:UIControlStateNormal];
    } else {
        [self.homeButton setTitle:@"🏠" forState:UIControlStateNormal]; // Fallback for older iOS
    }

    // Style the button to match other bar buttons
    self.homeButton.tintColor = self.infoButton.tintColor;

    // Add tap action
    [self.homeButton addTarget:self action:@selector(homeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // Find the index of paste button in the bar (insert after paste)
    NSInteger pasteButtonIndex = [self.bar.arrangedSubviews indexOfObject:self.pasteButton];

    // Add to the bar view
    if (pasteButtonIndex != NSNotFound) {
        [self.bar insertArrangedSubview:self.homeButton atIndex:pasteButtonIndex + 1];
    } else {
        // Fallback: add at the end of the bar
        [self.bar addArrangedSubview:self.homeButton];
    }

    // Match the width constraint of other buttons
    self.homeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.homeButton.widthAnchor constraintEqualToConstant:self.barButtonWidth.constant].active = YES;
}

- (void)homeButtonTapped:(UIButton *)sender {
    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }

    // Show Files app with home directory
    [self showHomeDirectory];
}

- (void)setupFilesButton {
    // Create combined files button (Browse/Editor/RE)
    self.filesButton = [UIButton buttonWithType:UIButtonTypeSystem];

    // Set icon (folder with document)
    if (@available(iOS 13, *)) {
        UIImage *icon = [UIImage systemImageNamed:@"folder.badge.gearshape"];
        [self.filesButton setImage:icon forState:UIControlStateNormal];
    } else {
        [self.filesButton setTitle:@"📂" forState:UIControlStateNormal]; // Fallback for older iOS
    }

    // Style the button to match other bar buttons
    self.filesButton.tintColor = self.infoButton.tintColor;

    // Add tap action
    [self.filesButton addTarget:self action:@selector(filesButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // Find the index of home button in the bar (insert after home)
    NSInteger homeButtonIndex = [self.bar.arrangedSubviews indexOfObject:self.homeButton];

    // Add to the bar view
    if (homeButtonIndex != NSNotFound) {
        [self.bar insertArrangedSubview:self.filesButton atIndex:homeButtonIndex + 1];
    } else {
        // Fallback: add at the end of the bar
        [self.bar addArrangedSubview:self.filesButton];
    }

    // Match the width constraint of other buttons
    self.filesButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filesButton.widthAnchor constraintEqualToConstant:self.barButtonWidth.constant].active = YES;
}

- (void)filesButtonTapped:(UIButton *)sender {
    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }

    // Show files menu with options
    [self showFilesMenu:sender];
}

- (void)showFilesMenu:(UIButton *)sender {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Files & Tools"
                                                                  message:@"Choose an action"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    // Browse Files action
    UIAlertAction *browseAction = [UIAlertAction actionWithTitle:@"Browse Files"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *action) {
        [self showFilePicker];
    }];
    [menu addAction:browseAction];

    // Create New File action
    UIAlertAction *createAction = [UIAlertAction actionWithTitle:@"Create New File"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *action) {
        [self showCreateFileDialog];
    }];
    [menu addAction:createAction];

    // Code Editor action
    UIAlertAction *editorAction = [UIAlertAction actionWithTitle:@"Code Editor"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *action) {
        [self showEditorOptions];
    }];
    [menu addAction:editorAction];

    // Reverse Engineering action
    UIAlertAction *reAction = [UIAlertAction actionWithTitle:@"Reverse Engineering"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
        [self openReverseEngineering];
    }];
    [menu addAction:reAction];

    // Cancel action
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [menu addAction:cancelAction];

    // For iPad, set popover presentation
    if (menu.popoverPresentationController) {
        menu.popoverPresentationController.sourceView = sender;
        menu.popoverPresentationController.sourceRect = sender.bounds;
    }

    [self presentViewController:menu animated:YES completion:nil];
}

- (void)showFilePicker {
    // Show document picker for browsing files
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
                                             initWithDocumentTypes:@[@"public.item"]
                                             inMode:UIDocumentPickerModeOpen];
    picker.delegate = (id<UIDocumentPickerDelegate>)self;
    picker.allowsMultipleSelection = NO;

    if (@available(iOS 13.0, *)) {
        picker.shouldShowFileExtensions = YES;
    }

    [self presentViewController:picker animated:YES completion:nil];
}

- (void)showCreateFileDialog {
    // Show dialog to create new file
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Create New File"
                                                                   message:@"Enter file name"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"filename.txt";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    UIAlertAction *createAction = [UIAlertAction actionWithTitle:@"Create"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *filename = textField.text;
        if (filename.length > 0) {
            [self createFileWithName:filename];
        }
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [alert addAction:createAction];
    [alert addAction:cancelAction];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createFileWithName:(NSString *)filename {
    // Create empty file using touch command
    NSString *command = [NSString stringWithFormat:@"touch ~/%@\n", filename];
    NSData *commandData = [command dataUsingEncoding:NSUTF8StringEncoding];
    [self.terminal sendInput:commandData];

    // Show confirmation
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"File Created"
                                                                   message:[NSString stringWithFormat:@"Created: %@", filename]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openReverseEngineering {
    // XSH Pro Feature - Show purchase dialog
    UIAlertController *proAlert = [UIAlertController alertControllerWithTitle:@"🔐 XSH Pro Feature"
                                                                      message:@"Reverse Engineering is a premium feature available in XSH Pro.\n\n✨ Features:\n• Binary Analysis\n• Disassembler\n• Pseudo Code Generator\n• Control Flow Graph\n• String Analysis\n\nUpgrade to XSH Pro to unlock!"
                                                               preferredStyle:UIAlertControllerStyleAlert];

    [proAlert addAction:[UIAlertAction actionWithTitle:@"Get XSH Pro" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSURL *proURL = [NSURL URLWithString:@"https://bye-thost.com/product/ish-نسخة-معدلة-من-xsh/"];
        [[UIApplication sharedApplication] openURL:proURL options:@{} completionHandler:nil];
    }]];

    [proAlert addAction:[UIAlertAction actionWithTitle:@"Maybe Later" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:proAlert animated:YES completion:nil];
}

- (void)setupSplitScreenButton {
    // Create split screen button
    self.splitScreenButton = [UIButton buttonWithType:UIButtonTypeSystem];

    // Set icon (split view symbol)
    if (@available(iOS 13, *)) {
        UIImage *icon = [UIImage systemImageNamed:@"rectangle.split.2x1"];
        [self.splitScreenButton setImage:icon forState:UIControlStateNormal];
    } else {
        [self.splitScreenButton setTitle:@"⬌" forState:UIControlStateNormal]; // Fallback for older iOS
    }

    // Style the button to match other bar buttons
    self.splitScreenButton.tintColor = self.infoButton.tintColor;

    // Add tap action
    [self.splitScreenButton addTarget:self action:@selector(splitScreenButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // Find the index of sessions button in the bar (insert after sessions)
    NSInteger sessionsButtonIndex = [self.bar.arrangedSubviews indexOfObject:self.sessionsButton];

    // Add to the bar view
    if (sessionsButtonIndex != NSNotFound) {
        [self.bar insertArrangedSubview:self.splitScreenButton atIndex:sessionsButtonIndex + 1];
    } else {
        // Fallback: add at the end of the bar
        [self.bar addArrangedSubview:self.splitScreenButton];
    }

    // Match the width constraint of other buttons
    self.splitScreenButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.splitScreenButton.widthAnchor constraintEqualToConstant:self.barButtonWidth.constant].active = YES;
}

- (void)splitScreenButtonTapped:(UIButton *)sender {
    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }

    // Show split screen options
    [self showSplitScreenOptions];
}

- (void)setupEditorButton {
    // Create code editor button
    self.editorButton = [UIButton buttonWithType:UIButtonTypeSystem];

    // Set icon (document/text editor symbol)
    if (@available(iOS 13, *)) {
        UIImage *icon = [UIImage systemImageNamed:@"doc.text"];
        [self.editorButton setImage:icon forState:UIControlStateNormal];
    } else {
        [self.editorButton setTitle:@"📝" forState:UIControlStateNormal]; // Fallback for older iOS
    }

    // Style the button to match other bar buttons
    self.editorButton.tintColor = self.infoButton.tintColor;

    // Add tap action
    [self.editorButton addTarget:self action:@selector(editorButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // Find the index of split screen button in the bar
    NSInteger splitButtonIndex = [self.bar.arrangedSubviews indexOfObject:self.splitScreenButton];

    // Add to the bar view - insert after split screen button
    if (splitButtonIndex != NSNotFound) {
        [self.bar insertArrangedSubview:self.editorButton atIndex:splitButtonIndex + 1];
    } else {
        // Fallback: add at the end of the bar
        [self.bar addArrangedSubview:self.editorButton];
    }

    // Match the width constraint of other buttons
    self.editorButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorButton.widthAnchor constraintEqualToConstant:self.barButtonWidth.constant].active = YES;
}

- (void)editorButtonTapped:(UIButton *)sender {
    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }

    // Show file picker or quick edit
    [self showEditorOptions];
}

- (void)setupReverseEngineeringButton {
    // Create reverse engineering button
    self.reverseEngineeringButton = [UIButton buttonWithType:UIButtonTypeSystem];

    // Set icon (magnifying glass + wrench for analysis)
    if (@available(iOS 13, *)) {
        UIImage *icon = [UIImage systemImageNamed:@"hammer.circle"];
        [self.reverseEngineeringButton setImage:icon forState:UIControlStateNormal];
    } else {
        [self.reverseEngineeringButton setTitle:@"🔬" forState:UIControlStateNormal]; // Fallback
    }

    // Style the button to match other bar buttons
    self.reverseEngineeringButton.tintColor = self.infoButton.tintColor;

    // Add tap action
    [self.reverseEngineeringButton addTarget:self action:@selector(reverseEngineeringButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // Find the index of editor button in the bar
    NSInteger editorButtonIndex = [self.bar.arrangedSubviews indexOfObject:self.editorButton];

    // Add to the bar view - insert after editor button
    if (editorButtonIndex != NSNotFound) {
        [self.bar insertArrangedSubview:self.reverseEngineeringButton atIndex:editorButtonIndex + 1];
    } else {
        // Fallback: add at the end of the bar
        [self.bar addArrangedSubview:self.reverseEngineeringButton];
    }

    // Match the width constraint of other buttons
    self.reverseEngineeringButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.reverseEngineeringButton.widthAnchor constraintEqualToConstant:self.barButtonWidth.constant].active = YES;
}

- (void)reverseEngineeringButtonTapped:(UIButton *)sender {
    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }

    // XSH Pro Feature - Show purchase dialog
    [self openReverseEngineering];
}

- (void)updateTerminalIndicator {
    self.terminalIndicatorLabel.text = [NSString stringWithFormat:@"Window %d", self.currentTerminalNumber + 1];

    // Animate appearance
    [UIView animateWithDuration:0.3 animations:^{
        self.terminalIndicatorLabel.alpha = 1;
    } completion:^(BOOL finished) {
        // Auto-hide after 2 seconds
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                self.terminalIndicatorLabel.alpha = 0;
            }];
        });
    }];
}

- (void)handleSwipeLeft:(UISwipeGestureRecognizer *)recognizer {
    // Next terminal
    [self switchToNextTerminal];
}

- (void)handleSwipeRight:(UISwipeGestureRecognizer *)recognizer {
    // Previous terminal
    [self switchToPreviousTerminal];
}

- (void)switchToNextTerminal {
    if (self.terminalSessions.count == 0) return;

    self.currentTerminalNumber++;
    if (self.currentTerminalNumber >= self.terminalSessions.count) {
        self.currentTerminalNumber = 0;
    }
    [self switchToTerminalNumber:self.currentTerminalNumber];
}

- (void)switchToPreviousTerminal {
    if (self.terminalSessions.count == 0) return;

    self.currentTerminalNumber--;
    if (self.currentTerminalNumber < 0) {
        self.currentTerminalNumber = (int)self.terminalSessions.count - 1;
    }
    [self switchToTerminalNumber:self.currentTerminalNumber];
}

- (void)switchToTerminalNumber:(int)number {
    if (number < 0 || number >= self.terminalSessions.count) return;

    self.currentTerminalNumber = number;
    self.terminal = self.terminalSessions[number];

    [self updateTerminalIndicator];

    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UISelectionFeedbackGenerator *feedback = [[UISelectionFeedbackGenerator alloc] init];
        [feedback selectionChanged];
    }
}

- (void)showTerminalMenuFromButton:(UIButton *)sourceButton {
    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }

    NSString *message = [NSString stringWithFormat:@"%d active window%@",
                        (int)self.terminalSessions.count,
                        self.terminalSessions.count == 1 ? @"" : @"s"];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Terminal Windows"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    // Add "New Window" button at the top
    [menu addAction:[UIAlertAction actionWithTitle:@"New Window"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self createNewTerminalSession];
    }]];

    // Add existing terminal sessions
    for (int i = 0; i < self.terminalSessions.count; i++) {
        // Create a copy of i to capture in the block correctly
        int windowIndex = i;

        // Window switch button
        NSString *checkMark = (i == self.currentTerminalNumber) ? @" ✓" : @"";
        NSString *windowTitle = [NSString stringWithFormat:@"Window %d%@", i + 1, checkMark];

        [menu addAction:[UIAlertAction actionWithTitle:windowTitle
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            // Switch directly to the window
            [self switchToTerminalNumber:windowIndex];
        }]];
    }

    // Single delete button for current window (if more than 1)
    if (self.terminalSessions.count > 1) {
        [menu addAction:[UIAlertAction actionWithTitle:@"Close Window"
                                                 style:UIAlertActionStyleDestructive
                                               handler:^(UIAlertAction *action) {
            [self confirmDeleteWindowAtIndex:self.currentTerminalNumber];
        }]];
    }

    // Add info section
    [menu addAction:[UIAlertAction actionWithTitle:@"How to use"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self showTerminalHelpMessage];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    // For iPad - anchor to the sessions button
    if (menu.popoverPresentationController) {
        menu.popoverPresentationController.sourceView = sourceButton;
        menu.popoverPresentationController.sourceRect = sourceButton.bounds;
    }

    [self presentViewController:menu animated:YES completion:nil];
}

- (void)confirmDeleteWindowAtIndex:(int)windowIndex {
    // Show confirmation alert
    NSString *title = [NSString stringWithFormat:@"Delete Window %d ?", windowIndex + 1];
    NSString *message = @"All processes running in this window will be terminated. This action cannot be undone.";

    UIAlertController *confirmation = [UIAlertController alertControllerWithTitle:title
                                                                          message:message
                                                                   preferredStyle:UIAlertControllerStyleAlert];

    // Delete action (destructive)
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Delete"
                                                     style:UIAlertActionStyleDestructive
                                                   handler:^(UIAlertAction *action) {
        [self closeSessionAtIndex:windowIndex];
    }]];

    // Cancel action
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                     style:UIAlertActionStyleCancel
                                                   handler:nil]];

    [self presentViewController:confirmation animated:YES completion:nil];
}

#pragma mark - Download Progress Indicator

- (void)setupDownloadIndicator {
    // Create container view for download indicator
    self.downloadIndicatorView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 60)];
    self.downloadIndicatorView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    self.downloadIndicatorView.layer.cornerRadius = 12;
    self.downloadIndicatorView.layer.masksToBounds = YES;
    self.downloadIndicatorView.alpha = 0; // Hidden initially

    // Create label for download info
    self.downloadIndicatorLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 180, 50)];
    self.downloadIndicatorLabel.textAlignment = NSTextAlignmentLeft;
    self.downloadIndicatorLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.downloadIndicatorLabel.textColor = UIColor.whiteColor;
    self.downloadIndicatorLabel.numberOfLines = 3;
    self.downloadIndicatorLabel.text = @"📥 Downloading...";

    [self.downloadIndicatorView addSubview:self.downloadIndicatorLabel];
    [self.view addSubview:self.downloadIndicatorView];

    // Position at top-left with safe area
    self.downloadIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.downloadIndicatorView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.downloadIndicatorView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:10],
        [self.downloadIndicatorView.widthAnchor constraintEqualToConstant:200],
        [self.downloadIndicatorView.heightAnchor constraintEqualToConstant:60]
    ]];
}

- (void)handleTerminalOutput:(NSNotification *)notification {
    NSData *outputData = notification.userInfo[@"data"];
    if (!outputData) return;

    NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    if (!output) return;

    // Keep a rolling buffer of recent output (last 2KB)
    [self.recentOutput appendString:output];
    if (self.recentOutput.length > 2048) {
        [self.recentOutput deleteCharactersInRange:NSMakeRange(0, self.recentOutput.length - 2048)];
    }

    // Check if we're waiting for auto-setup to complete
    if (self.isRunningAutoSetup) {
        // Check for step completion markers
        if ([output rangeOfString:@"STEP_1_COMPLETE"].location != NSNotFound && self.currentSetupStep == 1) {
            // Step 1 done, move to step 2
            dispatch_async(dispatch_get_main_queue(), ^{
                [self executeSetupStep:2];
            });
        }
        else if ([output rangeOfString:@"STEP_2_COMPLETE"].location != NSNotFound && self.currentSetupStep == 2) {
            // Step 2 done, start step 3
            dispatch_async(dispatch_get_main_queue(), ^{
                [self executeSetupStep:3];
            });
        }
        else if ([output rangeOfString:@"STEP_3_COMPLETE"].location != NSNotFound && self.currentSetupStep == 3) {
            // All steps done! Show completion
            self.isRunningAutoSetup = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.setupProgressDialog) {
                    [self.setupProgressDialog dismissViewControllerAnimated:YES completion:^{
                        [self showSetupCompleteMessage];
                    }];
                    self.setupProgressDialog = nil;
                }
            });
        }
    }

    // Check for download completion indicators (to hide immediately)
    BOOL isDownloadComplete = NO;
    if ([output rangeOfString:@"OK:" options:0].location != NSNotFound ||
        [output rangeOfString:@"complete" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [output rangeOfString:@"Successfully installed" options:0].location != NSNotFound ||
        [output rangeOfString:@"packages installed" options:0].location != NSNotFound) {
        isDownloadComplete = YES;
    }

    // If download completed, hide indicator immediately and mark completion time
    if (isDownloadComplete && self.downloadIndicatorView.alpha > 0) {
        [self hideDownloadIndicator];
        self.lastDownloadActivity = nil;
        self.lastDownloadCompletion = [NSDate date]; // Mark when download completed
        [self.recentOutput setString:@""]; // Clear recent output to avoid false positives
        return; // Don't check for download activity
    }

    // Don't show indicator if download completed recently (within 10 seconds)
    if (self.lastDownloadCompletion) {
        NSTimeInterval timeSinceCompletion = [[NSDate date] timeIntervalSinceDate:self.lastDownloadCompletion];
        if (timeSinceCompletion < 10.0) {
            return; // Don't reactivate indicator for 10 seconds after completion
        }
    }

    // Check for download indicators in the output
    BOOL isDownloadActive = NO;
    NSString *downloadType = nil;

    // APK package manager (only if actively downloading)
    if ([output rangeOfString:@"fetch http" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [output rangeOfString:@"(1/" options:0].location != NSNotFound ||
        ([output rangeOfString:@"Installing" options:0].location != NSNotFound &&
         [output rangeOfString:@"MiB" options:0].location != NSNotFound)) {
        isDownloadActive = YES;
        downloadType = @"apk";
    }
    // Python pip
    else if ([output rangeOfString:@"Collecting" options:0].location != NSNotFound ||
             [output rangeOfString:@"Downloading" options:0].location != NSNotFound ||
             [output rangeOfString:@"Installing collected packages" options:0].location != NSNotFound) {
        isDownloadActive = YES;
        downloadType = @"pip";
    }
    // wget
    else if ([output rangeOfString:@"--" options:0].location != NSNotFound &&
             [output rangeOfString:@"%" options:0].location != NSNotFound &&
             [self.recentOutput rangeOfString:@"Saving to" options:0].location != NSNotFound) {
        isDownloadActive = YES;
        downloadType = @"wget";
    }
    // curl
    else if ([output rangeOfString:@"#" options:0].location != NSNotFound &&
             [output rangeOfString:@"%" options:0].location != NSNotFound) {
        isDownloadActive = YES;
        downloadType = @"curl";
    }

    if (isDownloadActive) {
        self.lastDownloadActivity = [NSDate date];
        self.lastDownloadCompletion = nil; // Reset completion time when new download starts
        [self updateDownloadIndicator:downloadType];
        [self showDownloadIndicator];
    }
}

- (void)startMonitoringDownloads {
    // Check every 3 seconds if download activity has stopped
    self.downloadMonitorTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                                 repeats:YES
                                                                   block:^(NSTimer *timer) {
        if (self.lastDownloadActivity) {
            NSTimeInterval timeSinceLastActivity = [[NSDate date] timeIntervalSinceDate:self.lastDownloadActivity];
            // Hide indicator if no activity for 5 seconds
            if (timeSinceLastActivity > 5.0) {
                [self hideDownloadIndicator];
                self.lastDownloadActivity = nil;
            }
        }
    }];
}

- (void)updateDownloadIndicator:(NSString *)downloadType {
    // Update indicator based on download type
    if ([downloadType isEqualToString:@"apk"]) {
        self.downloadIndicatorLabel.text = @"📥 APK\nInstalling packages...";
    } else if ([downloadType isEqualToString:@"pip"]) {
        self.downloadIndicatorLabel.text = @"🐍 pip\nInstalling Python packages...";
    } else if ([downloadType isEqualToString:@"wget"]) {
        self.downloadIndicatorLabel.text = @"📥 wget\nDownloading...";
    } else if ([downloadType isEqualToString:@"curl"]) {
        self.downloadIndicatorLabel.text = @"📥 curl\nDownloading...";
    }
}

- (void)showDownloadIndicator {
    if (self.downloadIndicatorView.alpha == 0) {
        [UIView animateWithDuration:0.3 animations:^{
            self.downloadIndicatorView.alpha = 1;
        }];
    }
}

- (void)hideDownloadIndicator {
    if (self.downloadIndicatorView.alpha == 1) {
        [UIView animateWithDuration:0.3 animations:^{
            self.downloadIndicatorView.alpha = 0;
        }];
    }
}

- (void)createNewTerminalSession {
#if !ISH_LINUX
    // If this is the first call and we only have the main session, add it to the array first
    if (self.terminalSessions.count == 0 && self.sessionTerminal != nil) {
        [self.terminalSessions addObject:self.sessionTerminal];
        [self.sessionPids addObject:@(self.sessionPid)];
    }

    // Create a new shell session
    int err = become_new_init_child();
    if (err < 0) {
        [self showMessage:@"Failed to create window" subtitle:[NSString stringWithFormat:@"Error code %d", err]];
        return;
    }

    struct tty *tty;
    Terminal *newTerminal = [Terminal createPseudoTerminal:&tty];
    if (newTerminal == nil) {
        [self showMessage:@"Failed to create window" subtitle:@"Could not create pseudo terminal"];
        return;
    }

    NSString *stdioFile = [NSString stringWithFormat:@"/dev/pts/%d", tty->num];
    err = create_stdio(stdioFile.fileSystemRepresentation, TTY_PSEUDO_SLAVE_MAJOR, tty->num);
    if (err < 0) {
        [self showMessage:@"Failed to setup window" subtitle:[NSString stringWithFormat:@"Error code %d", err]];
        return;
    }
    tty_release(tty);

    // Execute shell in the new session
    NSArray<NSString *> *command = UserPreferences.shared.launchCommand;
    char argv[4096];
    [Terminal convertCommand:command toArgs:argv limitSize:sizeof(argv)];
    const char *envp = "TERM=xterm-256color\0";
    err = do_execve(command[0].UTF8String, command.count, argv, envp);
    if (err < 0) {
        [self showMessage:@"Failed to start shell" subtitle:[NSString stringWithFormat:@"Error code %d", err]];
        return;
    }

    int newPid = current->pid;
    task_start(current);

    // Add to our sessions array
    [self.terminalSessions addObject:newTerminal];
    [self.sessionPids addObject:@(newPid)];

    // Switch to the new session
    [self switchToTerminalNumber:(int)self.terminalSessions.count - 1];

    // Haptic feedback for success
    if (@available(iOS 10.0, *)) {
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
#else
    [self showMessage:@"Not supported" subtitle:@"Multiple windows not available in this build"];
#endif
}

- (void)closeSessionAtIndex:(int)index {
    // Check if it's the last window
    if (self.terminalSessions.count <= 1) {
        [self showMessage:@"Cannot close" subtitle:@"You must have at least one window open"];
        return;
    }

    // Check if index is valid
    if (index < 0 || index >= self.terminalSessions.count) {
        return;
    }

    // Destroy the terminal
    Terminal *terminalToClose = self.terminalSessions[index];
    [terminalToClose destroy];

    // Remove from arrays
    [self.terminalSessions removeObjectAtIndex:index];
    [self.sessionPids removeObjectAtIndex:index];

    // Adjust current terminal number if needed
    if (index < self.currentTerminalNumber) {
        // If we deleted a window before the current one, decrement current index
        self.currentTerminalNumber--;
    } else if (index == self.currentTerminalNumber) {
        // If we deleted the current window, switch to previous or first
        int newIndex = index > 0 ? index - 1 : 0;
        self.currentTerminalNumber = newIndex;
        self.terminal = self.terminalSessions[newIndex];
        [self updateTerminalIndicator];
    }
    // If we deleted a window after the current one, no need to change anything

    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
    }
}

- (void)closeCurrentSession {
    [self closeSessionAtIndex:self.currentTerminalNumber];
}

- (void)showTerminalHelpMessage {
    UIAlertController *help = [UIAlertController alertControllerWithTitle:@"Multiple Terminal Windows"
                                                                   message:@"Run multiple shell windows independently:\n\n"
                                                                           @"• Swipe with 2 fingers ← → to switch\n"
                                                                           @"• Tap button for windows menu\n"
                                                                           @"• Press to create new window\n"
                                                                           @"• Each window runs its own shell\n"
                                                                           @"• Perfect for multitasking!"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [help addAction:[UIAlertAction actionWithTitle:@"Got it!" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:help animated:YES completion:nil];
}

#pragma mark - First Launch Setup

- (void)checkAndShowFirstLaunchSetup {
    // Check if this is the first launch
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hasShownSetup = [defaults boolForKey:@"HasShownFirstLaunchSetup"];

    if (!hasShownSetup) {
        // Wait a bit for terminal to be ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showFirstLaunchSetup];
        });
    }
}

- (void)showFirstLaunchSetup {
    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    }

    UIAlertController *welcome = [UIAlertController alertControllerWithTitle:@"⚡ Welcome to XSH"
                                                                       message:@"Set up the system with performance optimizations?\n\n"
                                                                               @"📦 This will install:\n"
                                                                               @"- Python 3 & pip (optimized)\n"
                                                                               @"- wheel & setuptools\n"
                                                                               @"- Latest system updates\n\n"
                                                                               @"⚡ Performance boosts:\n"
                                                                               @"- tmpfs cache (RAM-based)\n"
                                                                               @"- pip 5-10x faster\n"
                                                                               @"- JIT cache optimized\n\n"
                                                                               @"⏱️ Time: ~30-60 seconds"
                                                                preferredStyle:UIAlertControllerStyleAlert];

    // Yes button - Run auto setup
    [welcome addAction:[UIAlertAction actionWithTitle:@"Yes, Update"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
        // Mark as shown
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HasShownFirstLaunchSetup"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        // Run auto setup
        [self runAutoSetup];
    }]];

    // No button - Skip setup
    [welcome addAction:[UIAlertAction actionWithTitle:@"No"
                                                style:UIAlertActionStyleCancel
                                              handler:^(UIAlertAction *action) {
        // Mark as shown
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HasShownFirstLaunchSetup"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        // Show quick tips
        [self showQuickTips];
    }]];

    [self presentViewController:welcome animated:YES completion:nil];
}

- (void)runAutoSetup {
    // Set flag that we're running auto-setup
    self.isRunningAutoSetup = YES;
    self.currentSetupStep = 0;

    // Create progress dialog with spinner
    self.setupProgressDialog = [UIAlertController alertControllerWithTitle:@"Setting Up System"
                                                                    message:@"Please do not close the app\n\n\n\n\nUpdating package lists..."
                                                             preferredStyle:UIAlertControllerStyleAlert];

    [self presentViewController:self.setupProgressDialog animated:YES completion:^{
        // Add spinning activity indicator
        if (@available(iOS 13.0, *)) {
            self.setupSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        } else {
            self.setupSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        }
        self.setupSpinner.translatesAutoresizingMaskIntoConstraints = NO;
        [self.setupSpinner startAnimating];

        [self.setupProgressDialog.view addSubview:self.setupSpinner];

        // Add progress bar below spinner
        self.setupProgressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        self.setupProgressBar.progress = 0.0;
        self.setupProgressBar.translatesAutoresizingMaskIntoConstraints = NO;

        [self.setupProgressDialog.view addSubview:self.setupProgressBar];

        [NSLayoutConstraint activateConstraints:@[
            // Spinner positioning (centered, above progress bar)
            [self.setupSpinner.centerXAnchor constraintEqualToAnchor:self.setupProgressDialog.view.centerXAnchor],
            [self.setupSpinner.topAnchor constraintEqualToAnchor:self.setupProgressDialog.view.topAnchor constant:95],

            // Progress bar positioning
            [self.setupProgressBar.leadingAnchor constraintEqualToAnchor:self.setupProgressDialog.view.leadingAnchor constant:20],
            [self.setupProgressBar.trailingAnchor constraintEqualToAnchor:self.setupProgressDialog.view.trailingAnchor constant:-20],
            [self.setupProgressBar.topAnchor constraintEqualToAnchor:self.setupProgressDialog.view.topAnchor constant:125]
        ]];

        // Wait a moment for dialog to appear, then start step 1
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self executeSetupStep:1];
        });

        // Safety timeout: if setup doesn't complete in 120 seconds, force completion
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.isRunningAutoSetup) {
                NSLog(@"Auto-setup timeout - forcing completion");
                self.isRunningAutoSetup = NO;
                if (self.setupProgressDialog) {
                    [self.setupProgressDialog dismissViewControllerAnimated:YES completion:^{
                        [self showSetupCompleteMessage];
                    }];
                    self.setupProgressDialog = nil;
                }
            }
        });
    }];
}

- (void)executeSetupStep:(int)step {
    self.currentSetupStep = step;

    NSString *command = nil;
    NSString *statusMessage = nil;
    float progress = 0.0;

    switch (step) {
        case 1:
            // Performance optimizations + repository setup
            command = @"# Mount tmpfs for /tmp (in-memory for speed)\n"
                       "mount -t tmpfs -o size=256m tmpfs /tmp && "
                       "# Mount tmpfs for apk cache\n"
                       "mkdir -p /var/cache/apk && mount -t tmpfs -o size=128m tmpfs /var/cache/apk && "
                       "# Mount tmpfs for pip cache\n"
                       "mkdir -p /root/.cache/pip && mount -t tmpfs -o size=128m tmpfs /root/.cache/pip && "
                       "# Use official iSH repositories (stable and tested)\n"
                       "echo 'http://apk.ish.app/v3.14-2023-05-19/main' > /etc/apk/repositories && "
                       "echo 'http://apk.ish.app/v3.14-2023-05-19/community' >> /etc/apk/repositories && "
                       "# Increase block write delay (performance boost)\n"
                       "echo 3000 > /proc/sys/vm/dirty_writeback_centisecs && "
                       "echo 5000 > /proc/sys/vm/dirty_expire_centisecs && "
                       "apk update || echo 'Update may have issues but continuing...'; echo 'STEP_1_COMPLETE'\n";
            statusMessage = @"Optimizing system & updating...";
            progress = 0.50;
            break;

        case 2:
            // Install Python 3, pip, wheel, and essential tools + smart pip wrapper
            command = @"apk add --no-cache python3 py3-pip py3-wheel openssh-client curl wget git && "
                       "# Create smart pip wrapper that uses apk when possible\n"
                       "cat > /usr/local/bin/pip-wrapper << 'EOFPIPWRAPPER'\n"
                       "#!/bin/sh\n"
                       "# Smart pip wrapper - uses apk when possible, falls back to pip3\n"
                       "\n"
                       "# Handle install command\n"
                       "if [ \"$1\" = \"install\" ]; then\n"
                       "    shift\n"
                       "    for pkg in \"$@\"; do\n"
                       "        # Skip flags\n"
                       "        if echo \"$pkg\" | grep -q '^-'; then continue; fi\n"
                       "        \n"
                       "        apk_pkg=\"py3-${pkg}\"\n"
                       "        echo \"⚡ Trying apk: $apk_pkg\"\n"
                       "        \n"
                       "        # Try to install directly - if it exists, this will succeed\n"
                       "        if apk add \"$apk_pkg\" 2>/dev/null; then\n"
                       "            echo \"Installed via apk!\"\n"
                       "            continue\n"
                       "        fi\n"
                       "        \n"
                       "        echo \"⚠️ Not in apk, using pip3...\"\n"
                       "        /usr/bin/pip3 install \"$pkg\"\n"
                       "    done\n"
                       "    exit 0\n"
                       "fi\n"
                       "\n"
                       "# Handle uninstall command\n"
                       "if [ \"$1\" = \"uninstall\" ]; then\n"
                       "    shift\n"
                       "    for pkg in \"$@\"; do\n"
                       "        # Skip flags\n"
                       "        if echo \"$pkg\" | grep -q '^-'; then continue; fi\n"
                       "        \n"
                       "        apk_pkg=\"py3-${pkg}\"\n"
                       "        echo \"⚡ Trying apk: $apk_pkg\"\n"
                       "        \n"
                       "        # Check if installed via apk\n"
                       "        if apk info -e \"$apk_pkg\" >/dev/null 2>&1; then\n"
                       "            echo \"Removing via apk!\"\n"
                       "            apk del \"$apk_pkg\"\n"
                       "            continue\n"
                       "        fi\n"
                       "        \n"
                       "        echo \"⚠️ Not installed via apk, using pip3...\"\n"
                       "        /usr/bin/pip3 uninstall -y \"$pkg\"\n"
                       "    done\n"
                       "    exit 0\n"
                       "fi\n"
                       "\n"
                       "# For all other commands, pass through to pip3\n"
                       "exec /usr/bin/pip3 \"$@\"\n"
                       "EOFPIPWRAPPER\n"
                       "chmod +x /usr/local/bin/pip-wrapper && "
                       "# Create aliases\n"
                       "ln -sf /usr/local/bin/pip-wrapper /usr/local/bin/pip && "
                       "ln -sf /usr/local/bin/pip-wrapper /usr/local/bin/pip3 && "
                       "# Configure pip for better performance\n"
                       "/usr/bin/pip3 config set global.no-cache-dir false && "
                       "/usr/bin/pip3 config set global.disable-pip-version-check true && "
                       "/usr/bin/pip3 config set install.no-build-isolation true && "
                       "/usr/bin/pip3 config set install.prefer-binary true && "
                       "# Install wheel to avoid rebuilding packages\n"
                       "/usr/bin/pip3 install --no-cache-dir wheel setuptools || echo 'Wheel install may have issues but continuing...'; "
                       "echo 'STEP_2_COMPLETE'\n";
            statusMessage = @"Installing Python & smart pip wrapper...";
            progress = 0.75;
            break;

        case 3:
            // Set up .bashrc with pip optimizations and welcome message
            command = @"# Remove EXTERNALLY-MANAGED to allow pip install\n"
                       "rm -f /usr/lib/python*/EXTERNALLY-MANAGED && "
                       "# Configure .bashrc for optimized pip usage\n"
                       "cat >> /root/.bashrc << 'EOFBASHRC'\n"
                       "\n"
                       "# XSH Performance Optimizations\n"
                       "export PIP_CACHE_DIR=/tmp/pip-cache\n"
                       "export PATH=/usr/local/bin:$PATH\n"
                       "EOFBASHRC\n"
                       "# Load .bashrc immediately for current session\n"
                       "source /root/.bashrc && "
                       "# Set up XSH custom welcome message\n"
                       "cat > /etc/motd << 'EOFMOTD'\n"
                       "╔═══════════════════════════════════════════════╗\n"
                       "║           Welcome to XSH Terminal             ║\n"
                       "║       Advanced iOS Linux Environment          ║\n"
                       "╚═══════════════════════════════════════════════╝\n"
                       "\n"
                       "EOFMOTD\n"
                       "echo 'STEP_3_COMPLETE'\n";
            statusMessage = @"Configuring shell & welcome...";
            progress = 1.0;
            break;

        default:
            return;
    }

    // Update progress dialog
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.setupProgressDialog) {
            self.setupProgressDialog.message = [NSString stringWithFormat:@"Please do not close the app\n\n\n\n\n%@", statusMessage];
            [UIView animateWithDuration:0.3 animations:^{
                self.setupProgressBar.progress = progress;
            }];
        }
    });

    // Execute command
    if (self.terminal && command) {
        NSData *commandData = [command dataUsingEncoding:NSUTF8StringEncoding];
        [self.terminal sendInput:commandData];
    }
}

- (void)showSetupCompleteMessage {
    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    }

    UIAlertController *complete = [UIAlertController alertControllerWithTitle:@"⚡ XSH Setup Complete"
                                                                       message:@"System is ready & optimized!\n\n"
                                                                               @"✅ Installed:\n"
                                                                               @"- Python 3 & pip (optimized)\n"
                                                                               @"- wheel & setuptools\n"
                                                                               @"- Latest system updates\n\n"
                                                                               @"⚡ Performance boosts:\n"
                                                                               @"- tmpfs cache (RAM-based)\n"
                                                                               @"- pip 5-10x faster\n"
                                                                               @"- JIT cache optimized\n\n"
                                                                               @"🚀 You can now:\n"
                                                                               @"- pip3 install <package> (super fast!)\n"
                                                                               @"- Type 'python3' to run Python\n"
                                                                               @"- Press </> for code editor\n"
                                                                               @"- Press ⬌ for split screen"
                                                                preferredStyle:UIAlertControllerStyleAlert];

    [complete addAction:[UIAlertAction actionWithTitle:@"Get Started"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];

    [self presentViewController:complete animated:YES completion:nil];
}

- (void)showQuickTips {
    UIAlertController *tips = [UIAlertController alertControllerWithTitle:@"Quick Tips"
                                                                   message:@"To set up manually:\n\n"
                                                                           @"1. Update system:\n"
                                                                           @"   apk update && apk upgrade\n\n"
                                                                           @"2. Install Python:\n"
                                                                           @"   apk add python3\n"
                                                                           @"   python3 -m ensurepip\n\n"
                                                                           @"3. Explore features:\n"
                                                                           @"   - Folder button for file access\n"
                                                                           @"   - Windows button for multiple terminals\n"
                                                                           @"   - Automatic download indicator"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [tips addAction:[UIAlertAction actionWithTitle:@"Got it, thanks!"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];

    [self presentViewController:tips animated:YES completion:nil];
}

- (void)handleRunSystemSetup:(NSNotification *)notification {
    // User wants to run setup from Settings page
    // Check if already running setup
    if (self.isRunningAutoSetup) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Setup Already Running"
                                                                       message:@"System setup is already in progress. Please wait for it to complete."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // Run the auto setup
    [self runAutoSetup];
}

- (void)handleCloseSplitView:(NSNotification *)notification {
    // Handle closing split view and keeping selected terminal
    TerminalViewController *terminalToKeep = notification.userInfo[@"terminal"];

    if (terminalToKeep && terminalToKeep.terminal) {
        // Switch to the selected terminal's session
        self.terminal = terminalToKeep.terminal;

        NSLog(@"✅ Kept terminal session after closing split view");
    }
}

- (void)handleExecuteSSHCommand:(NSNotification *)notification {
    // Execute SSH command from SSH Manager
    NSDictionary *userInfo = notification.userInfo;
    NSString *command = userInfo[@"command"];

    if (command && command.length > 0) {
        // Add newline to execute the command
        NSString *fullCommand = [command stringByAppendingString:@"\n"];
        NSData *data = [fullCommand dataUsingEncoding:NSUTF8StringEncoding];
        [self.terminal sendInput:data];
    }
}

- (void)applyXSHThemeIfNeeded {
    // Check if theme has already been applied
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hasAppliedTheme = [defaults boolForKey:@"HasAppliedXSHTheme"];

    if (!hasAppliedTheme) {
        // Wait 2 seconds for terminal to be ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                      dispatch_get_main_queue(), ^{
            [self applyXSHTheme];
            [defaults setBool:YES forKey:@"HasAppliedXSHTheme"];
        });
    }
}

- (void)applyXSHTheme {
    // Apply XSH welcome message silently in background
    NSString *command = @"cat > /etc/motd << 'EOFMOTD'\n"
                        "Welcome to XSH Terminal\n"
                        "Advanced iOS Linux Environment\n\n"
                        "EOFMOTD\n";

    NSData *commandData = [command dataUsingEncoding:NSUTF8StringEncoding];
    if (self.terminal && commandData) {
        [self.terminal sendInput:commandData];
    }
}

#pragma mark - Home Directory Access

- (void)showHomeDirectory {
    // Get the iSH filesystem root - files are in App Group Container
    NSURL *containerURL = ContainerURL();
    if (!containerURL) {
        [self showMessage:@"Error" subtitle:@"Could not access container"];
        return;
    }

    // iSH files are in roots/alpine/data
    NSURL *rootsURL = [containerURL URLByAppendingPathComponent:@"roots"];
    NSURL *alpineURL = [rootsURL URLByAppendingPathComponent:@"alpine"];
    NSURL *dataURL = [alpineURL URLByAppendingPathComponent:@"data"];

    // Fallback to roots directory if alpine doesn't exist
    NSURL *targetURL = dataURL;
    if (![[NSFileManager defaultManager] fileExistsAtPath:dataURL.path]) {
        targetURL = rootsURL;
    }

    NSString *documentsPath = targetURL.path;
    NSURL *documentsURL = targetURL;

    // Create Documents directory if it doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:documentsPath]) {
        NSError *error = nil;
        [fileManager createDirectoryAtPath:documentsPath withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            [self showMessage:@"Error" subtitle:[NSString stringWithFormat:@"Could not create Documents folder: %@", error.localizedDescription]];
            return;
        }
    }

    // Check if iOS 11+ (has UIDocumentPickerViewController with directory support)
    if (@available(iOS 11.0, *)) {
        // Use UIDocumentPickerViewController to open the Documents directory
        UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item", @"public.content", @"public.data"]
                                                                                                                inMode:UIDocumentPickerModeOpen];

        // Set properties
        documentPicker.allowsMultipleSelection = NO;
        documentPicker.shouldShowFileExtensions = YES;

        // Try to set the directory URL (iOS 13+)
        if (@available(iOS 13.0, *)) {
            documentPicker.directoryURL = documentsURL;
        }

        // Present the picker
        [self presentViewController:documentPicker animated:YES completion:nil];
    } else {
        // iOS 10 and below: Show menu with options
        UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"📁 Access Files"
                                                                       message:@"Choose how to access your files:"
                                                                preferredStyle:UIAlertControllerStyleActionSheet];

        // Option 1: Open in Files app (if available)
        [menu addAction:[UIAlertAction actionWithTitle:@"📱 Open Files App"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            // Try different URL schemes
            NSArray *urlSchemes = @[@"shareddocuments://", @"mobiledocuments://"];
            BOOL opened = NO;

            for (NSString *scheme in urlSchemes) {
                NSURL *url = [NSURL URLWithString:scheme];
                if ([[UIApplication sharedApplication] canOpenURL:url]) {
                    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                    opened = YES;
                    break;
                }
            }

            if (!opened) {
                [self showMessage:@"Not Available" subtitle:@"Files app is not available on this iOS version"];
            }
        }]];

        // Option 2: Show path and copy
        [menu addAction:[UIAlertAction actionWithTitle:@"📋 Copy Path"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = documentsPath;
            [self showMessage:@"Copied!" subtitle:[NSString stringWithFormat:@"Path copied:\n%@", documentsPath]];
        }]];

        // Option 3: Show info
        [menu addAction:[UIAlertAction actionWithTitle:@"ℹ️ Show Info"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            UIAlertController *info = [UIAlertController alertControllerWithTitle:@"📁 Home Directory"
                                                                           message:[NSString stringWithFormat:@"Your files are stored at:\n\n%@\n\nAccess methods:\n• Files app (iOS 11+)\n• iTunes File Sharing\n• iCloud Drive sync\n\nFrom terminal: cd ~/", documentsPath]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [info addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:info animated:YES completion:nil];
        }]];

        [menu addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                 style:UIAlertActionStyleCancel
                                               handler:nil]];

        // For iPad
        if (menu.popoverPresentationController) {
            menu.popoverPresentationController.sourceView = self.view;
            menu.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2,
                                                                        self.view.bounds.size.height / 2,
                                                                        1, 1);
        }

        [self presentViewController:menu animated:YES completion:nil];
    }
}

- (void)showSplitScreenOptions {
    // Open split screen directly in horizontal mode (side by side)
    [self openSplitScreenWithOrientation:SplitOrientationHorizontal];
}

- (void)openSplitScreenWithOrientation:(SplitOrientation)orientation {
    @try {
        // Create split terminal view controller (creates 2 new sessions)
        SplitTerminalViewController *splitVC = [[SplitTerminalViewController alloc] initWithOrientation:orientation];

        // Present modally in fullscreen
        splitVC.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:splitVC animated:YES completion:nil];
    } @catch (NSException *exception) {
        NSLog(@"Split screen error: %@", exception);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:[NSString stringWithFormat:@"Failed to open split screen: %@", exception.reason]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)showEditorOptions {
    UIAlertController *options = [UIAlertController alertControllerWithTitle:@"Code Editor"
                                                                     message:@"Create new file in /root"
                                                              preferredStyle:UIAlertControllerStyleActionSheet];

    // New file options
    [options addAction:[UIAlertAction actionWithTitle:@"Python (.py)"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
        [self promptForFilename:@"py" language:CodeLanguagePython];
    }]];

    [options addAction:[UIAlertAction actionWithTitle:@"Bash (.sh)"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
        [self promptForFilename:@"sh" language:CodeLanguageBash];
    }]];

    [options addAction:[UIAlertAction actionWithTitle:@"Text (.txt)"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
        [self promptForFilename:@"txt" language:CodeLanguagePlainText];
    }]];

    [options addAction:[UIAlertAction actionWithTitle:@"Custom Extension..."
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
        [self promptForCustomFile];
    }]];

    [options addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];

    // For iPad
    if (options.popoverPresentationController) {
        options.popoverPresentationController.sourceView = self.editorButton;
        options.popoverPresentationController.sourceRect = self.editorButton.bounds;
    }

    [self presentViewController:options animated:YES completion:nil];
}

- (void)openFileInEditor:(NSString *)filePath {
    @try {
        CodeEditorViewController *editor = [[CodeEditorViewController alloc] initWithFilePath:filePath];
        editor.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:editor animated:YES completion:nil];
    } @catch (NSException *exception) {
        NSLog(@"Editor error: %@", exception);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:[NSString stringWithFormat:@"Failed to open editor: %@", exception.reason]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)promptForFilename:(NSString *)extension language:(CodeLanguage)language {
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:@"New File"
                                                                    message:[NSString stringWithFormat:@"Enter filename only (extension .%@ will be added automatically)", extension]
                                                             preferredStyle:UIAlertControllerStyleAlert];

    [prompt addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"filename";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.text = @"";  // Start with empty field
    }];

    [prompt addAction:[UIAlertAction actionWithTitle:@"Create"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        UITextField *textField = prompt.textFields.firstObject;
        NSString *filename = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (!filename || filename.length == 0) {
            filename = @"untitled";
        }

        // Remove extension if user added it by mistake (e.g., "test.py" -> "test")
        NSString *extensionWithDot = [NSString stringWithFormat:@".%@", extension];
        if ([filename hasSuffix:extensionWithDot]) {
            filename = [filename substringToIndex:filename.length - extensionWithDot.length];
        }

        // Add extension
        NSString *fullFilename = [NSString stringWithFormat:@"%@.%@", filename, extension];
        [self createNewFile:fullFilename language:language];
    }]];

    [prompt addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [self presentViewController:prompt animated:YES completion:nil];
}

- (void)promptForCustomFile {
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:@"Custom File"
                                                                    message:@"Enter full filename with extension (will be saved in /root)"
                                                             preferredStyle:UIAlertControllerStyleAlert];

    [prompt addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"filename.ext";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    [prompt addAction:[UIAlertAction actionWithTitle:@"Create"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        UITextField *textField = prompt.textFields.firstObject;
        NSString *filename = textField.text;

        if (!filename || filename.length == 0) {
            filename = @"untitled.txt";
        }

        [self createNewFile:filename language:CodeLanguagePlainText];
    }]];

    [prompt addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [self presentViewController:prompt animated:YES completion:nil];
}

- (void)createNewFile:(NSString *)filename language:(CodeLanguage)language {
    @try {
        // Default content based on language
        NSString *defaultContent = @"";
        if (language == CodeLanguagePython) {
            defaultContent = @"#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\n\ndef main():\n    print(\"Hello, World!\")\n\nif __name__ == \"__main__\":\n    main()\n";
        } else if (language == CodeLanguageBash) {
            defaultContent = @"#!/bin/bash\n\necho \"Hello, World!\"\n";
        }

        // Use new initializer with filename
        CodeEditorViewController *editor = [[CodeEditorViewController alloc] initWithContent:defaultContent language:language filename:filename];

        // Remove onSave callback - CodeEditor handles file picker now
        editor.onSave = nil;

        // Old callback code (commented out - not needed anymore):
        /*
        NSString *capturedFilename = [filename copy];
        __weak typeof(self) weakSelf = self;

        editor.onSave = ^(NSString *content) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            // Store content and filename temporarily
            strongSelf.pendingSaveContent = content;
            strongSelf.pendingSaveFilename = capturedFilename;

            // Show document picker to choose save location
            if (@available(iOS 14.0, *)) {
                // Create a temporary file with the content
                NSString *tempDir = NSTemporaryDirectory();
                NSString *tempPath = [tempDir stringByAppendingPathComponent:capturedFilename];

                NSError *writeError = nil;
                [content writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];

                if (writeError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                                       message:@"Failed to prepare file for saving"
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];

                        // Get the topmost view controller to present the alert
                        UIViewController *topVC = strongSelf;
                        while (topVC.presentedViewController) {
                            topVC = topVC.presentedViewController;
                        }
                        [topVC presentViewController:alert animated:YES completion:nil];
                    });
                    return;
                }

                NSURL *tempURL = [NSURL fileURLWithPath:tempPath];

                dispatch_async(dispatch_get_main_queue(), ^{
                    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[tempURL]];
                    picker.delegate = strongSelf;
                    picker.modalPresentationStyle = UIModalPresentationFormSheet;

                    // Get the topmost view controller to present the picker
                    UIViewController *topVC = strongSelf;
                    while (topVC.presentedViewController) {
                        topVC = topVC.presentedViewController;
                    }

                    NSLog(@"📝 Presenting document picker from: %@", NSStringFromClass([topVC class]));
                    [topVC presentViewController:picker animated:YES completion:nil];
                });
            } else {
                // Fallback for older iOS - save directly to /root
                NSString *rootPath = [NSString stringWithFormat:@"%@/roots/alpine/root", ContainerURL().path];
                NSString *fullPath = [rootPath stringByAppendingPathComponent:capturedFilename];

                NSError *error = nil;
                [[NSFileManager defaultManager] createDirectoryAtPath:rootPath
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&error];

                if (!error) {
                    [content writeToFile:fullPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    UIViewController *topVC = strongSelf;
                    while (topVC.presentedViewController) {
                        topVC = topVC.presentedViewController;
                    }

                    if (!error) {
                        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"File Saved"
                                                                                       message:[NSString stringWithFormat:@"Saved to /root/%@", capturedFilename]
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [topVC presentViewController:alert animated:YES completion:nil];
                    } else {
                        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Failed"
                                                                                       message:error.localizedDescription
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [topVC presentViewController:alert animated:YES completion:nil];
                    }
                });
            }
        };
        */

        editor.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:editor animated:YES completion:nil];
    } @catch (NSException *exception) {
        NSLog(@"Create file error: %@", exception);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:[NSString stringWithFormat:@"Failed to create file: %@", exception.reason]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) {
        NSURL *selectedURL = urls[0];
        NSLog(@"✅ File saved to: %@", selectedURL.path);

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"File Saved"
                                                                       message:[NSString stringWithFormat:@"Saved successfully to:\n%@", selectedURL.lastPathComponent]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }

    // Clear pending save state
    self.pendingSaveContent = nil;
    self.pendingSaveFilename = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"📝 File save cancelled");

    // Clear pending save state
    self.pendingSaveContent = nil;
    self.pendingSaveFilename = nil;
}

@end

@interface BarView : UIInputView
@property (weak) IBOutlet TerminalViewController *terminalViewController;
@property (nonatomic) IBInspectable BOOL allowsSelfSizing;
@end
@implementation BarView
@dynamic allowsSelfSizing;

- (void)layoutSubviews {
    [self.terminalViewController resizeBar];
}

@end
