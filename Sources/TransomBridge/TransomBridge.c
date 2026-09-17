#include "TransomBridge.h"
#include <dlfcn.h>
#include <pthread.h>

// Independently written bridge. ABI reference links are in docs/SOURCES.md.
// Function existence does not guarantee compatibility with a new macOS version.
typedef AXError (*AXGetWindowFn)(AXUIElementRef, uint32_t *);
typedef int (*MainConnectionFn)(void);
typedef CFTypeRef (*TransactionCreateFn)(int);
typedef CGError (*TransactionOrderFn)(CFTypeRef, uint32_t, int, uint32_t);
typedef CGError (*TransactionCommitFn)(CFTypeRef, int);
// Signature per yabai's extern.h: CGError SLSGetWindowLevel(int cid, uint32_t wid, int *level)
typedef CGError (*WindowLevelFn)(int, uint32_t, int *);
typedef int32_t (*WindowSublevelFn)(int, uint32_t);
typedef CGError (*TransactionLevelFn)(CFTypeRef, uint32_t, int);

static pthread_once_t once = PTHREAD_ONCE_INIT;
static AXGetWindowFn getAXWindow;
static MainConnectionFn mainConnection;
static TransactionCreateFn createTransaction;
static TransactionOrderFn orderTransaction;
static TransactionCommitFn commitTransaction;
static WindowLevelFn getLevel;
static WindowSublevelFn getSublevel;
static TransactionLevelFn setLevel;
static TransactionLevelFn setSublevel;
static int32_t lastError;

static void *loadSymbol(void *handle, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    return symbol ? symbol : (handle ? dlsym(handle, name) : NULL);
}
static void initialize(void) {
    // System frameworks only; handles intentionally live for the process lifetime.
    void *ax = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY | RTLD_LOCAL);
    void *sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    getAXWindow = (AXGetWindowFn)loadSymbol(ax, "_AXUIElementGetWindow");
    mainConnection = (MainConnectionFn)loadSymbol(sky, "SLSMainConnectionID");
    createTransaction = (TransactionCreateFn)loadSymbol(sky, "SLSTransactionCreate");
    orderTransaction = (TransactionOrderFn)loadSymbol(sky, "SLSTransactionOrderWindow");
    commitTransaction = (TransactionCommitFn)loadSymbol(sky, "SLSTransactionCommit");
    getLevel = (WindowLevelFn)loadSymbol(sky, "SLSGetWindowLevel");
    getSublevel = (WindowSublevelFn)loadSymbol(sky, "SLSGetWindowSubLevel");
    setLevel = (TransactionLevelFn)loadSymbol(sky, "SLSTransactionSetWindowLevel");
    setSublevel = (TransactionLevelFn)loadSymbol(sky, "SLSTransactionSetWindowSubLevel");
}
bool WBHasAXWindowID(void) {
    pthread_once(&once, initialize);
    return getAXWindow != NULL;
}
AXError WBCopyAXWindowID(AXUIElementRef element, uint32_t *windowID) {
    pthread_once(&once, initialize);
    if (!element || !windowID) return kAXErrorIllegalArgument;
    *windowID = 0;
    return getAXWindow ? getAXWindow(element, windowID) : kAXErrorNotImplemented;
}
bool WBHasRelativeOrdering(void) {
    pthread_once(&once, initialize);
    return mainConnection && createTransaction && orderTransaction && commitTransaction &&
           getLevel && getSublevel && setLevel && setSublevel;
}
int32_t WBOrderAboveWindow(uint32_t ownWindow, uint32_t targetWindow) {
    if (!WBHasRelativeOrdering() || !ownWindow || !targetWindow) return -1;
    const int cid = mainConnection();
    if (cid <= 0) return -2;
    int level = 0;
    CGError error = getLevel(cid, targetWindow, &level);
    // The app only supports ordinary layer-zero windows. Never escalate to secure/UI levels.
    if (error != kCGErrorSuccess || level != 0) return -3;
    CFTypeRef transaction = createTransaction(cid);
    if (!transaction) return -4;
    // Step-coded failures (-5..-8) so the Swift layer can report WHICH private call failed
    // without exposing anything else. The raw CGError is kept in lastError.
    int32_t code = 0;
    error = setLevel(transaction, ownWindow, 0);
    if (error != kCGErrorSuccess) code = -5;
    if (code == 0) { error = setSublevel(transaction, ownWindow, getSublevel(cid, targetWindow)); if (error != kCGErrorSuccess) code = -6; }
    if (code == 0) { error = orderTransaction(transaction, ownWindow, 1, targetWindow); if (error != kCGErrorSuccess) code = -7; }
    if (code == 0) { error = commitTransaction(transaction, 0); if (error != kCGErrorSuccess) code = -8; }
    CFRelease(transaction);
    lastError = (int32_t)error;
    return code;
}
int32_t WBLastOrderCGError(void) { return lastError; }
CFArrayRef WBCopyOnScreenWindowIDs(void) {
    return CGWindowListCreate(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
}
