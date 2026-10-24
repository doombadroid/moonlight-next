//
//  MNBridge.m
//  Moonlight Next
//

@import AVFoundation;
@import VideoToolbox;

#import "MNBridge.h"
#import "DataManager.h"
#import "TemporaryApp.h"
#import "TemporarySettings.h"
#import "HttpManager.h"
#import "ServerInfoResponse.h"
#import "StreamConfiguration.h"
#import "StreamFrameViewController.h"
#import "ControllerSupport.h"

#include <Limelight.h>

@implementation MNBridge

+ (StreamConfiguration*) streamConfigForApp:(TemporaryApp*)app window:(UIWindow*)window {
    StreamConfiguration* config = [[StreamConfiguration alloc] init];
    config.host = app.host.activeAddress;
    config.httpsPort = app.host.httpsPort;
    config.appID = app.id;
    config.appName = app.name;
    config.serverCert = app.host.serverCert;

    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* streamSettings = [dataMan getSettings];

    // Don't stream more FPS than the display can show
    NSInteger maxFps = window.screen.maximumFramesPerSecond;
    config.frameRate = [streamSettings.framerate intValue];
    if (maxFps > 0 && config.frameRate > maxFps) {
        config.frameRate = (int)maxFps;
        Log(LOG_W, @"Clamping FPS to maximum refresh rate: %d", config.frameRate);
    }

    config.width = [streamSettings.width intValue];
    config.height = [streamSettings.height intValue];
    if (config.width == 0 || config.height == 0) {
        // "Native": the pixel size of the window the stream will fill. On a phone-sized
        // display the stream is landscape-only, so use the long edge as the width.
        CGFloat scale = window.screen.scale;
        CGFloat w = window.bounds.size.width * scale;
        CGFloat h = window.bounds.size.height * scale;
        if (window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact ||
            window.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact) {
            CGFloat longEdge = MAX(w, h), shortEdge = MIN(w, h);
            w = longEdge;
            h = shortEdge;
        }
        // Encoders want even dimensions
        config.width = ((int)w) & ~1;
        config.height = ((int)h) & ~1;
        Log(LOG_I, @"Native resolution resolved to %dx%d", config.width, config.height);
    }

    config.bitRate = [streamSettings.bitrate intValue];
    config.optimizeGameSettings = streamSettings.optimizeGames;
    config.playAudioOnPC = streamSettings.playAudioOnPC;
    config.useFramePacing = streamSettings.useFramePacing;
    config.swapABXYButtons = streamSettings.swapABXYButtons;

    // multiController must be set before calling getConnectedGamepadMask
    config.multiController = streamSettings.multiController;
    config.gamepadMask = [ControllerSupport getConnectedGamepadMask:config];

    // Probe for supported channel configurations
    int physicalOutputChannels = (int)[AVAudioSession sharedInstance].maximumOutputNumberOfChannels;
    int numberOfChannels = MIN([streamSettings.audioConfig intValue], physicalOutputChannels);
    if (numberOfChannels >= 8) {
        config.audioConfiguration = AUDIO_CONFIGURATION_71_SURROUND;
    }
    else if (numberOfChannels >= 6) {
        config.audioConfiguration = AUDIO_CONFIGURATION_51_SURROUND;
    }
    else {
        config.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    }

    config.serverCodecModeSupport = app.host.serverCodecModeSupport;

    switch (streamSettings.preferredCodec) {
        case CODEC_PREF_AV1:
            if (VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)) {
                config.supportedVideoFormats |= VIDEO_FORMAT_AV1_MAIN8;
            }
            // Fall-through

        case CODEC_PREF_AUTO:
        case CODEC_PREF_HEVC:
            if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
                config.supportedVideoFormats |= VIDEO_FORMAT_H265;
            }
            // Fall-through

        case CODEC_PREF_H264:
            config.supportedVideoFormats |= VIDEO_FORMAT_H264;
            break;
    }

    // HEVC is supported if the user wants it (or it's required by the chosen resolution) and the SoC supports it
    if ((config.width > 4096 || config.height > 4096 || streamSettings.enableHdr) && VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
        config.supportedVideoFormats |= VIDEO_FORMAT_H265;

        // HEVC Main10 is supported if the user wants it and the display supports it
        if (streamSettings.enableHdr && (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10) != 0) {
            config.supportedVideoFormats |= VIDEO_FORMAT_H265_MAIN10;
        }
    }

    // Add the AV1 Main10 format if AV1 and HDR are both enabled and supported
    if ((config.supportedVideoFormats & VIDEO_FORMAT_MASK_AV1) && streamSettings.enableHdr &&
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) && (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10) != 0) {
        config.supportedVideoFormats |= VIDEO_FORMAT_AV1_MAIN10;
    }

    return config;
}

+ (UIViewController*) streamControllerWithConfig:(StreamConfiguration*)config
                                          onExit:(void (^)(BOOL quitApp))onExit {
    StreamFrameViewController* stream = [[StreamFrameViewController alloc] init];
    stream.streamConfig = config;
    stream.onExit = onExit;
    stream.modalPresentationStyle = UIModalPresentationFullScreen;
    return stream;
}

+ (NSString*) refreshServerInfoForHost:(TemporaryHost*)host {
    HttpManager* hMan = [[HttpManager alloc] initWithHost:host];
    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                                        fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
    if (![serverInfoResp isStatusOk]) {
        Log(LOG_W, @"Failed to get server info: %@", serverInfoResp.statusMessage);
        return serverInfoResp.statusMessage ?: @"Failed to connect to the PC.";
    }
    [serverInfoResp populateHost:host];
    return nil;
}

+ (NSString*) quitAppOnHost:(TemporaryHost*)host {
    HttpManager* hMan = [[HttpManager alloc] initWithHost:host];
    HttpResponse* quitResponse = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:quitResponse withUrlRequest:[hMan newQuitAppRequest]]];
    if (quitResponse.statusCode == 200) {
        ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
        [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                                            fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
        if (![serverInfoResp isStatusOk] || [[serverInfoResp getStringTag:@"state"] hasSuffix:@"_SERVER_BUSY"]) {
            // On newer GFE versions, the quit request succeeds even though the app doesn't
            // really quit if another client tries to kill your app.
            quitResponse.statusCode = 599;
        }
        else {
            [serverInfoResp populateHost:host];
        }
    }

    if (quitResponse.statusCode != 200) {
        return @"Failed to quit app. If this app was started by another device, you'll need to quit from that device.";
    }
    host.currentGame = @"0";
    return nil;
}

+ (NSString*) runNetworkTest {
    unsigned int portTestResult = LiTestClientConnectivity(CONN_TEST_SERVER, 443, ML_PORT_FLAG_ALL);
    if (portTestResult == 0) {
        return @"This network does not appear to be blocking Moonlight. If you still have trouble connecting, check your PC's firewall settings.";
    }
    else if (portTestResult == ML_TEST_RESULT_INCONCLUSIVE) {
        return @"The network test could not be performed because none of Moonlight's connection testing servers were reachable. Check your Internet connection or try again later.";
    }
    char blockedPorts[512];
    LiStringifyPortFlags(portTestResult, "\n", blockedPorts, sizeof(blockedPorts));
    return [NSString stringWithFormat:@"Your current network connection seems to be blocking Moonlight. Streaming may not work while connected to this network.\n\nThe following network ports were blocked:\n%s", blockedPorts];
}

+ (NSString*) addHostPortBlockingNote {
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443,
                                                            ML_PORT_FLAG_TCP_47984 | ML_PORT_FLAG_TCP_47989);
    if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
        return @"\n\nYour device's network connection is blocking Moonlight. Streaming may not work while connected to this network.";
    }
    return @"";
}

+ (BOOL) hevcSupported {
    return VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC);
}

+ (BOOL) av1Supported {
    return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1);
}

+ (BOOL) hdrSupported {
    return [self hevcSupported] && (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10) != 0;
}

@end
