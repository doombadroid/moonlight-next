//
//  StreamView.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "ControllerSupport.h"
#import "OnScreenControls.h"
#import "Moonlight-Swift.h"
#import "StreamConfiguration.h"

@protocol UserInteractionDelegate <NSObject>

- (void) userInteractionBegan;
- (void) userInteractionEnded;

#if !TARGET_OS_TV
@optional
// Ctrl+Alt+Shift + a letter on a hardware keyboard; usage is the letter's UIKeyboardHIDUsage
- (void) streamHotkeyPressed:(NSInteger)usage;
#endif

@end

#if TARGET_OS_TV
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate>
#else
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate, UIPointerInteractionDelegate>
#endif

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                  config:(StreamConfiguration*)streamConfig;
- (void) showOnScreenControls;
- (OnScreenControlsLevel) getCurrentOscState;

#if !TARGET_OS_TV
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse;
// Hides the on-screen controls while the tabletop input deck is up, then restores their level.
- (void) setOnScreenControlsSuppressed:(BOOL)suppressed;
// Re-reads the on-screen controls level from the saved settings (changed mid-stream).
- (void) reloadOnScreenControlsLevel;
// The on-screen controls when they're showing (for the layout editor), else nil.
- (OnScreenControls*) visibleOnScreenControls;

// Touches on the stream do nothing (the Off touch mode, or the stream menu's toggle).
// On-screen controls keep working.
@property (nonatomic) BOOL touchInputDisabled;
// The soft keyboard is up, opened by a finger tap whose lowest finger was at this y
- (BOOL) softKeyboardShown;
- (CGFloat) softKeyboardAnchorY;
// Re-reads the mouse pointer style (MNMouse.cursorVisible changed)
- (void) refreshPointerStyle;
#endif

@end
