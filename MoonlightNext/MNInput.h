//
//  MNInput.h
//  Moonlight Next
//
//  Keyboard, mouse and gamepad input for the tabletop input deck (SwiftUI). Thin wrappers
//  over moonlight-common-c's LiSend* calls, which Swift can't reach directly.
//

#import <Foundation/Foundation.h>

@class ControllerSupport;

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(uint8_t, MNKeyModifiers) {
    MNKeyModifierShift = 0x01,
    MNKeyModifierCtrl  = 0x02,
    MNKeyModifierAlt   = 0x04,
    MNKeyModifierMeta  = 0x08,
};

typedef NS_ENUM(int, MNMouseButton) {
    MNMouseButtonLeft = 1,
    MNMouseButtonMiddle = 2,
    MNMouseButtonRight = 3,
};

@interface MNInput : NSObject

// Set by the stream while it runs (nil when it ends); gamepad calls do nothing without it.
+ (void) setControllerSupport:(nullable ControllerSupport*)controllerSupport;

// vk is a Windows virtual-key code (0x41 = A).
+ (void) keyDown:(short)vk modifiers:(MNKeyModifiers)modifiers;
+ (void) keyUp:(short)vk modifiers:(MNKeyModifiers)modifiers;

+ (void) mouseMoveX:(short)dx y:(short)dy;
+ (void) mouseButton:(MNMouseButton)button down:(BOOL)down;
// One notch is 120, positive scrolls up.
+ (void) scroll:(short)amount;
// Horizontal, same units; positive scrolls right.
+ (void) hscroll:(short)amount;

// Button flags as in Limelight.h (A_FLAG = 0x1000 ...), merged into the on-screen controller.
+ (void) gamepadButton:(int)flag down:(BOOL)down;
// -32768...32767, y up is positive.
+ (void) gamepadLeftStickX:(short)x y:(short)y;
+ (void) gamepadRightStickX:(short)x y:(short)y;
+ (void) gamepadLeftTrigger:(uint8_t)left;
+ (void) gamepadRightTrigger:(uint8_t)right;

// One notch is 120, positive scrolls right.
+ (void) horizontalScroll:(short)amount;
// Left stick x only, leaving y to the on-screen stick (gyro steering).
+ (void) gamepadSteerX:(short)x;
// Player 1 motion sample in the host's convention (SDL axes; m/s² for accel, deg/s for gyro).
// type: 1 = accelerometer, 2 = gyroscope (LI_MOTION_TYPE_*).
+ (void) controllerMotion:(uint8_t)type x:(float)x y:(float)y z:(float)z;

// L2 / left trigger held on the on-screen controller (on-screen controls or the deck); gyro
// aiming can be limited to this, aim-down-sights style.
+ (BOOL) aimTriggerHeld;

@end

NS_ASSUME_NONNULL_END
