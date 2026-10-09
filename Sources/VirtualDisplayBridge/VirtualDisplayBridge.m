#import "VirtualDisplayBridge.h"

// Private CoreGraphics interfaces, originally documented by Khaos Tian / DeskPad.
// Resolve classes at runtime so an OS change produces a useful error instead of a loader crash.
@interface SCRDisplayDescriptor : NSObject
@property(nonatomic, strong) NSString *name;
@property(nonatomic) unsigned int maxPixelsWide, maxPixelsHigh, vendorID, productID, serialNum;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@property(nonatomic) unsigned int serialNumber;
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end
@interface SCRDisplaySettings : NSObject
@property(nonatomic, strong) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@end
@interface SCRDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(CGFloat)rate;
@end
@interface SCRDisplay : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@end

@implementation SCRVirtualMonitor {
    SCRDisplay *_display;
}
- (instancetype)initWithFailure:(NSString **)failure {
    self = [super init];
    if (!self) return nil;
    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    NSString *message = nil;
    if (!descriptorClass || !displayClass || !settingsClass || !modeClass) {
        message = @"This macOS version does not expose the virtual display interface. Use a physical monitor or display emulator.";
    } else {
        @try {
            SCRDisplayDescriptor *descriptor = [[descriptorClass alloc] init];
            descriptor.name = @"Screener 4K";
            descriptor.maxPixelsWide = 7680;
            descriptor.maxPixelsHigh = 4320;
            descriptor.sizeInMillimeters = CGSizeMake(600, 338);
            descriptor.vendorID = 0x5343;
            descriptor.productID = 0x524E;
            descriptor.serialNum = 1; // Stable identity preserves macOS arrangement and scaling.
            [descriptor setDispatchQueue:dispatch_get_main_queue()];
            if ([descriptor respondsToSelector:@selector(setSerialNumber:)]) descriptor.serialNumber = 1;
            if ([descriptor respondsToSelector:@selector(setRedPrimary:)] && [descriptor respondsToSelector:@selector(setGreenPrimary:)] &&
                [descriptor respondsToSelector:@selector(setBluePrimary:)] && [descriptor respondsToSelector:@selector(setWhitePoint:)]) {
                descriptor.redPrimary = CGPointMake(0.64, 0.33);
                descriptor.greenPrimary = CGPointMake(0.30, 0.60);
                descriptor.bluePrimary = CGPointMake(0.15, 0.06);
                descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
            }
            _display = [[displayClass alloc] initWithDescriptor:descriptor];
            if (!_display || !_display.displayID) {
                message = @"macOS could not create the virtual monitor. Run Screener Server in your logged-in desktop session.";
            } else {
                SCRDisplaySettings *settings = [[settingsClass alloc] init];
                settings.hiDPI = 1;
                NSMutableArray *modes = [NSMutableArray array];
                // With hiDPI enabled, mode dimensions are logical; WindowServer renders at 2x.
                // This convention is also used by Chromium's virtual-display test utility.
                const NSUInteger sizes[][2] = {{1920,1080},{2560,1440},{3008,1692},{3360,1890},{3840,2160},{1280,720}};
                for (NSUInteger i = 0; i < sizeof(sizes)/sizeof(sizes[0]); i++) {
                    id mode = [[modeClass alloc] initWithWidth:sizes[i][0] height:sizes[i][1] refreshRate:60];
                    if (mode) [modes addObject:mode];
                }
                settings.modes = modes;
                if (![_display applySettings:settings]) message = @"macOS rejected the virtual monitor's HiDPI modes.";
            }
        } @catch (NSException *exception) {
            message = [NSString stringWithFormat:@"Virtual displays are incompatible with this macOS build: %@", exception.reason];
        }
    }
    if (message) {
        _display = nil;
        if (failure) *failure = message;
        return nil;
    }
    return self;
}
- (CGDirectDisplayID)displayID { return _display.displayID; }
@end
