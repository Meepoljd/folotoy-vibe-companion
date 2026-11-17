#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#define VIBE_BLE_PACKET_MAX 1537
#define VIBE_BLE_HEADER 7
/* One bounded in-flight packet. Gaps, overlap and expired fragments are rejected. */
typedef struct { uint8_t bytes[VIBE_BLE_PACKET_MAX],id; uint16_t total,used; uint64_t at; } vibe_ble_frame_t;
static inline bool vibe_ble_frame_feed(vibe_ble_frame_t *s,const uint8_t *p,size_t n,uint64_t now) {
    if (n<=VIBE_BLE_HEADER || p[0]!=0x56) { s->used=0;s->total=0;return false; }
    unsigned total=p[3]|(p[4]<<8),offset=p[5]|(p[6]<<8);size_t payload=n-VIBE_BLE_HEADER;
    if (!total || total>VIBE_BLE_PACKET_MAX || offset+payload>total || (p[2]&~3)) { s->total=s->used=0;return false; }
    if (p[2]&1) { s->id=p[1];s->total=(uint16_t)total;s->used=0;s->at=now; }
    if (s->id!=p[1] || s->total!=total || offset!=s->used || now<s->at || now-s->at>2000) { s->total=s->used=0;return false; }
    memcpy(s->bytes+s->used,p+VIBE_BLE_HEADER,payload);s->used+=(uint16_t)payload;
    if (p[2]&2) { bool complete=s->used==s->total;s->total=0;return complete; }
    return false;
}
