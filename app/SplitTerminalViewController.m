//
//  SplitTerminalViewController.m
//  iSH
//
//  XSH Split Screen Terminal
//

#import "SplitTerminalViewController.h"

@interface SplitTerminalViewController ()

@property (nonatomic, strong) UIView *containerLeft;
@property (nonatomic, strong) UIView *containerRight;
@property (nonatomic, strong) UIView *dividerView;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) NSLayoutConstraint *splitConstraint;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *swapButton;
@property (nonatomic, strong) UILabel *leftLabel;
@property (nonatomic, strong) UILabel *rightLabel;
@property (nonatomic, assign) BOOL constraintsSetUp;

@end

@implementation SplitTerminalViewController

- (instancetype)initWithOrientation:(SplitOrientation)orientation {
    self = [super init];
    if (self) {
        _orientation = orientation;
        _splitRatio = 0.5; // 50/50 split by default
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self setupContainers];
    [self setupDivider];
    [self setupControls];
    [self setupTerminals];
    [self setupGestures];
}

- (void)setupContainers {
    // Left/Top container
    self.containerLeft = [[UIView alloc] init];
    self.containerLeft.translatesAutoresizingMaskIntoConstraints = NO;
    self.containerLeft.backgroundColor = [UIColor blackColor];
    self.containerLeft.layer.borderColor = [UIColor systemGrayColor].CGColor;
    self.containerLeft.layer.borderWidth = 1.0;
    [self.view addSubview:self.containerLeft];

    // Right/Bottom container
    self.containerRight = [[UIView alloc] init];
    self.containerRight.translatesAutoresizingMaskIntoConstraints = NO;
    self.containerRight.backgroundColor = [UIColor blackColor];
    self.containerRight.layer.borderColor = [UIColor systemGrayColor].CGColor;
    self.containerRight.layer.borderWidth = 1.0;
    [self.view addSubview:self.containerRight];

    // Layout constraints
    [self updateLayout];
}

- (void)setupDivider {
    // No visible divider - drag from control bar instead
}

- (void)setupControls {
    // Control bar at top with blur effect - full bar is draggable
    UIVisualEffectView *controlBar;
    if (@available(iOS 13.0, *)) {
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
        controlBar = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    } else {
        controlBar = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleLight]];
    }
    controlBar.translatesAutoresizingMaskIntoConstraints = NO;
    controlBar.userInteractionEnabled = YES;
    [self.view addSubview:controlBar];

    [NSLayoutConstraint activateConstraints:@[
        [controlBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [controlBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [controlBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [controlBar.heightAnchor constraintEqualToConstant:44]
    ]];

    UIView *contentView = controlBar.contentView;

    // Left terminal label - simple text
    self.leftLabel = [[UILabel alloc] init];
    self.leftLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.leftLabel.text = @"1";
    self.leftLabel.font = [UIFont boldSystemFontOfSize:16];
    self.leftLabel.textColor = [UIColor systemBlueColor];
    [contentView addSubview:self.leftLabel];

    // Right terminal label - simple text
    self.rightLabel = [[UILabel alloc] init];
    self.rightLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.rightLabel.text = @"2";
    self.rightLabel.font = [UIFont systemFontOfSize:16];
    self.rightLabel.textColor = [UIColor secondaryLabelColor];
    [contentView addSubview:self.rightLabel];

    // Swap button - simple text
    self.swapButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.swapButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.swapButton setTitle:@"↔" forState:UIControlStateNormal];
    self.swapButton.titleLabel.font = [UIFont systemFontOfSize:20];
    self.swapButton.tintColor = [UIColor systemBlueColor];
    [self.swapButton addTarget:self action:@selector(swapTerminals) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:self.swapButton];

    // Close button - simple X
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:22];
    self.closeButton.tintColor = [UIColor systemRedColor];
    [self.closeButton addTarget:self action:@selector(closeSplitView) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:self.closeButton];

    // Drag indicator in center
    UILabel *dragIndicator = [[UILabel alloc] init];
    dragIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    dragIndicator.text = @"⋮⋮⋮";
    dragIndicator.font = [UIFont systemFontOfSize:14];
    dragIndicator.textColor = [UIColor.systemGrayColor colorWithAlphaComponent:0.5];
    [contentView addSubview:dragIndicator];

    // Layout controls
    [NSLayoutConstraint activateConstraints:@[
        // Left label
        [self.leftLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:16],
        [self.leftLabel.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],

        // Drag indicator in center
        [dragIndicator.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [dragIndicator.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],

        // Right label
        [self.rightLabel.trailingAnchor constraintEqualToAnchor:self.swapButton.leadingAnchor constant:-12],
        [self.rightLabel.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],

        // Swap button
        [self.swapButton.trailingAnchor constraintEqualToAnchor:self.closeButton.leadingAnchor constant:-12],
        [self.swapButton.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        [self.swapButton.widthAnchor constraintEqualToConstant:32],

        // Close button
        [self.closeButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-16],
        [self.closeButton.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        [self.closeButton.widthAnchor constraintEqualToConstant:32]
    ]];

    // Store control bar reference for gesture - whole bar is draggable
    self.dividerView = controlBar;
}

- (void)setupTerminals {
    // Create terminal view controllers from storyboard
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Terminal" bundle:nil];

    self.leftTerminal = [storyboard instantiateInitialViewController];
    self.rightTerminal = [storyboard instantiateInitialViewController];

    // Fallback if storyboard loading fails
    if (!self.leftTerminal) {
        self.leftTerminal = [[TerminalViewController alloc] init];
    }
    if (!self.rightTerminal) {
        self.rightTerminal = [[TerminalViewController alloc] init];
    }

    // Add left terminal as child view controller
    [self addChildViewController:self.leftTerminal];
    self.leftTerminal.view.frame = self.containerLeft.bounds;
    self.leftTerminal.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerLeft addSubview:self.leftTerminal.view];
    [self.leftTerminal didMoveToParentViewController:self];

    // Add right terminal as child view controller
    [self addChildViewController:self.rightTerminal];
    self.rightTerminal.view.frame = self.containerRight.bounds;
    self.rightTerminal.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerRight addSubview:self.rightTerminal.view];
    [self.rightTerminal didMoveToParentViewController:self];

    // Start new sessions after a small delay to avoid conflicts
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.leftTerminal startNewSession];
        [self.rightTerminal startNewSession];
    });

    // Set initial focus
    [self focusLeftTerminal];
}

- (void)setupGestures {
    // Pan gesture for divider
    self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.dividerView addGestureRecognizer:self.panGesture];

    // Tap gestures for focus switching
    UITapGestureRecognizer *leftTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusLeftTerminal)];
    [self.containerLeft addGestureRecognizer:leftTap];

    UITapGestureRecognizer *rightTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusRightTerminal)];
    [self.containerRight addGestureRecognizer:rightTap];
}

- (void)updateLayout {
    // Only update the split ratio constraint, keep other constraints
    if (self.splitConstraint) {
        self.splitConstraint.active = NO;
    }

    CGFloat topOffset = 44; // Control bar height

    // Set up basic constraints only once
    if (!self.constraintsSetUp) {
        self.constraintsSetUp = YES;

        if (self.orientation == SplitOrientationHorizontal) {
            // Side by side layout
            [NSLayoutConstraint activateConstraints:@[
                [self.containerLeft.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:topOffset],
                [self.containerLeft.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
                [self.containerLeft.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

                [self.containerRight.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:topOffset],
                [self.containerRight.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
                [self.containerRight.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

                [self.containerRight.leadingAnchor constraintEqualToAnchor:self.containerLeft.trailingAnchor]
            ]];
        } else {
            // Top and bottom layout
            [NSLayoutConstraint activateConstraints:@[
                [self.containerLeft.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:topOffset],
                [self.containerLeft.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
                [self.containerLeft.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

                [self.containerRight.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
                [self.containerRight.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
                [self.containerRight.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

                [self.containerRight.topAnchor constraintEqualToAnchor:self.containerLeft.bottomAnchor]
            ]];
        }
    }

    // Update split ratio constraint every time
    if (self.orientation == SplitOrientationHorizontal) {
        self.splitConstraint = [self.containerLeft.widthAnchor constraintEqualToAnchor:self.view.widthAnchor
                                                                             multiplier:self.splitRatio];
    } else {
        self.splitConstraint = [self.containerLeft.heightAnchor constraintEqualToAnchor:self.view.heightAnchor
                                                                              multiplier:self.splitRatio];
    }

    self.splitConstraint.active = YES;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.view];

    if (self.orientation == SplitOrientationHorizontal) {
        // Horizontal split - adjust width
        CGFloat newRatio = self.splitRatio + (translation.x / self.view.bounds.size.width);
        newRatio = MAX(0.2, MIN(0.8, newRatio)); // Limit to 20%-80%
        self.splitRatio = newRatio;
    } else {
        // Vertical split - adjust height
        CGFloat newRatio = self.splitRatio + (translation.y / self.view.bounds.size.height);
        newRatio = MAX(0.2, MIN(0.8, newRatio)); // Limit to 20%-80%
        self.splitRatio = newRatio;
    }

    [gesture setTranslation:CGPointZero inView:self.view];
    [self updateLayout];
}

- (void)focusLeftTerminal {
    [self.leftTerminal.view becomeFirstResponder];
    self.leftLabel.textColor = [UIColor systemBlueColor];
    self.leftLabel.font = [UIFont boldSystemFontOfSize:16];
    self.rightLabel.textColor = [UIColor secondaryLabelColor];
    self.rightLabel.font = [UIFont systemFontOfSize:16];
}

- (void)focusRightTerminal {
    [self.rightTerminal.view becomeFirstResponder];
    self.rightLabel.textColor = [UIColor systemBlueColor];
    self.rightLabel.font = [UIFont boldSystemFontOfSize:16];
    self.leftLabel.textColor = [UIColor secondaryLabelColor];
    self.leftLabel.font = [UIFont systemFontOfSize:16];
}

- (void)swapTerminals {
    // Swap the terminal instances
    TerminalViewController *temp = self.leftTerminal;
    self.leftTerminal = self.rightTerminal;
    self.rightTerminal = temp;

    // Swap the views
    [self.containerLeft.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self.containerRight.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    self.leftTerminal.view.frame = self.containerLeft.bounds;
    [self.containerLeft addSubview:self.leftTerminal.view];

    self.rightTerminal.view.frame = self.containerRight.bounds;
    [self.containerRight addSubview:self.rightTerminal.view];

    // Swap labels
    NSString *tempText = self.leftLabel.text;
    self.leftLabel.text = self.rightLabel.text;
    self.rightLabel.text = tempText;

    // Animate swap
    [UIView animateWithDuration:0.3 animations:^{
        self.containerLeft.transform = CGAffineTransformMakeScale(0.95, 0.95);
        self.containerRight.transform = CGAffineTransformMakeScale(0.95, 0.95);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            self.containerLeft.transform = CGAffineTransformIdentity;
            self.containerRight.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)closeSplitView {
    // Show simple confirmation alert
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Close Split View?"
                                                                   message:@"Both terminal sessions will be closed."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Close"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
