#include "CMultitouch.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <pthread.h>
#include <string.h>

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint pos;
    MTPoint vel;
} MTReadout;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;
    int32_t state;
    int32_t fingerID;
    int32_t handID;
    MTReadout normalized;
    float size;
    int32_t zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTReadout absolute;
    int32_t zero2[2];
    float zTotal;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device, MTTouch *data, int nFingers, double timestamp, int frame);

typedef CFArrayRef (*MTDeviceCreateListFn)(void);
typedef bool (*MTDeviceIsBuiltInFn)(MTDeviceRef);
typedef int (*MTDeviceGetDeviceIDFn)(MTDeviceRef, uint64_t *);
typedef void (*MTRegisterContactFrameCallbackFn)(MTDeviceRef, MTContactCallbackFunction);
typedef void (*MTUnregisterContactFrameCallbackFn)(MTDeviceRef, MTContactCallbackFunction);
typedef void (*MTDeviceStartFn)(MTDeviceRef, int);
typedef void (*MTDeviceStopFn)(MTDeviceRef);

static void *g_mtHandle = NULL;
static MTDeviceCreateListFn fn_CreateList = NULL;
static MTDeviceIsBuiltInFn fn_IsBuiltIn = NULL;
static MTDeviceGetDeviceIDFn fn_GetDeviceID = NULL;
static MTRegisterContactFrameCallbackFn fn_RegisterCallback = NULL;
static MTUnregisterContactFrameCallbackFn fn_UnregisterCallback = NULL;
static MTDeviceStartFn fn_Start = NULL;
static MTDeviceStopFn fn_Stop = NULL;

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static SMMultitouchFrameCallback g_userCallback = NULL;
static void *g_userContext = NULL;
static CFArrayRef g_activeDevices = NULL;

static bool sm_mt_load_locked(void) {
    if (g_mtHandle != NULL) {
        return fn_CreateList != NULL && fn_RegisterCallback != NULL && fn_Start != NULL && fn_Stop != NULL;
    }
    g_mtHandle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY);
    if (g_mtHandle == NULL) {
        return false;
    }
    fn_CreateList = (MTDeviceCreateListFn)dlsym(g_mtHandle, "MTDeviceCreateList");
    fn_IsBuiltIn = (MTDeviceIsBuiltInFn)dlsym(g_mtHandle, "MTDeviceIsBuiltIn");
    fn_GetDeviceID = (MTDeviceGetDeviceIDFn)dlsym(g_mtHandle, "MTDeviceGetDeviceID");
    fn_RegisterCallback = (MTRegisterContactFrameCallbackFn)dlsym(g_mtHandle, "MTRegisterContactFrameCallback");
    fn_UnregisterCallback = (MTUnregisterContactFrameCallbackFn)dlsym(g_mtHandle, "MTUnregisterContactFrameCallback");
    fn_Start = (MTDeviceStartFn)dlsym(g_mtHandle, "MTDeviceStart");
    fn_Stop = (MTDeviceStopFn)dlsym(g_mtHandle, "MTDeviceStop");
    return fn_CreateList != NULL && fn_RegisterCallback != NULL && fn_Start != NULL && fn_Stop != NULL;
}

static int sm_mt_contact_callback(MTDeviceRef device, MTTouch *data, int nFingers, double timestamp, int frameNum) {
    (void)timestamp;
    (void)frameNum;

    SMMultitouchFrameCallback cb = NULL;
    void *ctx = NULL;
    pthread_mutex_lock(&g_lock);
    cb = g_userCallback;
    ctx = g_userContext;
    pthread_mutex_unlock(&g_lock);

    if (cb == NULL) {
        return 0;
    }

    SMMultitouchFrame frame;
    memset(&frame, 0, sizeof(frame));
    if (fn_GetDeviceID != NULL) {
        fn_GetDeviceID(device, &frame.deviceID);
    }
    if (fn_IsBuiltIn != NULL) {
        frame.isBuiltIn = fn_IsBuiltIn(device);
    }

    int count = 0;
    if (data != NULL && nFingers > 0) {
        for (int i = 0; i < nFingers && count < 16; i++) {
            // States 3 (makeTouch) and 4 (touching) are active surface contacts
            if (data[i].state >= 3 && data[i].state <= 5) {
                frame.fingers[count].identifier = data[i].identifier;
                frame.fingers[count].state = data[i].state;
                frame.fingers[count].normX = data[i].normalized.pos.x;
                frame.fingers[count].normY = data[i].normalized.pos.y;
                frame.fingers[count].velX = data[i].normalized.vel.x;
                frame.fingers[count].velY = data[i].normalized.vel.y;
                count++;
            }
        }
    }
    frame.fingerCount = count;
    cb(&frame, ctx);
    return 0;
}

bool sm_mt_start(SMMultitouchFrameCallback callback, void *context) {
    pthread_mutex_lock(&g_lock);
    if (!sm_mt_load_locked()) {
        pthread_mutex_unlock(&g_lock);
        return false;
    }

    if (g_activeDevices != NULL) {
        CFIndex n = CFArrayGetCount(g_activeDevices);
        for (CFIndex i = 0; i < n; i++) {
            MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(g_activeDevices, i);
            if (fn_UnregisterCallback != NULL) {
                fn_UnregisterCallback(dev, sm_mt_contact_callback);
            }
            fn_Stop(dev);
        }
        CFRelease(g_activeDevices);
        g_activeDevices = NULL;
    }

    g_userCallback = callback;
    g_userContext = context;

    CFArrayRef list = fn_CreateList();
    if (list == NULL) {
        pthread_mutex_unlock(&g_lock);
        return false;
    }

    g_activeDevices = list;
    CFIndex n = CFArrayGetCount(list);
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(list, i);
        fn_RegisterCallback(dev, sm_mt_contact_callback);
        fn_Start(dev, 0);
    }

    pthread_mutex_unlock(&g_lock);
    return n > 0;
}

void sm_mt_stop(void) {
    pthread_mutex_lock(&g_lock);
    g_userCallback = NULL;
    g_userContext = NULL;
    if (g_activeDevices != NULL) {
        CFIndex n = CFArrayGetCount(g_activeDevices);
        for (CFIndex i = 0; i < n; i++) {
            MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(g_activeDevices, i);
            if (fn_UnregisterCallback != NULL) {
                fn_UnregisterCallback(dev, sm_mt_contact_callback);
            }
            if (fn_Stop != NULL) {
                fn_Stop(dev);
            }
        }
        CFRelease(g_activeDevices);
        g_activeDevices = NULL;
    }
    pthread_mutex_unlock(&g_lock);
}

int32_t sm_mt_list_devices(SMMultitouchDeviceInfo *outDevices, int32_t maxDevices) {
    pthread_mutex_lock(&g_lock);
    if (!sm_mt_load_locked()) {
        pthread_mutex_unlock(&g_lock);
        return 0;
    }
    CFArrayRef list = fn_CreateList();
    if (list == NULL) {
        pthread_mutex_unlock(&g_lock);
        return 0;
    }
    CFIndex n = CFArrayGetCount(list);
    int32_t written = 0;
    for (CFIndex i = 0; i < n && written < maxDevices; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(list, i);
        uint64_t devID = 0;
        if (fn_GetDeviceID != NULL) {
            fn_GetDeviceID(dev, &devID);
        }
        bool builtIn = fn_IsBuiltIn != NULL ? fn_IsBuiltIn(dev) : false;
        outDevices[written].deviceID = devID;
        outDevices[written].isBuiltIn = builtIn;
        written++;
    }
    CFRelease(list);
    pthread_mutex_unlock(&g_lock);
    return written;
}
