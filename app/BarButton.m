//
//  AccessoryButton.m
//  iSH
//
//  Created by Theodore Dubois on 9/22/18.
//

#import "BarButton.h"

@interface BarButton ()
@end

extern UIAccessibilityTraits UIAccessibilityTraitToggle;

@implementation BarButton

- (void)awakeFromNib {
    [super awakeFromNib];
    // Enhanced visual appearance with smoother corners and better shadows
    self.layer.cornerRadius = 8; // Increased from 5 for modern look
    self.layer.shadowOffset = CGSizeMake(0, 2); // Slightly deeper shadow
    self.layer.shadowOpacity = 0.3; // Softer shadow
    self.layer.shadowRadius = 2; // Blur the shadow for better depth
    self.backgroundColor = self.defaultColor;
    self.keyAppearance = UIKeyboardAppearanceLight;
    self.accessibilityTraits |= UIAccessibilityTraitKeyboardKey;
    if (self.toggleable) {
        self.accessibilityTraits |= 0x20000000000000;
    }

    // Add subtle border for better definition
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.1].CGColor;
}

- (UIColor *)primaryColor {
    if (self.keyAppearance == UIKeyboardAppearanceLight)
        return UIColor.whiteColor;
    else
        return [UIColor colorWithRed:1 green:1 blue:1 alpha:77/255.];
}
- (UIColor *)secondaryColor {
    if (self.keyAppearance == UIKeyboardAppearanceLight)
        return [UIColor colorWithRed:172/255. green:180/255. blue:190/255. alpha:1];
    else
        return [UIColor colorWithRed:147/255. green:147/255. blue:147/255. alpha:66/255.];
}
- (UIColor *)defaultColor {
    if (self.secondary)
        return self.secondaryColor;
    return self.primaryColor;
}
- (UIColor *)highlightedColor {
    if (!self.secondary)
        return self.secondaryColor;
    return self.primaryColor;
}

- (void)chooseBackground {
    if (self.selected || self.highlighted) {
        // Smooth transition with spring animation for better feel
        [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.backgroundColor = self.highlightedColor;
            self.transform = CGAffineTransformMakeScale(0.95, 0.95);
        } completion:nil];

        // Add haptic feedback for better user experience
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [feedback impactOccurred];
        }
    } else {
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.backgroundColor = self.defaultColor;
            self.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    if (self.keyAppearance == UIKeyboardAppearanceLight) {
        self.tintColor = UIColor.blackColor;
    } else {
        self.tintColor = UIColor.whiteColor;
    }
    [self setTitleColor:self.tintColor forState:UIControlStateNormal];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self chooseBackground];
}
- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self chooseBackground];
}

- (void)setKeyAppearance:(UIKeyboardAppearance)keyAppearance {
    _keyAppearance = keyAppearance;
    [self chooseBackground];
}

- (NSString *)accessibilityValue {
    if (self.toggleable) {
        return self.selected ? @"1" : @"0";
    }
    return nil;
}

@end
