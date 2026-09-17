#ifndef TRANSOM_BRIDGE_H
#define TRANSOM_BRIDGE_H
#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
/// All private entry points are optional, resolved at runtime. No injection/SIP changes.
bool WBHasAXWindowID(void);
AXError WBCopyAXWindowID(AXUIElementRef element, uint32_t *windowID);
bool WBHasRelativeOrdering(void);
/// Orders ONLY a window owned by this process; never mutates the target's level.
/// A success code is not proof of visual correctness; the Swift layer rechecks Z-order.
/// Returns 0 on success, -1..-4 for precondition failures, -5..-8 for the failing step
/// (set level, set sublevel, order, commit). WBLastOrderCGError returns the raw CGError of the last call.
int32_t WBOrderAboveWindow(uint32_t ownWindow, uint32_t targetWindow);
int32_t WBLastOrderCGError(void);
/// Public CoreGraphics API that Swift cannot call directly (CGWindowListCreate): the IDs of the on-screen
/// windows, front to back, desktop elements excluded. The caller owns the returned array.
CFArrayRef WBCopyOnScreenWindowIDs(void);
#ifdef __cplusplus
}
#endif
#endif
