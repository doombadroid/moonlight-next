//
//  Connection.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "VideoDecoderRenderer.h"
#import "StreamConfiguration.h"

#define CONN_TEST_SERVER "ios.conntest.moonlight-stream.org"

typedef struct {
    CFTimeInterval startTime;
    CFTimeInterval endTime;
    int totalFrames;
    int receivedFrames;
    int networkDroppedFrames;
    int totalHostProcessingLatency;
    int framesWithHostProcessingLatency;
    int maxHostProcessingLatency;
    int minHostProcessingLatency;
    // Stutter diagnostics: a frame is "late" by how much more time passed between its
    // arrival and the previous frame's than passed between their capture on the PC
    uint32_t maxLateUs;      // worst network delay spike in this window
    int networkStutters;     // frames late enough to show as a hitch
    int hostGaps;            // gaps the PC itself left between captured frames
} video_stats_t;

#define MN_STUTTER_HISTORY 16

@interface Connection : NSOperation <NSStreamDelegate>

-(id) initWithConfig:(StreamConfiguration*)config renderer:(VideoDecoderRenderer*)myRenderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks;
-(void) terminate;
-(void) main;
-(BOOL) getVideoStats:(video_stats_t*)stats;
// Arrival times (microseconds, LiGetMicroseconds clock) of the most recent network stutters,
// oldest first. Returns how many were written.
-(int) getRecentStutterTimes:(uint64_t*)times;
-(NSString*) getActiveCodecName;

@end
