//
//  AbsoluteTouchHandler.m
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "AbsoluteTouchHandler.h"

#include <Limelight.h>

// How long the fingers must be stationary to start a right click
#define LONG_PRESS_ACTIVATION_DELAY 0.650f

// How far the finger can move before it cancels a right click
#define LONG_PRESS_ACTIVATION_DELTA 0.01f

// How long the double tap deadzone stays in effect between touch up and touch down
#define DOUBLE_TAP_DEAD_ZONE_DELAY 0.250f

// How far the finger can move before it can override the double tap deadzone
#define DOUBLE_TAP_DEAD_ZONE_DELTA 0.025f

@implementation AbsoluteTouchHandler {
    StreamView* view;
    
    NSTimer* longPressTimer;
    UITouch* lastTouchDown;
    CGPoint lastTouchDownLocation;
    UITouch* lastTouchUp;
    CGPoint lastTouchUpLocation;

    // Fingers on the stream, oldest first
    NSMutableArray<UITouch*>* fingers;
    // Settings: tap clicks on lift instead of pressing on touch down; two fingers scroll,
    // pinch and right-click; how long a finger rests before moving drags instead of hovering
    BOOL clickOnLift;
    BOOL twoFingerGestures;
    NSTimeInterval dragHold;
    // The single-finger touch: moved past the long-press slop, left button held on the host,
    // long press already right-clicked (click-on-lift mode)
    BOOL moved;
    BOOL leftDown;
    // A long press holding the right button (click-on-lift off)
    BOOL rightDown;
    BOOL rightClicked;
    // A second finger joined: the single-finger click is off until all fingers lift
    BOOL multiFinger;
    NSUInteger peakFingers;
    NSTimeInterval downTime;
    MNTwoFingerScroll* scroller;
    BOOL scrolled;
}

- (id)initWithView:(StreamView*)view {
    self = [self init];
    self->view = view;
    fingers = [[NSMutableArray alloc] init];
    clickOnLift = MNTouchExtras.clickOnLift;
    twoFingerGestures = MNTouchExtras.twoFingerGestures;
    dragHold = MNTouchExtras.dragHold;
    scroller = [[MNTwoFingerScroll alloc] initWithUnitsPerPoint:10];
    return self;
}

- (void)dealloc {
    [longPressTimer invalidate];
    [scroller cancel];
    [scroller stopMomentum];
}

- (void)onLongPressStart:(NSTimer*)timer {
    if (clickOnLift) {
        // Adapted from VoidLink (GPLv3), Input/AbsoluteTouchHandler.m: a still hold right-clicks
        // and the lift then sends nothing
        rightClicked = YES;
        [self clickButton:BUTTON_RIGHT];
        return;
    }
    // Raise the left click and start a right click
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
    leftDown = NO;
    rightDown = YES;
}

- (void)clickButton:(int)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, button);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, button);
    });
}

- (CGPoint)midpoint {
    CGPoint a = [fingers[0] locationInView:view];
    CGPoint b = [fingers[1] locationInView:view];
    return CGPointMake((a.x + b.x) / 2, (a.y + b.y) / 2);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [scroller stopMomentum];
    BOOL wasEmpty = fingers.count == 0;
    for (UITouch* touch in touches) {
        [fingers addObject:touch];
    }
    peakFingers = wasEmpty ? fingers.count : MAX(peakFingers, fingers.count);
    
    if (!wasEmpty || fingers.count > 1) {
        // More than one finger: no single-finger click or right click
        [longPressTimer invalidate];
        longPressTimer = nil;
        if (!multiFinger) {
            multiFinger = YES;
            if (leftDown) {
                leftDown = NO;
                LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
            }
            if (rightDown) {
                // A second finger after a long press: the multi-finger lift won't release it
                rightDown = NO;
                LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
            }
        }
        if (twoFingerGestures && fingers.count == 2) {
            // Two fingers go to the host as a touchpad would: scroll, pinch, tap to right-click,
            // with the pointer between them so the scroll lands on what's under the fingers
            [view updateCursorLocation:[self midpoint] isMouse:NO];
            [scroller begin:[fingers[0] locationInView:view] and:[fingers[1] locationInView:view]];
        }
        else {
            [scroller cancel];
        }
        return;
    }
    
    UITouch* touch = [touches anyObject];
    CGPoint touchLocation = [touch locationInView:view];
    moved = NO;
    rightClicked = NO;
    scrolled = NO;
    
    // Don't reposition for finger down events within the deadzone. This makes double-clicking easier.
    if (touch.timestamp - lastTouchUp.timestamp > DOUBLE_TAP_DEAD_ZONE_DELAY ||
        sqrt(pow((touchLocation.x / view.bounds.size.width) - (lastTouchUpLocation.x / view.bounds.size.width), 2) +
             pow((touchLocation.y / view.bounds.size.height) - (lastTouchUpLocation.y / view.bounds.size.height), 2)) > DOUBLE_TAP_DEAD_ZONE_DELTA) {
        [view updateCursorLocation:touchLocation isMouse:NO];
    }
    
    // Press the left button down (click-on-lift waits to see whether this is a tap, a drag or a hover)
    if (!clickOnLift) {
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        leftDown = YES;
    }
    
    // Start the long press timer
    longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_PRESS_ACTIVATION_DELAY
                                                      target:self
                                                    selector:@selector(onLongPressStart:)
                                                    userInfo:nil
                                                     repeats:NO];
    
    lastTouchDown = touch;
    lastTouchDownLocation = touchLocation;
    // UITouch.timestamp moves on with the touch, so keep when it landed
    downTime = touch.timestamp;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (multiFinger) {
        if (twoFingerGestures && fingers.count == 2) {
            [scroller update:[fingers[0] locationInView:view] and:[fingers[1] locationInView:view]];
            scrolled = scrolled || scroller.engaged;
        }
        return;
    }
    if (fingers.count != 1 || ![touches containsObject:fingers[0]]) {
        return;
    }
    
    UITouch* touch = fingers[0];
    CGPoint touchLocation = [touch locationInView:view];
    
    if (!moved &&
        sqrt(pow((touchLocation.x / view.bounds.size.width) - (lastTouchDownLocation.x / view.bounds.size.width), 2) +
             pow((touchLocation.y / view.bounds.size.height) - (lastTouchDownLocation.y / view.bounds.size.height), 2)) > LONG_PRESS_ACTIVATION_DELTA) {
        // Moved too far since touch down. Cancel the long press timer.
        moved = YES;
        [longPressTimer invalidate];
        longPressTimer = nil;
        
        // Adapted from VoidLink (GPLv3), Input/AbsoluteTouchHandler.m: a finger that rested first
        // drags with the left button; one that moves straight away only moves the pointer
        if (clickOnLift && !rightClicked && touch.timestamp - downTime >= dragHold) {
            LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
            leftDown = YES;
        }
    }
    
    if (!rightClicked) {
        [view updateCursorLocation:touchLocation isMouse:NO];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self lift:touches cancelled:NO];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self lift:touches cancelled:YES];
}

- (void)lift:(NSSet *)touches cancelled:(BOOL)cancelled {
    NSUInteger before = fingers.count;
    for (UITouch* touch in touches) {
        [fingers removeObject:touch];
    }
    if (fingers.count == before) {
        return;
    }
    if (multiFinger && twoFingerGestures && before == 2) {
        if (cancelled) {
            [scroller cancel];
        }
        else {
            [scroller end];
        }
    }
    // Only fire this logic if all touches have ended
    if (fingers.count > 0) {
        return;
    }
    
    // Cancel the long press timer
    [longPressTimer invalidate];
    longPressTimer = nil;
    
    if (multiFinger) {
        multiFinger = NO;
        // A two-finger tap
        if (twoFingerGestures && peakFingers == 2 && !scrolled && !cancelled) {
            [self clickButton:BUTTON_RIGHT];
        }
        scrolled = NO;
    }
    else if (clickOnLift) {
        if (leftDown) {
            LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
        }
        else if (!moved && !rightClicked && !cancelled) {
            [self clickButton:BUTTON_LEFT];
        }
    }
    else {
        // Left button up on finger up
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
        
        // Raise right button too in case we triggered a long press gesture
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
        rightDown = NO;
    }
    leftDown = NO;
    
    // Remember this last touch for touch-down deadzoning
    lastTouchUp = [touches anyObject];
    lastTouchUpLocation = [lastTouchUp locationInView:view];
}

@end
