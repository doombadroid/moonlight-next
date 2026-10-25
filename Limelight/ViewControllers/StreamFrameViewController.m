//
//  StreamFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "StreamFrameViewController.h"
#import "MainFrameViewController.h"
#import "VideoDecoderRenderer.h"
#import "StreamManager.h"
#import "ControllerSupport.h"
#import "DataManager.h"
#if !TARGET_OS_TV
#import "MNInput.h"
#endif

#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <Limelight.h>
#include <os/log.h>

// The iPhone Duo hinge and fold APIs ship in the iOS 27.1 SDK
#if !TARGET_OS_TV && defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
#define MN_DUO_APIS 1
#endif

#if TARGET_OS_TV
#import <AVFoundation/AVDisplayCriteria.h>
#import <AVKit/AVDisplayManager.h>
#import <AVKit/UIWindow.h>
#endif

@interface AVDisplayCriteria()
@property(readonly) int videoDynamicRange;
@property(readonly, nonatomic) float refreshRate;
- (id)initWithRefreshRate:(float)arg1 videoDynamicRange:(int)arg2;
@end

#if !TARGET_OS_TV
@interface StreamFrameViewController () <UIEditMenuInteractionDelegate>
@end
#endif

@implementation StreamFrameViewController {
    ControllerSupport *_controllerSupport;
    StreamManager *_streamMan;
    TemporarySettings *_settings;
    NSTimer *_inactivityTimer;
    NSTimer *_statsUpdateTimer;
    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
    UITextView *_overlayView;
    UILabel *_stageLabel;
    UILabel *_tipLabel;
    UIActivityIndicatorView *_spinner;
    StreamView *_streamView;
    UIScrollView *_scrollView;
    BOOL _userIsInteracting;
    BOOL _tornDown;
    BOOL _quitOnExit;

#if !TARGET_OS_TV
    UIScreenEdgePanGestureRecognizer *_exitSwipeRecognizer;
    UIButton *_menuButton;
    UIViewController *_layoutEditorBar;
    __weak OnScreenControls *_layoutEditorControls;
    NSLayoutConstraint *_layoutEditorBarTop;
    NSLayoutConstraint *_layoutEditorBarBottom;

    // Tabletop input deck (keyboard, trackpad, gamepad) under the fold of an iPhone Duo
    UIViewController *_deckController;
    BOOL _deckDismissed;   // hidden with its chevron; back on the next fold
    BOOL _deckRequested;   // opened from the stream menu without a fold
    BOOL _wasTablePose;
    NSInteger _hingeStatus;     // UIHingeStatus; 0 = unknown
    CGFloat _hingeAngle;        // radians
    NSString *_lastDuoLog;

    // The ••• menu's items, also shown by a left-edge swipe (Settings › Left-edge swipe)
    void (^_menuProvider)(void (^)(NSArray<UIMenuElement*>*));
    UIEditMenuInteraction *_edgeMenuInteraction;
    // How far the stream is lifted to keep the spot the soft keyboard was opened from visible
    CGFloat _keyboardLift;
    // On-screen widgets, laid over the stream
    MNWidgetLayer *_widgetLayer;
#endif
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
#if !TARGET_OS_TV
    [[self revealViewController] setPrimaryViewController:self];
#endif
}

#if TARGET_OS_TV
- (void)controllerPauseButtonPressed:(id)sender { }
- (void)controllerPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Menu double-pressed -- backing out of stream");
    [self returnToMainFrame];
}
- (void)controllerPlayPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Play/Pause button pressed -- backing out of stream");
    [self returnToMainFrame];
}
#endif


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.navigationController setNavigationBarHidden:YES animated:YES];

    // Created in code (not from a storyboard) when presented by the SwiftUI launcher
    if (self.view.backgroundColor == nil) {
        self.view.backgroundColor = [UIColor blackColor];
    }

    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _settings = [[[DataManager alloc] init] getSettings];
    
    _stageLabel = [[UILabel alloc] init];
    [_stageLabel setUserInteractionEnabled:NO];
    [_stageLabel setText:[NSString stringWithFormat:@"Starting %@...", self.streamConfig.appName]];
    [_stageLabel sizeToFit];
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.textColor = [UIColor whiteColor];
    _stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
    
    _spinner = [[UIActivityIndicatorView alloc] init];
    [_spinner setUserInteractionEnabled:NO];
#if TARGET_OS_TV
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
#else
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhite];
#endif
    [_spinner sizeToFit];
    [_spinner startAnimating];
    _spinner.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2 - _stageLabel.frame.size.height - _spinner.frame.size.height);
    
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    _inactivityTimer = nil;
    
    _streamView = [[StreamView alloc] initWithFrame:self.view.frame];
    [_streamView setupStreamView:_controllerSupport interactionDelegate:self config:self.streamConfig];
#if !TARGET_OS_TV
    [MNInput setControllerSupport:_controllerSupport];
    [MNPhoneRumble.shared start];
    [MNVendorRumble.shared start];
    [MNGyro.shared startIn:self.view];
    // Nothing from an earlier stream's background state carries over
    MNAudio.backgroundMuted = NO;
    __weak StreamFrameViewController* weakSelf = self;
    MNPictureInPicture.shared.onClosedInBackground = ^{
        Log(LOG_I, @"Picture in picture closed in the background, ending stream");
        [weakSelf returnToMainFrame];
    };
    // No window was shown: the background keep-alive setting decides, as without PiP
    MNPictureInPicture.shared.onFailedInBackground = ^{
        [weakSelf backgroundWithoutPictureInPicture];
    };
    // Holding the quick menu button on a controller shows these as a wheel
    [MNQuickMenu.shared attach:self items:^NSArray<MNQuickMenuItem*>* {
        StreamFrameViewController* strongSelf = weakSelf;
        return strongSelf != nil ? [strongSelf quickMenuItems] : @[];
    }];
#endif
    
#if TARGET_OS_TV
    if (!_menuTapGestureRecognizer || !_menuDoubleTapGestureRecognizer || !_playPauseTapGestureRecognizer) {
        _menuTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonPressed:)];
        _menuTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];

        _playPauseTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonPressed:)];
        _playPauseTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        
        _menuDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonDoublePressed:)];
        _menuDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_menuTapGestureRecognizer requireGestureRecognizerToFail:_menuDoubleTapGestureRecognizer];
        _menuDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
    }
    
    [self.view addGestureRecognizer:_menuTapGestureRecognizer];
    [self.view addGestureRecognizer:_menuDoubleTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseTapGestureRecognizer];

#else
    _exitSwipeRecognizer = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeSwiped:)];
    _exitSwipeRecognizer.edges = UIRectEdgeLeft;
    _exitSwipeRecognizer.delaysTouchesBegan = NO;
    _exitSwipeRecognizer.delaysTouchesEnded = NO;
    
    [self.view addGestureRecognizer:_exitSwipeRecognizer];
    _exitSwipeRecognizer.enabled = MNTouchPrefs.edgeSwipeDisconnects || MNTouchPrefs.edgeSwipeOpensMenu;
    _edgeMenuInteraction = [[UIEditMenuInteraction alloc] initWithDelegate:self];
    [self.view addInteraction:_edgeMenuInteraction];
#endif
    
    _tipLabel = [[UILabel alloc] init];
    [_tipLabel setUserInteractionEnabled:NO];
    
#if TARGET_OS_TV
    [_tipLabel setText:@"Tip: Tap the Play/Pause button on the Apple TV Remote to disconnect from your PC"];
#else
    [_tipLabel setText:MNTouchPrefs.edgeSwipeDisconnects ? @"Tip: Swipe from the left edge or use the ••• menu to disconnect"
                                                          : @"Tip: Use the ••• menu to disconnect"];
#endif
    
    [_tipLabel sizeToFit];
    _tipLabel.textColor = [UIColor whiteColor];
    _tipLabel.textAlignment = NSTextAlignmentCenter;
    _tipLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height * 0.9);
    
    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                            renderView:_streamView
                                   connectionCallbacks:self];
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:_streamMan];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];

#if !TARGET_OS_TV
    // Lifts the stream so the spot the soft keyboard was opened from stays visible
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillShow:)
                                                 name: UIKeyboardWillShowNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillHide:)
                                                 name: UIKeyboardWillHideNotification
                                               object: nil];
#endif
    
    // Only enable scroll and zoom in absolute touch mode
    if (_settings.absoluteTouchMode) {
        _scrollView = [[UIScrollView alloc] initWithFrame:self.view.frame];
#if !TARGET_OS_TV
        [_scrollView.panGestureRecognizer setMinimumNumberOfTouches:2];
#endif
        [_scrollView setShowsHorizontalScrollIndicator:NO];
        [_scrollView setShowsVerticalScrollIndicator:NO];
        [_scrollView setDelegate:self];
        [_scrollView setMaximumZoomScale:10.0f];
        
        // Add StreamView inside a UIScrollView for absolute mode
        [_scrollView addSubview:_streamView];
        [self.view addSubview:_scrollView];
    }
    else {
        // Add StreamView directly in relative mode
        [self.view addSubview:_streamView];
    }
    
#if !TARGET_OS_TV
    // Saved in the on-screen controls' layouts, so it shares their posture and game
    _widgetLayer = [[MNWidgetLayer alloc] initWithControls:[_streamView layoutControls]];
    __weak StreamFrameViewController* widgetOwner = self;
    _widgetLayer.onFunction = ^(MNWidgetFunction function) {
        [widgetOwner runWidgetFunction:function];
    };
    [self.view addSubview:_widgetLayer];
#endif

    [self.view addSubview:_stageLabel];
    [self.view addSubview:_spinner];
    [self.view addSubview:_tipLabel];

#if !TARGET_OS_TV
    [self setupMenuButton];
    [self setupHingeObserver];
#endif
}

// Re-fit everything to the current bounds. The stream can be resized while running
// (iPhone Duo fold/unfold), so nothing here may assume the frame from viewDidLoad.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect fullBounds = self.view.bounds;
    CGRect bounds = fullBounds;
#if !TARGET_OS_TV
    // Half-open on a table: the stream keeps the top half, the input deck takes the bottom
    CGRect deckFrame = [self layoutInputDeckInBounds:fullBounds];
    if (!CGRectIsNull(deckFrame)) {
        bounds.size.height = MAX(CGRectGetMinY(deckFrame) - [self foldThickness], 0);
    }
#endif
    if (_scrollView != nil) {
        _scrollView.frame = bounds;
        if (_scrollView.zoomScale == 1.0f) {
            _streamView.frame = bounds;
            _scrollView.contentSize = bounds.size;
        }
    }
    else {
        _streamView.frame = bounds;
    }
#if !TARGET_OS_TV
    if (_keyboardLift > 0) {
        UIView* streamContainer = _scrollView != nil ? _scrollView : _streamView;
        streamContainer.frame = CGRectOffset(streamContainer.frame, 0, -_keyboardLift);
    }
    _widgetLayer.frame = (_scrollView != nil ? _scrollView : _streamView).frame;
#endif

    _stageLabel.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    _spinner.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds) - _stageLabel.frame.size.height - _spinner.frame.size.height);
    _tipLabel.center = CGPointMake(CGRectGetMidX(bounds), bounds.size.height * 0.9);

    if (_overlayView != nil && !_overlayView.hidden) {
        [self positionOverlay];
    }

#if !TARGET_OS_TV
    // Top-right inside the safe area and clear of the camera cut-out (an occlusion region,
    // not part of the safe area, on the iPhone Duo's outer display)
    UIEdgeInsets safe = [OnScreenControls obstructedInsetsForView:self.view];
    _menuButton.frame = CGRectMake(bounds.size.width - safe.right - 16 - 44, safe.top + 10, 44, 44);
    [self.view bringSubviewToFront:_menuButton];
    MNQuickMenu.shared.wheelArea = [self.view convertRect:bounds toView:nil];
#endif
}

#if !TARGET_OS_TV
- (void)setupMenuButton {
    _menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration* symbolConfig = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    [_menuButton setImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:symbolConfig] forState:UIControlStateNormal];
    _menuButton.tintColor = [UIColor whiteColor];
    _menuButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _menuButton.layer.cornerRadius = 22;
    _menuButton.layer.borderWidth = 1;
    _menuButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    _menuButton.accessibilityLabel = @"Stream menu";
    _menuButton.showsMenuAsPrimaryAction = YES;

    __weak StreamFrameViewController* weakSelf = self;
    _menuProvider = ^(void (^completion)(NSArray<UIMenuElement*>*)) {
        StreamFrameViewController* strongSelf = weakSelf;
        if (strongSelf == nil) {
            completion(@[]);
            return;
        }
        BOOL statsShown = strongSelf->_statsUpdateTimer != nil;
        UIAction* quitAction = [UIAction actionWithTitle:@"Quit App and Disconnect"
                                                   image:[UIImage systemImageNamed:@"power"]
                                              identifier:nil
                                                 handler:^(UIAction* action) {
            StreamFrameViewController* s = weakSelf;
            if (s != nil) {
                s->_quitOnExit = YES;
                [s returnToMainFrame];
            }
        }];
        quitAction.attributes = UIMenuElementAttributesDestructive;
        BOOL deckShown = strongSelf->_deckController != nil && !strongSelf->_deckController.view.hidden;
        NSMutableArray<UIMenuElement*>* gyroItems = [NSMutableArray array];
        if (MNGyro.isConfigured) {
            [gyroItems addObject:[UIAction actionWithTitle:MNGyro.isPaused ? @"Resume Gyro Aiming" : @"Pause Gyro Aiming"
                                                     image:[UIImage systemImageNamed:@"gyroscope"]
                                                identifier:nil
                                                   handler:^(UIAction* action) { MNGyro.isPaused = !MNGyro.isPaused; }]];
        }
        if (MNControllerMouse.hasController) {
            BOOL mouseOn = MNControllerMouse.shared.isOn;
            [gyroItems addObject:[UIAction actionWithTitle:mouseOn ? @"Controller Mouse Off" : @"Controller Mouse"
                                                     image:[UIImage systemImageNamed:@"cursorarrow.motionlines"]
                                                identifier:nil
                                                   handler:^(UIAction* action) { [MNControllerMouse.shared toggle]; }]];
        }
        if (MNPictureInPicture.shared.canStart) {
            [gyroItems addObject:[UIAction actionWithTitle:@"Picture in Picture"
                                                     image:[UIImage systemImageNamed:@"pip.enter"]
                                                identifier:nil
                                                   handler:^(UIAction* action) { [MNPictureInPicture.shared start]; }]];
        }
        if ([strongSelf->_streamView layoutControls] != nil) {
            [gyroItems addObject:[UIAction actionWithTitle:@"Edit Controls"
                                                     image:[UIImage systemImageNamed:@"arrow.up.and.down.and.arrow.left.and.right"]
                                                identifier:nil
                                                   handler:^(UIAction* action) { [weakSelf startLayoutEditor]; }]];
        }
        BOOL touchOff = strongSelf->_streamView.touchInputDisabled;
        [gyroItems addObject:[UIAction actionWithTitle:touchOff ? @"Turn Touch On" : @"Turn Touch Off"
                                                 image:[UIImage systemImageNamed:touchOff ? @"hand.point.up.left" : @"hand.raised.slash"]
                                            identifier:nil
                                               handler:^(UIAction* action) {
            StreamFrameViewController* s = weakSelf;
            if (s != nil) {
                s->_streamView.touchInputDisabled = !touchOff;
            }
        }]];
        completion([gyroItems arrayByAddingObjectsFromArray:@[
            [UIAction actionWithTitle:deckShown ? @"Hide Keyboard & Trackpad" : @"Keyboard & Trackpad"
                                image:[UIImage systemImageNamed:@"keyboard"]
                           identifier:nil
                              handler:^(UIAction* action) { [weakSelf toggleInputDeck]; }],
            [UIAction actionWithTitle:@"Settings"
                                image:[UIImage systemImageNamed:@"gearshape"]
                           identifier:nil
                              handler:^(UIAction* action) { [weakSelf presentStreamSettings]; }],
            [UIAction actionWithTitle:statsShown ? @"Hide Stats" : @"Show Stats"
                                image:[UIImage systemImageNamed:@"chart.bar.xaxis"]
                           identifier:nil
                              handler:^(UIAction* action) { [weakSelf toggleStatsOverlay]; }],
            [UIAction actionWithTitle:@"Disconnect"
                                image:[UIImage systemImageNamed:@"xmark"]
                           identifier:nil
                              handler:^(UIAction* action) { [weakSelf returnToMainFrame]; }],
            quitAction,
        ]]);
    };
    _menuButton.menu = [UIMenu menuWithChildren:@[[UIDeferredMenuElement elementWithUncachedProvider:_menuProvider]]];

    [self.view addSubview:_menuButton];
}

// The controller quick menu: the ••• menu's actions, for a wheel picked with a stick
- (NSArray<MNQuickMenuItem*>*)quickMenuItems {
    __weak StreamFrameViewController* weakSelf = self;
    NSMutableArray<MNQuickMenuItem*>* items = [NSMutableArray array];
    BOOL deckShown = _deckController != nil && !_deckController.view.hidden;
    [items addObject:[[MNQuickMenuItem alloc] initWithTitle:deckShown ? @"Hide Keyboard" : @"Keyboard & Trackpad"
                                                     symbol:@"keyboard" destructive:NO
                                                    handler:^{ [weakSelf toggleInputDeck]; }]];
    [items addObject:[[MNQuickMenuItem alloc] initWithTitle:_statsUpdateTimer != nil ? @"Hide Stats" : @"Show Stats"
                                                     symbol:@"chart.bar.xaxis" destructive:NO
                                                    handler:^{ [weakSelf toggleStatsOverlay]; }]];
    [items addObject:[[MNQuickMenuItem alloc] initWithTitle:@"Settings" symbol:@"gearshape" destructive:NO
                                                    handler:^{ [weakSelf presentStreamSettings]; }]];
    BOOL mouseOn = MNControllerMouse.shared.isOn;
    [items addObject:[[MNQuickMenuItem alloc] initWithTitle:mouseOn ? @"Controller Mouse Off" : @"Controller Mouse"
                                                     symbol:@"cursorarrow.motionlines" destructive:NO
                                                    handler:^{ [MNControllerMouse.shared toggle]; }]];
    BOOL touchOff = _streamView.touchInputDisabled;
    [items addObject:[[MNQuickMenuItem alloc] initWithTitle:touchOff ? @"Turn Touch On" : @"Turn Touch Off"
                                                     symbol:touchOff ? @"hand.point.up.left" : @"hand.raised.slash" destructive:NO
                                                    handler:^{
        StreamFrameViewController* s = weakSelf;
        if (s != nil) {
            s->_streamView.touchInputDisabled = !touchOff;
        }
    }]];
    if (MNGyro.isConfigured) {
        [items addObject:[[MNQuickMenuItem alloc] initWithTitle:MNGyro.isPaused ? @"Resume Gyro" : @"Pause Gyro"
                                                         symbol:@"gyroscope" destructive:NO
                                                        handler:^{ MNGyro.isPaused = !MNGyro.isPaused; }]];
    }
    if (MNPictureInPicture.shared.canStart) {
        [items addObject:[[MNQuickMenuItem alloc] initWithTitle:@"Picture in Picture" symbol:@"pip.enter" destructive:NO
                                                        handler:^{ [MNPictureInPicture.shared start]; }]];
    }
    // Same condition as the ••• menu: widgets can be edited even with the controls hidden
    if ([_streamView layoutControls] != nil) {
        [items addObject:[[MNQuickMenuItem alloc] initWithTitle:@"Edit Controls"
                                                         symbol:@"arrow.up.and.down.and.arrow.left.and.right" destructive:NO
                                                        handler:^{ [weakSelf startLayoutEditor]; }]];
    }
    [items addObject:[[MNQuickMenuItem alloc] initWithTitle:@"Quit App" symbol:@"power" destructive:YES handler:^{
        StreamFrameViewController* s = weakSelf;
        if (s != nil) {
            s->_quitOnExit = YES;
            [s returnToMainFrame];
        }
    }]];
    [items addObject:[[MNQuickMenuItem alloc] initWithTitle:@"Disconnect" symbol:@"xmark" destructive:NO
                                                    handler:^{ [weakSelf returnToMainFrame]; }]];
    return items;
}

// MARK: iPhone Duo hinge + tabletop input deck

static os_log_t DuoLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.doombadroid.moonlightnext", "duo"); });
    return log;
}

- (void)setupHingeObserver {
    // Folding or unfolding changes the size class, and with it the orientation mask above
    [self registerForTraitChanges:@[UITraitHorizontalSizeClass.class]
                       withAction:@selector(setNeedsUpdateOfSupportedInterfaceOrientations)];
#ifdef MN_DUO_APIS
    if (@available(iOS 27.1, *)) {
        __weak StreamFrameViewController* weakSelf = self;
        UIHingeInteraction* hinge = [[UIHingeInteraction alloc] initWithUpdateHandler:^(UIHingeInteraction* interaction, UIHingeInteractionUpdate* update) {
            StreamFrameViewController* strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            strongSelf->_hingeStatus = update.hinge != nil ? update.hinge.status : 0;
            strongSelf->_hingeAngle = update.hinge != nil ? update.hinge.angle : 0;
            os_log(DuoLog(), "hinge update: status=%ld angle=%.0f deg", (long)strongSelf->_hingeStatus, strongSelf->_hingeAngle * 180 / M_PI);
            // The fold region follows the hinge: lay out now, and again once it has settled
            [strongSelf.view setNeedsLayout];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf.view setNeedsLayout];
            });
        }];
        [self.view addInteraction:hinge];
    }
#endif
}

// The fold while the device stands half-open like a laptop (inner screen up, its lower half
// on the table), in this view's coordinates, or CGRectNull. Prefers the system's division
// region; if that isn't reported, a partly open hinge on a portrait-shaped screen means the
// same pose, with the fold across the middle.
- (CGRect)tableFold {
    CGRect bounds = self.view.bounds;
    CGRect fold = CGRectNull;
    NSMutableString* diag = [NSMutableString stringWithFormat:@"view=%.0fx%.0f hinge=%ld/%.0fdeg regions=[",
                             bounds.size.width, bounds.size.height, (long)_hingeStatus, _hingeAngle * 180 / M_PI];
#ifdef MN_DUO_APIS
    if (@available(iOS 27.1, *)) {
        NSArray<UIViewReservedRegion*>* regions = [self.view reservedRegionsOfKind:[UIViewReservedRegionKind divisionRegionKind]
                                                                           options:UIViewReservedRegionQueryOptionsIncludeInactive];
        for (UIViewReservedRegion* region in regions) {
            CGRect frame = region.frame;
            [diag appendFormat:@" %@%@", NSStringFromCGRect(frame), region.isActive ? @"" : @"(inactive)"];
            if (CGRectIsNull(fold) && region.isActive && frame.size.width > frame.size.height) {
                fold = frame;
            }
        }
        if (CGRectIsNull(fold) && _hingeStatus == UIHingeStatusPartiallyOpen &&
            bounds.size.height > bounds.size.width) {
            CGFloat thickness = 40;
            fold = CGRectMake(0, floor(bounds.size.height / 2 - thickness / 2), bounds.size.width, thickness);
            [diag appendString:@" ] fallback"];
        }
        else {
            [diag appendString:@" ]"];
        }
    }
#endif
    [diag appendFormat:@" -> %@ safe=%@ obstructed=%@", CGRectIsNull(fold) ? @"no table pose" : NSStringFromCGRect(fold),
     NSStringFromUIEdgeInsets(self.view.safeAreaInsets),
     NSStringFromUIEdgeInsets([OnScreenControls obstructedInsetsForView:self.view])];
    if (![diag isEqualToString:_lastDuoLog]) {
        _lastDuoLog = diag;
        os_log(DuoLog(), "%{public}@", diag);
    }
    return fold;
}

- (CGFloat)foldThickness {
    CGRect fold = [self tableFold];
    return CGRectIsNull(fold) ? 0 : fold.size.height;
}

// Shows, hides and places the input deck; returns its frame, or CGRectNull when hidden.
- (CGRect)layoutInputDeckInBounds:(CGRect)bounds {
    CGRect fold = [self tableFold];
    BOOL tablePose = !CGRectIsNull(fold);
    if (tablePose != _wasTablePose) {
        // Every new fold brings the deck back; unfolding closes a deck the fold opened
        _deckDismissed = NO;
        _wasTablePose = tablePose;
    }

    BOOL show = (tablePose && !_deckDismissed) || _deckRequested;
    if (!show) {
        if (_deckController != nil) {
            _deckController.view.hidden = YES;
            [_streamView setOnScreenControlsSuppressed:NO];
        }
        return CGRectNull;
    }

    if (_deckController == nil) {
        __weak StreamFrameViewController* weakSelf = self;
        _deckController = [MNInputDeck makeViewControllerOnHide:^{
            [weakSelf hideInputDeck];
        }];
        [self addChildViewController:_deckController];
        [self.view addSubview:_deckController.view];
        [_deckController didMoveToParentViewController:self];
    }

    CGRect deck;
    if (tablePose) {
        deck = CGRectMake(0, CGRectGetMaxY(fold), bounds.size.width, CGRectGetMaxY(bounds) - CGRectGetMaxY(fold));
    }
    else {
        // Opened by hand on a flat screen: the lower half
        CGFloat height = floor(bounds.size.height * 0.48);
        deck = CGRectMake(0, CGRectGetMaxY(bounds) - height, bounds.size.width, height);
    }
    _deckController.view.frame = deck;
    _deckController.view.hidden = NO;
    [self.view bringSubviewToFront:_deckController.view];
    // The deck has its own gamepad; on-screen controls over the shrunken video would only cover it
    [_streamView setOnScreenControlsSuppressed:YES];
    return deck;
}

// Rearranging the on-screen controls: touches select and drag controls until Save or Cancel
// Widgets are edited in the same session. The controls may be hidden (turned off, or a controller
// is connected): their layouts still hold the widgets.
- (void)startLayoutEditor {
    OnScreenControls* osc = [_streamView layoutControls];
    if (osc == nil || _layoutEditorBar != nil) {
        return;
    }
    [osc setEditing:YES];
    [_widgetLayer setEditing:YES];
    _layoutEditorControls = osc;
    __weak StreamFrameViewController* weakSelf = self;
    __weak OnScreenControls* weakOsc = osc;
    _layoutEditorBar = [MNLayoutEditorBar makeViewControllerWithControls:osc
                                                                 widgets:_widgetLayer
                                                           hasGameLayout:[osc hasLayoutForThisGame]
                                                                  onSave:^(BOOL thisGame) {
        [weakOsc saveLayoutForThisGame:thisGame];
        [weakSelf endLayoutEditor];
    }
                                                                onCancel:^{ [weakSelf endLayoutEditor]; }
                                                               onMoveBar:^(BOOL toBottom) {
        // The bar can sit at the bottom when the controls under it at the top need moving
        StreamFrameViewController* strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_layoutEditorBarTop.active = !toBottom;
            strongSelf->_layoutEditorBarBottom.active = toBottom;
        }
    }];
    [self addChildViewController:_layoutEditorBar];
    UIView* bar = _layoutEditorBar.view;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    _layoutEditorBarTop = [bar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8];
    _layoutEditorBarBottom = [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8];
    [NSLayoutConstraint activateConstraints:@[
        [bar.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        _layoutEditorBarTop,
        [bar.widthAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-16],
    ]];
    [_layoutEditorBar didMoveToParentViewController:self];
    _menuButton.hidden = YES;
}

- (void)endLayoutEditor {
    // Not saved: this puts the saved layout back. Saved: it reloads what was just saved.
    [_layoutEditorControls setEditing:NO];
    [_widgetLayer setEditing:NO];
    _layoutEditorControls = nil;
    [_layoutEditorBar willMoveToParentViewController:nil];
    [_layoutEditorBar.view removeFromSuperview];
    [_layoutEditorBar removeFromParentViewController];
    _layoutEditorBar = nil;
    _menuButton.hidden = NO;
}

- (void)presentStreamSettings {
    __weak StreamFrameViewController* weakSelf = self;
    UIViewController* sheet = [MNSettingsSheet makeViewControllerOnClose:^{
        StreamFrameViewController* strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf->_streamView reloadOnScreenControlsLevel];
            strongSelf->_exitSwipeRecognizer.enabled = MNTouchPrefs.edgeSwipeDisconnects || MNTouchPrefs.edgeSwipeOpensMenu;
            [MNPictureInPicture.shared settingChanged];
        }
    }];
    sheet.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)runWidgetFunction:(MNWidgetFunction)function {
    switch (function) {
        case MNWidgetFunctionSettings:
            if (self.presentedViewController == nil) {
                [self presentStreamSettings];
            }
            break;
        case MNWidgetFunctionDisconnect:
            [self returnToMainFrame];
            break;
        case MNWidgetFunctionQuitApp:
            _quitOnExit = YES;
            [self returnToMainFrame];
            break;
        case MNWidgetFunctionPictureInPicture:
            if (MNPictureInPicture.shared.canStart) {
                [MNPictureInPicture.shared start];
            }
            break;
        case MNWidgetFunctionEditControls:
            [self startLayoutEditor];
            break;
        case MNWidgetFunctionSoftKeyboard:
            [_streamView toggleSoftKeyboard];
            break;
        case MNWidgetFunctionInputDeck:
            [self toggleInputDeck];
            break;
        case MNWidgetFunctionTouchToggle:
            _streamView.touchInputDisabled = !_streamView.touchInputDisabled;
            break;
        case MNWidgetFunctionControllerMouse:
            [MNControllerMouse.shared toggle];
            break;
        case MNWidgetFunctionStats:
            [self toggleStatsOverlay];
            break;
        case MNWidgetFunctionProfiles:
            [_widgetLayer presentProfilesFrom:self];
            break;
    }
}

- (void)toggleInputDeck {
    BOOL shown = _deckController != nil && !_deckController.view.hidden;
    if (shown) {
        [self hideInputDeck];
    }
    else {
        _deckDismissed = NO;
        _deckRequested = CGRectIsNull([self tableFold]);
        [self.view setNeedsLayout];
    }
}

- (void)hideInputDeck {
    _deckRequested = NO;
    _deckDismissed = YES;
    [self.view setNeedsLayout];
}

- (void)toggleStatsOverlay {
    if (_statsUpdateTimer != nil) {
        [_statsUpdateTimer invalidate];
        _statsUpdateTimer = nil;
        [self updateOverlayText:nil];
    }
    else {
        _statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                             target:self
                                                           selector:@selector(updateStatsOverlay)
                                                           userInfo:nil
                                                            repeats:YES];
    }
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    // Landscape only on a compact-width (phone-sized) window. The iPhone Duo's inner display
    // is regular width and doesn't rotate its window for us: a landscape-only mask there left
    // the stream laid out landscape-sized inside the portrait window, cut off at the side.
    if (self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone &&
        self.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassRegular) {
        return UIInterfaceOrientationMaskLandscape;
    }
    return UIInterfaceOrientationMaskAll;
}
#endif

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _streamView;
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    // Only cleanup when we're being destroyed
    if (parent == nil) {
        [self teardownStream];
    }
}

- (void)teardownStream {
    if (_tornDown) {
        return;
    }
    _tornDown = YES;
#if !TARGET_OS_TV
    [MNQuickMenu.shared detach];
    // Nothing a widget holds may stay down on the host
    [_widgetLayer releaseAll];
    [MNGyro.shared stop];
    [MNPhoneRumble.shared end];
    [MNControllerMouse.shared stop];
    [MNDummyInput stop];
    [MNInput setControllerSupport:nil];
    [MNExternalDisplay.shared streamEnded];
    MNAudio.backgroundMuted = NO;
    // Here, not in the renderer's late async detach, which could clear the next stream's
    MNPictureInPicture.shared.onClosedInBackground = nil;
    MNPictureInPicture.shared.onFailedInBackground = nil;
#endif

    [_controllerSupport cleanup];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [_streamMan stopStream];
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#if !TARGET_OS_TV
- (void)keyboardWillShow:(NSNotification *)notification {
    // Only for the stream's own soft keyboard (opened with a finger tap)
    if (![_streamView softKeyboardShown]) {
        return;
    }
    CGRect keyboard = [self.view convertRect:[notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue]
                         fromCoordinateSpace:self.view.window.windowScene.screen.coordinateSpace];
    // Adapted from VoidLink (GPLv3), Input/StreamView.m: a set keyboard height (a fraction of the
    // screen) for keyboards whose reported height is wrong (floating, third-party)
    if (MNTouchExtras.keyboardHeight > 0) {
        CGFloat height = self.view.bounds.size.height * MNTouchExtras.keyboardHeight;
        keyboard = CGRectMake(0, CGRectGetMaxY(self.view.bounds) - height, self.view.bounds.size.width, height);
    }
    // Where the tap was before any lift, plus room to see what's being typed into
    CGFloat anchor = [_streamView convertPoint:CGPointMake(0, [_streamView softKeyboardAnchorY]) toView:self.view].y + _keyboardLift;
    CGFloat lift = MIN(MAX(anchor + 48 - CGRectGetMinY(keyboard), 0), keyboard.size.height);
    [self setKeyboardLift:lift notification:notification];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    [self setKeyboardLift:0 notification:notification];
}

- (void)setKeyboardLift:(CGFloat)lift notification:(NSNotification *)notification {
    if (lift == _keyboardLift) {
        return;
    }
    _keyboardLift = lift;
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
}
#endif

- (void)updateStatsOverlay {
    NSString* overlayText = [self->_streamMan getStatsOverlayText];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateOverlayText:overlayText];
    });
}

- (void)updateOverlayText:(NSString*)text {
    if (_overlayView == nil) {
        _overlayView = [[UITextView alloc] init];
#if !TARGET_OS_TV
        [_overlayView setEditable:NO];
#endif
        [_overlayView setUserInteractionEnabled:NO];
        [_overlayView setSelectable:NO];
        [_overlayView setScrollEnabled:NO];
        
        // HACK: If not using stats overlay, center the text
        if (_statsUpdateTimer == nil) {
            [_overlayView setTextAlignment:NSTextAlignmentCenter];
        }
        
#if TARGET_OS_TV
        [_overlayView setTextColor:[UIColor lightGrayColor]];
        [_overlayView setBackgroundColor:[UIColor blackColor]];
        [_overlayView setFont:[UIFont systemFontOfSize:24]];
        [_overlayView setAlpha:0.5];
#else
        // Eclipse theme: dark translucent pill, monospaced stats
        [_overlayView setTextColor:[UIColor colorWithRed:0xD7/255.0 green:0xD7/255.0 blue:0xDC/255.0 alpha:1]];
        [_overlayView setBackgroundColor:[UIColor colorWithWhite:0 alpha:0.72]];
        [_overlayView setFont:[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular]];
        [_overlayView setTextContainerInset:UIEdgeInsetsMake(6, 10, 6, 10)];
        _overlayView.layer.cornerRadius = 12;
        _overlayView.layer.cornerCurve = kCACornerCurveContinuous;
#endif
        [self.view addSubview:_overlayView];
    }

    if (text != nil) {
        // We set our bounds to the maximum width in order to work around a bug where
        // sizeToFit interacts badly with the UITextView's line breaks, causing the
        // width to get smaller and smaller each time as more line breaks are inserted.
        [_overlayView setBounds:CGRectMake(self.view.frame.origin.x,
                                           _overlayView.frame.origin.y,
                                           self.view.frame.size.width,
                                           _overlayView.frame.size.height)];
        [_overlayView setText:text];
        [_overlayView sizeToFit];
        [self positionOverlay];
        [_overlayView setHidden:NO];
    }
    else {
        [_overlayView setHidden:YES];
    }
}

- (void)positionOverlay {
#if TARGET_OS_TV
    [_overlayView setCenter:CGPointMake(self.view.frame.size.width / 2, _overlayView.frame.size.height / 2)];
#else
    // Stats sit top-left; connection warnings are centered at the top
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGRect frame = _overlayView.frame;
    frame.origin.y = safe.top + 10;
    frame.origin.x = _statsUpdateTimer != nil ? safe.left + 16 : (self.view.bounds.size.width - frame.size.width) / 2;
    _overlayView.frame = frame;
#endif
}

- (void) returnToMainFrame {
    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];
    
    [_statsUpdateTimer invalidate];
    _statsUpdateTimer = nil;

    if (self.onExit != nil) {
        // Presented by the SwiftUI launcher: no navigation stack to pop
        void (^onExit)(BOOL) = self.onExit;
        self.onExit = nil;
        [self teardownStream];
        onExit(_quitOnExit);
        return;
    }

    [self.navigationController popToRootViewControllerAnimated:YES];
}

// This will fire if the user opens control center or gets a low battery message
- (void)applicationWillResignActive:(NSNotification *)notification {
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
    }
    
#if !TARGET_OS_TV
    // The stream can stay connected in the background (keep-alive, picture in picture), where no
    // release would ever come: let go of every held button, key and stick on the host now.
    // Keyboard keys are released by StreamView's pressesCancelled, gyro aiming and controller
    // mouse pause themselves while the app isn't active.
    [[_streamView layoutControls] releaseAllInput];
    [_controllerSupport releaseAllInput];
    for (int button = BUTTON_LEFT; button <= BUTTON_X2; button++) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, button);
    }

    // Terminate the stream if the app is inactive for 60 seconds
    Log(LOG_I, @"Starting inactivity termination timer");
    _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:60
                                                      target:self
                                                    selector:@selector(inactiveTimerExpired:)
                                                    userInfo:nil
                                                     repeats:NO];
#endif
}

- (void)inactiveTimerExpired:(NSTimer*)timer {
#if !TARGET_OS_TV
    if (MNPictureInPicture.shared.isActive) {
        // Watching in picture in picture counts as active
        _inactivityTimer = nil;
        return;
    }
#endif
    Log(LOG_I, @"Terminating stream after inactivity");

    [self returnToMainFrame];
    
    _inactivityTimer = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
#if !TARGET_OS_TV
    MNAudio.backgroundMuted = NO;
#endif
    // Stop the background timer, since we're foregrounded again
    if (_inactivityTimer != nil) {
        Log(LOG_I, @"Stopping inactivity timer after becoming active again");
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
}

// This fires when the home button is pressed
- (void)applicationDidEnterBackground:(UIApplication *)application {
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }

#if !TARGET_OS_TV
    if (MNPictureInPicture.enabled || MNPictureInPicture.shared.isActive) {
        // Picture in picture starts around the same moment the app backgrounds; give it a
        // moment, and keep the stream if it did. Audio background mode keeps us running.
        __weak StreamFrameViewController* weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (MNPictureInPicture.shared.isActive || UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) {
                return;
            }
            [weakSelf backgroundWithoutPictureInPicture];
        });
        return;
    }
    [self backgroundWithoutPictureInPicture];
    return;
#endif

    Log(LOG_I, @"Terminating stream immediately for backgrounding");
    [self returnToMainFrame];
}

#if !TARGET_OS_TV
// In the background without picture in picture: stay connected for the minutes chosen in
// Settings (audio background mode keeps the app running, muted if asked), else end now.
// Adapted from VoidLink (GPLv3), StreamFrameViewController.m (background session timer).
- (void)backgroundWithoutPictureInPicture {
    if (_tornDown) {
        // A late background check (or PiP failure) after the stream already ended
        return;
    }
    NSInteger minutes = MNAudio.backgroundMinutes;
    if (minutes <= 0) {
        Log(LOG_I, @"Terminating stream for backgrounding");
        [self returnToMainFrame];
        return;
    }
    Log(LOG_I, @"Keeping the stream connected in the background for %ld min", (long)minutes);
    MNAudio.backgroundMuted = MNAudio.muteInBackground;
    [_inactivityTimer invalidate];
    _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:minutes * 60
                                                        target:self
                                                      selector:@selector(inactiveTimerExpired:)
                                                      userInfo:nil
                                                       repeats:NO];
}
#endif

- (void)edgeSwiped:(UIGestureRecognizer*)gesture {
#if !TARGET_OS_TV
    if (MNTouchPrefs.edgeSwipeOpensMenu) {
        if (gesture.state == UIGestureRecognizerStateEnded) {
            // Off the very edge, where the swipe ended
            CGPoint point = [gesture locationInView:self.view];
            point.x = MAX(point.x, 80);
            [_edgeMenuInteraction presentEditMenuWithConfiguration:[UIEditMenuConfiguration configurationWithIdentifier:nil sourcePoint:point]];
        }
        return;
    }
#endif
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    Log(LOG_I, @"User swiped to end stream");
    
    [self returnToMainFrame];
}

#if !TARGET_OS_TV
- (UIMenu *)editMenuInteraction:(UIEditMenuInteraction *)interaction
           menuForConfiguration:(UIEditMenuConfiguration *)configuration
               suggestedActions:(NSArray<UIMenuElement *> *)suggestedActions {
    // The provider fills the items in synchronously
    __block NSArray<UIMenuElement*>* items = @[];
    _menuProvider(^(NSArray<UIMenuElement*>* elements) { items = elements; });
    return [UIMenu menuWithChildren:items];
}

- (void)streamHotkeyPressed:(NSInteger)usage {
    switch (usage) {
        case UIKeyboardHIDUsageKeyboardD:
            [self returnToMainFrame];
            break;
        case UIKeyboardHIDUsageKeyboardQ:
            _quitOnExit = YES;
            [self returnToMainFrame];
            break;
        case UIKeyboardHIDUsageKeyboardS:
            if (self.presentedViewController == nil) {
                [self presentStreamSettings];
            }
            break;
        case UIKeyboardHIDUsageKeyboardO:
            [self toggleStatsOverlay];
            break;
        case UIKeyboardHIDUsageKeyboardM:
            MNMouse.captured = !MNMouse.captured;
            [self setNeedsUpdateOfPrefersPointerLocked];
            break;
        case UIKeyboardHIDUsageKeyboardC:
            MNMouse.cursorVisible = !MNMouse.cursorVisible;
            [_streamView refreshPointerStyle];
            break;
    }
}
#endif

- (void) connectionStarted {
    Log(LOG_I, @"Connection started");
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_tornDown) {
            // Disconnected as the connection came up: nothing here may start (external display
            // routing, the stats timer that would keep this controller alive)
            return;
        }
        // Leave the spinner spinning until it's obscured by
        // the first frame of video.
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
        
        [self->_streamView showOnScreenControls];
#if !TARGET_OS_TV
        [MNExternalDisplay.shared streamStarted:self->_streamView
                                    aspectRatio:(CGFloat)self.streamConfig.width / self.streamConfig.height];
#endif
        
        [self->_controllerSupport connectionEstablished];
#if !TARGET_OS_TV
        [MNDummyInput startWithFps:self->_settings.framerate.intValue];
#endif
        
        if (self->_settings.statsOverlay) {
            self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                       target:self
                                                                     selector:@selector(updateStatsOverlay)
                                                                     userInfo:nil
                                                                      repeats:YES];
        }
    });
}

// A sheet over the stream (Settings, widget profiles) would make UIKit refuse the alert, leaving
// a frozen stream with no way out but finding Disconnect: close the sheet first
- (void)presentStreamAlert:(UIAlertController*)alert {
    if (self.presentedViewController != nil) {
        [self dismissViewControllerAnimated:NO completion:^{
            [self presentViewController:alert animated:YES completion:nil];
        }];
    }
    else {
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %d", errorCode);
    
    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* title;
        NSString* message;
        
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = @"Connection Error";
            message = @"Your device's network connection is blocking Moonlight. Streaming may not work while connected to this network.";
        }
        else {
            switch (errorCode) {
                case ML_ERROR_GRACEFUL_TERMINATION:
                    [self returnToMainFrame];
                    return;
                    
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = @"Connection Error";
                    message = @"No video received from host.";
                    if (portFlags != 0) {
                        char failingPorts[256];
                        LiStringifyPortFlags(portFlags, "\n", failingPorts, sizeof(failingPorts));
                        message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
                    }
                    break;
                    
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = @"Connection Error";
                    message = @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection.";
                    break;
                    
                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
                case ML_ERROR_PROTECTED_CONTENT:
                    title = @"Connection Error";
                    message = @"Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC.\n\nIf the issue persists, try reinstalling your GPU drivers and GeForce Experience.";
                    break;
                    
                case ML_ERROR_FRAME_CONVERSION:
                    title = @"Connection Error";
                    message = @"The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution.";
                    break;
                    
                default:
                {
                    NSString* errorString;
                    if (abs(errorCode) > 1000) {
                        // We'll assume large errors are hex values
                        errorString = [NSString stringWithFormat:@"%08X", (uint32_t)errorCode];
                    }
                    else {
                        // Smaller values will just be printed as decimal (probably errno.h values)
                        errorString = [NSString stringWithFormat:@"%d", errorCode];
                    }
                    
                    title = @"Connection Terminated";
                    message = [NSString stringWithFormat: @"The connection was terminated\n\nError code: %@", errorString];
                    NSString* hint = [StreamFrameViewController adviceForTerminationCode:errorCode];
                    if (hint != nil) {
                        message = [NSString stringWithFormat:@"%@\n\n%@", hint, message];
                    }
                    break;
                }
            }
        }
        
        UIAlertController* conTermAlert = [UIAlertController alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:conTermAlert];
        [conTermAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentStreamAlert:conTermAlert];
    });

    [_streamMan stopStream];
}

// Plain advice for the usual ways a running stream drops. common-c reports socket errors as
// errno values and a lost or silent PC as -1. Idea from VoidLink (GPLv3), StreamFrameViewController.m.
+ (NSString*)adviceForTerminationCode:(int)errorCode {
    switch (errorCode) {
        case -1:
            return @"The PC stopped answering. It may have gone to sleep, lost its network, or Sunshine restarted. Check the PC is awake and reachable, then reconnect.";
        case ETIMEDOUT:
            return @"The connection timed out. The Wi-Fi signal probably dropped; move closer to the router or use a 5 or 6 GHz network.";
        case ECONNRESET:
        case EPIPE:
        case ECONNABORTED:
            return @"The PC closed the connection. Sunshine may have restarted, or the session was ended on the PC.";
        case ENETDOWN:
        case ENETUNREACH:
        case EHOSTUNREACH:
        case EADDRNOTAVAIL:
            return @"This device lost its network: Wi-Fi turned off, it switched networks, or a VPN changed. Reconnect once you're back on the PC's network.";
        case ENOBUFS:
        case ENOMEM:
            return @"This device ran out of network buffers or memory. Close other apps or lower the bitrate.";
        default:
            return nil;
    }
}

- (void) stageStarting:(const char*)stageName {
    Log(LOG_I, @"Starting %s", stageName);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* lowerCase = [NSString stringWithFormat:@"%s in progress...", stageName];
        NSString* titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        [self->_stageLabel setText:titleCase];
        [self->_stageLabel sizeToFit];
        self->_stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self->_stageLabel.center.y);
    });
}

- (void) stageComplete:(const char*)stageName {
}

- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    Log(LOG_I, @"Stage %s failed: %d", stageName, errorCode);
    
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portTestFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
        }
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            message = [message stringByAppendingString:@"\n\nYour device's network connection is blocking Moonlight. Streaming may not work while connected to this network."];
        }
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Failed"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentStreamAlert:alert];
    });
    
    [_streamMan stopStream];
}

- (void) launchFailed:(NSString*)message {
    Log(LOG_I, @"Launch failed: %@", message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Error"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentStreamAlert:alert];
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    Log(LOG_I, @"Rumble on gamepad %d: %04x %04x", controllerNumber, lowFreqMotor, highFreqMotor);
    
    [_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    Log(LOG_I, @"Trigger rumble on gamepad %d: %04x %04x", controllerNumber, leftTrigger, rightTrigger);
    
    [_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    Log(LOG_I, @"Set motion state on gamepad %d: %02x %u Hz", controllerNumber, motionType, reportRateHz);
    
    [_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    Log(LOG_I, @"Set controller LED on gamepad %d: l%02x%02x%02x", controllerNumber, r, g, b);
    
    [_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
}

- (void) setAdaptiveTriggers:(uint16_t)controllerNumber eventFlags:(uint8_t)eventFlags typeLeft:(uint8_t)typeLeft typeRight:(uint8_t)typeRight left:(const uint8_t*)left right:(const uint8_t*)right {
    Log(LOG_I, @"Set adaptive triggers on gamepad %d: flags %02x types %02x %02x", controllerNumber, eventFlags, typeLeft, typeRight);

    [_controllerSupport setAdaptiveTriggers:controllerNumber eventFlags:eventFlags typeLeft:typeLeft typeRight:typeRight left:left right:right];
}

- (void)connectionStatusUpdate:(int)status {
    Log(LOG_W, @"Connection status update: %d", status);

    // The stats overlay takes precedence over these warnings
    if (_statsUpdateTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (status) {
            case CONN_STATUS_OKAY:
                [self updateOverlayText:nil];
                break;
                
            case CONN_STATUS_POOR:
                if (self->_streamConfig.bitRate > 5000) {
                    [self updateOverlayText:@"Slow connection to PC\nReduce your bitrate"];
                }
                else {
                    [self updateOverlayText:@"Poor connection to PC"];
                }
                break;
        }
    });
}

- (void) updatePreferredDisplayMode:(BOOL)streamActive {
#if TARGET_OS_TV
    if (@available(tvOS 11.2, *)) {
        UIWindow* window = [[[UIApplication sharedApplication] delegate] window];
        AVDisplayManager* displayManager = [window avDisplayManager];
        
        // This logic comes from Kodi and MrMC
        if (streamActive) {
            int dynamicRange;
            
            if (LiGetCurrentHostDisplayHdrMode()) {
                dynamicRange = 2; // HDR10
            }
            else {
                dynamicRange = 0; // SDR
            }
            
            AVDisplayCriteria* displayCriteria = [[AVDisplayCriteria alloc] initWithRefreshRate:[_settings.framerate floatValue]
                                                                              videoDynamicRange:dynamicRange];
            displayManager.preferredDisplayCriteria = displayCriteria;
        }
        else {
            // Switch back to the default display mode
            displayManager.preferredDisplayCriteria = nil;
        }
    }
#endif
}

- (void) setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s", enabled ? "active" : "inactive");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updatePreferredDisplayMode:YES];
    });
}

- (void) videoContentShown {
    [_spinner stopAnimating];
    [self.view setBackgroundColor:[UIColor blackColor]];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)gamepadPresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)mousePresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
#endif
}

- (void) streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit");
    
    [self returnToMainFrame];
}

- (void)userInteractionBegan {
    // Disable hiding home bar when user is interacting.
    // iOS will force it to be shown anyway, but it will
    // also discard our edges deferring system gestures unless
    // we willingly give up home bar hiding preference.
    _userIsInteracting = YES;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)userInteractionEnded {
    // Enable home bar hiding again if conditions allow
    _userIsInteracting = NO;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

#if !TARGET_OS_TV
// Require a confirmation when streaming to activate a system gesture
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    if ([_controllerSupport getConnectedGamepadCount] > 0 &&
        [_streamView getCurrentOscState] == OnScreenControlsLevelOff &&
        _userIsInteracting == NO) {
        // Autohide the home bar when a gamepad is connected
        // and the on-screen controls are disabled. We can't
        // do this all the time because any touch on the display
        // will cause the home indicator to reappear, and our
        // preferredScreenEdgesDeferringSystemGestures will also
        // be suppressed (leading to possible errant exits of the
        // stream).
        return YES;
    }
    
    return NO;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (BOOL)prefersPointerLocked {
    // Pointer lock breaks the UIKit mouse APIs, which is a problem because
    // GCMouse is horribly broken on iOS 14.0 for certain mice. Only lock
    // the cursor if there is a GCMouse present.
    return MNMouse.captured && [GCMouse mice].count > 0;
}
#endif

@end
