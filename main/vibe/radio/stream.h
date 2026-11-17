#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
/* 100 ms of independently decodable 16 kHz mono IMA ADPCM. Sixteen credits bound
 * RAM and latency. A new random session + ownership generation reject old audio. */
#define V_RADIO_FORMAT 2
#define V_RADIO_RATE 16000
#define V_RADIO_SAMPLES 1600
#define V_RADIO_BYTES 804
#define V_RADIO_WINDOW 16
#define V_RADIO_PREFILL 12
#define V_RADIO_HEADER 14
#define V_RADIO_PACKET (V_RADIO_HEADER+V_RADIO_BYTES)
typedef struct {
    uint64_t session;
    uint32_t generation,next,last_wifi,last_ble;
    uint16_t mask;
    uint8_t head;
    /* Individually owned blocks survive the fragmented heap left by voice. */
    uint8_t *frames[V_RADIO_WINDOW];
} vibe_radio_stream_t;
static inline uint64_t vibe_radio_read64(const uint8_t *p) {
    uint64_t n=0;for (unsigned i=0;i<8;i++) n|=(uint64_t)p[i]<<(8*i);return n;
}
static inline uint32_t vibe_radio_read32(const uint8_t *p) {
    uint32_t n=0;for (unsigned i=0;i<4;i++) n|=(uint32_t)p[i]<<(8*i);return n;
}
static inline void vibe_radio_stream_init(vibe_radio_stream_t *s,uint64_t session,uint32_t generation,uint8_t *const frames[V_RADIO_WINDOW]) {
    memset(s,0,sizeof(*s));memcpy(s->frames,frames,sizeof(s->frames));s->session=session;s->generation=generation;s->last_wifi=s->last_ble=UINT32_MAX;
}
static inline bool vibe_radio_stream_receive(vibe_radio_stream_t *s,const uint8_t *p,size_t n,uint32_t generation,bool ble) {
    if (n!=V_RADIO_PACKET || p[0]!=5 || p[13]!=V_RADIO_FORMAT || p[16]>88 || p[17]!=0 ||
        !s->session || vibe_radio_read64(p+1)!=s->session || generation!=s->generation) return false;
    uint32_t seq=vibe_radio_read32(p+9),delta=seq-s->next;
    /* Old frames acknowledge a transport probe, without replaying audio. */
    if (delta>=V_RADIO_WINDOW && delta<0x80000000u) return false;
    if (ble) s->last_ble=seq;else s->last_wifi=seq;
    if (delta< V_RADIO_WINDOW) {
        memcpy(s->frames[(s->head+delta)%V_RADIO_WINDOW],p+V_RADIO_HEADER,V_RADIO_BYTES);s->mask|=(uint16_t)(1u<<delta);
    }
    return true;
}
static inline bool vibe_radio_stream_pop(vibe_radio_stream_t *s,uint8_t *frame) {
    if (!(s->mask&1)) return false;
    memcpy(frame,s->frames[s->head],V_RADIO_BYTES);++s->next;s->head=(uint8_t)((s->head+1)%V_RADIO_WINDOW);s->mask>>=1;return true;
}
