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

// Buttons a finger can slide between: A, B, X, Y, Start, Select, L1, R1, L2, R2
#define MN_SLIDE_COUNT 10

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
    
    UITouch* _dpadTouch;
    UITouch* _lsTouch;
    UITouch* _rsTouch;
    UITouch* _r3Touch;
    UITouch* _l3Touch;
    // Touches holding a face, shoulder, Start or Select button -> index into the slide table.
    // A finger can roll from one of these onto another.
    NSMapTable<UITouch*, NSNumber*>* _buttonTouches;
    BOOL _slideHeld[MN_SLIDE_COUNT];
    // Buttons set to tap-to-toggle that are latched down, and the touches that tapped them
    BOOL _latched[MN_SLIDE_COUNT];
    NSMutableSet<UITouch*>* _latchTouches;
    BOOL _pressHighlight;
    
    NSDate* l3TouchStart;
    NSDate* r3TouchStart;
    
    BOOL l3Set;
    BOOL r3Set;
    
    BOOL _iPad;
    CGRect _controlArea;
    // Layout editor: the layout for the current posture (see OnScreenControls.h for its format)
    NSString* _appID;
    NSString* _layoutPosture;
    NSMutableDictionary<NSString*, id>* _layout;
    NSMutableArray<NSDictionary*>* _undoStack;
    BOOL _editing;
    NSString* _selected;
    NSString* _dragGroup;
    UITouch* _dragTouch;
    CGPoint _dragLast;
    CGPoint _dragRaw;          // where the finger has taken the control, before snapping
    CGPoint _dragStartCenter;
    CGPoint _dragStartOffset;
    BOOL _dragMoved;
    CAShapeLayer* _selectionLayer;
    CAShapeLayer* _guideLayer;
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
    _buttonTouches = [NSMapTable strongToStrongObjectsMapTable];
    _latchTouches = [NSMutableSet set];
    id snap = [NSUserDefaults.standardUserDefaults objectForKey:@"mnOSCSnap"];
    _snapToGuides = snap == nil || [snap boolValue];
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
    if (level != _level) {
        // Hidden controls can't be tapped to release a latched button (a controller connected,
        // or the tabletop deck took over)
        [self releaseAllInput];
    }
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
    // Settings › Input › Highlight pressed buttons (on unless turned off)
    id highlight = [NSUserDefaults.standardUserDefaults objectForKey:@"mnOSCPressHighlight"];
    _pressHighlight = highlight == nil || [highlight boolValue];
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
    [self applyControlStyles];
    [self updateEditorOverlays];
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

// Judged on the whole screen: the inset control area of a phone in landscape (Dynamic Island
// insets on both sides, edge strips) is squarer than 1.8 too, and the square layout, which runs
// to the screen edges, would put L1 and the D-pad under the island
- (BOOL) isSquare {
    CGSize screen = _view.bounds.size;
    return screen.height > 0 && screen.width / screen.height < 1.8;
}

- (void) setupComplexControls
{
    if (!_iPad && [self isSquare]) {
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

#pragma mark - Button presses

static const int MN_SLIDE_FLAGS[MN_SLIDE_COUNT] = { A_FLAG, B_FLAG, X_FLAG, Y_FLAG, PLAY_FLAG, BACK_FLAG, LB_FLAG, RB_FLAG,
                                                    0 /* L2 */, 0 /* R2 */ };

- (CALayer*) slideLayer:(int)i {
    switch (i) {
        case 0: return _aButton;
        case 1: return _bButton;
        case 2: return _xButton;
        case 3: return _yButton;
        case 4: return _startButton;
        case 5: return _selectButton;
        case 6: return _l1Button;
        case 7: return _r1Button;
        case 8: return _l2Button;
        default: return _r2Button;
    }
}

// The layout group each slide-table button belongs to
static NSString* const MN_SLIDE_GROUPS[MN_SLIDE_COUNT] = { @"abxy", @"abxy", @"abxy", @"abxy", @"start", @"select",
                                                          @"l1", @"r1", @"l2", @"r2" };

// The slide-table button under a point, or -1
- (int) slideButtonAt:(CGPoint)p {
    for (int i = 0; i < MN_SLIDE_COUNT; i++) {
        CALayer* layer = [self slideLayer:i];
        if (layer.superlayer != nil && CGRectContainsPoint(layer.frame, p)) {
            return i;
        }
    }
    return -1;
}

// Presses and releases slide-table buttons to match the touches holding them: a button is down
// while any finger is on it. Returns whether anything changed; counts the new presses.
- (BOOL) syncSlideButtons:(NSInteger*)newlyPressed {
    BOOL want[MN_SLIDE_COUNT];
    memcpy(want, _latched, sizeof(want));
    for (UITouch* touch in _buttonTouches) {
        want[[_buttonTouches objectForKey:touch].intValue] = YES;
    }
    BOOL changed = NO;
    for (int i = 0; i < MN_SLIDE_COUNT; i++) {
        if (want[i] == _slideHeld[i]) {
            continue;
        }
        _slideHeld[i] = want[i];
        changed = YES;
        if (i == 8) {
            [_controllerSupport updateLeftTrigger:_controller left:want[i] ? 0xFF : 0];
        }
        else if (i == 9) {
            [_controllerSupport updateRightTrigger:_controller right:want[i] ? 0xFF : 0];
        }
        else if (want[i]) {
            [_controllerSupport setButtonFlag:_controller flags:MN_SLIDE_FLAGS[i]];
        }
        else {
            [_controllerSupport clearButtonFlag:_controller flags:MN_SLIDE_FLAGS[i]];
        }
        [self setLayer:[self slideLayer:i] highlighted:want[i]];
        if (want[i] && newlyPressed != NULL) {
            (*newlyPressed)++;
        }
    }
    return changed;
}

- (CALayer*) dpadLayerAt:(CGPoint)p {
    for (CALayer* layer in @[_upButton, _downButton, _leftButton, _rightButton]) {
        if (layer.superlayer != nil && CGRectContainsPoint(layer.frame, p)) {
            return layer;
        }
    }
    return nil;
}

- (int) flagForDpadLayer:(CALayer*)layer {
    return layer == _upButton ? UP_FLAG : layer == _downButton ? DOWN_FLAG : layer == _leftButton ? LEFT_FLAG : RIGHT_FLAG;
}

- (void) highlightDpad:(CALayer*)pressed {
    for (CALayer* layer in @[_upButton, _downButton, _leftButton, _rightButton]) {
        [self setLayer:layer highlighted:layer == pressed];
    }
}

// A glow in the accent colour around a held control, at full opacity even in a faded layout
- (void) setLayer:(CALayer*)layer highlighted:(BOOL)on {
    on = on && _pressHighlight;
    if (!on && layer.shadowOpacity == 0) {
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (on) {
        CGRect glow = CGRectInset(layer.bounds, -5, -5);
        layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:glow
                                                      cornerRadius:MIN(glow.size.width, glow.size.height) / 2].CGPath;
        layer.shadowColor = [UIColor colorWithRed:0x8A / 255.0 green:0xB4 / 255.0 blue:1 alpha:1].CGColor; // Theme.accent
        layer.shadowOffset = CGSizeZero;
        layer.shadowRadius = 6;
        layer.shadowOpacity = 0.9;
        layer.opacity = 1;
    }
    else {
        layer.shadowOpacity = 0;
        NSNumber* base = [layer valueForKey:@"mnBaseOpacity"];
        layer.opacity = base != nil ? base.floatValue : 1;
    }
    [CATransaction commit];
}

- (void) pressHaptic {
#if !TARGET_OS_TV
    // A tap you can feel for every button press
    // Settings › Input › Haptics on button presses (on unless turned off)
    id hapticsSetting = [[NSUserDefaults standardUserDefaults] objectForKey:@"mnHapticsEnabled"];
    if (hapticsSetting != nil && ![hapticsSetting boolValue]) {
        return;
    }
    if (_pressHaptic == nil) {
        _pressHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    }
    [_pressHaptic impactOccurredWithIntensity:0.8];
    [_pressHaptic prepare];
#endif
}

#pragma mark - Layout editor

// Movable groups and the statics that position them; the layers say whether it's on screen
static NSString* const MN_GROUPS[] = { @"dpad", @"abxy", @"ls", @"rs", @"start", @"select",
                                       @"l1", @"l2", @"r1", @"r2", @"l3", @"r3" };
static NSString* const MN_GROUP_NAMES[] = { @"D-pad", @"A B X Y", @"Left stick", @"Right stick", @"Start", @"Select",
                                            @"L1", @"L2", @"R1", @"R2", @"L3", @"R3" };
static float* const MN_GROUP_X[] = { &D_PAD_CENTER_X, &BUTTON_CENTER_X, &LS_CENTER_X, &RS_CENTER_X, &START_X, &SELECT_X,
                                     &L1_X, &L2_X, &R1_X, &R2_X, &L3_X, &R3_X };
static float* const MN_GROUP_Y[] = { &D_PAD_CENTER_Y, &BUTTON_CENTER_Y, &LS_CENTER_Y, &RS_CENTER_Y, &START_Y, &SELECT_Y,
                                     &L1_Y, &L2_Y, &R1_Y, &R2_Y, &L3_Y, &R3_Y };
static const int MN_GROUP_COUNT = sizeof(MN_GROUPS) / sizeof(MN_GROUPS[0]);

static int MNGroupIndex(NSString* name) {
    for (int i = 0; i < MN_GROUP_COUNT; i++) {
        if ([MN_GROUPS[i] isEqualToString:name]) {
            return i;
        }
    }
    return -1;
}

// One control's entry in a layout: @[dx, dy] (the original format), @[dx, dy, scale, opacity,
// hidden] or @[dx, dy, scale, opacity, hidden, toggle]. Entries come from saved layouts and
// imported files, so anything odd reads as the default.
typedef struct {
    CGPoint offset;
    CGFloat scale;
    CGFloat opacity;
    BOOL hidden;
    BOOL toggle; // tap to latch, tap again to release
} MNControlStyle;

static const CGFloat MN_MIN_SCALE = 0.5;
static const CGFloat MN_MAX_SCALE = 2;
static const CGFloat MN_MIN_OPACITY = 0.15;
static const CGFloat MN_SNAP_DISTANCE = 8;
static const NSUInteger MN_UNDO_LIMIT = 50;

static void MNSnapAxis(CGFloat value, CGFloat candidate, CGFloat* best, CGFloat* snapped) {
    if (fabs(candidate - value) < *best) {
        *best = fabs(candidate - value);
        *snapped = candidate;
    }
}

static CGFloat MNClamp(double v, CGFloat lo, CGFloat hi, CGFloat fallback) {
    return isfinite(v) ? MIN(MAX(v, lo), hi) : fallback;
}

static MNControlStyle MNStyleFromEntry(id entry) {
    MNControlStyle style = { CGPointZero, 1, 1, NO, NO };
    if (![entry isKindOfClass:NSArray.class] || [entry count] < 2) {
        return style;
    }
    for (id value in entry) {
        if (![value isKindOfClass:NSNumber.class]) {
            return style;
        }
    }
    NSArray<NSNumber*>* a = entry;
    style.offset = CGPointMake(MNClamp(a[0].doubleValue, -4000, 4000, 0), MNClamp(a[1].doubleValue, -4000, 4000, 0));
    if (a.count >= 5) {
        style.scale = MNClamp(a[2].doubleValue, MN_MIN_SCALE, MN_MAX_SCALE, 1);
        style.opacity = MNClamp(a[3].doubleValue, MN_MIN_OPACITY, 1, 1);
        style.hidden = a[4].boolValue;
    }
    if (a.count >= 6) {
        style.toggle = a[5].boolValue;
    }
    return style;
}

static id MNEntryFromStyle(MNControlStyle s) {
    if (s.toggle) {
        return @[ @(s.offset.x), @(s.offset.y), @(s.scale), @(s.opacity), @(s.hidden), @YES ];
    }
    if (s.scale == 1 && s.opacity == 1 && !s.hidden) {
        return CGPointEqualToPoint(s.offset, CGPointZero) ? nil : @[ @(s.offset.x), @(s.offset.y) ];
    }
    return @[ @(s.offset.x), @(s.offset.y), @(s.scale), @(s.opacity), @(s.hidden) ];
}

+ (NSArray<NSString*>*) controlIds {
    return [NSArray arrayWithObjects:MN_GROUPS count:MN_GROUP_COUNT];
}

- (NSArray<CALayer*>*) layersForGroup:(int)i {
    switch (i) {
        case 0: return @[_upButton, _downButton, _leftButton, _rightButton];
        case 1: return @[_aButton, _bButton, _xButton, _yButton];
        case 2: return @[_leftStickBackground, _leftStick];
        case 3: return @[_rightStickBackground, _rightStick];
        case 4: return @[_startButton];
        case 5: return @[_selectButton];
        case 6: return @[_l1Button];
        case 7: return @[_l2Button];
        case 8: return @[_r1Button];
        case 9: return @[_r2Button];
        case 10: return @[_l3Button];
        default: return @[_r3Button];
    }
}

// The on-screen extent of a group, or CGRectNull when it isn't shown
- (CGRect) frameForGroup:(int)i {
    CGRect frame = CGRectNull;
    for (CALayer* layer in [self layersForGroup:i]) {
        if (layer.superlayer != nil) {
            frame = CGRectUnion(frame, layer.frame);
        }
    }
    return frame;
}

// Layouts are saved per posture (the folded outer display, a phone in landscape, the roomy
// inner display), since one arrangement never fits all three, and optionally per game.
- (NSString*) currentPosture {
    if (_iPad) {
        return @"roomy";
    }
    return [self isSquare] ? @"square" : @"wide";
}

- (NSString*) layoutKeyForApp:(NSString*)appID {
    return appID != nil ? [NSString stringWithFormat:@"mnOSCLayout.%@.%@", appID, [self currentPosture]]
                        : [NSString stringWithFormat:@"mnOSCLayout.%@", [self currentPosture]];
}

- (void) loadLayout {
    _layoutPosture = [self currentPosture];
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary* saved = (_appID != nil ? [defaults dictionaryForKey:[self layoutKeyForApp:_appID]] : nil)
                          ?: [defaults dictionaryForKey:[self layoutKeyForApp:nil]];
    _layout = saved != nil ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    [_undoStack removeAllObjects];
    [self releaseLatches];
}

- (NSMutableDictionary<NSString*, id>*) layout {
    if (_layout == nil || ![_layoutPosture isEqualToString:[self currentPosture]]) {
        [self loadLayout];
    }
    return _layout;
}

- (MNControlStyle) styleForGroup:(NSString*)name {
    return MNStyleFromEntry([self layout][name]);
}

- (BOOL) isToggleSlide:(int)i {
    return [self styleForGroup:MN_SLIDE_GROUPS[i]].toggle;
}

- (void) setStyle:(MNControlStyle)style forGroup:(NSString*)name {
    [self layout][name] = MNEntryFromStyle(style);
}

- (void) applyLayoutOffsets {
    CGRect b = _view.bounds;
    for (int i = 0; i < MN_GROUP_COUNT; i++) {
        CGPoint d = [self styleForGroup:MN_GROUPS[i]].offset;
        if (CGPointEqualToPoint(d, CGPointZero)) {
            continue;
        }
        *MN_GROUP_X[i] = MIN(MAX(*MN_GROUP_X[i] + d.x, CGRectGetMinX(b)), CGRectGetMaxX(b));
        *MN_GROUP_Y[i] = MIN(MAX(*MN_GROUP_Y[i] + d.y, CGRectGetMinY(b)), CGRectGetMaxY(b));
    }
}

// Size, opacity and hiding, after the draw methods have placed every layer at its natural size.
// A group scales about its centre, so a cluster keeps its shape. While editing, hidden controls
// stay on screen, faint, so they can be selected and shown again.
- (void) applyControlStyles {
    CGFloat global = self.globalOpacity;
    for (int i = 0; i < MN_GROUP_COUNT; i++) {
        MNControlStyle style = [self styleForGroup:MN_GROUPS[i]];
        CGPoint c = CGPointMake(*MN_GROUP_X[i], *MN_GROUP_Y[i]);
        for (CALayer* layer in [self layersForGroup:i]) {
            if (layer.superlayer == nil) {
                continue;
            }
            if (style.hidden && !_editing) {
                [layer removeFromSuperlayer];
                continue;
            }
            if (style.scale != 1) {
                CGRect f = layer.frame;
                layer.frame = CGRectMake(c.x + (f.origin.x - c.x) * style.scale, c.y + (f.origin.y - c.y) * style.scale,
                                         f.size.width * style.scale, f.size.height * style.scale);
                layer.cornerRadius *= style.scale;
            }
            CGFloat base = style.opacity * global * (style.hidden ? 0.3 : 1);
            [layer setValue:@(base) forKey:@"mnBaseOpacity"];
            if (layer.shadowOpacity > 0) {
                [self setLayer:layer highlighted:YES]; // still held: refit the glow
            }
            else {
                layer.opacity = base;
            }
        }
    }
}

- (void) notifyEditor {
    if (self.editorChanged != nil) {
        self.editorChanged();
    }
}

- (void) refreshLayout {
    if (_visible) {
        [self updateControls];
    }
    [self notifyEditor];
}

- (void) setEditing:(BOOL)editing {
    if (editing && !_editing) {
        // Touches go to the editor from now on, so their lifts would never release what they hold
        [self releaseAllInput];
    }
    _editing = editing;
    _dragGroup = nil;
    _dragTouch = nil;
    _selected = nil;
    if (_undoStack == nil) {
        _undoStack = [NSMutableArray array];
    }
    [_undoStack removeAllObjects];
    if (!editing) {
        // Leaving without saving puts the saved layout back
        [self loadLayout];
        self.editorChanged = nil;
        [_guideLayer removeFromSuperlayer];
    }
    [self refreshLayout];
}

- (BOOL) isEditing {
    return _editing;
}

- (void) resetLayout {
    [self pushUndo];
    // Widgets aren't controls: they stay
    id widgets = [self layout][@"widgets"];
    [[self layout] removeAllObjects];
    [self layout][@"widgets"] = widgets;
    [self releaseLatches];
    [self refreshLayout];
}

- (void) saveLayoutForThisGame:(BOOL)thisGame {
    NSDictionary* plist = [[self layout] copy];
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

- (NSString*) selectedControl {
    return _selected;
}

- (void) selectControl:(NSString*)control {
    _selected = control != nil && MNGroupIndex(control) >= 0 ? control : nil;
    [self refreshLayout];
}

- (NSString*) displayNameForControl:(NSString*)control {
    int i = MNGroupIndex(control);
    return i >= 0 ? MN_GROUP_NAMES[i] : control;
}

- (CGFloat) scaleForControl:(NSString*)control {
    return [self styleForGroup:control].scale;
}

- (void) setScale:(CGFloat)scale forControl:(NSString*)control {
    MNControlStyle style = [self styleForGroup:control];
    style.scale = MNClamp(scale, MN_MIN_SCALE, MN_MAX_SCALE, 1);
    [self setStyle:style forGroup:control];
    [self refreshLayout];
}

- (CGFloat) opacityForControl:(NSString*)control {
    return [self styleForGroup:control].opacity;
}

- (void) setOpacity:(CGFloat)opacity forControl:(NSString*)control {
    MNControlStyle style = [self styleForGroup:control];
    style.opacity = MNClamp(opacity, MN_MIN_OPACITY, 1, 1);
    [self setStyle:style forGroup:control];
    [self refreshLayout];
}

- (BOOL) isControlHidden:(NSString*)control {
    return [self styleForGroup:control].hidden;
}

- (void) setHidden:(BOOL)hidden forControl:(NSString*)control {
    [self pushUndo];
    MNControlStyle style = [self styleForGroup:control];
    style.hidden = hidden;
    [self setStyle:style forGroup:control];
    [self refreshLayout];
}

- (BOOL) controlSupportsToggle:(NSString*)control {
    for (int i = 0; i < MN_SLIDE_COUNT; i++) {
        if ([MN_SLIDE_GROUPS[i] isEqualToString:control]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL) isControlToggle:(NSString*)control {
    return [self styleForGroup:control].toggle;
}

- (void) setToggle:(BOOL)toggle forControl:(NSString*)control {
    [self pushUndo];
    MNControlStyle style = [self styleForGroup:control];
    style.toggle = toggle && [self controlSupportsToggle:control];
    [self setStyle:style forGroup:control];
    [self releaseLatches];
    [self refreshLayout];
}

// Lets go of everything the controls hold on the host: fingers on buttons, the d-pad and sticks,
// latched buttons and L3/R3. Used when touches stop reaching the controls (editing starts, the
// controls are hidden, the app leaves the foreground); the fingers' later lifts then find nothing.
- (void) releaseAllInput {
    BOOL anyLatched = NO;
    for (int i = 0; i < MN_SLIDE_COUNT; i++) {
        anyLatched = anyLatched || _latched[i];
    }
    if (_buttonTouches.count == 0 && !anyLatched && _dpadTouch == nil && _lsTouch == nil && _rsTouch == nil && !l3Set && !r3Set) {
        // Nothing held: in particular, don't bring back a virtual pad the host was told to drop
        [_latchTouches removeAllObjects];
        [_deadTouches removeAllObjects];
        _l3Touch = _r3Touch = nil;
        return;
    }
    [_buttonTouches removeAllObjects];
    [_latchTouches removeAllObjects];
    [_deadTouches removeAllObjects];
    memset(_latched, 0, sizeof(_latched));
    [self syncSlideButtons:NULL];

    [self highlightDpad:nil];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _leftStick.position = CGPointMake(LS_CENTER_X, LS_CENTER_Y);
    _rightStick.position = CGPointMake(RS_CENTER_X, RS_CENTER_Y);
    [CATransaction commit];
    [self setLayer:_leftStick highlighted:NO];
    [self setLayer:_rightStick highlighted:NO];
    _l3Button.borderWidth = 0.0f;
    _r3Button.borderWidth = 0.0f;
    l3Set = r3Set = NO;
    _dpadTouch = _lsTouch = _rsTouch = _l3Touch = _r3Touch = nil;

    [_controllerSupport clearButtonFlag:_controller
                                  flags:UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG | LS_CLK_FLAG | RS_CLK_FLAG];
    [_controllerSupport updateLeftStick:_controller x:0 y:0];
    [_controllerSupport updateRightStick:_controller x:0 y:0];
    [_controllerSupport updateFinished:_controller];
}

// Lets go of every latched button, e.g. when a button stops being tap-to-toggle
- (void) releaseLatches {
    memset(_latched, 0, sizeof(_latched));
    if ([self syncSlideButtons:NULL]) {
        [_controllerSupport updateFinished:_controller];
    }
}

- (void) resetControl:(NSString*)control {
    [self pushUndo];
    [[self layout] removeObjectForKey:control];
    [self releaseLatches];
    [self refreshLayout];
}

- (CGFloat) globalOpacity {
    id value = [self layout][@"opacity"];
    return [value isKindOfClass:NSNumber.class] ? MNClamp([value doubleValue], MN_MIN_OPACITY, 1, 1) : 1;
}

- (void) setGlobalOpacity:(CGFloat)opacity {
    opacity = MNClamp(opacity, MN_MIN_OPACITY, 1, 1);
    [self layout][@"opacity"] = opacity < 1 ? @(opacity) : nil;
    [self refreshLayout];
}

- (void) setSnapToGuides:(BOOL)snap {
    _snapToGuides = snap;
    [NSUserDefaults.standardUserDefaults setBool:snap forKey:@"mnOSCSnap"];
    [self notifyEditor];
}

- (void) pushUndo {
    if (_undoStack == nil) {
        _undoStack = [NSMutableArray array];
    }
    [_undoStack addObject:[[self layout] copy]];
    if (_undoStack.count > MN_UNDO_LIMIT) {
        [_undoStack removeObjectAtIndex:0];
    }
    [self notifyEditor];
}

- (BOOL) canUndo {
    return _undoStack.count > 0;
}

- (void) undo {
    if (_undoStack.count == 0) {
        return;
    }
    _layout = [_undoStack.lastObject mutableCopy];
    [_undoStack removeLastObject];
    [self releaseLatches];
    [self refreshLayout];
}

- (NSDictionary<NSString*, id>*) layoutDictionary {
    return [[self layout] copy];
}

- (void) applyLayoutDictionary:(NSDictionary<NSString*, id>*)layout {
    [self pushUndo];
    _layout = [layout mutableCopy];
    [self releaseLatches];
    [self refreshLayout];
}

- (void) setLayoutValue:(id)value forKey:(NSString*)key {
    [self layout][key] = value;
    [self notifyEditor];
}

- (NSArray<NSValue*>*) controlCenters {
    NSMutableArray<NSValue*>* centers = [NSMutableArray array];
    for (int i = 0; i < MN_GROUP_COUNT; i++) {
        if (!CGRectIsNull([self frameForGroup:i])) {
            [centers addObject:[NSValue valueWithCGPoint:CGPointMake(*MN_GROUP_X[i], *MN_GROUP_Y[i])]];
        }
    }
    return centers;
}

// The dashed outline around the selected control while editing
- (void) updateEditorOverlays {
    int i = _editing && _selected != nil ? MNGroupIndex(_selected) : -1;
    CGRect frame = i >= 0 ? [self frameForGroup:i] : CGRectNull;
    if (CGRectIsNull(frame)) {
        [_selectionLayer removeFromSuperlayer];
        return;
    }
    if (_selectionLayer == nil) {
        _selectionLayer = [CAShapeLayer layer];
        _selectionLayer.fillColor = UIColor.clearColor.CGColor;
        _selectionLayer.strokeColor = [UIColor colorWithRed:0x8A / 255.0 green:0xB4 / 255.0 blue:1 alpha:1].CGColor;
        _selectionLayer.lineWidth = 1.5;
        _selectionLayer.lineDashPattern = @[ @6, @4 ];
    }
    _selectionLayer.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(frame, -6, -6) cornerRadius:10].CGPath;
    [_view.layer addSublayer:_selectionLayer];
}

// Alignment guides while dragging: a line across the view on each axis that snapped (NAN: none)
- (void) drawGuidesX:(CGFloat)x y:(CGFloat)y {
    if (isnan(x) && isnan(y)) {
        [_guideLayer removeFromSuperlayer];
        return;
    }
    if (_guideLayer == nil) {
        _guideLayer = [CAShapeLayer layer];
        _guideLayer.strokeColor = [UIColor colorWithRed:0x8A / 255.0 green:0xB4 / 255.0 blue:1 alpha:0.7].CGColor;
        _guideLayer.lineWidth = 1;
        _guideLayer.lineDashPattern = @[ @4, @4 ];
    }
    CGRect b = _view.bounds;
    UIBezierPath* path = [UIBezierPath bezierPath];
    if (!isnan(x)) {
        [path moveToPoint:CGPointMake(x, CGRectGetMinY(b))];
        [path addLineToPoint:CGPointMake(x, CGRectGetMaxY(b))];
    }
    if (!isnan(y)) {
        [path moveToPoint:CGPointMake(CGRectGetMinX(b), y)];
        [path addLineToPoint:CGPointMake(CGRectGetMaxX(b), y)];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _guideLayer.path = path.CGPath;
    [_view.layer addSublayer:_guideLayer];
    [CATransaction commit];
}

// Snaps a dragged group's centre to the screen's centre lines, to another control's row or
// column, or to the mirror of another control (so pairs like L1 and R1 sit symmetrically).
- (CGPoint) snapPoint:(CGPoint)p forGroup:(int)g guideX:(CGFloat*)guideX guideY:(CGFloat*)guideY {
    CGRect b = _view.bounds;
    CGFloat bestX = MN_SNAP_DISTANCE, bestY = MN_SNAP_DISTANCE;
    *guideX = NAN;
    *guideY = NAN;
    MNSnapAxis(p.x, CGRectGetMidX(b), &bestX, guideX);
    MNSnapAxis(p.y, CGRectGetMidY(b), &bestY, guideY);
    for (int i = 0; i < MN_GROUP_COUNT; i++) {
        if (i == g || CGRectIsNull([self frameForGroup:i])) {
            continue;
        }
        MNSnapAxis(p.x, *MN_GROUP_X[i], &bestX, guideX);
        MNSnapAxis(p.x, CGRectGetMinX(b) + CGRectGetMaxX(b) - *MN_GROUP_X[i], &bestX, guideX);
        MNSnapAxis(p.y, *MN_GROUP_Y[i], &bestY, guideY);
    }
    // And to the on-screen widgets, whose centres are saved as fractions of this view
    // (MoonlightNext/Widgets/WidgetModel.swift); the widgets snap to the controls the same way
    id widgets = [self layout][@"widgets"];
    if ([widgets isKindOfClass:NSArray.class]) {
        for (id widget in (NSArray*)widgets) {
            if (![widget isKindOfClass:NSDictionary.class]) {
                continue;
            }
            id x = widget[@"x"], y = widget[@"y"];
            if (![x isKindOfClass:NSNumber.class] || ![y isKindOfClass:NSNumber.class]) {
                continue;
            }
            CGFloat wx = CGRectGetMinX(b) + [x doubleValue] * CGRectGetWidth(b);
            CGFloat wy = CGRectGetMinY(b) + [y doubleValue] * CGRectGetHeight(b);
            MNSnapAxis(p.x, wx, &bestX, guideX);
            MNSnapAxis(p.x, CGRectGetMinX(b) + CGRectGetMaxX(b) - wx, &bestX, guideX);
            MNSnapAxis(p.y, wy, &bestY, guideY);
        }
    }
    return CGPointMake(isnan(*guideX) ? p.x : *guideX, isnan(*guideY) ? p.y : *guideY);
}

// The group a touch at p means: the one it lands on, else the nearest within a thumb's reach
- (int) groupNear:(CGPoint)p {
    int best = -1;
    CGFloat bestScore = CGFLOAT_MAX;
    for (int i = 0; i < MN_GROUP_COUNT; i++) {
        CGRect r = [self frameForGroup:i];
        if (CGRectIsNull(r)) {
            continue;
        }
        CGFloat dx = MAX(MAX(CGRectGetMinX(r) - p.x, 0), p.x - CGRectGetMaxX(r));
        CGFloat dy = MAX(MAX(CGRectGetMinY(r) - p.y, 0), p.y - CGRectGetMaxY(r));
        CGFloat edge = hypot(dx, dy);
        if (edge > 24) {
            continue;
        }
        CGFloat score = edge * 10 + hypot(p.x - CGRectGetMidX(r), p.y - CGRectGetMidY(r));
        if (score < bestScore) {
            bestScore = score;
            best = i;
        }
    }
    return best;
}

// While editing, a touch selects the control under it and drags it; nothing reaches the PC.
// Touching empty space clears the selection.
- (void) handleEditTouches:(NSSet*)touches phase:(UITouchPhase)phase {
    for (UITouch* touch in touches) {
        CGPoint p = [touch locationInView:_view];
        if (phase == UITouchPhaseBegan && _dragTouch == nil) {
            int g = [self groupNear:p];
            _selected = g >= 0 ? MN_GROUPS[g] : nil;
            if (g >= 0) {
                _dragGroup = MN_GROUPS[g];
                _dragTouch = touch;
                _dragLast = p;
                _dragStartCenter = _dragRaw = CGPointMake(*MN_GROUP_X[g], *MN_GROUP_Y[g]);
                _dragStartOffset = [self styleForGroup:_dragGroup].offset;
                _dragMoved = NO;
            }
            [self refreshLayout];
        }
        else if (touch == _dragTouch && phase == UITouchPhaseMoved) {
            if (!_dragMoved) {
                // A tap only selects: ignore the wobble of a finger landing
                if (hypot(p.x - _dragLast.x, p.y - _dragLast.y) < 4) {
                    continue;
                }
                [self pushUndo];
                _dragMoved = YES;
            }
            _dragRaw.x += p.x - _dragLast.x;
            _dragRaw.y += p.y - _dragLast.y;
            _dragLast = p;
            CGFloat guideX = NAN, guideY = NAN;
            CGPoint target = _snapToGuides ? [self snapPoint:_dragRaw forGroup:MNGroupIndex(_dragGroup) guideX:&guideX guideY:&guideY]
                                           : _dragRaw;
            MNControlStyle style = [self styleForGroup:_dragGroup];
            style.offset = CGPointMake(_dragStartOffset.x + target.x - _dragStartCenter.x,
                                       _dragStartOffset.y + target.y - _dragStartCenter.y);
            [self setStyle:style forGroup:_dragGroup];
            [self updateControls];
            [self drawGuidesX:guideX y:guideY];
        }
        else if (touch == _dragTouch) {
            _dragTouch = nil;
            _dragGroup = nil;
            [self drawGuidesX:NAN y:NAN];
            [self notifyEditor];
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
    // Each stick's own size: the editor can scale them
    float rsHalf = _rightStickBackground.bounds.size.width / 2;
    float lsHalf = _leftStickBackground.bounds.size.width / 2;
    float rsMaxX = RS_CENTER_X + rsHalf;
    float rsMaxY = RS_CENTER_Y + rsHalf;
    float rsMinX = RS_CENTER_X - rsHalf;
    float rsMinY = RS_CENTER_Y - rsHalf;
    float lsMaxX = LS_CENTER_X + lsHalf;
    float lsMaxY = LS_CENTER_Y + lsHalf;
    float lsMinX = LS_CENTER_X - lsHalf;
    float lsMinY = LS_CENTER_Y - lsHalf;
    
    for (UITouch* touch in touches) {
        CGPoint touchLocation = [touch locationInView:_view];
        float xLoc = touchLocation.x;
        float yLoc = touchLocation.y;
        if (touch == _lsTouch) {
            if (xLoc > lsMaxX) xLoc = lsMaxX;
            if (xLoc < lsMinX) xLoc = lsMinX;
            if (yLoc > lsMaxY) yLoc = lsMaxY;
            if (yLoc < lsMinY) yLoc = lsMinY;
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _leftStick.position = CGPointMake(xLoc, yLoc);
            [CATransaction commit];
            
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
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _rightStick.position = CGPointMake(xLoc, yLoc);
            [CATransaction commit];
            
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
            CALayer* pressed = [self dpadLayerAt:touchLocation];
            if (pressed != nil) {
                [_controllerSupport setButtonFlag:_controller flags:[self flagForDpadLayer:pressed]];
            }
            [self highlightDpad:pressed];
            updated = true;
            buttonTouch = true;
        } else if ([_buttonTouches objectForKey:touch] != nil || [_deadTouches containsObject:touch]) {
            // Rolling a thumb from one button onto another: the new one takes over. Off every
            // button, the last one stays held, so a thumb drifting into a gap doesn't drop it.
            // A touch that landed in the dead space around the buttons picks one up the same way.
            int i = [self slideButtonAt:touchLocation];
            if (i >= 0 && ![self isToggleSlide:i]) {
                [_buttonTouches setObject:@(i) forKey:touch];
                [_deadTouches removeObject:touch];
            }
            buttonTouch = true;
        } else if (touch == _l3Touch || touch == _r3Touch || [_latchTouches containsObject:touch]) {
            buttonTouch = true;
        }
        if ([_deadTouches containsObject:touch]) {
            updated = true;
        }
    }
    NSInteger newlyPressed = 0;
    if ([self syncSlideButtons:&newlyPressed]) {
        updated = true;
    }
    if (newlyPressed > 0) {
        [self pressHaptic];
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
    for (UITouch* touch in touches) {
        CGPoint touchLocation = [touch locationInView:_view];
        CALayer* dpad = nil;
        int slide = [self slideButtonAt:touchLocation];
        
        if (slide >= 0 && [self isToggleSlide:slide]) {
            // Tap-to-toggle: each tap latches or releases the button
            _latched[slide] = !_latched[slide];
            [_latchTouches addObject:touch];
            if (!_latched[slide]) {
                [self pressHaptic];
            }
        } else if (slide >= 0) {
            [_buttonTouches setObject:@(slide) forKey:touch];
        } else if ((dpad = [self dpadLayerAt:touchLocation]) != nil) {
            [_controllerSupport setButtonFlag:_controller flags:[self flagForDpadLayer:dpad]];
            [self highlightDpad:dpad];
            _dpadTouch = touch;
            updated = true;
            [self pressHaptic];
        } else if (_l3Button.superlayer != nil && CGRectContainsPoint(_l3Button.frame, touchLocation)) {
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
            [self pressHaptic];
        } else if (_r3Button.superlayer != nil && CGRectContainsPoint(_r3Button.frame, touchLocation)) {
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
            [self pressHaptic];
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
            [self setLayer:_leftStick highlighted:YES];
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
            [self setLayer:_rightStick highlighted:YES];
            _rsTouch = touch;
            stickTouch = true;
        } else if ([self isInDeadZone:touch]) {
            [_deadTouches addObject:touch];
            updated = true;
        }
    }
    NSInteger newlyPressed = 0;
    if ([self syncSlideButtons:&newlyPressed]) {
        updated = true;
    }
    if (newlyPressed > 0) {
        [self pressHaptic];
    }
    if (updated) {
        [_controllerSupport updateFinished:_controller];
    }
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
        if ([_buttonTouches objectForKey:touch] != nil) {
            [_buttonTouches removeObjectForKey:touch];
            touched = true;
        } else if ([_latchTouches containsObject:touch]) {
            [_latchTouches removeObject:touch];
            touched = true;
        } else if (touch == _dpadTouch) {
            [_controllerSupport clearButtonFlag:_controller
                                          flags:UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG];
            [self highlightDpad:nil];
            _dpadTouch = nil;
            updated = true;
        } else if (touch == _lsTouch) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _leftStick.position = CGPointMake(LS_CENTER_X, LS_CENTER_Y);
            [CATransaction commit];
            [self setLayer:_leftStick highlighted:NO];
            [_controllerSupport updateLeftStick:_controller x:0 y:0];
            [_controllerSupport clearButtonFlag:_controller flags:LS_CLK_FLAG];
            l3TouchStart = [NSDate date];
            _lsTouch = nil;
            updated = true;
        } else if (touch == _rsTouch) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _rightStick.position = CGPointMake(RS_CENTER_X, RS_CENTER_Y);
            [CATransaction commit];
            [self setLayer:_rightStick highlighted:NO];
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
    if ([self syncSlideButtons:NULL]) {
        updated = true;
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
