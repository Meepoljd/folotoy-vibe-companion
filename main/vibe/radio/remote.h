#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
bool vibe_radio_remote_init(void);
void vibe_radio_remote_receive(const uint8_t *packet,size_t n,uint32_t generation,bool ble);
void vibe_radio_remote_status(const char *session,bool failed);
