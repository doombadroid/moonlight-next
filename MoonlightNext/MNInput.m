//
//  MNInput.m
//  Moonlight Next
//

#import "MNInput.h"
#import "ControllerSupport.h"

#include <Limelight.h>

static __weak ControllerSupport* sControllerSupport;

@implementation MNInput

+ (void) setControllerSupport:(ControllerSupport*)controllerSupport {
    sControllerSupport = controllerSupport;
}

+ (void) keyDown:(short)vk modifiers:(MNKeyModifiers)modifiers {
    LiSendKeyboardEvent(0x8000 | vk, KEY_ACTION_DOWN, modifiers);
}

+ (void) keyUp:(short)vk modifiers:(MNKeyModifiers)modifiers {
    LiSendKeyboardEvent(0x8000 | vk, KEY_ACTION_UP, modifiers);
}

+ (void) mouseMoveX:(short)dx y:(short)dy {
    if (dx != 0 || dy != 0) {
        LiSendMouseMoveEvent(dx, dy);
    }
}

+ (void) mouseButton:(MNMouseButton)button down:(BOOL)down {
    LiSendMouseButtonEvent(down ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, button);
}

+ (void) mousePositionX:(short)x y:(short)y width:(short)width height:(short)height {
    if (width > 0 && height > 0) {
        LiSendMousePositionEvent(x, y, width, height);
    }
}

+ (void) scroll:(short)amount {
    if (amount != 0) {
        LiSendHighResScrollEvent(amount);
    }
}

+ (void) hscroll:(short)amount {
    if (amount != 0) {
        LiSendHighResHScrollEvent(amount);
    }
}

+ (void) gamepadButton:(int)flag down:(BOOL)down {
    ControllerSupport* cs = sControllerSupport;
    Controller* controller = [cs getOscController];
    if (controller == nil) {
        return;
    }
    if (down) {
        [cs setButtonFlag:controller flags:flag];
    }
    else {
        [cs clearButtonFlag:controller flags:flag];
    }
    [cs updateFinished:controller];
}

+ (void) gamepadLeftStickX:(short)x y:(short)y {
    ControllerSupport* cs = sControllerSupport;
    Controller* controller = [cs getOscController];
    if (controller == nil) {
        return;
    }
    [cs updateLeftStick:controller x:x y:y];
    [cs updateFinished:controller];
}

+ (void) gamepadRightStickX:(short)x y:(short)y {
    ControllerSupport* cs = sControllerSupport;
    Controller* controller = [cs getOscController];
    if (controller == nil) {
        return;
    }
    [cs updateRightStick:controller x:x y:y];
    [cs updateFinished:controller];
}

+ (void) gamepadLeftTrigger:(uint8_t)left {
    ControllerSupport* cs = sControllerSupport;
    Controller* controller = [cs getOscController];
    if (controller == nil) {
        return;
    }
    [cs updateLeftTrigger:controller left:left];
    [cs updateFinished:controller];
}

+ (void) gamepadRightTrigger:(uint8_t)right {
    ControllerSupport* cs = sControllerSupport;
    Controller* controller = [cs getOscController];
    if (controller == nil) {
        return;
    }
    [cs updateRightTrigger:controller right:right];
    [cs updateFinished:controller];
}

+ (void) gamepadSteerX:(short)x {
    ControllerSupport* cs = sControllerSupport;
    Controller* controller = [cs getOscController];
    if (controller == nil) {
        return;
    }
    [cs updateLeftStick:controller x:x y:controller.lastLeftStickY];
    [cs updateFinished:controller];
}

+ (void) controllerTouch:(MNControllerTouchPhase)phase pointer:(uint32_t)pointer x:(float)x y:(float)y {
    Controller* controller = [sControllerSupport getOscController];
    uint8_t type = phase == MNControllerTouchPhaseDown ? LI_TOUCH_EVENT_DOWN
                 : phase == MNControllerTouchPhaseUp ? LI_TOUCH_EVENT_UP : LI_TOUCH_EVENT_MOVE;
    LiSendControllerTouchEvent(controller != nil ? (uint8_t)controller.playerIndex : 0, type, pointer, x, y, 1.0f);
}

+ (void) controllerMotion:(uint8_t)type x:(float)x y:(float)y z:(float)z {
    LiSendControllerMotionEvent(0, type, x, y, z);
}

+ (BOOL) aimTriggerHeld {
    return [sControllerSupport getOscController].lastLeftTrigger > 64;
}

@end
