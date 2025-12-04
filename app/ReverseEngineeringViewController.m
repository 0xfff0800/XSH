//
//  ReverseEngineeringViewController.m
//  iSH
//
//  XSH Pro Feature - Available at https://bye-thost.com/product/ish-نسخة-معدلة-من-xsh/
//

#import "ReverseEngineeringViewController.h"

@implementation ReverseEngineeringViewController

- (instancetype)initWithTerminal:(id)terminal {
    self = [super init];
    if (self) {
        // XSH Pro Feature - Stub only
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"XSH Pro Feature";
    self.view.backgroundColor = [UIColor blackColor];

    // Show Pro message
    UILabel *proLabel = [[UILabel alloc] init];
    proLabel.text = @"🔐 XSH Pro Feature\n\nReverse Engineering is available in XSH Pro.\n\nVisit: bye-thost.com";
    proLabel.textColor = [UIColor whiteColor];
    proLabel.textAlignment = NSTextAlignmentCenter;
    proLabel.numberOfLines = 0;
    proLabel.font = [UIFont systemFontOfSize:18];
    proLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:proLabel];
    [NSLayoutConstraint activateConstraints:@[
        [proLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [proLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [proLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [proLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20]
    ]];
}

@end
