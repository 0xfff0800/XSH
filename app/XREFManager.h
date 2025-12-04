//
//  XREFManager.h
//  iSH - Cross-Reference Manager (XREF System)
//
//  Complete XREF tracking system like Hopper/IDA
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DetectedFunction;

// XREF Types
typedef NS_ENUM(NSInteger, XREFType) {
    XREFTypeCall,           // BL, BLR (function call)
    XREFTypeJump,           // B, BR (jump/branch)
    XREFTypeDataRead,       // LDR (load from address)
    XREFTypeDataWrite,      // STR (store to address)
    XREFTypeStringRef,      // ADRP+ADD to string
    XREFTypeCodeRef,        // ADR to code
};

// Single Cross-Reference
@interface XREF : NSObject

@property (nonatomic, assign) uint64_t fromAddress;     // Source address
@property (nonatomic, assign) uint64_t toAddress;       // Target address
@property (nonatomic, assign) XREFType type;            // Type of reference
@property (nonatomic, strong, nullable) NSString *instruction; // Original instruction
@property (nonatomic, assign) uint64_t offset;          // Offset within function

// Display name
- (NSString *)displayName;                               // "sub_100028420+64"
- (NSString *)typeSymbol;                                // "→" for call, "⇒" for jump, etc.

@end

// XREF Manager - Main System
@interface XREFManager : NSObject

// Storage
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<XREF *> *> *incomingRefs;  // target → [sources]
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<XREF *> *> *outgoingRefs;  // source → [targets]

// Navigation Stack (Back/Forward like IDA/Hopper)
@property (nonatomic, strong) NSMutableArray<NSNumber *> *navigationHistory;
@property (nonatomic, assign) NSInteger currentHistoryIndex;

// Initialize
- (instancetype)init;

// Add XREF
- (void)addXREF:(XREF *)xref;
- (void)addXREFFrom:(uint64_t)from
                 to:(uint64_t)to
               type:(XREFType)type
        instruction:(nullable NSString *)instruction
             offset:(uint64_t)offset;

// Query XREFs
- (NSArray<XREF *> *)getIncomingXREFs:(uint64_t)address;   // Who calls/references this?
- (NSArray<XREF *> *)getOutgoingXREFs:(uint64_t)address;   // What does this call/reference?

// Navigation
- (void)navigateTo:(uint64_t)address;
- (BOOL)canGoBack;
- (BOOL)canGoForward;
- (uint64_t)goBack;      // Returns previous address
- (uint64_t)goForward;   // Returns next address

// Statistics
- (NSUInteger)totalXREFCount;
- (NSDictionary<NSString *, NSNumber *> *)statistics;

// Clear
- (void)clear;

@end

NS_ASSUME_NONNULL_END
