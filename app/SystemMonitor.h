//
//  SystemMonitor.h
//  iSH - System Resource Monitor
//
//  مراقبة استخدام المعالج والذاكرة مثل Hopper
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// System status
typedef NS_ENUM(NSInteger, SystemStatus) {
    SystemStatusNormal,      // 🟢 Green - كل شيء طبيعي
    SystemStatusWarning,     // 🟡 Yellow - استخدام متوسط
    SystemStatusCritical     // 🔴 Red - ضغط شديد
};

@interface SystemMonitor : NSObject

// Current stats
@property (nonatomic, assign, readonly) float cpuUsage;        // 0.0 - 100.0
@property (nonatomic, assign, readonly) float memoryUsage;     // 0.0 - 100.0
@property (nonatomic, assign, readonly) uint64_t usedMemory;   // Bytes
@property (nonatomic, assign, readonly) uint64_t totalMemory;  // Bytes

// Status
@property (nonatomic, assign, readonly) SystemStatus systemStatus;

// Initialize
+ (instancetype)shared;

// Update stats (يتم استدعاؤها دورياً)
- (void)updateStats;

// Get color for current status
- (UIColor *)statusColor;
- (NSString *)statusText;
- (NSString *)statusEmoji;

// Format helpers
- (NSString *)formattedMemoryUsage;  // "1.2 GB / 4.0 GB"
- (NSString *)formattedCPUUsage;     // "45%"

@end

NS_ASSUME_NONNULL_END
