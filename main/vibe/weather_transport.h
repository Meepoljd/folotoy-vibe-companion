#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
/* Admit optional HTTPS only with room for TLS and live BLE/controller traffic. */
bool vibe_weather_memory_ready(size_t pending_stack_bytes);
/* Caller frees the bounded complete response. A cancelled/failed request returns NULL. */
char *vibe_weather_fetch(const char *url,bool (*allowed)(void),uint64_t (*clock_ms)(void));
