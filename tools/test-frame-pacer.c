// Self-check for Limelight/Stream/FramePacer.h:  cc -I Limelight/Stream tools/test-frame-pacer.c -o /tmp/t && /tmp/t
#include <assert.h>
#include <stdio.h>
#include "FramePacer.h"

int main(void)
{
    // Lowest latency: everything goes
    MNFramePacer lowest = {0, false, false};
    assert(MNFramePacerRelease(&lowest, 3) == 3);
    assert(MNFramePacerRelease(&lowest, 0) == 0);

    // Balanced: Moonlight's old behaviour, drain to one held frame, never hold a lone one
    MNFramePacer balanced = {1, false, false};
    assert(MNFramePacerRelease(&balanced, 1) == 1);
    assert(MNFramePacerRelease(&balanced, 2) == 1);
    assert(MNFramePacerRelease(&balanced, 4) == 3);

    // Smoothest, depth 3: fill first, then one per refresh
    MNFramePacer smooth = {3, true, true};
    assert(MNFramePacerRelease(&smooth, 1) == 0);
    assert(MNFramePacerRelease(&smooth, 3) == 0);
    assert(MNFramePacerRelease(&smooth, 4) == 1);
    assert(MNFramePacerRelease(&smooth, 2) == 1);   // draining below depth still shows one
    assert(MNFramePacerRelease(&smooth, 6) == 1);   // 2 over depth is tolerated
    assert(MNFramePacerRelease(&smooth, 7) == 4);   // past it: skip back down to depth
    assert(MNFramePacerRelease(&smooth, 0) == 0);   // ran dry: refill before showing again
    assert(MNFramePacerRelease(&smooth, 3) == 0);
    assert(MNFramePacerRelease(&smooth, 4) == 1);

    // Steady 60 fps into a 60 Hz refresh keeps the buffer at depth
    MNFramePacer steady = {2, true, true};
    int queued = 0, shown = 0;
    for (int tick = 0; tick < 100; tick++) {
        queued++;
        int n = MNFramePacerRelease(&steady, queued);
        queued -= n;
        shown += n;
    }
    assert(queued == 2 && shown == 98);

    puts("frame pacer ok");
    return 0;
}
