#pragma once
#include <stdbool.h>
#include <stdint.h>
/* Link procedures share the controller with DLE, PHY and encryption. Defer the
 * first parameter request; an accepted command is not a completed negotiation.
 * Timeout units below are the BLE-defined 10 ms units. No permanent timer. */
#define VIBE_BLE_PARAMETER_ATTEMPTS 4
#define VIBE_BLE_MIN_SUPERVISION 200
#define VIBE_BLE_SUPERVISION 600
#define VIBE_BLE_PARAMETER_WAIT_MS 5000

typedef struct { uint64_t due;uint8_t attempts;bool waiting; } vibe_ble_parameters_t;
static inline void vibe_ble_parameters_start(vibe_ble_parameters_t *s,uint64_t now) {
    *s=(vibe_ble_parameters_t){.due=now+1000};
}
static inline void vibe_ble_parameters_observe(vibe_ble_parameters_t *s,uint64_t now,uint16_t timeout) {
    s->waiting=false;
    if (timeout>=VIBE_BLE_MIN_SUPERVISION || s->attempts>=VIBE_BLE_PARAMETER_ATTEMPTS) {s->due=0;return;}
    unsigned shift=s->attempts?s->attempts-1:0;
    s->due=now+(1000u<<shift);
}
static inline bool vibe_ble_parameters_due(vibe_ble_parameters_t *s,uint64_t now) {
    if (!s->due || now<s->due) return false;
    if (s->attempts>=VIBE_BLE_PARAMETER_ATTEMPTS) {s->due=0;s->waiting=false;return false;}
    ++s->attempts;s->waiting=true;s->due=now+VIBE_BLE_PARAMETER_WAIT_MS;return true;
}
