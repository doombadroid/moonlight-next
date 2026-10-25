//
//  FramePacer.h
//  MoonLume
//
//  Decides how many queued frames to show on each display refresh. Used twice by the renderer:
//  on Moonlight's queue of received frames, and on the queue of decoded (and interpolated)
//  frames when VideoToolbox decodes. Plain C so tools/test-frame-pacer.c can check it.
//
//  depth is how many frames stay buffered after a refresh shows one.
//  depth 0: show everything (lowest latency)
//  steady 0, depth 1: drain to one held frame, as Moonlight always did ("Balanced")
//  steady 1: one frame per refresh, keeping `depth` frames buffered ("Smoothest"). After running
//            dry it refills before showing again; if the buffer grows 2 frames past its depth
//            (the PC's clock running ahead of the screen) it skips back down.
//

#ifndef FramePacer_h
#define FramePacer_h

#include <stdbool.h>

typedef struct {
    int depth;
    bool steady;
    bool refilling;
} MNFramePacer;

static inline int MNFramePacerRelease(MNFramePacer* p, int pending)
{
    if (pending <= 0) {
        p->refilling = p->steady;
        return 0;
    }
    if (p->depth <= 0) {
        return pending;
    }
    if (!p->steady) {
        // Keep one pending frame to smooth out network jitter, but never hold a lone frame
        return pending == 1 ? 1 : pending - p->depth;
    }
    if (p->refilling) {
        if (pending <= p->depth) {
            return 0;
        }
        p->refilling = false;
    }
    return pending > p->depth + 3 ? pending - p->depth : 1;
}

#endif /* FramePacer_h */
