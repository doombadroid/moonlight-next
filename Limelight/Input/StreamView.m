//
//  StreamView.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import AVFoundation;

#import "StreamView.h"
#include <Limelight.h>
#import "DataManager.h"
#import "ControllerSupport.h"
#import "KeyboardSupport.h"
#import "RelativeTouchHandler.h"
#import "AbsoluteTouchHandler.h"
#import "KeyboardInputField.h"

static const double X1_MOUSE_SPEED_DIVISOR = 2.5;

@implementation StreamView {
    OnScreenControls* onScreenControls;
    __weak ControllerSupport* oscControllerSupport;
    BOOL oscSuppressed;
    OnScreenControlsLevel levelBeforeSuppression;
    
    KeyboardInputField* keyInputField;
    BOOL isInputingText;
    
    float streamAspectRatio;
    
    // iOS 13.4 mouse support
    NSInteger lastMouseButtonMask;
    float lastMouseX;
    float lastMouseY;
    CGPoint lastScrollTranslation;
    
    // Citrix X1 mouse support
    X1Mouse* x1mouse;
    double accumulatedMouseDeltaX;
    double accumulatedMouseDeltaY;
    
    UIResponder* touchHandler;
    
    id<UserInteractionDelegate> interactionDelegate;
    NSTimer* interactionTimer;
    BOOL hasUserInteracted;
    
    NSDictionary<NSString *, NSNumber *> *dictCodes;

#if !TARGET_OS_TV
    MNTouchMode touchMode;
    // Native touch: host pointer id (0-10) for each finger on the screen
    NSMutableDictionary<NSValue*, NSNumber*>* nativeTouchIds;
    CGFloat softKeyboardAnchorY;
    UIPointerInteraction* pointerInteraction;
    // The key row above the soft keyboard
    MNKeyBar* keyBar;
    // Native touch: fingers landing right of nativeSplit (a fraction of the width) move
    // nativeSpeed times as far on the host
    CGFloat nativeSpeed;
    CGFloat nativeSplit;
    NSMutableDictionary<NSValue*, NSValue*>* nativeFastTouches;
#endif
}

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                  config:(StreamConfiguration*)streamConfig {
    self->interactionDelegate = interactionDelegate;
    self->streamAspectRatio = (float)streamConfig.width / (float)streamConfig.height;
    
    TemporarySettings* settings = [[[DataManager alloc] init] getSettings];
    
    keyInputField = [[KeyboardInputField alloc] initWithFrame:CGRectZero];
    [keyInputField setKeyboardType:UIKeyboardTypeDefault];
    [keyInputField setAutocorrectionType:UITextAutocorrectionTypeNo];
    [keyInputField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [keyInputField setSpellCheckingType:UITextSpellCheckingTypeNo];
    [self addSubview:keyInputField];
    
#if TARGET_OS_TV
    // tvOS requires RelativeTouchHandler to manage Apple Remote input
    self->touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
#else
    // iOS uses RelativeTouchHandler or AbsoluteTouchHandler depending on user preference
    touchMode = [MNTouchPrefs touchModeWithAbsolute:settings.absoluteTouchMode];
    self.touchInputDisabled = touchMode == MNTouchModeDisabled;
    nativeTouchIds = [[NSMutableDictionary alloc] init];
    nativeFastTouches = [[NSMutableDictionary alloc] init];
    nativeSpeed = MNTouchExtras.nativeSpeed;
    nativeSplit = MNTouchExtras.nativeSplit;
    [MNMouse reset];
    if (touchMode == MNTouchModeTouchscreen || touchMode == MNTouchModeNative) {
        // Native touch falls back to this when the host can't take touch events
        self->touchHandler = [[AbsoluteTouchHandler alloc] initWithView:self];
    }
    else {
        // Also what the Off mode uses once touch is turned back on from the stream menu
        self->touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
    }
    
    onScreenControls = [[OnScreenControls alloc] initWithView:self controllerSup:controllerSupport streamConfig:streamConfig];
    oscControllerSupport = controllerSupport;
    OnScreenControlsLevel level = (OnScreenControlsLevel)[settings.onscreenControls integerValue];
    if (settings.absoluteTouchMode) {
        Log(LOG_I, @"On-screen controls disabled in absolute touch mode");
        [onScreenControls setLevel:OnScreenControlsLevelOff];
    }
    else if (level == OnScreenControlsLevelAuto) {
        [controllerSupport initAutoOnScreenControlMode:onScreenControls];
    }
    else {
        Log(LOG_I, @"Setting manual on-screen controls level: %d", (int)level);
        [onScreenControls setLevel:level];
    }
    
    // It would be nice to just use GCMouse on iOS 14+ and the older API on iOS 13
    // but unfortunately that isn't possible today. GCMouse doesn't recognize many
    // mice correctly, but UIKit does. We will register for both and ignore UIKit
    // events if a GCMouse is connected.
    if (@available(iOS 13.4, *)) {
        pointerInteraction = [[UIPointerInteraction alloc] initWithDelegate:self];
        [self addInteraction:pointerInteraction];
        
        UIPanGestureRecognizer *discreteMouseWheelRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mouseWheelMovedDiscrete:)];
        discreteMouseWheelRecognizer.maximumNumberOfTouches = 0;
        discreteMouseWheelRecognizer.allowedScrollTypesMask = UIScrollTypeMaskDiscrete;
        discreteMouseWheelRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [self addGestureRecognizer:discreteMouseWheelRecognizer];
        
        UIPanGestureRecognizer *continuousMouseWheelRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mouseWheelMovedContinuous:)];
        continuousMouseWheelRecognizer.maximumNumberOfTouches = 0;
        continuousMouseWheelRecognizer.allowedScrollTypesMask = UIScrollTypeMaskContinuous;
        continuousMouseWheelRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [self addGestureRecognizer:continuousMouseWheelRecognizer];
    }
    
#if defined(__IPHONE_16_1) || defined(__TVOS_16_1)
    if (@available(iOS 16.1, *)) {
        UIHoverGestureRecognizer *stylusHoverRecognizer = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(sendStylusHoverEvent:)];
        stylusHoverRecognizer.allowedTouchTypes = @[@(UITouchTypePencil)];
        [self addGestureRecognizer:stylusHoverRecognizer];
    }
#endif
#endif
    
    x1mouse = [[X1Mouse alloc] init];
    x1mouse.delegate = self;
    
    if (settings.btMouseSupport) {
        [x1mouse start];
    }
    
    // This is critical to ensure keyboard events are delivered to this
    // StreamView and not our parent UIView, especially on tvOS.
    [self becomeFirstResponder];
}

- (void)startInteractionTimer {
    // Restart user interaction tracking
    hasUserInteracted = NO;
    
    BOOL timerAlreadyRunning = interactionTimer != nil;
    
    // Start/restart the timer
    [interactionTimer invalidate];
    interactionTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                        target:self
                        selector:@selector(interactionTimerExpired:)
                        userInfo:nil
                        repeats:NO];
    
    // Notify the delegate if this was a new user interaction
    if (!timerAlreadyRunning) {
        [interactionDelegate userInteractionBegan];
    }
}

- (void)interactionTimerExpired:(NSTimer *)timer {
    if (!hasUserInteracted) {
        // User has finished touching the screen
        interactionTimer = nil;
        [interactionDelegate userInteractionEnded];
    }
    else {
        // User is still touching the screen. Restart the timer.
        [self startInteractionTimer];
    }
}

- (void) layoutSubviews {
    [super layoutSubviews];

    // Keep the video aspect-fit to our current bounds. The display layer is sized once when it's
    // created, so without this a window resize (iPhone Duo fold/unfold) leaves it stale.
    for (CALayer* layer in self.layer.sublayers) {
        if ([layer isKindOfClass:[AVSampleBufferDisplayLayer class]]) {
            CGSize videoSize = [self getVideoAreaSize];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            layer.bounds = CGRectMake(0, 0, videoSize.width, videoSize.height);
            layer.position = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
            [CATransaction commit];
        }
    }

#if !TARGET_OS_TV
    [onScreenControls relayout];
#endif
}

- (void) showOnScreenControls {
#if !TARGET_OS_TV
    [onScreenControls show];
#endif
}

#if !TARGET_OS_TV
- (void) reloadOnScreenControlsLevel {
    if (onScreenControls == nil) {
        return;
    }
    TemporarySettings* settings = [[[DataManager alloc] init] getSettings];
    OnScreenControlsLevel level = settings.absoluteTouchMode ? OnScreenControlsLevelOff
                                                             : (OnScreenControlsLevel)[settings.onscreenControls integerValue];
    if (oscSuppressed) {
        // The input deck is up; this is what comes back when it goes
        levelBeforeSuppression = level;
    }
    else if (level == OnScreenControlsLevelAuto) {
        [oscControllerSupport initAutoOnScreenControlMode:onScreenControls];
    }
    else {
        [onScreenControls setLevel:level];
    }
}

- (OnScreenControls*) visibleOnScreenControls {
    if (onScreenControls == nil || oscSuppressed || [onScreenControls getLevel] == OnScreenControlsLevelOff) {
        return nil;
    }
    return onScreenControls;
}

- (void) setOnScreenControlsSuppressed:(BOOL)suppressed {
    if (onScreenControls == nil || suppressed == oscSuppressed) {
        return;
    }
    oscSuppressed = suppressed;
    if (suppressed) {
        levelBeforeSuppression = [onScreenControls getLevel];
        [onScreenControls setLevel:OnScreenControlsLevelOff];
    }
    else {
        [onScreenControls setLevel:levelBeforeSuppression];
    }
}
#endif

- (OnScreenControlsLevel) getCurrentOscState {
    if (onScreenControls == nil) {
        return OnScreenControlsLevelOff;
    }
    else {
        return [onScreenControls getLevel];
    }
}

- (CGSize) getVideoAreaSize {
    if (self.bounds.size.width > self.bounds.size.height * streamAspectRatio) {
        return CGSizeMake(self.bounds.size.height * streamAspectRatio, self.bounds.size.height);
    } else {
        return CGSizeMake(self.bounds.size.width, self.bounds.size.width / streamAspectRatio);
    }
}

- (CGPoint) adjustCoordinatesForVideoArea:(CGPoint)point {
    // These are now relative to the StreamView, however we need to scale them
    // further to make them relative to the actual video portion.
    float x = point.x - self.bounds.origin.x;
    float y = point.y - self.bounds.origin.y;
    
    // For some reason, we don't seem to always get to the bounds of the window
    // so we'll subtract 1 pixel if we're to the left/below of the origin and
    // and add 1 pixel if we're to the right/above. It should be imperceptible
    // to the user but it will allow activation of gestures that require contact
    // with the edge of the screen (like Aero Snap).
    if (x < self.bounds.size.width / 2) {
        x--;
    }
    else {
        x++;
    }
    if (y < self.bounds.size.height / 2) {
        y--;
    }
    else {
        y++;
    }
    
    // This logic mimics what iOS does with AVLayerVideoGravityResizeAspect
    CGSize videoSize = [self getVideoAreaSize];
    CGPoint videoOrigin = CGPointMake(self.bounds.size.width / 2 - videoSize.width / 2,
                                      self.bounds.size.height / 2 - videoSize.height / 2);
    
    // Confine the cursor to the video region. We don't just discard events outside
    // the region because we won't always get one exactly when the mouse leaves the region.
    return CGPointMake(MIN(MAX(x, videoOrigin.x), videoOrigin.x + videoSize.width) - videoOrigin.x,
                       MIN(MAX(y, videoOrigin.y), videoOrigin.y + videoSize.height) - videoOrigin.y);
}

#if !TARGET_OS_TV

- (uint16_t)getRotationFromAzimuthAngle:(float)azimuthAngle {
    // iOS reports azimuth of 0 when the stylus is pointing west, but Moonlight expects
    // rotation of 0 to mean the stylus is pointing north. Rotate the azimuth angle
    // clockwise by 90 degrees to convert from iOS to Moonlight rotation conventions.
    int32_t rotationAngle = (azimuthAngle - M_PI_2) * (180.f / M_PI);
    if (rotationAngle < 0) {
        rotationAngle += 360;
    }
    return (uint16_t)rotationAngle;
}

- (uint8_t)getTiltFromAltitudeAngle:(float)altitudeAngle {
    // iOS reports an altitude of 0 when the stylus is parallel to the touch surface,
    // while Moonlight expects a tilt of 0 when the stylus is perpendicular to the surface.
    // Subtract the tilt angle from 90 to convert from iOS to Moonlight tilt conventions.
    uint8_t altitudeDegs = abs((int16_t)(altitudeAngle * (180.f / M_PI)));
    return 90 - MIN(90, altitudeDegs);
}

- (BOOL)sendStylusEvent:(UITouch*)event {
    uint8_t type;
    
    // Don't touch stylus events if the host doesn't support them. We want to pass
    // them as normal touches for legacy hosts that don't understand pen events.
    if (!(LiGetHostFeatureFlags() & LI_FF_PEN_TOUCH_EVENTS)) {
        return NO;
    }
    
    switch (event.phase) {
        case UITouchPhaseBegan:
            type = LI_TOUCH_EVENT_DOWN;
            break;
        case UITouchPhaseMoved:
            type = LI_TOUCH_EVENT_MOVE;
            break;
        case UITouchPhaseEnded:
            type = LI_TOUCH_EVENT_UP;
            break;
        case UITouchPhaseCancelled:
            type = LI_TOUCH_EVENT_CANCEL;
            break;
        default:
            return YES;
    }

    CGPoint location = [self adjustCoordinatesForVideoArea:[event locationInView:self]];
    CGSize videoSize = [self getVideoAreaSize];
    
    return LiSendPenEvent(type, LI_TOOL_TYPE_PEN, 0, location.x / videoSize.width, location.y / videoSize.height,
                          (event.force / event.maximumPossibleForce) / sin(event.altitudeAngle),
                          0.0f, 0.0f,
                          [self getRotationFromAzimuthAngle:[event azimuthAngleInView:self]],
                          [self getTiltFromAltitudeAngle:event.altitudeAngle]) != LI_ERR_UNSUPPORTED;
}

- (void)sendStylusHoverEvent:(UIHoverGestureRecognizer*)gesture API_AVAILABLE(ios(13.0)) {
    uint8_t type;
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            type = LI_TOUCH_EVENT_HOVER;
            break;

        case UIGestureRecognizerStateEnded:
            type = LI_TOUCH_EVENT_HOVER_LEAVE;
            break;

        default:
            return;
    }

    CGPoint location = [self adjustCoordinatesForVideoArea:[gesture locationInView:self]];
    CGSize videoSize = [self getVideoAreaSize];
    
    float distance = 0.0f;
#if defined(__IPHONE_16_1) || defined(__TVOS_16_1)
    if (@available(iOS 16.1, *)) {
        distance = gesture.zOffset;
    }
#endif
    
    uint16_t rotationAngle = LI_ROT_UNKNOWN;
    uint8_t tiltAngle = LI_TILT_UNKNOWN;
#if defined(__IPHONE_16_4) || defined(__TVOS_16_4)
    if (@available(iOS 16.4, *)) {
        rotationAngle = [self getRotationFromAzimuthAngle:[gesture azimuthAngleInView:self]];
        tiltAngle = [self getTiltFromAltitudeAngle:gesture.altitudeAngle];
    }
#endif
    
    LiSendPenEvent(type, LI_TOOL_TYPE_PEN, 0, location.x / videoSize.width, location.y / videoSize.height,
                   distance, 0.0f, 0.0f, rotationAngle, tiltAngle);
}

#endif

#if !TARGET_OS_TV
// Native touch: each finger goes to the host as its own touch point, with pressure where the
// screen reports it. NO when that mode is off or the host can't take touch events (macOS
// Sunshine, older hosts); the touchscreen handler takes the touches instead.
- (BOOL)sendNativeTouches:(NSSet*)touches type:(uint8_t)type {
    if (touchMode != MNTouchModeNative || !(LiGetHostFeatureFlags() & LI_FF_PEN_TOUCH_EVENTS)) {
        return NO;
    }
    CGSize videoSize = [self getVideoAreaSize];
    for (UITouch* touch in touches) {
        NSValue* key = [NSValue valueWithNonretainedObject:touch];
        NSNumber* pointerId = nativeTouchIds[key];
        if (type == LI_TOUCH_EVENT_DOWN) {
            // The lowest free id; hosts take up to 11 fingers
            NSArray<NSNumber*>* used = [nativeTouchIds allValues];
            uint32_t next = 0;
            while ([used containsObject:@(next)]) {
                next++;
            }
            if (next > 10) {
                continue;
            }
            pointerId = @(next);
            nativeTouchIds[key] = pointerId;
        }
        else if (pointerId == nil) {
            continue;
        }

        CGPoint point = [self nativeTouchPoint:touch key:key type:type pointerId:pointerId.unsignedIntValue];
        CGPoint location = [self adjustCoordinatesForVideoArea:point];
        // 0 means the pressure is unknown (screens without force sensing)
        float pressure = touch.maximumPossibleForce > 0 ? touch.force / touch.maximumPossibleForce : 0.0f;
        LiSendTouchEvent(type, pointerId.unsignedIntValue,
                         location.x / videoSize.width, location.y / videoSize.height,
                         pressure, 0.0f, 0.0f, LI_ROT_UNKNOWN);
        if (type == LI_TOUCH_EVENT_UP || type == LI_TOUCH_EVENT_CANCEL) {
            [nativeTouchIds removeObjectForKey:key];
            [nativeFastTouches removeObjectForKey:key];
        }
    }
    return YES;
}

// Adapted from VoidLink (GPLv3), Input/NativeTouchPointer.m: a finger that lands in the fast
// zone (camera side in mobile-style games) moves nativeSpeed times as far as it travels. When
// that runs off the screen, the host's touch lifts and lands again where the finger started,
// so a camera swipe keeps turning.
typedef struct {
    CGPoint start;
    CGPoint last;
    CGPoint sent;
} MNFastTouch;

- (CGPoint)nativeTouchPoint:(UITouch*)touch key:(NSValue*)key type:(uint8_t)type pointerId:(uint32_t)pointerId {
    CGPoint p = [touch locationInView:self];
    if (type == LI_TOUCH_EVENT_DOWN) {
        if (nativeSpeed != 1 && p.x > self.bounds.size.width * nativeSplit) {
            MNFastTouch fast = { p, p, p };
            nativeFastTouches[key] = [NSValue valueWithBytes:&fast objCType:@encode(MNFastTouch)];
        }
        return p;
    }
    NSValue* stored = nativeFastTouches[key];
    if (stored == nil) {
        return p;
    }
    MNFastTouch fast;
    [stored getValue:&fast];
    CGPoint sent = CGPointMake(fast.sent.x + (p.x - fast.last.x) * nativeSpeed,
                               fast.sent.y + (p.y - fast.last.y) * nativeSpeed);
    fast.last = p;
    if (type == LI_TOUCH_EVENT_MOVE && !CGRectContainsPoint(self.bounds, sent)) {
        CGSize videoSize = [self getVideoAreaSize];
        CGPoint edge = [self adjustCoordinatesForVideoArea:sent];
        LiSendTouchEvent(LI_TOUCH_EVENT_UP, pointerId, edge.x / videoSize.width, edge.y / videoSize.height,
                         0.0f, 0.0f, 0.0f, LI_ROT_UNKNOWN);
        CGPoint start = [self adjustCoordinatesForVideoArea:fast.start];
        LiSendTouchEvent(LI_TOUCH_EVENT_DOWN, pointerId, start.x / videoSize.width, start.y / videoSize.height,
                         0.0f, 0.0f, 0.0f, LI_ROT_UNKNOWN);
        sent = fast.start;
    }
    fast.sent = sent;
    nativeFastTouches[key] = [NSValue valueWithBytes:&fast objCType:@encode(MNFastTouch)];
    return sent;
}

- (BOOL)softKeyboardShown {
    return isInputingText;
}

- (CGFloat)softKeyboardAnchorY {
    return softKeyboardAnchorY;
}

// Ctrl+Alt+Shift + D, Q, S, O, M or C: handled here instead of going to the host
- (BOOL)handleStreamHotkey:(UIPress*)press API_AVAILABLE(ios(13.4)) {
    UIKey* key = press.key;
    UIKeyModifierFlags wanted = UIKeyModifierControl | UIKeyModifierAlternate | UIKeyModifierShift;
    if (key == nil || (key.modifierFlags & (wanted | UIKeyModifierCommand)) != wanted) {
        return NO;
    }
    switch (key.keyCode) {
        case UIKeyboardHIDUsageKeyboardD:
        case UIKeyboardHIDUsageKeyboardQ:
        case UIKeyboardHIDUsageKeyboardS:
        case UIKeyboardHIDUsageKeyboardO:
        case UIKeyboardHIDUsageKeyboardM:
        case UIKeyboardHIDUsageKeyboardC:
            break;
        default:
            return NO;
    }
    if ([interactionDelegate respondsToSelector:@selector(streamHotkeyPressed:)]) {
        [interactionDelegate streamHotkeyPressed:key.keyCode];
    }
    return YES;
}

- (void)refreshPointerStyle {
    if (@available(iOS 13.4, *)) {
        [pointerInteraction invalidate];
    }
}

// A physical mouse goes through GCMouse while captured, and through UIKit's pointer otherwise
- (BOOL)mouseHandledByGCMouse {
    if (@available(iOS 14.0, *)) {
        return [GCMouse current] != nil && MNMouse.captured;
    }
    return NO;
}
#endif

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self handleMouseButtonEvent:BUTTON_ACTION_PRESS
                          forTouches:touches
                           withEvent:event]) {
        // If it's a mouse event, we're done
        return;
    }
    
    Log(LOG_D, @"Touch down");
    
    // Notify of user interaction and start expiration timer
    [self startInteractionTimer];
    
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
    }
#endif
    
    if (![onScreenControls handleTouchDownEvent:touches]) {
#if !TARGET_OS_TV
        if (self.touchInputDisabled) {
            return;
        }
        BOOL sentNative = [self sendNativeTouches:touches type:LI_TOUCH_EVENT_DOWN];
        NSUInteger keyboardFingers = MNTouchPrefs.keyboardFingers;
#else
        BOOL sentNative = NO;
        NSUInteger keyboardFingers = 3;
#endif
        // We still inform the touch handler even if we're going trigger the
        // keyboard activation gesture. This is important to ensure the touch
        // handler has a consistent view of touch events to correctly suppress
        // activation of one or two finger gestures when a three finger gesture
        // is triggered.
        if (!sentNative) {
            [touchHandler touchesBegan:touches withEvent:event];
        }
        
        if (keyboardFingers > 0 && [[event allTouches] count] == keyboardFingers) {
            CGFloat anchorY = 0;
            for (UITouch* touch in [event allTouches]) {
                anchorY = MAX(anchorY, [touch locationInView:self].y);
            }
            [self toggleSoftKeyboardAnchoredAt:anchorY];
        }
    }
}

// Opens the soft keyboard (lifting the stream so anchorY stays above it), or closes it
- (void)toggleSoftKeyboardAnchoredAt:(CGFloat)anchorY {
    if (isInputingText) {
        Log(LOG_D, @"Closing the keyboard");
        [keyInputField resignFirstResponder];
        isInputingText = false;
    } else {
        Log(LOG_D, @"Opening the keyboard");
#if !TARGET_OS_TV
        // The stream is lifted to keep this spot above the keyboard
        softKeyboardAnchorY = anchorY;
        // Set before the keyboard comes up: its will-show notification reads it
        isInputingText = true;
#endif
        // Prepare the textbox used to capture keyboard events.
        keyInputField.delegate = self;
        keyInputField.text = @"0";
#if !TARGET_OS_TV
        // The key row above the keyboard (Settings picks its keys)
        __weak StreamView* weakSelf = self;
        keyBar = [[MNKeyBar alloc] initWithDismiss:^{
            [weakSelf toggleSoftKeyboardAnchoredAt:0];
        }];
        keyInputField.inputAccessoryView = keyBar;
#endif
        [keyInputField becomeFirstResponder];
        [keyInputField addTarget:self action:@selector(onKeyboardPressed:) forControlEvents:UIControlEventEditingChanged];
        
        // Undo causes issues for our state management, so turn it off
        [keyInputField.undoManager disableUndoRegistration];
        
        isInputingText = true;
    }
}

#if !TARGET_OS_TV
- (void)toggleSoftKeyboard {
    [self toggleSoftKeyboardAnchoredAt:0];
}

- (OnScreenControls*)layoutControls {
    return onScreenControls;
}
#endif

- (BOOL)handleMouseButtonEvent:(int)buttonAction forTouches:(NSSet *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        UITouch* touch = [touches anyObject];
        if (touch.type == UITouchTypeIndirectPointer) {
            if ([self mouseHandledByGCMouse]) {
                // We'll handle this with GCMouse. Do nothing here.
                return YES;
            }
            
            UIEventButtonMask normalizedButtonMask;
            
            // iOS 14 includes the released button in the buttonMask for the release
            // event, while iOS 13 does not. Normalize that behavior here.
            if (@available(iOS 14.0, *)) {
                if (buttonAction == BUTTON_ACTION_RELEASE) {
                    normalizedButtonMask = lastMouseButtonMask & ~event.buttonMask;
                }
                else {
                    normalizedButtonMask = event.buttonMask;
                }
            }
            else {
                normalizedButtonMask = event.buttonMask;
            }
            
            UIEventButtonMask changedButtons = lastMouseButtonMask ^ normalizedButtonMask;
                        
            for (int i = BUTTON_LEFT; i <= BUTTON_X2; i++) {
                UIEventButtonMask buttonFlag;
                
                switch (i) {
                    // Right and Middle are reversed from what iOS uses
                    case BUTTON_RIGHT:
                        buttonFlag = UIEventButtonMaskForButtonNumber(2);
                        break;
                    case BUTTON_MIDDLE:
                        buttonFlag = UIEventButtonMaskForButtonNumber(3);
                        break;
                        
                    default:
                        buttonFlag = UIEventButtonMaskForButtonNumber(i);
                        break;
                }
                
                if (changedButtons & buttonFlag) {
                    LiSendMouseButtonEvent(buttonAction, i);
                }
            }
            
            lastMouseButtonMask = normalizedButtonMask;
            return YES;
        }
    }
#endif
    
    return NO;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
        
        UITouch *touch = [touches anyObject];
        if (touch.type == UITouchTypeIndirectPointer) {
            if ([self mouseHandledByGCMouse]) {
                // We'll handle this with GCMouse. Do nothing here.
                return;
            }
            
            // We must handle this event to properly support
            // drags while the middle, X1, or X2 mouse buttons are
            // held down. For some reason, left and right buttons
            // don't require this, but we do it anyway for them too.
            // Cursor movement without a button held down is handled
            // in pointerInteraction:regionForRequest:defaultRegion.
            [self updateCursorLocation:[touch locationInView:self] isMouse:YES];
            return;
        }
    }
#endif
    
    hasUserInteracted = YES;
    
    if (![onScreenControls handleTouchMovedEvent:touches]) {
#if !TARGET_OS_TV
        if (self.touchInputDisabled || [self sendNativeTouches:touches type:LI_TOUCH_EVENT_MOVE]) {
            return;
        }
#endif
        [touchHandler touchesMoved:touches withEvent:event];
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
#if !TARGET_OS_TV
            if ([self handleStreamHotkey:press]) {
                handled = YES;
                continue;
            }
#endif
            // For now, we'll treated it as handled if we handle at least one of the
            // UIPress events inside the set.
            if ([KeyboardSupport sendKeyEventForPress:press down:YES]) {
                // This will prevent the legacy UITextField from receiving the event
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesBegan:presses withEvent:event];
    }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
            // For now, we'll treated it as handled if we handle at least one of the
            // UIPress events inside the set.
            if ([KeyboardSupport sendKeyEventForPress:press down:NO]) {
                // This will prevent the legacy UITextField from receiving the event
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesEnded:presses withEvent:event];
    }
}

// Keys held as the app leaves the foreground (the stream may stay connected there) are cancelled,
// not ended: release them on the host too
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
            if ([KeyboardSupport sendKeyEventForPress:press down:NO]) {
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesCancelled:presses withEvent:event];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self handleMouseButtonEvent:BUTTON_ACTION_RELEASE
                          forTouches:touches
                           withEvent:event]) {
        // If it's a mouse event, we're done
        return;
    }
    
    Log(LOG_D, @"Touch up");
    
    hasUserInteracted = YES;
    
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
    }
#endif
    
    if (![onScreenControls handleTouchUpEvent:touches]) {
#if !TARGET_OS_TV
        // Lifts still go through while touch is off, so nothing stays held down
        if ([self sendNativeTouches:touches type:LI_TOUCH_EVENT_UP]) {
            return;
        }
#endif
        [touchHandler touchesEnded:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    // Release any on-screen button a cancelled touch was holding
    [onScreenControls handleTouchUpEvent:touches];
#if !TARGET_OS_TV
    BOOL sentNative = [self sendNativeTouches:touches type:LI_TOUCH_EVENT_CANCEL];
#else
    BOOL sentNative = NO;
#endif
    if (!sentNative) {
        [touchHandler touchesCancelled:touches withEvent:event];
    }
    [self handleMouseButtonEvent:BUTTON_ACTION_RELEASE
                      forTouches:touches
                       withEvent:event];
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                [self sendStylusEvent:touch];
            }
        }
    }
#endif
}

#if !TARGET_OS_TV
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse {
    CGPoint normalizedLocation = [self adjustCoordinatesForVideoArea:location];
    CGSize videoSize = [self getVideoAreaSize];
    
    // Send the mouse position relative to the video region if it has changed
    // if we're receiving coordinates from a real mouse.
    //
    // NB: It is important for functionality (not just optimization) to only
    // send it if the value has changed. We will receive one of these events
    // any time the user presses a modifier key, which can result in errant
    // mouse motion when using a Citrix X1 mouse.
    if (normalizedLocation.x != lastMouseX || normalizedLocation.y != lastMouseY || !isMouse) {
        if (lastMouseX != 0 || lastMouseY != 0 || !isMouse) {
            LiSendMousePositionEvent(normalizedLocation.x, normalizedLocation.y, videoSize.width, videoSize.height);
        }
        
        if (isMouse) {
            lastMouseX = normalizedLocation.x;
            lastMouseY = normalizedLocation.y;
        }
    }
}

- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction
                       regionForRequest:(UIPointerRegionRequest *)request
                          defaultRegion:(UIPointerRegion *)defaultRegion API_AVAILABLE(ios(13.4)) {
    if ([self mouseHandledByGCMouse]) {
        // We'll handle this with GCMouse. Do nothing here.
        return nil;
    }
    
    // This logic mimics what iOS does with AVLayerVideoGravityResizeAspect
    CGSize videoSize;
    CGPoint videoOrigin;
    if (self.bounds.size.width > self.bounds.size.height * streamAspectRatio) {
        videoSize = CGSizeMake(self.bounds.size.height * streamAspectRatio, self.bounds.size.height);
    } else {
        videoSize = CGSizeMake(self.bounds.size.width, self.bounds.size.width / streamAspectRatio);
    }
    videoOrigin = CGPointMake(self.bounds.size.width / 2 - videoSize.width / 2,
                              self.bounds.size.height / 2 - videoSize.height / 2);
    
    // Move the cursor on the host if no buttons are pressed.
    // Motion with buttons pressed in handled in touchesMoved:
    if (lastMouseButtonMask == 0) {
        [self updateCursorLocation:request.location isMouse:YES];
    }
    
    // The pointer interaction should cover the video region only
    return [UIPointerRegion regionWithRect:CGRectMake(videoOrigin.x, videoOrigin.y, videoSize.width, videoSize.height) identifier:nil];
}

- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region  API_AVAILABLE(ios(13.4)) {
    // Hide the mouse cursor over our stream view unless it was asked for (Settings or Ctrl+Alt+Shift+C)
    return MNMouse.cursorVisible ? [UIPointerStyle systemPointerStyle] : [UIPointerStyle hiddenPointerStyle];
}

// -1 when Settings asks for the mouse wheel reversed
- (int)wheelDirection {
    return MNTouchPrefs.reverseScroll ? -1 : 1;
}

- (void)mouseWheelMovedContinuous:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            break;
        
        case UIGestureRecognizerStateEnded:
        default:
            // Ignore recognition failure and other states
            lastScrollTranslation = CGPointMake(0, 0);
            return;
    }
    
    CGPoint currentScrollTranslation = [gesture translationInView:self];
    const short translationMultiplier = 120 * 20; // WHEEL_DELTA * 20
    
    {
        short translationDeltaY = ((currentScrollTranslation.y - lastScrollTranslation.y) / self.bounds.size.height) * translationMultiplier * [self wheelDirection];
        if (translationDeltaY != 0) {
            LiSendHighResScrollEvent(translationDeltaY);
            lastScrollTranslation = currentScrollTranslation;
        }
    }

    {
        short translationDeltaX = ((currentScrollTranslation.x - lastScrollTranslation.x) / self.bounds.size.width) * translationMultiplier * [self wheelDirection];
        if (translationDeltaX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHighResHScrollEvent(-translationDeltaX);
            lastScrollTranslation = currentScrollTranslation;
        }
    }
}

- (void)mouseWheelMovedDiscrete:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            break;
        
        case UIGestureRecognizerStateEnded:
        default:
            // Ignore recognition failure and other states
            lastScrollTranslation = CGPointMake(0, 0);
            return;
    }
    
    // Using velocityInView is 0 for discrete scroll events
    // when scrolling very slowly, but translationInView does work.
    CGPoint currentScrollTranslation = [gesture translationInView:self];
    
    {
        short translationDeltaY = (currentScrollTranslation.y - lastScrollTranslation.y) * [self wheelDirection];
        if (translationDeltaY != 0) {
            LiSendScrollEvent(translationDeltaY > 0 ? 1 : -1);
        }
    }

    {
        short translationDeltaX = (currentScrollTranslation.x - lastScrollTranslation.x) * [self wheelDirection];
        if (translationDeltaX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHScrollEvent(translationDeltaX < 0 ? 1 : -1);
        }
    }
    
    lastScrollTranslation = currentScrollTranslation;
}

#endif

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (@available(iOS 13.0, *)) {
        // Disable the 3 finger tap gestures that trigger the copy/paste/undo toolbar on iOS 13+
        return gestureRecognizer.name == nil || ![gestureRecognizer.name hasPrefix:@"kbProductivity."];
    }
    else {
        return YES;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    // This method is called when the "Return" key is pressed.
    LiSendKeyboardEvent(0x0d, KEY_ACTION_DOWN, 0);
    usleep(50 * 1000);
    LiSendKeyboardEvent(0x0d, KEY_ACTION_UP, 0);
    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
#if !TARGET_OS_TV
    // Latched modifiers on the key bar go up with the keyboard
    [keyBar releaseKeys];
#endif
}

- (void)onKeyboardPressed:(UITextField *)textField {
    NSString* inputText = textField.text;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // If the text became empty, we know the user pressed the backspace key.
        if ([inputText isEqual:@""]) {
            LiSendKeyboardEvent(0x08, KEY_ACTION_DOWN, 0);
            usleep(50 * 1000);
            LiSendKeyboardEvent(0x08, KEY_ACTION_UP, 0);
        } else {
            // Character 0 will be our known sentinel value
            
            // Check if any characters exist which can't be represented in a basic key event
            for (int i = 1; i < [inputText length]; i++) {
                struct KeyEvent event = [KeyboardSupport translateKeyEvent:[inputText characterAtIndex:i] withModifierFlags:0];
                if (event.keycode == 0) {
                    // We found an unknown key, so send the entire string as UTF-8
                    const char* utf8String = [inputText UTF8String];
                    
                    // Skip the first character which is our sentinel
                    LiSendUtf8TextEvent(utf8String + 1, (int)strlen(utf8String) - 1);
                    return;
                }
            }
            
            // We didn't find any unknown characters, so send them all as basic key events
            for (int i = 1; i < [inputText length]; i++) {
                struct KeyEvent event = [KeyboardSupport translateKeyEvent:[inputText characterAtIndex:i] withModifierFlags:0];
                assert(event.keycode != 0);
                [self sendLowLevelEvent:event];
            }
        }
    });
    
    // Reset text field back to known state
    textField.text = @"0";
    
    // Move the insertion point back to the end of the text box
    UITextRange *textRange = [textField textRangeFromPosition:textField.endOfDocument toPosition:textField.endOfDocument];
    [textField setSelectedTextRange:textRange];
}

- (void)specialCharPressed:(UIKeyCommand *)cmd {
    struct KeyEvent event = [KeyboardSupport translateKeyEvent:0x20 withModifierFlags:[cmd modifierFlags]];
    event.keycode = [[dictCodes valueForKey:[cmd input]] intValue];
    [self sendLowLevelEvent:event];
}

- (void)keyPressed:(UIKeyCommand *)cmd {
    struct KeyEvent event = [KeyboardSupport translateKeyEvent:[[cmd input] characterAtIndex:0] withModifierFlags:[cmd modifierFlags]];
    [self sendLowLevelEvent:event];
}

- (void)sendLowLevelEvent:(struct KeyEvent)event {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // When we want to send a modified key (like uppercase letters) we need to send the
        // modifier ("shift") seperately from the key itself.
        if (event.modifier != 0) {
            LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_DOWN, event.modifier);
        }
        // Let the host know these are not (necessarily) normalized to US English scancodes
        LiSendKeyboardEvent2(event.keycode, KEY_ACTION_DOWN, event.modifier, SS_KBE_FLAG_NON_NORMALIZED);
        usleep(50 * 1000);
        LiSendKeyboardEvent2(event.keycode, KEY_ACTION_UP, event.modifier, SS_KBE_FLAG_NON_NORMALIZED);
        if (event.modifier != 0) {
            LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_UP, event.modifier);
        }
    });
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (NSArray<UIKeyCommand *> *)keyCommands
{
    NSString *charset = @"qwertyuiopasdfghjklzxcvbnm1234567890\t§[]\\'\"/.,`<>-´ç+`¡'º;ñ= ";
    
    NSMutableArray<UIKeyCommand *> * commands = [NSMutableArray<UIKeyCommand *> array];
    dictCodes = [[NSDictionary alloc] initWithObjectsAndKeys: [NSNumber numberWithInt: 0x0d], @"\r", [NSNumber numberWithInt: 0x08], @"\b", [NSNumber numberWithInt: 0x1b], UIKeyInputEscape, [NSNumber numberWithInt: 0x28], UIKeyInputDownArrow, [NSNumber numberWithInt: 0x26], UIKeyInputUpArrow, [NSNumber numberWithInt: 0x25], UIKeyInputLeftArrow, [NSNumber numberWithInt: 0x27], UIKeyInputRightArrow, nil];
    
    [charset enumerateSubstringsInRange:NSMakeRange(0, charset.length)
                                options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:0 action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierShift action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierControl action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierAlternate action:@selector(keyPressed:)]];
                             }];
    
    for (NSString *c in [dictCodes keyEnumerator]) {
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:0
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift | UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift | UIKeyModifierControl
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierControl
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierControl | UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
    }
    
    return commands;
}

- (void)connectedStateDidChangeWithIdentifier:(NSUUID * _Nonnull)identifier isConnected:(BOOL)isConnected {
    NSLog(@"Citrix X1 mouse state change: %@ -> %s",
          identifier, isConnected ? "connected" : "disconnected");
}

- (void)mouseDidMoveWithIdentifier:(NSUUID * _Nonnull)identifier deltaX:(int16_t)deltaX deltaY:(int16_t)deltaY {
    accumulatedMouseDeltaX += deltaX / X1_MOUSE_SPEED_DIVISOR;
    accumulatedMouseDeltaY += deltaY / X1_MOUSE_SPEED_DIVISOR;
    
    short shortX = (short)accumulatedMouseDeltaX;
    short shortY = (short)accumulatedMouseDeltaY;
    
    if (shortX == 0 && shortY == 0) {
        return;
    }
    
    LiSendMouseMoveEvent(shortX, shortY);
    
    accumulatedMouseDeltaX -= shortX;
    accumulatedMouseDeltaY -= shortY;
}

- (int) buttonFromX1ButtonCode:(enum X1MouseButton)button {
    switch (button) {
        case X1MouseButtonLeft:
            return BUTTON_LEFT;
        case X1MouseButtonRight:
            return BUTTON_RIGHT;
        case X1MouseButtonMiddle:
            return BUTTON_MIDDLE;
        default:
            return -1;
    }
}

- (void)mouseDownWithIdentifier:(NSUUID * _Nonnull)identifier button:(enum X1MouseButton)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, [self buttonFromX1ButtonCode:button]);
}

- (void)mouseUpWithIdentifier:(NSUUID * _Nonnull)identifier button:(enum X1MouseButton)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, [self buttonFromX1ButtonCode:button]);
}

- (void)wheelDidScrollWithIdentifier:(NSUUID * _Nonnull)identifier deltaZ:(int8_t)deltaZ {
    LiSendScrollEvent(deltaZ);
}

#if !TARGET_OS_TV
- (BOOL)isMultipleTouchEnabled {
    return YES;
}
#endif

@end
