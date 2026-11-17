#pragma once
#include "ble_frame.h"
#include "radio/stream.h"
#include <stdlib.h>
/* A separate, disposable assembly for downlink audio. ATT write requests may
 * interleave with write commands; control must never reset a partial radio
 * packet. The scratch is reclaimed on completion, disconnect or expiry. */
typedef struct { vibe_ble_frame_t *frame; } vibe_ble_media_t;
static inline void vibe_ble_media_clear(vibe_ble_media_t *media) { free(media->frame);media->frame=NULL; }
static inline void vibe_ble_media_expire(vibe_ble_media_t *media,uint64_t now) {
    if(media->frame && (now<media->frame->at || now-media->frame->at>2000)) vibe_ble_media_clear(media);
}
static inline vibe_ble_frame_t *vibe_ble_media_feed(vibe_ble_media_t *media,uint8_t *packet,size_t n,uint64_t now) {
    vibe_ble_media_expire(media,now);
    if(n<=7 || packet[0]!=0x56 || (packet[2]&~7) || !(packet[2]&4)) return NULL;
    if(packet[2]&1) {
        if(packet[7]!=5 || (packet[3]|(packet[4]<<8))!=V_RADIO_PACKET || (n>20 && packet[20]!=V_RADIO_FORMAT)) return NULL;
        if(!media->frame) media->frame=calloc(1,sizeof(*media->frame));
    }
    if(!media->frame) return NULL;
    packet[2]&=(uint8_t)~4;
    if(vibe_ble_frame_feed(media->frame,packet,n,now)) return media->frame;
    return NULL;
}
