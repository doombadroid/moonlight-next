//
//  MNBridge.h
//  Moonlight Next
//
//  Launcher logic that needs moonlight-common-c macros or stream-side headers, which Swift
//  can't import directly. Ported from MainFrameViewController with the logic unchanged.
//

#import <UIKit/UIKit.h>

@class TemporaryApp;
@class TemporaryHost;
@class StreamConfiguration;

NS_ASSUME_NONNULL_BEGIN

@interface MNBridge : NSObject

// Stream configuration from the saved settings (was prepareToStreamApp:). A saved 0x0
// resolution means "Native": it is resolved here from the window the stream will fill,
// so launching folded or unfolded on an iPhone Duo picks the matching size.
+ (StreamConfiguration*) streamConfigForApp:(TemporaryApp*)app window:(UIWindow*)window;

// Full-screen stream view controller. onExit runs once when the stream ends.
+ (UIViewController*) streamControllerWithConfig:(StreamConfiguration*)config
                                          onExit:(void (^)(BOOL quitApp))onExit;

// Blocking network calls: run these off the main thread.

// Fetches serverinfo and populates the host. Returns nil on success, else an error message.
+ (nullable NSString*) refreshServerInfoForHost:(TemporaryHost*)host;

// Quits the running app. Returns nil on success, else an error message.
+ (nullable NSString*) quitAppOnHost:(TemporaryHost*)host;

// Full port-blocking test; returns a user-facing result message.
+ (NSString*) runNetworkTest;

// Extra text for an add-host failure if this network blocks Moonlight's ports, else "".
+ (NSString*) addHostPortBlockingNote;

// Video capability checks used by Settings.
+ (BOOL) hevcSupported;
+ (BOOL) av1Supported;
+ (BOOL) hdrSupported;

@end

NS_ASSUME_NONNULL_END
