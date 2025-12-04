//
//  SplitTerminalViewController.h
//  iSH
//
//  XSH Split Screen Terminal
//

#import <UIKit/UIKit.h>
#import "TerminalViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SplitOrientation) {
    SplitOrientationHorizontal, // Side by side (⬌)
    SplitOrientationVertical    // Top and bottom (⬍)
};

@interface SplitTerminalViewController : UIViewController

@property (nonatomic, strong) TerminalViewController *leftTerminal;  // or top terminal
@property (nonatomic, strong) TerminalViewController *rightTerminal; // or bottom terminal
@property (nonatomic, assign) SplitOrientation orientation;
@property (nonatomic, assign) CGFloat splitRatio; // 0.0 - 1.0 (default: 0.5)

// Initialize with orientation
- (instancetype)initWithOrientation:(SplitOrientation)orientation;

- (void)focusLeftTerminal;
- (void)focusRightTerminal;
- (void)swapTerminals;
- (void)closeSplitView;

@end

NS_ASSUME_NONNULL_END
