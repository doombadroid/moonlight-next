//
//  StreamManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamManager.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "Utils.h"

#import "StreamView.h"
#import "ServerInfoResponse.h"
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "IdManager.h"

#include <Limelight.h>

@implementation StreamManager {
    StreamConfiguration* _config;

    UIView* _renderView;
    id<ConnectionCallbacks> _callbacks;
    Connection* _connection;
    NSMutableArray<NSNumber*>* _lateHistory;   // worst delay spike per second, ms
    NSMutableArray<NSNumber*>* _stutterHistory; // network hitches per second
    NSMutableArray<NSNumber*>* _hostGapHistory; // PC frame gaps per second
    CFTimeInterval _lastStatsEnd;
}

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
    _config = config;
    _renderView = view;
    _callbacks = callbacks;
    _config.riKey = [Utils randomBytes:16];
    _config.riKeyId = arc4random();
    return self;
}

- (void)main {
    [CryptoManager generateKeyPairUsingSSL];
    
    HttpManager* hMan = [[HttpManager alloc] initWithAddress:_config.host httpsPort:_config.httpsPort
                                                     serverCert:_config.serverCert];
    
    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                       fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
    NSString* pairStatus = [serverInfoResp getStringTag:@"PairStatus"];
    NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
    NSString* gfeVersion = [serverInfoResp getStringTag:@"GfeVersion"];
    NSString* serverState = [serverInfoResp getStringTag:@"state"];
    if (![serverInfoResp isStatusOk]) {
        [_callbacks launchFailed:serverInfoResp.statusMessage];
        return;
    }
    else if (pairStatus == NULL || appversion == NULL || serverState == NULL) {
        [_callbacks launchFailed:@"Failed to connect to PC"];
        return;
    }
    
    if (![pairStatus isEqualToString:@"1"]) {
        // Not paired
        [_callbacks launchFailed:@"Device not paired to PC"];
        return;
    }
    
    // Only perform this check on GFE (as indicated by MJOLNIR in state value)
    if ((_config.width > 4096 || _config.height > 4096) && [serverState containsString:@"MJOLNIR"]) {
        // Pascal added support for 8K HEVC encoding support. Maxwell 2 could encode HEVC but only up to 4K.
        // We can't directly identify Pascal, but we can look for HEVC Main10 which was added in the same generation.
        NSString* codecSupport = [serverInfoResp getStringTag:@"ServerCodecModeSupport"];
        if (codecSupport == nil || !([codecSupport intValue] & 0x200)) {
            [_callbacks launchFailed:@"Your host PC's GPU doesn't support streaming video resolutions over 4K."];
            return;
        }
    }
    
    // Populate the config's version fields from serverinfo
    _config.appVersion = appversion;
    _config.gfeVersion = gfeVersion;
    
    // resumeApp and launchApp handle calling launchFailed
    NSString* sessionUrl;
    if ([serverState hasSuffix:@"_SERVER_BUSY"]) {
        // App already running, resume it
        if (![self resumeApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    } else {
        // Start app
        if (![self launchApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    }
    
    // Populate RTSP session URL from launch/resume response
    _config.rtspSessionUrl = sessionUrl;
    
    // Initializing the renderer must be done on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        VideoDecoderRenderer* renderer = [[VideoDecoderRenderer alloc] initWithView:self->_renderView callbacks:self->_callbacks streamAspectRatio:(float)self->_config.width / (float)self->_config.height useFramePacing:self->_config.useFramePacing];
        self->_connection = [[Connection alloc] initWithConfig:self->_config renderer:renderer connectionCallbacks:self->_callbacks];
        NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
        [opQueue addOperation:self->_connection];
    });
}

- (void) stopStream
{
    [_connection terminate];
}

- (BOOL) launchApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* launchResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:launchResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"launch" config:_config]]];
    NSString *gameSession = [launchResp getStringTag:@"gamesession"];
    if (![launchResp isStatusOk]) {
        [_callbacks launchFailed:launchResp.statusMessage];
        Log(LOG_E, @"Failed Launch Response: %@", launchResp.statusMessage);
        return FALSE;
    } else if (gameSession == NULL || [gameSession isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to launch app"];
        Log(LOG_E, @"Failed to parse game session");
        return FALSE;
    }
    
    *sessionUrl = [launchResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (BOOL) resumeApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* resumeResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:resumeResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"resume" config:_config]]];
    NSString* resume = [resumeResp getStringTag:@"resume"];
    if (![resumeResp isStatusOk]) {
        [_callbacks launchFailed:resumeResp.statusMessage];
        Log(LOG_E, @"Failed Resume Response: %@", resumeResp.statusMessage);
        return FALSE;
    } else if (resume == NULL || [resume isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to resume app"];
        Log(LOG_E, @"Failed to parse resume response");
        return FALSE;
    }
    
    *sessionUrl = [resumeResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (NSString*) getStatsOverlayText {
    video_stats_t stats;
    
    if (!_connection) {
        return nil;
    }
    
    if (![_connection getVideoStats:&stats]) {
        return nil;
    }
    
    uint32_t rtt, variance;
    NSString* latencyString;
    if (LiGetEstimatedRttInfo(&rtt, &variance)) {
        latencyString = [NSString stringWithFormat:@"%u ms (variance: %u ms)", rtt, variance];
    }
    else {
        latencyString = @"N/A";
    }
    
    NSString* hostProcessingString;
    if (stats.framesWithHostProcessingLatency != 0) {
        hostProcessingString = [NSString stringWithFormat:@"\nHost processing latency min/max/avg: %.1f/%.1f/%.1f ms",
                                stats.minHostProcessingLatency / 10.f,
                                stats.maxHostProcessingLatency / 10.f,
                                (float)stats.totalHostProcessingLatency / stats.framesWithHostProcessingLatency / 10.f];
    }
    else {
        hostProcessingString = @"";
    }
    
    float interval = stats.endTime - stats.startTime;
    return [NSString stringWithFormat:@"Video stream: %dx%d %.2f FPS (Codec: %@)\nFrames dropped by your network connection: %.2f%%\nAverage network latency: %@%@%@",
            _config.width,
            _config.height,
            stats.totalFrames / interval,
            [_connection getActiveCodecName],
            stats.networkDroppedFrames / interval,
            latencyString,
            hostProcessingString,
            [self stutterTextForStats:&stats]];
}

// Stutter diagnostics: a 30-second graph of network delay spikes, hitch counts split
// between the network and the PC, and a tip when hitches repeat on a fixed period (the
// usual sign of Wi-Fi scanning or AirDrop/AWDL channel hopping on the phone).
- (NSString*) stutterTextForStats:(video_stats_t*)stats {
    const NSUInteger window = 30;
    if (_lateHistory == nil) {
        _lateHistory = [NSMutableArray array];
        _stutterHistory = [NSMutableArray array];
        _hostGapHistory = [NSMutableArray array];
    }
    if (stats->endTime != _lastStatsEnd) {
        // The overlay timer can read the same one-second window twice
        _lastStatsEnd = stats->endTime;
        [_lateHistory addObject:@(stats->maxLateUs / 1000.0)];
        [_stutterHistory addObject:@(stats->networkStutters)];
        [_hostGapHistory addObject:@(stats->hostGaps)];
        while (_lateHistory.count > window) {
            [_lateHistory removeObjectAtIndex:0];
            [_stutterHistory removeObjectAtIndex:0];
            [_hostGapHistory removeObjectAtIndex:0];
        }
    }

    NSMutableString* graph = [NSMutableString string];
    double worst = 0;
    for (NSNumber* ms in _lateHistory) {
        double v = ms.doubleValue;
        worst = MAX(worst, v);
        [graph appendString:v < 5 ? @"▁" : v < 10 ? @"▂" : v < 20 ? @"▃" : v < 35 ? @"▄" : v < 60 ? @"▆" : @"█"];
    }
    int network = [[_stutterHistory valueForKeyPath:@"@sum.self"] intValue];
    int host = [[_hostGapHistory valueForKeyPath:@"@sum.self"] intValue];

    NSMutableString* text = [NSMutableString stringWithFormat:@"\nNetwork delay spikes: %@ worst %.0f ms\nHitches in %lus: %d from the network, %d from the PC",
                             graph, worst, (unsigned long)_lateHistory.count, network, host];

    // Periodic hitches: evenly spaced stutters within the last minute
    uint64_t times[MN_STUTTER_HISTORY];
    int n = [_connection getRecentStutterTimes:times];
    uint64_t now = LiGetMicroseconds();
    int first = 0;
    while (first < n && now - times[first] > 60000000ULL) first++;
    int count = n - first;
    double period = 0;
    if (count >= 5) {
        double sum = 0, sumSq = 0;
        for (int i = first + 1; i < n; i++) {
            double d = (times[i] - times[i - 1]) / 1e6;
            sum += d;
            sumSq += d * d;
        }
        double mean = sum / (count - 1);
        double sd = sqrt(MAX(sumSq / (count - 1) - mean * mean, 0));
        if (mean >= 0.25 && mean <= 15 && sd / mean < 0.25) {
            period = mean;
        }
    }

    if (period > 0) {
        [text appendFormat:@"\nTip: hitches repeat every %.1f s. That rhythm is usually the phone scanning Wi-Fi. Turn off AirDrop and Handoff, and use a 5 or 6 GHz network.", period];
    }
    else if (network >= 3) {
        [text appendString:@"\nTip: the network is delaying frames. Move closer to the router, use 5 or 6 GHz, wire the PC, or lower the bitrate."];
    }
    else if (host >= 10 && network == 0) {
        [text appendString:@"\nThe PC is skipping frames: the game or encoder isn't keeping up. A still desktop does this too."];
    }
    return text;
}

@end
