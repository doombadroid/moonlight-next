//
//  OnScreenControls.h
//  Moonlight
//
//  Created by Diego Waxemberg on 12/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ControllerSupport;
@class StreamConfiguration;

@interface OnScreenControls : NSObject

typedef NS_ENUM(NSInteger, OnScreenControlsLevel) {
    OnScreenControlsLevelOff,
    OnScreenControlsLevelAuto,
    OnScreenControlsLevelSimple,
    OnScreenControlsLevelFull,
    
    // Internal levels selected by ControllerSupport
    OnScreenControlsLevelAutoGCGamepad,
    OnScreenControlsLevelAutoGCExtendedGamepad,
    OnScreenControlsLevelAutoGCExtendedGamepadWithStickButtons
};

- (id) initWithView:(UIView*)view controllerSup:(ControllerSupport*)controllerSupport streamConfig:(StreamConfiguration*)streamConfig;
- (BOOL) handleTouchDownEvent:(NSSet*)touches;
- (BOOL) handleTouchUpEvent:(NSSet*)touches;
- (BOOL) handleTouchMovedEvent:(NSSet*)touches;
- (void) setLevel:(OnScreenControlsLevel)level;
- (OnScreenControlsLevel) getLevel;
- (void) show;
- (void) relayout;
// The view's safe-area insets, grown to keep clear of active occlusion regions such as the
// iPhone Duo's outer camera (iOS 27.1), which the safe area does not include.
+ (UIEdgeInsets) obstructedInsetsForView:(UIView*)view;

// Layout editor: while editing, touches drag controls instead of pressing them. Layouts are
// kept per posture (folded, phone landscape, unfolded) and either per game or for all games.
- (void) setEditing:(BOOL)editing;
- (BOOL) isEditing;
- (void) resetLayout;
- (void) saveLayoutForThisGame:(BOOL)thisGame;
- (BOOL) hasLayoutForThisGame;

@end
