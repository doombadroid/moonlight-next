//
//  VideoDecoderRenderer.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/18/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "VideoDecoderRenderer.h"
#import "StreamView.h"
#if !TARGET_OS_TV
#import "Moonlight-Swift.h"
#endif
#include "FramePacer.h"

@import VideoToolbox;
#include <os/lock.h>

#include <libavcodec/avcodec.h>
#include <libavcodec/cbs.h>
#include <libavcodec/cbs_av1.h>
#include <libavformat/avio.h>
#include <libavutil/mem.h>

// Private libavformat API for writing the AV1 Codec Configuration Box
extern int ff_isom_write_av1c(AVIOContext *pb, const uint8_t *buf, int size,
                              int write_seq_header);

@implementation VideoDecoderRenderer {
    StreamView* _view;
    id<ConnectionCallbacks> _callbacks;
    float _streamAspectRatio;
    
    AVSampleBufferDisplayLayer* displayLayer;
    int videoFormat;
    int frameRate;
    
    NSMutableArray *parameterSetBuffers;
    NSData *masteringDisplayColorVolume;
    NSData *contentLightLevelInfo;
    CMVideoFormatDescriptionRef formatDesc;
    
    CADisplayLink* _displayLink;
    int _tickRate; // display refreshes per second we ask for: the frame rate, doubled when interpolating

    // Settings › Video, read when the stream starts
    int _pacingMode;
    int _queueDepth;
    BOOL _videoToolbox;
    BOOL _interpolating;
    MNFramePacer _receivedPacer; // frames waiting in moonlight-common-c's queue
    MNFramePacer _decodedPacer;  // frames VideoToolbox decoded (and interpolated), waiting to be shown

    // VideoToolbox renderer: decodes to pixel buffers, which go to the same display layer as
    // uncompressed sample buffers, so picture in picture and the external display keep working
    VTDecompressionSessionRef _vtSession;
    CMVideoFormatDescriptionRef _imageFormatDesc; // only touched on VideoToolbox's output thread
    OSStatus _decodeStatus;
    NSMutableArray* _decoded; // CMSampleBuffers, guarded by @synchronized(_decoded)
#if !TARGET_OS_TV
    MNFrameInterpolator* _interpolator;
#endif

    // Stats: decode time and interpolated frames, in one-second windows
    os_unfair_lock _statsLock;
    CFTimeInterval _statsWindowStart;
    double _decodeSumMs, _decodeMaxMs, _lastDecodeAvgMs, _lastDecodeMaxMs;
    int _decodeCount, _drawnCount, _lastDecodeCount, _lastDrawnCount;
}

#define MN_PACING_LOWEST 0
#define MN_PACING_BALANCED 1
#define MN_PACING_SMOOTHEST 2

- (void)reinitializeDisplayLayer
{
    CALayer *oldLayer = displayLayer;
    
    displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    displayLayer.backgroundColor = [UIColor blackColor].CGColor;
    
    // Ensure the AVSampleBufferDisplayLayer is sized to preserve the aspect ratio
    // of the video stream. We used to use AVLayerVideoGravityResizeAspect, but that
    // respects the PAR encoded in the SPS which causes our computed video-relative
    // touch location to be wrong in StreamView if the aspect ratio of the host
    // desktop doesn't match the aspect ratio of the stream.
    CGSize videoSize;
    if (_view.bounds.size.width > _view.bounds.size.height * _streamAspectRatio) {
        videoSize = CGSizeMake(_view.bounds.size.height * _streamAspectRatio, _view.bounds.size.height);
    } else {
        videoSize = CGSizeMake(_view.bounds.size.width, _view.bounds.size.width / _streamAspectRatio);
    }
    displayLayer.position = CGPointMake(CGRectGetMidX(_view.bounds), CGRectGetMidY(_view.bounds));
    displayLayer.bounds = CGRectMake(0, 0, videoSize.width, videoSize.height);
    displayLayer.videoGravity = AVLayerVideoGravityResize;

    // Hide the layer until we get an IDR frame. This ensures we
    // can see the loading progress label as the stream is starting.
    displayLayer.hidden = YES;
    
    // The layer may have been moved to an external display; replace it wherever it is
    CALayer *parent = oldLayer.superlayer ?: _view.layer;
    if (oldLayer != nil) {
        // Switch out the old display layer with the new one
        [parent replaceSublayer:oldLayer with:displayLayer];
    }
    else {
        [parent addSublayer:displayLayer];
    }
    // Lets the hosting view re-fit the new layer to its own bounds
    [parent setNeedsLayout];
    
    if (formatDesc != nil) {
        CFRelease(formatDesc);
        formatDesc = nil;
    }

#if !TARGET_OS_TV
    // A replacement layer (after a decoder failure) becomes the new PiP source
    if (frameRate > 0) {
        [MNPictureInPicture.shared attach:displayLayer frameRate:frameRate];
    }
#endif
}

- (id)initWithView:(StreamView*)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspectRatio useFramePacing:(BOOL)useFramePacing
{
    self = [super init];
    
    _view = view;
    _callbacks = callbacks;
    _streamAspectRatio = aspectRatio;

    // Set on iOS by Settings › Video; tvOS keeps the system decoder and its on/off pacing
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSNumber* pacing = [defaults objectForKey:@"mnFramePacingMode"];
    _pacingMode = pacing != nil ? pacing.intValue : (useFramePacing ? MN_PACING_BALANCED : MN_PACING_LOWEST);
    _queueDepth = MAX(1, MIN(4, (int)[defaults integerForKey:@"mnFrameQueueDepth"] ?: 2));
    _videoToolbox = [defaults integerForKey:@"mnVideoRenderer"] == 1;
    if (_videoToolbox) {
        _decoded = [[NSMutableArray alloc] init];
    }
    _statsLock = OS_UNFAIR_LOCK_INIT;
    
    parameterSetBuffers = [[NSMutableArray alloc] init];
    
    [self reinitializeDisplayLayer];
    
    return self;
}

- (void)setupWithVideoFormat:(int)videoFormat width:(int)videoWidth height:(int)videoHeight frameRate:(int)frameRate
{
    self->videoFormat = videoFormat;
    self->frameRate = frameRate;
}

- (void)start
{
#if !TARGET_OS_TV
    // x2 interpolation needs the VideoToolbox renderer and a screen fast enough for twice the frame rate
    if (_videoToolbox && [[NSUserDefaults standardUserDefaults] boolForKey:@"mnFrameInterpolation"]
        && frameRate * 2 <= [UIScreen mainScreen].maximumFramesPerSecond && MNFrameInterpolator.isSupported) {
        __weak VideoDecoderRenderer* weakSelf = self;
        _interpolator = [[MNFrameInterpolator alloc] initWithOutput:^(CMSampleBufferRef frame, BOOL drawn) {
            [weakSelf queueDecodedFrame:frame drawn:drawn];
        }];
        _interpolating = YES;
    }
#endif
    _tickRate = _interpolating ? frameRate * 2 : frameRate;

    int hold = _pacingMode == MN_PACING_SMOOTHEST ? _queueDepth : _pacingMode == MN_PACING_BALANCED ? 1 : 0;
    BOOL steady = _pacingMode == MN_PACING_SMOOTHEST;
    if (_interpolating) {
        // Decode on arrival, then show one decoded or drawn frame per 120 Hz refresh. The buffer
        // is counted in refreshes, two per stream frame, and always keeps at least one.
        _receivedPacer = (MNFramePacer){0, false, false};
        _decodedPacer = (MNFramePacer){MAX(1, hold * 2), true, true};
    }
    else {
        _receivedPacer = (MNFramePacer){hold, steady, steady};
        _decodedPacer = (MNFramePacer){0, false, false};
    }

    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
    if (@available(iOS 15.0, tvOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(_tickRate, _tickRate, _tickRate);
    }
    else {
        _displayLink.preferredFramesPerSecond = _tickRate;
    }
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];

#if !TARGET_OS_TV
    // The display link stops in the background, so PiP pulls frames on its own timer
    __weak VideoDecoderRenderer* weakSelf = self;
    MNPictureInPicture.shared.pump = ^{ [weakSelf pollFramesPaced:NO]; };
    [MNPictureInPicture.shared attach:displayLayer frameRate:frameRate];
#endif
}

// TODO: Refactor this
int DrSubmitDecodeUnit(PDECODE_UNIT decodeUnit);

- (void)displayLinkCallback:(CADisplayLink *)sender
{
    [self pollFramesPaced:YES];
}

- (void)pollFramesPaced:(BOOL)paced
{
    if (paced) {
        // Only pace frames if the display refresh rate is >= 90% of the rate we asked for.
        // Battery saver, accessibility settings, or device thermals can cause the actual
        // refresh rate of the display to drop below the physical maximum.
        double displayRefreshRate = 1 / (_displayLink.targetTimestamp - _displayLink.timestamp);
        paced = displayRefreshRate >= _tickRate * 0.9f;
    }

    VIDEO_FRAME_HANDLE handle;
    PDECODE_UNIT du;
    int count = paced ? MNFramePacerRelease(&_receivedPacer, LiGetPendingVideoFrames()) : INT_MAX;
    while (count-- > 0 && LiPollNextVideoFrame(&handle, &du)) {
        LiCompleteVideoFrame(handle, DrSubmitDecodeUnit(du));
    }

    if (_decoded != nil) {
        [self showDecodedFramesPaced:paced];
    }
}

- (void)stop
{
    [_displayLink invalidate];
#if !TARGET_OS_TV
    [MNPictureInPicture.shared detach];
#endif
    // Decoding happens on the main thread, so the decoder is torn down there too
    dispatch_async(dispatch_get_main_queue(), ^{
        [self destroyDecompressionSession];
#if !TARGET_OS_TV
        [self->_interpolator stop];
#endif
    });
}

- (void)dealloc
{
    [self destroyDecompressionSession];
    if (_imageFormatDesc != NULL) {
        CFRelease(_imageFormatDesc);
    }
    if (formatDesc != NULL) {
        CFRelease(formatDesc);
    }
}

#pragma mark - VideoToolbox renderer
// Adapted from VoidLink (GPLv3), Stream/VideoDecoderRenderer.m (VTDecompressionSession path)

- (void)destroyDecompressionSession
{
    if (_vtSession != NULL) {
        VTDecompressionSessionWaitForAsynchronousFrames(_vtSession);
        VTDecompressionSessionInvalidate(_vtSession);
        CFRelease(_vtSession);
        _vtSession = NULL;
    }
}

- (BOOL)createDecompressionSession
{
    [self destroyDecompressionSession];

    // No pixel format requested: the decoder's own format (8 or 10 bit, 4:2:0 or 4:4:4, the
    // stream's range) needs no conversion, and the display layer shows any of them
    NSDictionary* attributes = @{ (id)kCVPixelBufferIOSurfacePropertiesKey: @{} };
    OSStatus status = VTDecompressionSessionCreate(kCFAllocatorDefault, formatDesc, NULL,
                                                   (__bridge CFDictionaryRef)attributes, NULL, &_vtSession);
    if (status != noErr) {
        Log(LOG_E, @"VTDecompressionSessionCreate failed: %d", (int)status);
        _vtSession = NULL;
        return NO;
    }
    VTSessionSetProperty(_vtSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    return YES;
}

// Decodes on the calling (main) thread and waits, so the frame is ready before this returns
- (int)decodeSampleBuffer:(CMSampleBufferRef)sampleBuffer frameType:(int)frameType
{
    BOOL idr = frameType == FRAME_TYPE_IDR;
    if (idr) {
        // A new format description comes with every IDR frame (HDR on/off, resolution)
        if (![self createDecompressionSession]) {
            return DR_NEED_IDR;
        }
    }
    else if (_vtSession == NULL) {
        // A new decoder has to start at an IDR frame
        return DR_NEED_IDR;
    }

    // HDR metadata as it was for this frame, attached to the decoded image
    NSData* mdcv = masteringDisplayColorVolume;
    NSData* cll = contentLightLevelInfo;
    CFTimeInterval start = CACurrentMediaTime();
    _decodeStatus = noErr;
    OSStatus status = VTDecompressionSessionDecodeFrameWithOutputHandler(_vtSession, sampleBuffer, 0, NULL,
        ^(OSStatus outStatus, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime pts, CMTime duration) {
            if (outStatus != noErr) {
                self->_decodeStatus = outStatus;
            }
            else if (imageBuffer != NULL) {
                [self decodedImage:imageBuffer pts:pts decodeMs:(CACurrentMediaTime() - start) * 1000
                           restart:idr mdcv:mdcv cll:cll];
            }
        });
    if (status == noErr) {
        VTDecompressionSessionWaitForAsynchronousFrames(_vtSession);
        status = _decodeStatus;
    }
    if (status != noErr) {
        Log(LOG_E, @"VideoToolbox decode failed: %d", (int)status);
        if (status == kVTInvalidSessionErr) {
            // iOS dropped the decoder (usually while in the background); a new one starts at the next IDR frame
            [self destroyDecompressionSession];
        }
        return DR_NEED_IDR;
    }
    return DR_OK;
}

// On VideoToolbox's output thread
- (void)decodedImage:(CVImageBufferRef)image pts:(CMTime)pts decodeMs:(double)decodeMs
             restart:(BOOL)restart mdcv:(NSData*)mdcv cll:(NSData*)cll
{
    os_unfair_lock_lock(&_statsLock);
    [self rollStatsWindow];
    _decodeSumMs += decodeMs;
    _decodeMaxMs = MAX(_decodeMaxMs, decodeMs);
    _decodeCount++;
    os_unfair_lock_unlock(&_statsLock);

    // The decoder tags color primaries, transfer and matrix; HDR10 mastering metadata is added here
    if (mdcv != nil) {
        CVBufferSetAttachment(image, kCVImageBufferMasteringDisplayColorVolumeKey, (__bridge CFDataRef)mdcv, kCVAttachmentMode_ShouldPropagate);
    }
    if (cll != nil) {
        CVBufferSetAttachment(image, kCVImageBufferContentLightLevelInfoKey, (__bridge CFDataRef)cll, kCVAttachmentMode_ShouldPropagate);
    }

    if (_imageFormatDesc == NULL || !CMVideoFormatDescriptionMatchesImageBuffer(_imageFormatDesc, image)) {
        if (_imageFormatDesc != NULL) {
            CFRelease(_imageFormatDesc);
            _imageFormatDesc = NULL;
        }
        if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, image, &_imageFormatDesc) != noErr) {
            _imageFormatDesc = NULL;
            return;
        }
    }

    CMSampleTimingInfo timing = {kCMTimeInvalid, pts, kCMTimeInvalid};
    CMSampleBufferRef frame;
    if (CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, image, _imageFormatDesc, &timing, &frame) != noErr) {
        return;
    }
#if !TARGET_OS_TV
    if (_interpolator != nil) {
        [_interpolator submit:frame restart:restart];
        CFRelease(frame);
        return;
    }
#endif
    [self queueDecodedFrame:frame drawn:NO];
    CFRelease(frame);
}

- (void)queueDecodedFrame:(CMSampleBufferRef)frame drawn:(BOOL)drawn
{
    if (drawn) {
        os_unfair_lock_lock(&_statsLock);
        [self rollStatsWindow];
        _drawnCount++;
        os_unfair_lock_unlock(&_statsLock);
    }
    @synchronized (_decoded) {
        [_decoded addObject:(__bridge id)frame];
        // Nothing is showing them (the display link stopped): keep only the newest
        while (_decoded.count > 8) {
            [_decoded removeObjectAtIndex:0];
        }
    }
}

- (void)showDecodedFramesPaced:(BOOL)paced
{
    id frame;
    @synchronized (_decoded) {
        int count = (int)_decoded.count;
        if (paced) {
            count = MNFramePacerRelease(&_decodedPacer, count);
        }
        if (count <= 0) {
            return;
        }
        // Frames released together would land in the same refresh; only the newest would be seen
        frame = _decoded[count - 1];
        [_decoded removeObjectsInRange:NSMakeRange(0, count)];
    }
    [displayLayer enqueueSampleBuffer:(__bridge CMSampleBufferRef)frame];
    if (displayLayer.hidden) {
        // The first frame after a new layer is always an IDR frame
        displayLayer.hidden = NO;
        [_callbacks videoContentShown];
    }
}

// Call with _statsLock held
- (void)rollStatsWindow
{
    CFTimeInterval now = CACurrentMediaTime();
    if (now - _statsWindowStart < 1.0) {
        return;
    }
    _lastDecodeAvgMs = _decodeCount > 0 ? _decodeSumMs / _decodeCount : 0;
    _lastDecodeMaxMs = _decodeMaxMs;
    _lastDecodeCount = _decodeCount;
    _lastDrawnCount = _drawnCount;
    _decodeSumMs = _decodeMaxMs = 0;
    _decodeCount = _drawnCount = 0;
    _statsWindowStart = now;
}

- (BOOL)getDecodeTime:(double*)averageMs max:(double*)maxMs
{
    os_unfair_lock_lock(&_statsLock);
    *averageMs = _lastDecodeAvgMs;
    *maxMs = _lastDecodeMaxMs;
    BOOL have = _lastDecodeCount > 0;
    os_unfair_lock_unlock(&_statsLock);
    return _videoToolbox && have;
}

- (NSString*)statsDescription
{
    NSMutableString* text = [NSMutableString stringWithString:_videoToolbox ? @"VideoToolbox" : @"System decoder"];
    switch (_pacingMode) {
        case MN_PACING_SMOOTHEST:
            [text appendFormat:@", smoothest pacing (%d-frame queue)", _queueDepth];
            break;
        case MN_PACING_BALANCED:
            [text appendString:@", balanced pacing"];
            break;
        default:
            [text appendString:@", lowest latency"];
            break;
    }
    if (_interpolating) {
        os_unfair_lock_lock(&_statsLock);
        int drawn = _lastDrawnCount;
        os_unfair_lock_unlock(&_statsLock);
        [text appendFormat:@", x2 interpolation (%d drawn frames/s)", drawn];
    }
    int buffered = LiGetPendingVideoFrames();
    if (_decoded != nil) {
        @synchronized (_decoded) {
            buffered += (int)_decoded.count;
        }
    }
    [text appendFormat:@" · %d frame(s) buffered", buffered];
    return text;
}

#define NALU_START_PREFIX_SIZE 3
#define NAL_LENGTH_PREFIX_SIZE 4

- (void)updateAnnexBBufferForRange:(CMBlockBufferRef)frameBuffer dataBlock:(CMBlockBufferRef)dataBuffer offset:(int)offset length:(int)nalLength
{
    OSStatus status;
    size_t oldOffset = CMBlockBufferGetDataLength(frameBuffer);
    
    // Append a 4 byte buffer to the frame block for the length prefix
    status = CMBlockBufferAppendMemoryBlock(frameBuffer, NULL,
                                            NAL_LENGTH_PREFIX_SIZE,
                                            kCFAllocatorDefault, NULL, 0,
                                            NAL_LENGTH_PREFIX_SIZE, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendMemoryBlock failed: %d", (int)status);
        return;
    }
    
    // Write the length prefix to the new buffer
    const int dataLength = nalLength - NALU_START_PREFIX_SIZE;
    const uint8_t lengthBytes[] = {(uint8_t)(dataLength >> 24), (uint8_t)(dataLength >> 16),
        (uint8_t)(dataLength >> 8), (uint8_t)dataLength};
    status = CMBlockBufferReplaceDataBytes(lengthBytes, frameBuffer,
                                           oldOffset, NAL_LENGTH_PREFIX_SIZE);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferReplaceDataBytes failed: %d", (int)status);
        return;
    }
    
    // Attach the data buffer to the frame buffer by reference
    status = CMBlockBufferAppendBufferReference(frameBuffer, dataBuffer, offset + NALU_START_PREFIX_SIZE, dataLength, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendBufferReference failed: %d", (int)status);
        return;
    }
}

- (NSData*)getAv1CodecConfigurationBox:(NSData*)frameData  {
    AVIOContext* ioctx = NULL;
    int err;
    
    err = avio_open_dyn_buf(&ioctx);
    if (err < 0) {
        Log(LOG_E, @"avio_open_dyn_buf() failed: %d", err);
        return nil;
    }

    // Submit the IDR frame to write the av1C blob
    err = ff_isom_write_av1c(ioctx, (uint8_t*)frameData.bytes, (int)frameData.length, 1);
    if (err < 0) {
        Log(LOG_E, @"ff_isom_write_av1c() failed: %d", err);
        // Fall-through to close and free buffer
    }
    
    // Close the dynbuf and get the underlying buffer back (which we must free)
    uint8_t* av1cBuf = NULL;
    int av1cBufLen = avio_close_dyn_buf(ioctx, &av1cBuf);
    
    Log(LOG_I, @"av1C block is %d bytes", av1cBufLen);
    
    // Only return data if ff_isom_write_av1c() was successful
    NSData* data = nil;
    if (err >= 0 && av1cBufLen > 0) {
        data = [NSData dataWithBytes:av1cBuf length:av1cBufLen];
    }
    else {
        data = nil;
    }
    
    av_free(av1cBuf);
    return data;
}

// Much of this logic comes from Chrome
- (CMVideoFormatDescriptionRef)createAV1FormatDescriptionForIDRFrame:(NSData*)frameData {
    NSMutableDictionary* extensions = [[NSMutableDictionary alloc] init];

    CodedBitstreamContext* cbsCtx = NULL;
    int err = ff_cbs_init(&cbsCtx, AV_CODEC_ID_AV1, NULL);
    if (err < 0) {
        Log(LOG_E, @"ff_cbs_init() failed: %d", err);
        return nil;
    }
    
    AVPacket avPacket = {};
    avPacket.data = (uint8_t*)frameData.bytes;
    avPacket.size = (int)frameData.length;
    
    // Read the sequence header OBU
    CodedBitstreamFragment cbsFrag = {};
    err = ff_cbs_read_packet(cbsCtx, &cbsFrag, &avPacket);
    if (err < 0) {
        Log(LOG_E, @"ff_cbs_read_packet() failed: %d", err);
        ff_cbs_close(&cbsCtx);
        return nil;
    }
    
#define SET_CFSTR_EXTENSION(key, value) extensions[(__bridge NSString*)key] = (__bridge NSString*)(value)
#define SET_EXTENSION(key, value) extensions[(__bridge NSString*)key] = (value)

    SET_EXTENSION(kCMFormatDescriptionExtension_FormatName, @"av01");
    
    // We use the value for YUV without alpha, same as Chrome
    // https://developer.apple.com/library/archive/qa/qa1183/_index.html
    SET_EXTENSION(kCMFormatDescriptionExtension_Depth, @24);
    
    CodedBitstreamAV1Context* bitstreamCtx = (CodedBitstreamAV1Context*)cbsCtx->priv_data;
    AV1RawSequenceHeader* seqHeader = bitstreamCtx->sequence_header;
    if (seqHeader == NULL) {
        Log(LOG_E, @"AV1 sequence header not found in IDR frame!");
        ff_cbs_fragment_free(&cbsFrag);
        ff_cbs_close(&cbsCtx);
        return nil;
    }
    
    switch (seqHeader->color_config.color_primaries) {
        case 1: // CP_BT_709
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ColorPrimaries,
                                kCMFormatDescriptionColorPrimaries_ITU_R_709_2);
            break;
            
        case 6: // CP_BT_601
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ColorPrimaries,
                                kCMFormatDescriptionColorPrimaries_SMPTE_C);
            break;
            
        case 9: // CP_BT_2020
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ColorPrimaries,
                                kCMFormatDescriptionColorPrimaries_ITU_R_2020);
            break;
            
        default:
            Log(LOG_W, @"Unsupported color_primaries value: %d", seqHeader->color_config.color_primaries);
            break;
    }
    
    switch (seqHeader->color_config.transfer_characteristics) {
        case 1: // TC_BT_709
        case 6: // TC_BT_601
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_ITU_R_709_2);
            break;
            
        case 7: // TC_SMPTE_240
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_SMPTE_240M_1995);
            break;
            
        case 8: // TC_LINEAR
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_Linear);
            break;
            
        case 14: // TC_BT_2020_10_BIT
        case 15: // TC_BT_2020_12_BIT
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_ITU_R_2020);
            break;
            
        case 16: // TC_SMPTE_2084
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ);
            break;
            
        case 17: // TC_HLG
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG);
            break;
            
        default:
            Log(LOG_W, @"Unsupported transfer_characteristics value: %d", seqHeader->color_config.transfer_characteristics);
            break;
    }
    
    switch (seqHeader->color_config.matrix_coefficients) {
        case 1: // MC_BT_709
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2);
            break;
            
        case 6: // MC_BT_601
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4);
            break;
            
        case 7: // MC_SMPTE_240
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_SMPTE_240M_1995);
            break;
            
        case 9: // MC_BT_2020_NCL
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_ITU_R_2020);
            break;
            
        default:
            Log(LOG_W, @"Unsupported matrix_coefficients value: %d", seqHeader->color_config.matrix_coefficients);
            break;
    }
    
    SET_EXTENSION(kCMFormatDescriptionExtension_FullRangeVideo, @(seqHeader->color_config.color_range == 1));
    
    // Progressive content
    SET_EXTENSION(kCMFormatDescriptionExtension_FieldCount, @(1));
    
    switch (seqHeader->color_config.chroma_sample_position) {
        case 1: // CSP_VERTICAL
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ChromaLocationTopField,
                                kCMFormatDescriptionChromaLocation_Left);
            break;
            
        case 2: // CSP_COLOCATED
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ChromaLocationTopField,
                                kCMFormatDescriptionChromaLocation_TopLeft);
            break;
            
        default:
            Log(LOG_W, @"Unsupported chroma_sample_position value: %d", seqHeader->color_config.chroma_sample_position);
            break;
    }
    
    if (contentLightLevelInfo) {
        SET_EXTENSION(kCMFormatDescriptionExtension_ContentLightLevelInfo, contentLightLevelInfo);
    }
    
    if (masteringDisplayColorVolume) {
        SET_EXTENSION(kCMFormatDescriptionExtension_MasteringDisplayColorVolume, masteringDisplayColorVolume);
    }
    
    // Referenced the VP9 code in Chrome that performs a similar function
    // https://source.chromium.org/chromium/chromium/src/+/main:media/gpu/mac/vt_config_util.mm;drc=977dc02c431b4979e34c7792bc3d646f649dacb4;l=155
    extensions[(__bridge NSString*)kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] =
    @{
        @"av1C" : [self getAv1CodecConfigurationBox:frameData],
    };
    extensions[@"BitsPerComponent"] = @(bitstreamCtx->bit_depth);
    
#undef SET_EXTENSION
#undef SET_CFSTR_EXTENSION
    
    // AV1 doesn't have a special format description function like H.264 and HEVC have, so we just use the generic one
    CMVideoFormatDescriptionRef formatDesc = NULL;
    OSStatus status = CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCMVideoCodecType_AV1,
                                                     bitstreamCtx->frame_width, bitstreamCtx->frame_height,
                                                     (__bridge CFDictionaryRef)extensions,
                                                     &formatDesc);
    if (status != noErr) {
        Log(LOG_E, @"Failed to create AV1 format description: %d", (int)status);
        formatDesc = NULL;
    }
    
    ff_cbs_fragment_free(&cbsFrag);
    ff_cbs_close(&cbsCtx);
    return formatDesc;
}

// This function must free data for bufferType == BUFFER_TYPE_PICDATA
- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)bufferType decodeUnit:(PDECODE_UNIT)du
{
    OSStatus status;
    
    // Construct a new format description object each time we receive an IDR frame
    if (du->frameType == FRAME_TYPE_IDR) {
        if (bufferType != BUFFER_TYPE_PICDATA) {
            if (bufferType == BUFFER_TYPE_VPS || bufferType == BUFFER_TYPE_SPS || bufferType == BUFFER_TYPE_PPS) {
                // Add new parameter set into the parameter set array
                int startLen = data[2] == 0x01 ? 3 : 4;
                [parameterSetBuffers addObject:[NSData dataWithBytes:&data[startLen] length:length - startLen]];
            }
            
            // Data is NOT to be freed here. It's a direct usage of the caller's buffer.
            
            // No frame data to submit for these NALUs
            return DR_OK;
        }
        
        // Create the new format description when we get the first picture data buffer of an IDR frame.
        // This is the only way we know that there is no more CSD for this frame.
        //
        // NB: This logic depends on the fact that we submit all picture data in one buffer!
        
        // Free the old format description
        if (formatDesc != NULL) {
            CFRelease(formatDesc);
            formatDesc = NULL;
        }
        
        if (videoFormat & VIDEO_FORMAT_MASK_H264) {
            // Construct parameter set arrays for the format description
            size_t parameterSetCount = [parameterSetBuffers count];
            const uint8_t* parameterSetPointers[parameterSetCount];
            size_t parameterSetSizes[parameterSetCount];
            for (int i = 0; i < parameterSetCount; i++) {
                NSData* parameterSet = parameterSetBuffers[i];
                parameterSetPointers[i] = parameterSet.bytes;
                parameterSetSizes[i] = parameterSet.length;
            }
            
            Log(LOG_I, @"Constructing new H264 format description");
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                         parameterSetCount,
                                                                         parameterSetPointers,
                                                                         parameterSetSizes,
                                                                         NAL_LENGTH_PREFIX_SIZE,
                                                                         &formatDesc);
            if (status != noErr) {
                Log(LOG_E, @"Failed to create H264 format description: %d", (int)status);
                formatDesc = NULL;
            }
            
            // Free parameter set buffers after submission
            [parameterSetBuffers removeAllObjects];
        }
        else if (videoFormat & VIDEO_FORMAT_MASK_H265) {
            // Construct parameter set arrays for the format description
            size_t parameterSetCount = [parameterSetBuffers count];
            const uint8_t* parameterSetPointers[parameterSetCount];
            size_t parameterSetSizes[parameterSetCount];
            for (int i = 0; i < parameterSetCount; i++) {
                NSData* parameterSet = parameterSetBuffers[i];
                parameterSetPointers[i] = parameterSet.bytes;
                parameterSetSizes[i] = parameterSet.length;
            }
            
            Log(LOG_I, @"Constructing new HEVC format description");
            
            NSMutableDictionary* videoFormatParams = [[NSMutableDictionary alloc] init];
            
            if (contentLightLevelInfo) {
                [videoFormatParams setObject:contentLightLevelInfo forKey:(__bridge NSString*)kCMFormatDescriptionExtension_ContentLightLevelInfo];
            }
            
            if (masteringDisplayColorVolume) {
                [videoFormatParams setObject:masteringDisplayColorVolume forKey:(__bridge NSString*)kCMFormatDescriptionExtension_MasteringDisplayColorVolume];
            }
            
            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault,
                                                                         parameterSetCount,
                                                                         parameterSetPointers,
                                                                         parameterSetSizes,
                                                                         NAL_LENGTH_PREFIX_SIZE,
                                                                         (__bridge CFDictionaryRef)videoFormatParams,
                                                                         &formatDesc);
            
            if (status != noErr) {
                Log(LOG_E, @"Failed to create HEVC format description: %d", (int)status);
                formatDesc = NULL;
            }
            
            // Free parameter set buffers after submission
            [parameterSetBuffers removeAllObjects];
        }
        else if (videoFormat & VIDEO_FORMAT_MASK_AV1) {
            NSData* fullFrameData = [NSData dataWithBytesNoCopy:data length:length freeWhenDone:NO];
            
            Log(LOG_I, @"Constructing new AV1 format description");
            formatDesc = [self createAV1FormatDescriptionForIDRFrame:fullFrameData];
        }
        else {
            // Unsupported codec!
            abort();
        }
    }
    
    if (formatDesc == NULL) {
        // Can't decode if we haven't gotten our parameter sets yet
        free(data);
        return DR_NEED_IDR;
    }
    
    // Check for previous decoder errors before doing anything
    if (displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        Log(LOG_E, @"Display layer rendering failed: %@", displayLayer.error);
        
        // Recreate the display layer. We are already on the main thread,
        // so this is safe to do right here.
        [self reinitializeDisplayLayer];
        
        // Request an IDR frame to initialize the new decoder
        free(data);
        return DR_NEED_IDR;
    }
    
    // Now we're decoding actual frame data here
    CMBlockBufferRef frameBlockBuffer;
    CMBlockBufferRef dataBlockBuffer;
    
    status = CMBlockBufferCreateWithMemoryBlock(NULL, data, length, kCFAllocatorDefault, NULL, 0, length, 0, &dataBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateWithMemoryBlock failed: %d", (int)status);
        free(data);
        return DR_NEED_IDR;
    }
    
    // From now on, CMBlockBuffer owns the data pointer and will free it when it's dereferenced
    
    status = CMBlockBufferCreateEmpty(NULL, 0, 0, &frameBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateEmpty failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        return DR_NEED_IDR;
    }
    
    // H.264 and HEVC formats require NAL prefix fixups from Annex B to length-delimited
    if (videoFormat & (VIDEO_FORMAT_MASK_H264 | VIDEO_FORMAT_MASK_H265)) {
        int lastOffset = -1;
        for (int i = 0; i < length - NALU_START_PREFIX_SIZE; i++) {
            // Search for a NALU
            if (data[i] == 0 && data[i+1] == 0 && data[i+2] == 1) {
                // It's the start of a new NALU
                if (lastOffset != -1) {
                    // We've seen a start before this so enqueue that NALU
                    [self updateAnnexBBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:i - lastOffset];
                }
                
                lastOffset = i;
            }
        }
        
        if (lastOffset != -1) {
            // Enqueue the remaining data
            [self updateAnnexBBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:length - lastOffset];
        }
    }
    else {
        // For formats that require no length-changing fixups, just append a reference to the raw data block
        status = CMBlockBufferAppendBufferReference(frameBlockBuffer, dataBlockBuffer, 0, length, 0);
        if (status != noErr) {
            Log(LOG_E, @"CMBlockBufferAppendBufferReference failed: %d", (int)status);
            return DR_NEED_IDR;
        }
    }
        
    CMSampleBufferRef sampleBuffer;
    
    CMSampleTimingInfo sampleTiming = {kCMTimeInvalid, CMTimeMake(du->presentationTimeUs, 1000000), kCMTimeInvalid};
    
    status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                  frameBlockBuffer,
                                  formatDesc, 1, 1,
                                  &sampleTiming, 0, NULL,
                                  &sampleBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMSampleBufferCreate failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        CFRelease(frameBlockBuffer);
        return DR_NEED_IDR;
    }

    int result = DR_OK;
    if (_videoToolbox) {
        result = [self decodeSampleBuffer:sampleBuffer frameType:du->frameType];
    }
    else {
        // Enqueue the next frame
        [self->displayLayer enqueueSampleBuffer:sampleBuffer];

        if (du->frameType == FRAME_TYPE_IDR) {
            // Ensure the layer is visible now
            self->displayLayer.hidden = NO;

            // Tell our parent VC to hide the progress indicator
            [self->_callbacks videoContentShown];
        }
    }
    
    // Dereference the buffers
    CFRelease(dataBlockBuffer);
    CFRelease(frameBlockBuffer);
    CFRelease(sampleBuffer);
    
    return result;
}

- (void)setHdrMode:(BOOL)enabled {
    SS_HDR_METADATA hdrMetadata;
    
    BOOL hasMetadata = enabled && LiGetHdrMetadata(&hdrMetadata);
    BOOL metadataChanged = NO;
    
    if (hasMetadata && hdrMetadata.displayPrimaries[0].x != 0 && hdrMetadata.maxDisplayLuminance != 0) {
        // This data is all in big-endian
        struct {
          vector_ushort2 primaries[3];
          vector_ushort2 white_point;
          uint32_t luminance_max;
          uint32_t luminance_min;
        } __attribute__((packed, aligned(4))) mdcv;

        // mdcv is in GBR order while SS_HDR_METADATA is in RGB order
        mdcv.primaries[0].x = __builtin_bswap16(hdrMetadata.displayPrimaries[1].x);
        mdcv.primaries[0].y = __builtin_bswap16(hdrMetadata.displayPrimaries[1].y);
        mdcv.primaries[1].x = __builtin_bswap16(hdrMetadata.displayPrimaries[2].x);
        mdcv.primaries[1].y = __builtin_bswap16(hdrMetadata.displayPrimaries[2].y);
        mdcv.primaries[2].x = __builtin_bswap16(hdrMetadata.displayPrimaries[0].x);
        mdcv.primaries[2].y = __builtin_bswap16(hdrMetadata.displayPrimaries[0].y);

        mdcv.white_point.x = __builtin_bswap16(hdrMetadata.whitePoint.x);
        mdcv.white_point.y = __builtin_bswap16(hdrMetadata.whitePoint.y);

        // These luminance values are in 10000ths of a nit
        mdcv.luminance_max = __builtin_bswap32((uint32_t)hdrMetadata.maxDisplayLuminance * 10000);
        mdcv.luminance_min = __builtin_bswap32(hdrMetadata.minDisplayLuminance);

        NSData* newMdcv = [NSData dataWithBytes:&mdcv length:sizeof(mdcv)];
        if (masteringDisplayColorVolume == nil || ![newMdcv isEqualToData:masteringDisplayColorVolume]) {
            masteringDisplayColorVolume = newMdcv;
            metadataChanged = YES;
        }
    }
    else if (masteringDisplayColorVolume != nil) {
        masteringDisplayColorVolume = nil;
        metadataChanged = YES;
    }
    
    if (hasMetadata && hdrMetadata.maxContentLightLevel != 0 && hdrMetadata.maxFrameAverageLightLevel != 0) {
        // This data is all in big-endian
        struct {
            uint16_t max_content_light_level;
            uint16_t max_frame_average_light_level;
        } __attribute__((packed, aligned(2))) cll;

        cll.max_content_light_level = __builtin_bswap16(hdrMetadata.maxContentLightLevel);
        cll.max_frame_average_light_level = __builtin_bswap16(hdrMetadata.maxFrameAverageLightLevel);

        NSData* newCll = [NSData dataWithBytes:&cll length:sizeof(cll)];
        if (contentLightLevelInfo == nil || ![newCll isEqualToData:contentLightLevelInfo]) {
            contentLightLevelInfo = newCll;
            metadataChanged = YES;
        }
    }
    else if (contentLightLevelInfo != nil) {
        contentLightLevelInfo = nil;
        metadataChanged = YES;
    }
    
    // If the metadata changed, request an IDR frame to re-create the CMVideoFormatDescription
    if (metadataChanged) {
        LiRequestIdrFrame();
    }
}

@end
