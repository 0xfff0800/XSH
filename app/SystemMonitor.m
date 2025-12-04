//
//  SystemMonitor.m
//  iSH - System Resource Monitor Implementation
//
//  مراقبة استخدام المعالج والذاكرة مثل Hopper
//

#import "SystemMonitor.h"
#import <mach/mach.h>
#import <sys/sysctl.h>

@interface SystemMonitor ()
@property (nonatomic, assign) float cpuUsage;
@property (nonatomic, assign) float memoryUsage;
@property (nonatomic, assign) uint64_t usedMemory;
@property (nonatomic, assign) uint64_t totalMemory;
@property (nonatomic, assign) SystemStatus systemStatus;
@end

@implementation SystemMonitor

+ (instancetype)shared {
    static SystemMonitor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SystemMonitor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _cpuUsage = 0.0;
        _memoryUsage = 0.0;
        _usedMemory = 0;
        _totalMemory = [self getTotalMemory];
        _systemStatus = SystemStatusNormal;
    }
    return self;
}

#pragma mark - Update Stats

- (void)updateStats {
    // Update CPU
    self.cpuUsage = [self getCurrentCPUUsage];

    // Update Memory
    self.usedMemory = [self getCurrentMemoryUsage];
    self.memoryUsage = (self.totalMemory > 0) ?
                       ((float)self.usedMemory / (float)self.totalMemory * 100.0f) : 0.0f;

    // Determine system status based on CPU and Memory
    [self determineSystemStatus];
}

#pragma mark - CPU Monitoring

- (float)getCurrentCPUUsage {
    kern_return_t kr;
    task_info_data_t tinfo;
    mach_msg_type_number_t task_info_count;

    task_info_count = TASK_INFO_MAX;
    kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)tinfo, &task_info_count);
    if (kr != KERN_SUCCESS) {
        return 0.0f;
    }

    thread_array_t thread_list;
    mach_msg_type_number_t thread_count;

    thread_info_data_t thinfo;
    mach_msg_type_number_t thread_info_count;

    thread_basic_info_t basic_info_th;

    // Get threads in task
    kr = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (kr != KERN_SUCCESS) {
        return 0.0f;
    }

    float tot_cpu = 0;

    for (int j = 0; j < thread_count; j++) {
        thread_info_count = THREAD_INFO_MAX;
        kr = thread_info(thread_list[j], THREAD_BASIC_INFO,
                        (thread_info_t)thinfo, &thread_info_count);
        if (kr != KERN_SUCCESS) {
            continue;
        }

        basic_info_th = (thread_basic_info_t)thinfo;

        if (!(basic_info_th->flags & TH_FLAGS_IDLE)) {
            tot_cpu += basic_info_th->cpu_usage / (float)TH_USAGE_SCALE * 100.0f;
        }
    }

    // Cleanup
    kr = vm_deallocate(mach_task_self(), (vm_offset_t)thread_list,
                      thread_count * sizeof(thread_t));

    return tot_cpu;
}

#pragma mark - Memory Monitoring

- (uint64_t)getTotalMemory {
    // Get total physical memory
    int mib[2];
    int64_t physical_memory;
    size_t length;

    mib[0] = CTL_HW;
    mib[1] = HW_MEMSIZE;
    length = sizeof(int64_t);
    sysctl(mib, 2, &physical_memory, &length, NULL, 0);

    return (uint64_t)physical_memory;
}

- (uint64_t)getCurrentMemoryUsage {
    // Get current task memory usage
    struct mach_task_basic_info info;
    mach_msg_type_number_t size = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(),
                                 MACH_TASK_BASIC_INFO,
                                 (task_info_t)&info,
                                 &size);

    if (kr != KERN_SUCCESS) {
        return 0;
    }

    return info.resident_size;
}

#pragma mark - System Status

- (void)determineSystemStatus {
    // تحديد حالة النظام بناءً على CPU و Memory

    // Critical: CPU > 80% OR Memory > 85%
    if (self.cpuUsage > 80.0f || self.memoryUsage > 85.0f) {
        self.systemStatus = SystemStatusCritical;
    }
    // Warning: CPU > 50% OR Memory > 60%
    else if (self.cpuUsage > 50.0f || self.memoryUsage > 60.0f) {
        self.systemStatus = SystemStatusWarning;
    }
    // Normal: Everything stable
    else {
        self.systemStatus = SystemStatusNormal;
    }
}

#pragma mark - Display Helpers

- (UIColor *)statusColor {
    switch (self.systemStatus) {
        case SystemStatusNormal:
            return [UIColor colorWithRed:0.2 green:0.8 blue:0.3 alpha:1.0];  // 🟢 Green
        case SystemStatusWarning:
            return [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];  // 🟡 Yellow
        case SystemStatusCritical:
            return [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];  // 🔴 Red
    }
}

- (NSString *)statusText {
    switch (self.systemStatus) {
        case SystemStatusNormal:
            return @"Stable";
        case SystemStatusWarning:
            return @"Moderate Load";
        case SystemStatusCritical:
            return @"High Load";
    }
}

- (NSString *)statusEmoji {
    switch (self.systemStatus) {
        case SystemStatusNormal:
            return @"🟢";
        case SystemStatusWarning:
            return @"🟡";
        case SystemStatusCritical:
            return @"🔴";
    }
}

- (NSString *)formattedMemoryUsage {
    return [NSString stringWithFormat:@"%@ / %@",
            [self formatBytes:self.usedMemory],
            [self formatBytes:self.totalMemory]];
}

- (NSString *)formattedCPUUsage {
    return [NSString stringWithFormat:@"%.1f%%", self.cpuUsage];
}

#pragma mark - Helpers

- (NSString *)formatBytes:(uint64_t)bytes {
    double kb = bytes / 1024.0;
    double mb = kb / 1024.0;
    double gb = mb / 1024.0;

    if (gb >= 1.0) {
        return [NSString stringWithFormat:@"%.1f GB", gb];
    } else if (mb >= 1.0) {
        return [NSString stringWithFormat:@"%.1f MB", mb];
    } else {
        return [NSString stringWithFormat:@"%.1f KB", kb];
    }
}

@end
