#pragma once
#include "esp_err.h"
typedef enum {ESP_COEX_PREFER_WIFI,ESP_COEX_PREFER_BT,ESP_COEX_PREFER_BALANCE} esp_coex_prefer_t;
esp_err_t esp_coex_preference_set(esp_coex_prefer_t preference);
