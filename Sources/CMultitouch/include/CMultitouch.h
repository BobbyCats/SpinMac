#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t identifier;
    int32_t state;
    float normX;
    float normY;
    float velX;
    float velY;
} SMMultitouchFinger;

typedef struct {
    uint64_t deviceID;
    bool isBuiltIn;
    int32_t fingerCount;
    SMMultitouchFinger fingers[16];
} SMMultitouchFrame;

typedef struct {
    uint64_t deviceID;
    bool isBuiltIn;
} SMMultitouchDeviceInfo;

typedef void (*SMMultitouchFrameCallback)(const SMMultitouchFrame *frame, void *context);

bool sm_mt_start(SMMultitouchFrameCallback callback, void *context);
void sm_mt_stop(void);
int32_t sm_mt_list_devices(SMMultitouchDeviceInfo *outDevices, int32_t maxDevices);

#ifdef __cplusplus
}
#endif

#endif
