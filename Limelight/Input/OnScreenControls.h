//
//  OnScreenControls.h
//  Moonlight
//
//  Created by Diego Waxemberg on 12/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

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

// Layout editor: while editing, touches select and drag controls instead of pressing them.
// Layouts are kept per posture (folded, phone landscape, unfolded) and either per game or for
// all games. A layout is a property list: control id -> @[dx, dy] or @[dx, dy, scale, opacity,
// hidden], plus @"opacity" -> NSNumber for every control. Keys this build doesn't know are kept
// as they are, so other kinds of control can store their own entries in the same layout.
- (void) setEditing:(BOOL)editing;
- (BOOL) isEditing;
- (void) resetLayout NS_SWIFT_NAME(resetLayout());
- (void) saveLayoutForThisGame:(BOOL)thisGame;
- (BOOL) hasLayoutForThisGame;

// Called on every change the editor UI should show: selection, layout, undo stack
@property (nonatomic, copy, nullable) void (^editorChanged)(void);
// Ids of the controls the editor can select, in a fixed order
+ (NSArray<NSString*>*) controlIds NS_SWIFT_NAME(controlIds());
- (NSString*) currentPosture NS_SWIFT_NAME(currentPosture());
- (nullable NSString*) selectedControl NS_SWIFT_NAME(selectedControl());
- (void) selectControl:(nullable NSString*)control NS_SWIFT_NAME(selectControl(_:));
- (NSString*) displayNameForControl:(NSString*)control NS_SWIFT_NAME(displayName(forControl:));
- (CGFloat) scaleForControl:(NSString*)control NS_SWIFT_NAME(scale(forControl:));
- (void) setScale:(CGFloat)scale forControl:(NSString*)control NS_SWIFT_NAME(setScale(_:forControl:));
- (CGFloat) opacityForControl:(NSString*)control NS_SWIFT_NAME(opacity(forControl:));
- (void) setOpacity:(CGFloat)opacity forControl:(NSString*)control NS_SWIFT_NAME(setOpacity(_:forControl:));
- (BOOL) isControlHidden:(NSString*)control NS_SWIFT_NAME(isControlHidden(_:));
- (void) setHidden:(BOOL)hidden forControl:(NSString*)control NS_SWIFT_NAME(setHidden(_:forControl:));
- (void) resetControl:(NSString*)control NS_SWIFT_NAME(resetControl(_:));
@property (nonatomic) CGFloat globalOpacity;
@property (nonatomic) BOOL snapToGuides;
// Slider setters don't record undo steps on their own: call pushUndo once when a slider drag
// begins. Every other change records its own step.
- (void) pushUndo NS_SWIFT_NAME(pushUndo());
- (BOOL) canUndo NS_SWIFT_NAME(canUndo());
- (void) undo NS_SWIFT_NAME(undo());
// The layout being edited, and replacing it (an undoable step), for profiles and templates
- (NSDictionary<NSString*, id>*) layoutDictionary NS_SWIFT_NAME(layoutDictionary());
- (void) applyLayoutDictionary:(NSDictionary<NSString*, id>*)layout NS_SWIFT_NAME(applyLayoutDictionary(_:));

@end

NS_ASSUME_NONNULL_END
