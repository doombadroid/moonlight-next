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

// Deck and widget input goes to its own controller and gyro input to another, both merged into
// player 1 when sent, so neither releases what the on-screen controls (or each other) hold
+ (void) gamepadButton:(int)flag down:(BOOL)down {
    ControllerSupport* cs = sControllerSupport;
    Controller* controller = [cs getInputController];
    if (controller == nil) {
        return;
    }
    if (down) {
        [cs setButtonFlag:controller flags:flag];
    }
    else {
        [cs clearButtonFlag:controller flags:flag];
    }
    [cs updateFinished:[cs getOscController]];
}

+ (void) gamepadLeftStickX:(short)x y:(short)y {
    ControllerSupport* cs = sControllerSupport;
    [cs updateLeftStick:[cs getInputController] x:x y:y];
    [cs updateFinished:[cs getOscController]];
}

+ (void) gamepadRightStickX:(short)x y:(short)y {
    ControllerSupport* cs = sControllerSupport;
    [cs updateRightStick:[cs getInputController] x:x y:y];
    [cs updateFinished:[cs getOscController]];
}

+ (void) gamepadLeftTrigger:(uint8_t)left {
    ControllerSupport* cs = sControllerSupport;
    [cs updateLeftTrigger:[cs getInputController] left:left];
    [cs updateFinished:[cs getOscController]];
}

+ (void) gamepadRightTrigger:(uint8_t)right {
    ControllerSupport* cs = sControllerSupport;
    [cs updateRightTrigger:[cs getInputController] right:right];
    [cs updateFinished:[cs getOscController]];
}

+ (void) gamepadGyroStickX:(short)x y:(short)y {
    ControllerSupport* cs = sControllerSupport;
    [cs updateRightStick:[cs getGyroController] x:x y:y];
    [cs updateFinished:[cs getOscController]];
}

+ (void) gamepadSteerX:(short)x {
    ControllerSupport* cs = sControllerSupport;
    [cs updateLeftStick:[cs getGyroController] x:x y:0];
    [cs updateFinished:[cs getOscController]];
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
    ControllerSupport* cs = sControllerSupport;
    return MAX([cs getOscController].lastLeftTrigger, [cs getInputController].lastLeftTrigger) > 64;
}

@end
