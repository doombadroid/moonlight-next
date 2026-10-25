//
//  OnScreenControls.m
//  Moonlight
//
//  Created by Diego Waxemberg on 12/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "OnScreenControls.h"
#import "StreamView.h"
#import "ControllerSupport.h"
#import "Controller.h"
#include "Limelight.h"

#define UPDATE_BUTTON(x, y) (buttonFlags = \
(y) ? (buttonFlags | (x)) : (buttonFlags & ~(x)))

@implementation OnScreenControls {
#if !TARGET_OS_TV
    UIImpactFeedbackGenerator* _pressHaptic;
#endif
    CALayer* _aButton;
    CALayer* _bButton;
    CALayer* _xButton;
    CALayer* _yButton;
    CALayer* _upButton;
    CALayer* _downButton;
    CALayer* _leftButton;
    CALayer* _rightButton;
    CALayer* _leftStickBackground;
    CALayer* _leftStick;
    CALayer* _rightStickBackground;
    CALayer* _rightStick;
    CALayer* _startButton;
    CALayer* _selectButton;
    CALayer* _r1Button;
    CALayer* _r2Button;
    CALayer* _r3Button;
    CALayer* _l1Button;
    CALayer* _l2Button;
    CALayer* _l3Button;
    
    UITouch* _aTouch;
    UITouch* _bTouch;
    UITouch* _xTouch;
    UITouch* _yTouch;
    UITouch* _dpadTouch;
    UITouch* _lsTouch;
    UITouch* _rsTouch;
    UITouch* _startTouch;
    UITouch* _selectTouch;
    UITouch* _r1Touch;
    UITouch* _r2Touch;
    UITouch* _r3Touch;
    UITouch* _l1Touch;
    UITouch* _l2Touch;
    UITouch* _l3Touch;
    
    NSDate* l3TouchStart;
    NSDate* r3TouchStart;
    
    BOOL l3Set;
    BOOL r3Set;
    
    BOOL _iPad;
    CGRect _controlArea;
    // Layout editor: per-control offsets in points for the current posture
    NSString* _appID;
    NSString* _layoutPosture;
    NSMutableDictionary<NSString*, NSValue*>* _layoutOffsets;
    BOOL _editing;
    NSString* _dragGroup;
    UITouch* _dragTouch;
    CGPoint _dragLast;
    CGRect _usableArea;
    UIView* _view;
    OnScreenControlsLevel _level;
    BOOL _visible;
    
    ControllerSupport *_controllerSupport;
    Controller *_controller;
    NSMutableArray* _deadTouches;
    BOOL _swapABXY;
}

static const float EDGE_WIDTH = .05;

//static const float BUTTON_SIZE = 50;
static const float BUTTON_DIST = 20;
static float BUTTON_CENTER_X;
static float BUTTON_CENTER_Y;

static const float D_PAD_DIST = 10;
static float D_PAD_CENTER_X;
static float D_PAD_CENTER_Y;

static const float DEAD_ZONE_PADDING = 15;

static const double STICK_CLICK_RATE = 100;
static const float STICK_DEAD_ZONE = .1;
static float STICK_INNER_SIZE;
static float STICK_OUTER_SIZE;
static float LS_CENTER_X;
static float LS_CENTER_Y;
static float RS_CENTER_X;
static float RS_CENTER_Y;

static float START_X;
static float START_Y;

static float SELECT_X;
static float SELECT_Y;

static float R1_X;
static float R1_Y;
static float R2_X;
static float R2_Y;
static float R3_X;
static float R3_Y;
static float L1_X;
static float L1_Y;
static float L2_X;
static float L2_Y;
static float L3_X;
static float L3_Y;

- (id) initWithView:(UIView*)view controllerSup:(ControllerSupport*)controllerSupport streamConfig:(StreamConfiguration*)streamConfig {
    self = [self init];
    _view = view;
    _controllerSupport = controllerSupport;
    _controller = [controllerSupport getOscController];
    _deadTouches = [[NSMutableArray alloc] init];
    _swapABXY = streamConfig.swapABXYButtons;
    _appID = streamConfig.appID;
    
    [self relayout];

    _aButton = [CALayer layer];
    _bButton = [CALayer layer];
    _xButton = [CALayer layer];
    _yButton = [CALayer layer];
    _upButton = [CALayer layer];
    _downButton = [CALayer layer];
    _leftButton = [CALayer layer];
    _rightButton = [CALayer layer];
    _l1Button = [CALayer layer];
    _r1Button = [CALayer layer];
    _l2Button = [CALayer layer];
    _r2Button = [CALayer layer];
    _l3Button = [CALayer layer];
    _r3Button = [CALayer layer];
    _startButton = [CALayer layer];
    _selectButton = [CALayer layer];
    _leftStickBackground = [CALayer layer];
    _rightStickBackground = [CALayer layer];
    _leftStick = [CALayer layer];
    _rightStick = [CALayer layer];
    
    return self;
}

+ (UIEdgeInsets) obstructedInsetsForView:(UIView*)view {
    UIEdgeInsets insets = view.safeAreaInsets;
#if !TARGET_OS_TV && defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        CGRect b = view.bounds;
        for (UIViewReservedRegion* region in [view reservedRegionsOfKind:[UIViewReservedRegionKind occlusionRegionKind]]) {
            CGRect f = CGRectIntersection(region.frame, b);
            if (!region.isActive || CGRectIsEmpty(f)) {
                continue;
            }
            // Clear the region from the edge it sits closest to. A side edge wins a near tie:
            // that keeps a corner camera to a strip down the side, as the system bar does,
            // instead of a band across the whole top.
            CGFloat left = CGRectGetMinX(f) - CGRectGetMinX(b);
            CGFloat right = CGRectGetMaxX(b) - CGRectGetMaxX(f);
            CGFloat top = CGRectGetMinY(f) - CGRectGetMinY(b);
            CGFloat bottom = CGRectGetMaxY(b) - CGRectGetMaxY(f);
            CGFloat side = MIN(left, right), cap = MIN(top, bottom);
            if (side <= cap + 24) {
                if (left <= right) insets.left = MAX(insets.left, CGRectGetMaxX(f) - CGRectGetMinX(b));
                else insets.right = MAX(insets.right, CGRectGetMaxX(b) - CGRectGetMinX(f));
            }
            else {
                if (top <= bottom) insets.top = MAX(insets.top, CGRectGetMaxY(f) - CGRectGetMinY(b));
                else insets.bottom = MAX(insets.bottom, CGRectGetMaxY(b) - CGRectGetMinY(f));
            }
        }
    }
#endif
    return insets;
}

// Recompute the control area from the view's current bounds and per-edge safe area.
// Called again whenever the view resizes (e.g. folding or unfolding an iPhone Duo mid-stream).
- (void) relayout {
    UITraitCollection* traits = _view.traitCollection;
    BOOL roomy = traits.horizontalSizeClass == UIUserInterfaceSizeClassRegular &&
                 traits.verticalSizeClass == UIUserInterfaceSizeClassRegular;
    CGRect area = UIEdgeInsetsInsetRect(_view.bounds, [OnScreenControls obstructedInsetsForView:_view]);

    if (roomy == _iPad && CGRectEqualToRect(area, _usableArea)) {
        return;
    }
    _iPad = roomy;
    _usableArea = area;

    if (_iPad)
    {
        // Cut down the control area on large displays so the controls are more reachable
        area.origin.y += area.size.height / 2.0;
        area.size.height /= 2.0;
    }
    else
    {
        CGFloat edge = area.size.width * EDGE_WIDTH;
        area.origin.x += edge;
        area.size.width -= edge * 2;
    }
    _controlArea = area;

    if (_visible) {
        [self updateControls];
    }
}

- (void) show {
    _visible = YES;
        
    [self updateControls];
}

- (void) setLevel:(OnScreenControlsLevel)level {
    _level = level;
    
    // Only update controls if we're showing, otherwise
    // show will do it for us.
    if (_visible) {
        [self updateControls];
    }
}

- (OnScreenControlsLevel) getLevel {
    return _level;
}

- (void) updateControls {
    // Controls jump to their new place while dragging, without implicit animations
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    switch (_level) {
        case OnScreenControlsLevelOff:
            [self hideButtons];
            [self hideBumpers];
            [self hideTriggers];
            [self hideStartSelect];
            [self hideSticks];
            [self hideL3R3];
            break;
        case OnScreenControlsLevelAutoGCGamepad:
            // GCGamepad is missing triggers, both analog sticks,
            // and the select button
            [self setupGamepadControls];
            [self applyLayoutOffsets];
            
            [self hideButtons];
            [self hideBumpers];
            [self hideL3R3];
            [self drawTriggers];
            [self drawStartSelect];
            [self drawSticks];
            break;
        case OnScreenControlsLevelAutoGCExtendedGamepad:
            // GCExtendedGamepad is missing R3, L3, and select
            [self setupExtendedGamepadControls];
            [self applyLayoutOffsets];
            
            [self hideButtons];
            [self hideBumpers];
            [self hideTriggers];
            [self drawStartSelect];
            [self hideSticks];
            [self drawL3R3];
            break;
        case OnScreenControlsLevelAutoGCExtendedGamepadWithStickButtons:
            // This variant of GCExtendedGamepad has L3 and R3 but
            // is still missing Select
            [self setupExtendedGamepadControls];
            [self applyLayoutOffsets];
            
            [self hideButtons];
            [self hideBumpers];
            [self hideTriggers];
            [self hideL3R3];
            [self drawStartSelect];
            [self hideSticks];
            break;
        case OnScreenControlsLevelSimple:
            [self setupSimpleControls];
            [self applyLayoutOffsets];
            
            [self hideTriggers];
            [self hideL3R3];
            [self hideBumpers];
            [self hideSticks];
            [self drawStartSelect];
            [self drawButtons];
            break;
        case OnScreenControlsLevelFull:
            [self setupComplexControls];
            [self applyLayoutOffsets];
            
            [self drawButtons];
            [self drawStartSelect];
            [self drawBumpers];
            [self drawTriggers];
            [self drawSticks];
            [self hideL3R3]; // Full controls don't need these they have the sticks
            break;
        default:
            Log(LOG_W, @"Unknown on-screen controls level: %d", (int)_level);
            break;
    }
    [CATransaction commit];
}

// For GCExtendedGamepad controls we move start, select, L3, and R3 to the button
- (void) setupExtendedGamepadControls {
    // Start with the default complex layout
    [self setupComplexControls];
    
    START_X = _controlArea.size.width * .95 + _controlArea.origin.x;
    START_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    SELECT_X = _controlArea.size.width * .05 + _controlArea.origin.x;
    SELECT_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    
    L3_Y = _controlArea.size.height * .85 + _controlArea.origin.y;
    R3_Y = _controlArea.size.height * .85 + _controlArea.origin.y;
    
    if (_iPad) {
        L3_X = _controlArea.size.width * .15 + _controlArea.origin.x;
        R3_X = _controlArea.size.width * .85 + _controlArea.origin.x;
    }
    else {
        L3_X = _controlArea.size.width * .25 + _controlArea.origin.x;
        R3_X = _controlArea.size.width * .75 + _controlArea.origin.x;
    }
}

// For GCGamepad controls we move triggers, start, and select
// to sit right above the analog sticks
- (void) setupGamepadControls {
    // Start with the default complex layout
    [self setupComplexControls];
    
    L2_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
    L2_X = _controlArea.size.width * .05 + _controlArea.origin.x;
    
    R2_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
    R2_X = _controlArea.size.width * .95 + _controlArea.origin.x;
    
    START_X = _controlArea.size.width * .95 + _controlArea.origin.x;
    START_Y = _controlArea.size.height * .95 + _controlArea.origin.y;
    SELECT_X = _controlArea.size.width * .05 + _controlArea.origin.x;
    SELECT_Y = _controlArea.size.height * .95 + _controlArea.origin.y;
    
    if (_iPad) {
        // The analog sticks are kept closer to the sides on iPad
        LS_CENTER_X = _controlArea.size.width * .15 + _controlArea.origin.x;
        RS_CENTER_X = _controlArea.size.width * .85 + _controlArea.origin.x;
    }
}

// For simple controls we move the triggers and buttons to the bottom
- (void) setupSimpleControls {
    // Start with the default complex layout
    [self setupComplexControls];
    
    START_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    SELECT_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    
    L2_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    L2_X = _controlArea.size.width * .1 + _controlArea.origin.x;

    R2_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    R2_X = _controlArea.size.width * .9 + _controlArea.origin.x;
    
    if (_iPad) {
        // Lower the D-pad and buttons on iPad
        D_PAD_CENTER_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
        BUTTON_CENTER_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
        
        // Move Start and Select closer to sides
        SELECT_X = _controlArea.size.width * .2 + _controlArea.origin.x;
        START_X = _controlArea.size.width * .8 + _controlArea.origin.x;
    }
    else {
        SELECT_X = _controlArea.size.width * .4 + _controlArea.origin.x;
        START_X = _controlArea.size.width * .6 + _controlArea.origin.x;
    }
}

// Squarer than a phone in landscape (the iPhone Duo's outer display is about 1.45:1): the
// percentage layout below overlaps the sticks with the D-pad and buttons. This is the same
// arrangement as the unfolded (iPad) layout, packed to the edges: D-pad and ABXY at the far
// sides, the sticks inward and lower, shoulders stacked on the outer edges above them, Select
// under the D-pad and Start under ABXY. It uses the full width, including the strip the
// camera sits in, and only keeps clear of the camera hole itself and the home indicator.
// Positions are points from the edges, taken from the design canvas (proposal D, 678x466).
static const CGFloat SQUARE_MARGIN = 12;
static const CGFloat CAMERA_KEEPOUT_RADIUS = 30;

- (void) setupSquareControls
{
    CGRect b = _view.bounds;
    UIEdgeInsets safe = _view.safeAreaInsets;
    CGFloat w = b.size.width;
    CGFloat bottom = CGRectGetMaxY(b) - safe.bottom; // above the home indicator
    CGFloat left = CGRectGetMinX(b) + SQUARE_MARGIN;
    CGFloat right = CGRectGetMaxX(b) - SQUARE_MARGIN;
    UIImage* l1 = [UIImage imageNamed:@"L1"];
    UIImage* l2 = [UIImage imageNamed:@"L2"];
    UIImage* b1 = [UIImage imageNamed:@"BButton"];
    UIImage* lb = [UIImage imageNamed:@"LeftButton"];
    UIImage* select = [UIImage imageNamed:@"SelectButton"];
    UIImage* start = [UIImage imageNamed:@"StartButton"];

    CGFloat dpadHalfW = D_PAD_DIST + lb.size.width;
    CGFloat buttonsHalfW = BUTTON_DIST + b1.size.width;
    CGFloat shoulderHalfW = MAX(l1.size.width, l2.size.width) / 2;

    // Shoulders: L2 over L1 on the left edge, R2 over R1 on the right, below the camera corner
    L2_X = left + shoulderHalfW;
    R2_X = right - shoulderHalfW;
    L1_X = L2_X;
    R1_X = R2_X;
    L2_Y = R2_Y = CGRectGetMinY(b) + 128;
    L1_Y = R1_Y = CGRectGetMinY(b) + 173;

    // D-pad and ABXY at the sides, sticks inward and lower, Select / Start under them
    D_PAD_CENTER_X = left + dpadHalfW;
    BUTTON_CENTER_X = right - buttonsHalfW;
    D_PAD_CENTER_Y = BUTTON_CENTER_Y = bottom - 152;
    LS_CENTER_X = CGRectGetMinX(b) + w * 0.28;
    RS_CENTER_X = CGRectGetMinX(b) + w * 0.69;
    LS_CENTER_Y = RS_CENTER_Y = bottom - 62;
    SELECT_X = D_PAD_CENTER_X;
    START_X = BUTTON_CENTER_X;
    SELECT_Y = START_Y = bottom - MAX(select.size.height, start.size.height) / 2 - 16;

    // The camera hole sits at the top of the strip on whichever side has it (bottom of the
    // strip when the phone is turned the other way): push anything that would cover it inward.
    CGFloat strip = safe.left - safe.right;
    if (fabs(strip) >= 20) {
        BOOL onLeft = strip > 0;
        CGPoint hole = onLeft ? CGPointMake(CGRectGetMinX(b) + 40, CGRectGetMinY(b) + 45)
                              : CGPointMake(CGRectGetMaxX(b) - 40, CGRectGetMaxY(b) - 45);
        float* xs[] = { &L2_X, &L1_X, &R2_X, &R1_X, &D_PAD_CENTER_X, &BUTTON_CENTER_X, &SELECT_X, &START_X };
        CGFloat ys[] = { L2_Y, L1_Y, R2_Y, R1_Y, D_PAD_CENTER_Y, BUTTON_CENTER_Y, SELECT_Y, START_Y };
        CGFloat halfWs[] = { shoulderHalfW, shoulderHalfW, shoulderHalfW, shoulderHalfW, dpadHalfW, buttonsHalfW,
                             select.size.width / 2, start.size.width / 2 };
        CGFloat halfHs[] = { l2.size.height / 2, l1.size.height / 2, l2.size.height / 2, l1.size.height / 2,
                             dpadHalfW, buttonsHalfW, select.size.height / 2, start.size.height / 2 };
        for (int i = 0; i < 8; i++) {
            CGFloat x = *xs[i];
            BOOL overlapsY = fabs(ys[i] - hole.y) < halfHs[i] + CAMERA_KEEPOUT_RADIUS;
            BOOL overlapsX = fabs(x - hole.x) < halfWs[i] + CAMERA_KEEPOUT_RADIUS;
            if (overlapsX && overlapsY) {
                *xs[i] = onLeft ? hole.x + CAMERA_KEEPOUT_RADIUS + halfWs[i]
                                : hole.x - CAMERA_KEEPOUT_RADIUS - halfWs[i];
            }
        }
    }
}

- (void) setupComplexControls
{
    if (!_iPad && _controlArea.size.height > 0 && _controlArea.size.width / _controlArea.size.height < 1.8) {
        [self setupSquareControls];
        return;
    }

    D_PAD_CENTER_X = _controlArea.size.width * .1 + _controlArea.origin.x;
    D_PAD_CENTER_Y = _controlArea.size.height * .60 + _controlArea.origin.y;
    BUTTON_CENTER_X = _controlArea.size.width * .9 + _controlArea.origin.x;
    BUTTON_CENTER_Y = _controlArea.size.height * .60 + _controlArea.origin.y;
    
    if (_iPad)
    {
        // The analog sticks are kept closer to the sides on iPad
        LS_CENTER_X = _controlArea.size.width * .22 + _controlArea.origin.x;
        LS_CENTER_Y = _controlArea.size.height * .80 + _controlArea.origin.y;
        RS_CENTER_X = _controlArea.size.width * .77 + _controlArea.origin.x;
        RS_CENTER_Y = _controlArea.size.height * .80 + _controlArea.origin.y;
    }
    else
    {
        LS_CENTER_X = _controlArea.size.width * .35 + _controlArea.origin.x;
        LS_CENTER_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
        RS_CENTER_X = _controlArea.size.width * .65 + _controlArea.origin.x;
        RS_CENTER_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
    }
    
    START_X = _controlArea.size.width * .9 + _controlArea.origin.x;
    START_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    SELECT_X = _controlArea.size.width * .1 + _controlArea.origin.x;
    SELECT_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    
    L1_Y = _controlArea.size.height * .27 + _controlArea.origin.y;
    L2_Y = _controlArea.size.height * .1 + _controlArea.origin.y;
    R1_Y = _controlArea.size.height * .27 + _controlArea.origin.y;
    R2_Y = _controlArea.size.height * .1 + _controlArea.origin.y;
    
    if (_iPad) {
        // Move L/R buttons closer to the side on iPad
        L1_X = _controlArea.size.width * .05 + _controlArea.origin.x;
        L2_X = _controlArea.size.width * .05 + _controlArea.origin.x;
        R1_X = _controlArea.size.width * .95 + _controlArea.origin.x;
        R2_X = _controlArea.size.width * .95 + _controlArea.origin.x;
    }
    else {
        L1_X = _controlArea.size.width * .1 + _controlArea.origin.x;
        L2_X = _controlArea.size.width * .1 + _controlArea.origin.x;
        R1_X = _controlArea.size.width * .9 + _controlArea.origin.x;
        R2_X = _controlArea.size.width * .9 + _controlArea.origin.x;
    }
}

- (void) drawButtons {
    UIImage* aButtonImage = [UIImage imageNamed:@"AButton"];
    UIImage* bButtonImage = [UIImage imageNamed:@"BButton"];
    UIImage* xButtonImage = [UIImage imageNamed:@"XButton"];
    UIImage* yButtonImage = [UIImage imageNamed:@"YButton"];
    
    CGRect aButtonFrame = CGRectMake(BUTTON_CENTER_X - aButtonImage.size.width / 2, BUTTON_CENTER_Y + BUTTON_DIST, aButtonImage.size.width, aButtonImage.size.height);
    CGRect bButtonFrame = CGRectMake(BUTTON_CENTER_X + BUTTON_DIST, BUTTON_CENTER_Y - bButtonImage.size.height / 2, bButtonImage.size.width, bButtonImage.size.height);
    CGRect xButtonFrame = CGRectMake(BUTTON_CENTER_X - BUTTON_DIST - xButtonImage.size.width, BUTTON_CENTER_Y - xButtonImage.size.height/ 2, xButtonImage.size.width, xButtonImage.size.height);
    CGRect yButtonFrame = CGRectMake(BUTTON_CENTER_X - yButtonImage.size.width / 2, BUTTON_CENTER_Y - BUTTON_DIST - yButtonImage.size.height, yButtonImage.size.width, yButtonImage.size.height);
    
    // create A button
    _aButton.contents = (id) aButtonImage.CGImage;
    _aButton.frame = _swapABXY ? bButtonFrame : aButtonFrame;
    [_view.layer addSublayer:_aButton];
    
    // create B button
    _bButton.frame = _swapABXY ? aButtonFrame : bButtonFrame;
    _bButton.contents = (id) bButtonImage.CGImage;
    [_view.layer addSublayer:_bButton];
    
    // create X Button
    _xButton.frame = _swapABXY ? yButtonFrame : xButtonFrame;
    _xButton.contents = (id) xButtonImage.CGImage;
    [_view.layer addSublayer:_xButton];
    
    // create Y Button
    _yButton.frame = _swapABXY ? xButtonFrame : yButtonFrame;
    _yButton.contents = (id) yButtonImage.CGImage;
    [_view.layer addSublayer:_yButton];
    
    // create Down button
    UIImage* downButtonImage = [UIImage imageNamed:@"DownButton"];
    _downButton.frame = CGRectMake(D_PAD_CENTER_X - downButtonImage.size.width / 2, D_PAD_CENTER_Y + D_PAD_DIST, downButtonImage.size.width, downButtonImage.size.height);
    _downButton.contents = (id) downButtonImage.CGImage;
    [_view.layer addSublayer:_downButton];
    
    // create Right button
    UIImage* rightButtonImage = [UIImage imageNamed:@"RightButton"];
    _rightButton.frame = CGRectMake(D_PAD_CENTER_X + D_PAD_DIST, D_PAD_CENTER_Y - rightButtonImage.size.height / 2, rightButtonImage.size.width, rightButtonImage.size.height);
    _rightButton.contents = (id) rightButtonImage.CGImage;
    [_view.layer addSublayer:_rightButton];
    
    // create Up button
    UIImage* upButtonImage = [UIImage imageNamed:@"UpButton"];
    _upButton.frame = CGRectMake(D_PAD_CENTER_X - upButtonImage.size.width / 2, D_PAD_CENTER_Y - D_PAD_DIST - upButtonImage.size.height, upButtonImage.size.width, upButtonImage.size.height);
    _upButton.contents = (id) upButtonImage.CGImage;
    [_view.layer addSublayer:_upButton];
    
    // create Left button
    UIImage* leftButtonImage = [UIImage imageNamed:@"LeftButton"];
    _leftButton.frame = CGRectMake(D_PAD_CENTER_X - D_PAD_DIST - leftButtonImage.size.width, D_PAD_CENTER_Y - leftButtonImage.size.height / 2, leftButtonImage.size.width, leftButtonImage.size.height);
    _leftButton.contents = (id) leftButtonImage.CGImage;
    [_view.layer addSublayer:_leftButton];
}

- (void) drawStartSelect {
    // create Start button
    UIImage* startButtonImage = [UIImage imageNamed:@"StartButton"];
    _startButton.frame = CGRectMake(START_X - startButtonImage.size.width / 2, START_Y - startButtonImage.size.height / 2, startButtonImage.size.width, startButtonImage.size.height);
    _startButton.contents = (id) startButtonImage.CGImage;
    [_view.layer addSublayer:_startButton];
    
    // create Select button
    UIImage* selectButtonImage = [UIImage imageNamed:@"SelectButton"];
    _selectButton.frame = CGRectMake(SELECT_X - selectButtonImage.size.width / 2, SELECT_Y - selectButtonImage.size.height / 2, selectButtonImage.size.width, selectButtonImage.size.height);
    _selectButton.contents = (id) selectButtonImage.CGImage;
    [_view.layer addSublayer:_selectButton];
}

- (void) drawBumpers {
    // create L1 button
    UIImage* l1ButtonImage = [UIImage imageNamed:@"L1"];
    _l1Button.frame = CGRectMake(L1_X - l1ButtonImage.size.width / 2, L1_Y - l1ButtonImage.size.height / 2, l1ButtonImage.size.width, l1ButtonImage.size.height);
    _l1Button.contents = (id) l1ButtonImage.CGImage;
    [_view.layer addSublayer:_l1Button];
    
    // create R1 button
    UIImage* r1ButtonImage = [UIImage imageNamed:@"R1"];
    _r1Button.frame = CGRectMake(R1_X - r1ButtonImage.size.width / 2, R1_Y - r1ButtonImage.size.height / 2, r1ButtonImage.size.width, r1ButtonImage.size.height);
    _r1Button.contents = (id) r1ButtonImage.CGImage;
    [_view.layer addSublayer:_r1Button];
}

- (void) drawTriggers {
    // create L2 button
    UIImage* l2ButtonImage = [UIImage imageNamed:@"L2"];
    _l2Button.frame = CGRectMake(L2_X - l2ButtonImage.size.width / 2, L2_Y - l2ButtonImage.size.height / 2, l2ButtonImage.size.width, l2ButtonImage.size.height);
    _l2Button.contents = (id) l2ButtonImage.CGImage;
    [_view.layer addSublayer:_l2Button];
    
    // create R2 button
    UIImage* r2ButtonImage = [UIImage imageNamed:@"R2"];
    _r2Button.frame = CGRectMake(R2_X - r2ButtonImage.size.width / 2, R2_Y - r2ButtonImage.size.height / 2, r2ButtonImage.size.width, r2ButtonImage.size.height);
    _r2Button.contents = (id) r2ButtonImage.CGImage;
    [_view.layer addSublayer:_r2Button];
}

- (void) drawSticks {
    // create left analog stick
    UIImage* leftStickBgImage = [UIImage imageNamed:@"StickOuter"];
    _leftStickBackground.frame = CGRectMake(LS_CENTER_X - leftStickBgImage.size.width / 2, LS_CENTER_Y - leftStickBgImage.size.height / 2, leftStickBgImage.size.width, leftStickBgImage.size.height);
    _leftStickBackground.contents = (id) leftStickBgImage.CGImage;
    [_view.layer addSublayer:_leftStickBackground];
    
    UIImage* leftStickImage = [UIImage imageNamed:@"StickInner"];
    _leftStick.frame = CGRectMake(LS_CENTER_X - leftStickImage.size.width / 2, LS_CENTER_Y - leftStickImage.size.height / 2, leftStickImage.size.width, leftStickImage.size.height);
    _leftStick.contents = (id) leftStickImage.CGImage;
    [_view.layer addSublayer:_leftStick];
    
    // create right analog stick
    UIImage* rightStickBgImage = [UIImage imageNamed:@"StickOuter"];
    _rightStickBackground.frame = CGRectMake(RS_CENTER_X - rightStickBgImage.size.width / 2, RS_CENTER_Y - rightStickBgImage.size.height / 2, rightStickBgImage.size.width, rightStickBgImage.size.height);
    _rightStickBackground.contents = (id) rightStickBgImage.CGImage;
    [_view.layer addSublayer:_rightStickBackground];
    
    UIImage* rightStickImage = [UIImage imageNamed:@"StickInner"];
    _rightStick.frame = CGRectMake(RS_CENTER_X - rightStickImage.size.width / 2, RS_CENTER_Y - rightStickImage.size.height / 2, rightStickImage.size.width, rightStickImage.size.height);
    _rightStick.contents = (id) rightStickImage.CGImage;
    [_view.layer addSublayer:_rightStick];
    
    STICK_INNER_SIZE = rightStickImage.size.width;
    STICK_OUTER_SIZE = rightStickBgImage.size.width;
}

- (void) drawL3R3 {
    UIImage* l3ButtonImage = [UIImage imageNamed:@"L3"];
    _l3Button.frame = CGRectMake(L3_X - l3ButtonImage.size.width / 2, L3_Y - l3ButtonImage.size.height / 2, l3ButtonImage.size.width, l3ButtonImage.size.height);
    _l3Button.contents = (id) l3ButtonImage.CGImage;
    _l3Button.cornerRadius = l3ButtonImage.size.width / 2;
    _l3Button.borderColor = [UIColor colorWithRed:15.f/255 green:160.f/255 blue:40.f/255 alpha:1.f].CGColor;
    [_view.layer addSublayer:_l3Button];
    
    UIImage* r3ButtonImage = [UIImage imageNamed:@"R3"];
    _r3Button.frame = CGRectMake(R3_X - r3ButtonImage.size.width / 2, R3_Y - r3ButtonImage.size.height / 2, r3ButtonImage.size.width, r3ButtonImage.size.height);
    _r3Button.contents = (id) r3ButtonImage.CGImage;
    _r3Button.cornerRadius = r3ButtonImage.size.width / 2;
    _r3Button.borderColor = [UIColor colorWithRed:15.f/255 green:160.f/255 blue:40.f/255 alpha:1.f].CGColor;
    [_view.layer addSublayer:_r3Button];
}

- (void) hideButtons {
    [_aButton removeFromSuperlayer];
    [_bButton removeFromSuperlayer];
    [_xButton removeFromSuperlayer];
    [_yButton removeFromSuperlayer];
    [_upButton removeFromSuperlayer];
    [_downButton removeFromSuperlayer];
    [_leftButton removeFromSuperlayer];
    [_rightButton removeFromSuperlayer];
}

- (void) hideStartSelect {
    [_startButton removeFromSuperlayer];
    [_selectButton removeFromSuperlayer];
}

- (void) hideBumpers {
    [_l1Button removeFromSuperlayer];
    [_r1Button removeFromSuperlayer];
}

- (void) hideTriggers {
    [_l2Button removeFromSuperlayer];
    [_r2Button removeFromSuperlayer];
}

- (void) hideSticks {
    [_leftStickBackground removeFromSuperlayer];
    [_rightStickBackground removeFromSuperlayer];
    [_leftStick removeFromSuperlayer];
    [_rightStick removeFromSuperlayer];
}

- (void) hideL3R3 {
    [_l3Button removeFromSuperlayer];
    [_r3Button removeFromSuperlayer];
}

#pragma mark - Layout editor

// Movable groups and the statics that position them; the layer says whether it's on screen
static NSString* const MN_GROUPS[] = { @"dpad", @"abxy", @"ls", @"rs", @"start", @"select",
                                       @"l1", @"l2", @"r1", @"r2", @"l3", @"r3" };
static float* const MN_GROUP_X[] = { &D_PAD_CENTER_X, &BUTTON_CENTER_X, &LS_CENTER_X, &RS_CENTER_X, &START_X, &SELECT_X,
                                     &L1_X, &L2_X, &R1_X, &R2_X, &L3_X, &R3_X };
static float* const MN_GROUP_Y[] = { &D_PAD_CENTER_Y, &BUTTON_CENTER_Y, &LS_CENTER_Y, &RS_CENTER_Y, &START_Y, &SELECT_Y,
                                     &L1_Y, &L2_Y, &R1_Y, &R2_Y, &L3_Y, &R3_Y };
static const int MN_GROUP_COUNT = sizeof(MN_GROUPS) / sizeof(MN_GROUPS[0]);

- (CALayer*) layerForGroup:(int)i {
    CALayer* layers[] = { _upButton, _aButton, _leftStickBackground, _rightStickBackground, _startButton, _selectButton,
                          _l1Button, _l2Button, _r1Button, _r2Button, _l3Button, _r3Button };
    return layers[i];
}

// Layouts are saved per posture (the folded outer display, a phone in landscape, the roomy
// inner display), since one arrangement never fits all three, and optionally per game.
- (NSString*) currentPosture {
    if (_iPad) {
        return @"roomy";
    }
    BOOL square = _controlArea.size.height > 0 && _controlArea.size.width / _controlArea.size.height < 1.8;
    return square ? @"square" : @"wide";
}

- (NSString*) layoutKeyForApp:(NSString*)appID {
    return appID != nil ? [NSString stringWithFormat:@"mnOSCLayout.%@.%@", appID, [self currentPosture]]
                        : [NSString stringWithFormat:@"mnOSCLayout.%@", [self currentPosture]];
}

- (void) loadLayoutOffsets {
    _layoutPosture = [self currentPosture];
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary* saved = (_appID != nil ? [defaults dictionaryForKey:[self layoutKeyForApp:_appID]] : nil)
                          ?: [defaults dictionaryForKey:[self layoutKeyForApp:nil]];
    _layoutOffsets = [NSMutableDictionary dictionary];
    for (NSString* name in saved) {
        NSArray* xy = saved[name];
        if ([xy isKindOfClass:NSArray.class] && xy.count == 2) {
            _layoutOffsets[name] = [NSValue valueWithCGPoint:CGPointMake([xy[0] doubleValue], [xy[1] doubleValue])];
        }
    }
}

- (void) applyLayoutOffsets {
    if (_layoutOffsets == nil || ![_layoutPosture isEqualToString:[self currentPosture]]) {
        [self loadLayoutOffsets];
    }
    CGRect b = _view.bounds;
    for (int i = 0; i < MN_GROUP_COUNT; i++) {
        NSValue* offset = _layoutOffsets[MN_GROUPS[i]];
        if (offset == nil) {
            continue;
        }
        CGPoint d = offset.CGPointValue;
        *MN_GROUP_X[i] = MIN(MAX(*MN_GROUP_X[i] + d.x, CGRectGetMinX(b)), CGRectGetMaxX(b));
        *MN_GROUP_Y[i] = MIN(MAX(*MN_GROUP_Y[i] + d.y, CGRectGetMinY(b)), CGRectGetMaxY(b));
    }
}

- (void) setEditing:(BOOL)editing {
    _editing = editing;
    _dragGroup = nil;
    _dragTouch = nil;
    if (!editing) {
        // Leaving without saving puts the saved layout back
        [self loadLayoutOffsets];
    }
    if (_visible) {
        [self updateControls];
    }
}

- (BOOL) isEditing {
    return _editing;
}

- (void) resetLayout {
    [_layoutOffsets removeAllObjects];
    if (_visible) {
        [self updateControls];
    }
}

- (void) saveLayoutForThisGame:(BOOL)thisGame {
    NSMutableDictionary* plist = [NSMutableDictionary dictionary];
    for (NSString* name in _layoutOffsets) {
        CGPoint d = _layoutOffsets[name].CGPointValue;
        plist[name] = @[ @(d.x), @(d.y) ];
    }
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    if (thisGame && _appID != nil) {
        [defaults setObject:plist forKey:[self layoutKeyForApp:_appID]];
    }
    else {
        [defaults setObject:plist forKey:[self layoutKeyForApp:nil]];
        // A layout saved for every game replaces this game's own
        if (_appID != nil) {
            [defaults removeObjectForKey:[self layoutKeyForApp:_appID]];
        }
    }
}

- (BOOL) hasLayoutForThisGame {
    return _appID != nil && [NSUserDefaults.standardUserDefaults dictionaryForKey:[self layoutKeyForApp:_appID]] != nil;
}

// While editing, a touch grabs the nearest visible control and drags it; nothing reaches the PC.
- (void) handleEditTouches:(NSSet*)touches phase:(UITouchPhase)phase {
    for (UITouch* touch in touches) {
        CGPoint p = [touch locationInView:_view];
        if (phase == UITouchPhaseBegan && _dragTouch == nil) {
            CGFloat best = 80;
            for (int i = 0; i < MN_GROUP_COUNT; i++) {
                if ([self layerForGroup:i].superlayer == nil) {
                    continue;
                }
                CGFloat dist = hypot(p.x - *MN_GROUP_X[i], p.y - *MN_GROUP_Y[i]);
                if (dist < best) {
                    best = dist;
                    _dragGroup = MN_GROUPS[i];
                }
            }
            if (_dragGroup != nil) {
                _dragTouch = touch;
                _dragLast = p;
            }
        }
        else if (touch == _dragTouch && phase == UITouchPhaseMoved) {
            CGPoint d = _layoutOffsets[_dragGroup].CGPointValue;
            d.x += p.x - _dragLast.x;
            d.y += p.y - _dragLast.y;
            _layoutOffsets[_dragGroup] = [NSValue valueWithCGPoint:d];
            _dragLast = p;
            [self updateControls];
        }
        else if (touch == _dragTouch) {
            _dragTouch = nil;
            _dragGroup = nil;
        }
    }
}

- (BOOL) handleTouchMovedEvent:touches {
    if (_editing) {
        [self handleEditTouches:touches phase:UITouchPhaseMoved];
        return YES;
    }
    BOOL updated = false;
    BOOL buttonTouch = false;
    float rsMaxX = RS_CENTER_X + STICK_OUTER_SIZE / 2;
    float rsMaxY = RS_CENTER_Y + STICK_OUTER_SIZE / 2;
    float rsMinX = RS_CENTER_X - STICK_OUTER_SIZE / 2;
    float rsMinY = RS_CENTER_Y - STICK_OUTER_SIZE / 2;
    float lsMaxX = LS_CENTER_X + STICK_OUTER_SIZE / 2;
    float lsMaxY = LS_CENTER_Y + STICK_OUTER_SIZE / 2;
    float lsMinX = LS_CENTER_X - STICK_OUTER_SIZE / 2;
    float lsMinY = LS_CENTER_Y - STICK_OUTER_SIZE / 2;
    
    for (UITouch* touch in touches) {
        CGPoint touchLocation = [touch locationInView:_view];
        float xLoc = touchLocation.x;
        float yLoc = touchLocation.y;
        if (touch == _lsTouch) {
            if (xLoc > lsMaxX) xLoc = lsMaxX;
            if (xLoc < lsMinX) xLoc = lsMinX;
            if (yLoc > lsMaxY) yLoc = lsMaxY;
            if (yLoc < lsMinY) yLoc = lsMinY;
            
            _leftStick.frame = CGRectMake(xLoc - STICK_INNER_SIZE / 2, yLoc - STICK_INNER_SIZE / 2, STICK_INNER_SIZE, STICK_INNER_SIZE);
            
            float xStickVal = (xLoc - LS_CENTER_X) / (lsMaxX - LS_CENTER_X);
            float yStickVal = (yLoc - LS_CENTER_Y) / (lsMaxY - LS_CENTER_Y);
            
            if (fabsf(xStickVal) < STICK_DEAD_ZONE) xStickVal = 0;
            if (fabsf(yStickVal) < STICK_DEAD_ZONE) yStickVal = 0;
            
            [_controllerSupport updateLeftStick:_controller x:0x7FFE * xStickVal y:0x7FFE * -yStickVal];
            
            updated = true;
        } else if (touch == _rsTouch) {
            if (xLoc > rsMaxX) xLoc = rsMaxX;
            if (xLoc < rsMinX) xLoc = rsMinX;
            if (yLoc > rsMaxY) yLoc = rsMaxY;
            if (yLoc < rsMinY) yLoc = rsMinY;
            
            _rightStick.frame = CGRectMake(xLoc - STICK_INNER_SIZE / 2, yLoc - STICK_INNER_SIZE / 2, STICK_INNER_SIZE, STICK_INNER_SIZE);
            
            float xStickVal = (xLoc - RS_CENTER_X) / (rsMaxX - RS_CENTER_X);
            float yStickVal = (yLoc - RS_CENTER_Y) / (rsMaxY - RS_CENTER_Y);
            
            if (fabsf(xStickVal) < STICK_DEAD_ZONE) xStickVal = 0;
            if (fabsf(yStickVal) < STICK_DEAD_ZONE) yStickVal = 0;
            
            [_controllerSupport updateRightStick:_controller x:0x7FFE * xStickVal y:0x7FFE * -yStickVal];
            
            updated = true;
        } else if (touch == _dpadTouch) {
            [_controllerSupport clearButtonFlag:_controller
                                          flags:UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG];
            
            // Allow the user to slide their finger to another d-pad button
            if ([_upButton.presentationLayer hitTest:touchLocation]) {
                [_controllerSupport setButtonFlag:_controller flags:UP_FLAG];
                updated = true;
            } else if ([_downButton.presentationLayer hitTest:touchLocation]) {
                [_controllerSupport setButtonFlag:_controller flags:DOWN_FLAG];
                updated = true;
            } else if ([_leftButton.presentationLayer hitTest:touchLocation]) {
                [_controllerSupport setButtonFlag:_controller flags:LEFT_FLAG];
                updated = true;
            } else if ([_rightButton.presentationLayer hitTest:touchLocation]) {
                [_controllerSupport setButtonFlag:_controller flags:RIGHT_FLAG];
                updated = true;
            }
            
            buttonTouch = true;
        } else if (touch == _aTouch) {
            buttonTouch = true;
        } else if (touch == _bTouch) {
            buttonTouch = true;
        } else if (touch == _xTouch) {
            buttonTouch = true;
        } else if (touch == _yTouch) {
            buttonTouch = true;
        } else if (touch == _startTouch) {
            buttonTouch = true;
        } else if (touch == _selectTouch) {
            buttonTouch = true;
        } else if (touch == _l1Touch) {
            buttonTouch = true;
        } else if (touch == _r1Touch) {
            buttonTouch = true;
        } else if (touch == _l2Touch) {
            buttonTouch = true;
        } else if (touch == _r2Touch) {
            buttonTouch = true;
        } else if (touch == _l3Touch) {
            buttonTouch = true;
        } else if (touch == _r3Touch) {
            buttonTouch = true;
        }
        if ([_deadTouches containsObject:touch]) {
            updated = true;
        }
    }
    if (updated) {
        [_controllerSupport updateFinished:_controller];
    }
    return updated || buttonTouch;
}

- (BOOL)handleTouchDownEvent:touches {
    if (_editing) {
        [self handleEditTouches:touches phase:UITouchPhaseBegan];
        return YES;
    }
    BOOL updated = false;
    BOOL stickTouch = false;
    BOOL buttonPressed = false;
    for (UITouch* touch in touches) {
        CGPoint touchLocation = [touch locationInView:_view];
        BOOL updatedBefore = updated;
        
        if (_aButton.superlayer != nil && [_aButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:A_FLAG];
            _aTouch = touch;
            updated = true;
        } else if (_bButton.superlayer != nil && [_bButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:B_FLAG];
            _bTouch = touch;
            updated = true;
        } else if (_xButton.superlayer != nil && [_xButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:X_FLAG];
            _xTouch = touch;
            updated = true;
        } else if (_yButton.superlayer != nil && [_yButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:Y_FLAG];
            _yTouch = touch;
            updated = true;
        } else if (_upButton.superlayer != nil && [_upButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:UP_FLAG];
            _dpadTouch = touch;
            updated = true;
        } else if (_downButton.superlayer != nil && [_downButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:DOWN_FLAG];
            _dpadTouch = touch;
            updated = true;
        } else if (_leftButton.superlayer != nil && [_leftButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:LEFT_FLAG];
            _dpadTouch = touch;
            updated = true;
        } else if (_rightButton.superlayer != nil && [_rightButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:RIGHT_FLAG];
            _dpadTouch = touch;
            updated = true;
        } else if (_startButton.superlayer != nil && [_startButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:PLAY_FLAG];
            _startTouch = touch;
            updated = true;
        } else if (_selectButton.superlayer != nil && [_selectButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:BACK_FLAG];
            _selectTouch = touch;
            updated = true;
        } else if (_l1Button.superlayer != nil && [_l1Button.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:LB_FLAG];
            _l1Touch = touch;
            updated = true;
        } else if (_r1Button.superlayer != nil && [_r1Button.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:RB_FLAG];
            _r1Touch = touch;
            updated = true;
        } else if (_l2Button.superlayer != nil && [_l2Button.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport updateLeftTrigger:_controller left:0xFF];
            _l2Touch = touch;
            updated = true;
        } else if (_r2Button.superlayer != nil && [_r2Button.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport updateRightTrigger:_controller right:0xFF];
            _r2Touch = touch;
            updated = true;
        } else if (_l3Button.superlayer != nil && [_l3Button.presentationLayer hitTest:touchLocation]) {
            if (l3Set) {
                [_controllerSupport clearButtonFlag:_controller flags:LS_CLK_FLAG];
                _l3Button.borderWidth = 0.0f;
            } else {
                [_controllerSupport setButtonFlag:_controller flags:LS_CLK_FLAG];
                _l3Button.borderWidth = 2.0f;
            }
            l3Set = !l3Set;
            _l3Touch = touch;
            updated = true;
        } else if (_r3Button.superlayer != nil && [_r3Button.presentationLayer hitTest:touchLocation]) {
            if (r3Set) {
                [_controllerSupport clearButtonFlag:_controller flags:RS_CLK_FLAG];
                _r3Button.borderWidth = 0.0f;
            } else {
                [_controllerSupport setButtonFlag:_controller flags:RS_CLK_FLAG];
                _r3Button.borderWidth = 2.0f;
            }
            r3Set = !r3Set;
            _r3Touch = touch;
            updated = true;
        } else if (_leftStick.superlayer != nil && [_leftStick.presentationLayer hitTest:touchLocation]) {
            if (l3TouchStart != nil) {
                // Find elapsed time and convert to milliseconds
                // Use (-) modifier to conversion since receiver is earlier than now
                double l3TouchTime = [l3TouchStart timeIntervalSinceNow] * -1000.0;
                if (l3TouchTime < STICK_CLICK_RATE) {
                    [_controllerSupport setButtonFlag:_controller flags:LS_CLK_FLAG];
                    updated = true;
                }
            }
            _lsTouch = touch;
            stickTouch = true;
        } else if (_rightStick.superlayer != nil && [_rightStick.presentationLayer hitTest:touchLocation]) {
            if (r3TouchStart != nil) {
                // Find elapsed time and convert to milliseconds
                // Use (-) modifier to conversion since receiver is earlier than now
                double r3TouchTime = [r3TouchStart timeIntervalSinceNow] * -1000.0;
                if (r3TouchTime < STICK_CLICK_RATE) {
                    [_controllerSupport setButtonFlag:_controller flags:RS_CLK_FLAG];
                    updated = true;
                }
            }
            _rsTouch = touch;
            stickTouch = true;
        }
        if (updated && !updatedBefore) {
            buttonPressed = true;
        }
        if (!updated && !stickTouch && [self isInDeadZone:touch]) {
            [_deadTouches addObject:touch];
            updated = true;
        }
    }
    if (updated) {
        [_controllerSupport updateFinished:_controller];
    }
#if !TARGET_OS_TV
    // A tap you can feel for every button press
    // Settings › Input › Haptics on button presses (on unless turned off)
    id hapticsSetting = [[NSUserDefaults standardUserDefaults] objectForKey:@"mnHapticsEnabled"];
    if (buttonPressed && (hapticsSetting == nil || [hapticsSetting boolValue])) {
        if (_pressHaptic == nil) {
            _pressHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        }
        [_pressHaptic impactOccurredWithIntensity:0.8];
        [_pressHaptic prepare];
    }
#endif
    return updated || stickTouch;
}

- (BOOL)handleTouchUpEvent:touches {
    if (_editing) {
        [self handleEditTouches:touches phase:UITouchPhaseEnded];
        return YES;
    }
    BOOL updated = false;
    BOOL touched = false;
    for (UITouch* touch in touches) {
        if (touch == _aTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:A_FLAG];
            _aTouch = nil;
            updated = true;
        } else if (touch == _bTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:B_FLAG];
            _bTouch = nil;
            updated = true;
        } else if (touch == _xTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:X_FLAG];
            _xTouch = nil;
            updated = true;
        } else if (touch == _yTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:Y_FLAG];
            _yTouch = nil;
            updated = true;
        } else if (touch == _dpadTouch) {
            [_controllerSupport clearButtonFlag:_controller
                                          flags:UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG];
            _dpadTouch = nil;
            updated = true;
        } else if (touch == _startTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:PLAY_FLAG];
            _startTouch = nil;
            updated = true;
        } else if (touch == _selectTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:BACK_FLAG];
            _selectTouch = nil;
            updated = true;
        } else if (touch == _l1Touch) {
            [_controllerSupport clearButtonFlag:_controller flags:LB_FLAG];
            _l1Touch = nil;
            updated = true;
        } else if (touch == _r1Touch) {
            [_controllerSupport clearButtonFlag:_controller flags:RB_FLAG];
            _r1Touch = nil;
            updated = true;
        } else if (touch == _l2Touch) {
            [_controllerSupport updateLeftTrigger:_controller left:0];
            _l2Touch = nil;
            updated = true;
        } else if (touch == _r2Touch) {
            [_controllerSupport updateRightTrigger:_controller right:0];
            _r2Touch = nil;
            updated = true;
        } else if (touch == _lsTouch) {
            _leftStick.frame = CGRectMake(LS_CENTER_X - STICK_INNER_SIZE / 2, LS_CENTER_Y - STICK_INNER_SIZE / 2, STICK_INNER_SIZE, STICK_INNER_SIZE);
            [_controllerSupport updateLeftStick:_controller x:0 y:0];
            [_controllerSupport clearButtonFlag:_controller flags:LS_CLK_FLAG];
            l3TouchStart = [NSDate date];
            _lsTouch = nil;
            updated = true;
        } else if (touch == _rsTouch) {
            _rightStick.frame = CGRectMake(RS_CENTER_X - STICK_INNER_SIZE / 2, RS_CENTER_Y - STICK_INNER_SIZE / 2, STICK_INNER_SIZE, STICK_INNER_SIZE);
            [_controllerSupport updateRightStick:_controller x:0 y:0];
            [_controllerSupport clearButtonFlag:_controller flags:RS_CLK_FLAG];
            r3TouchStart = [NSDate date];
            _rsTouch = nil;
            updated = true;
        }
        else if (touch == _l3Touch) {
            _l3Touch = nil;
            touched = true;
        }
        else if (touch == _r3Touch) {
            _r3Touch = nil;
            touched = true;
        }
        if ([_deadTouches containsObject:touch]) {
            [_deadTouches removeObject:touch];
            updated = true;
        }
    }
    if (updated) {
        [_controllerSupport updateFinished:_controller];
    }
    
    return updated || touched;
}

- (BOOL) isInDeadZone:(UITouch*) touch {
    // Dynamically evaluate deadzones based on the controls
    // on screen at the time
    if (_leftButton.superlayer != nil && [self isDpadDeadZone:touch]) {
        return true;
    }
    else if (_aButton.superlayer != nil && [self isAbxyDeadZone:touch]) {
        return true;
    }
    else if (_l2Button.superlayer != nil && [self isTriggerDeadZone:touch]) {
        return true;
    }
    else if (_l1Button.superlayer != nil && [self isBumperDeadZone:touch]) {
        return true;
    }
    else if (_startButton.superlayer != nil && [self isStartSelectDeadZone:touch]) {
        return true;
    }
    else if (_l3Button.superlayer != nil && [self isL3R3DeadZone:touch]) {
        return true;
    }
    else if (_leftStickBackground.superlayer != nil && [self isStickDeadZone:touch]) {
        return true;
    }
    
    return false;
}

- (BOOL) isDpadDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_upButton.frame.origin.y
                       endX:_rightButton.frame.origin.x + _rightButton.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isAbxyDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_xButton.frame.origin.x
                     startY:_yButton.frame.origin.y
                       endX:_view.frame.origin.x + _view.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isBumperDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_l2Button.frame.origin.y + _l2Button.frame.size.height
                       endX:_l1Button.frame.origin.x + _l1Button.frame.size.width
                       endY:_upButton.frame.origin.y]
    || [self isDeadZone:touch
                 startX:_r2Button.frame.origin.x
                 startY:_r2Button.frame.origin.y + _r2Button.frame.size.height
                   endX:_view.frame.origin.x + _view.frame.size.width
                   endY:_yButton.frame.origin.y];
}

- (BOOL) isTriggerDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_l2Button.frame.origin.y
                       endX:_l2Button.frame.origin.x + _l2Button.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_r2Button.frame.origin.x
                 startY:_r2Button.frame.origin.y
                   endX:_view.frame.origin.x + _view.frame.size.width
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isL3R3DeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_l3Button.frame.origin.y
                       endX:_view.frame.origin.x
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_r3Button.frame.origin.x
                 startY:_r3Button.frame.origin.y
                   endX:_view.frame.origin.x + _view.frame.size.width
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isStartSelectDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_startButton.frame.origin.x
                     startY:_startButton.frame.origin.y
                       endX:_view.frame.origin.x + _view.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_view.frame.origin.x
                 startY:_selectButton.frame.origin.y
                   endX:_selectButton.frame.origin.x + _selectButton.frame.size.width
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isStickDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_leftStickBackground.frame.origin.x - 15
                     startY:_leftStickBackground.frame.origin.y - 15
                       endX:_leftStickBackground.frame.origin.x + _leftStickBackground.frame.size.width + 15
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_rightStickBackground.frame.origin.x - 15
                 startY:_rightStickBackground.frame.origin.y - 15
                   endX:_rightStickBackground.frame.origin.x + _rightStickBackground.frame.size.width + 15
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isDeadZone:(UITouch*) touch startX:(float)deadZoneStartX startY:(float)deadZoneStartY endX:(float)deadZoneEndX endY:(float)deadZoneEndY {
    deadZoneStartX -= DEAD_ZONE_PADDING;
    deadZoneStartY -= DEAD_ZONE_PADDING;
    deadZoneEndX += DEAD_ZONE_PADDING;
    deadZoneEndY += DEAD_ZONE_PADDING;
    
    CGPoint touchLocation = [touch locationInView:_view];
    return (touchLocation.x > deadZoneStartX && touchLocation.x < deadZoneEndX
            && touchLocation.y > deadZoneStartY && touchLocation.y < deadZoneEndY);
    
}

@end
