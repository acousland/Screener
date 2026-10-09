#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
/// Creates a persistent, HiDPI monitor. Retain this object for the lifetime of the server.
@interface SCRVirtualMonitor : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (nullable instancetype)initWithFailure:(NSString * _Nullable * _Nullable)failure NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end
NS_ASSUME_NONNULL_END
