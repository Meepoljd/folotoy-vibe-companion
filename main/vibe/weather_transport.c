#include "weather_transport.h"
#include "esp_http_client.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <stdlib.h>
#include <string.h>
typedef struct { char *body; size_t used; bool overflow; } weather_response_t;
bool vibe_weather_memory_ready(size_t pending_stack_bytes) {
    /* On C3, weather TLS exhausted the heap and the BLE controller then lost
     * allocations/connection events. Budget 48 KiB after the worker stack:
     * response + TLS handshake workspace + at least 12 KiB communication room.
     * A cached forecast is preferable to breaking the active control link. */
    return heap_caps_get_free_size(MALLOC_CAP_INTERNAL|MALLOC_CAP_8BIT)>=48*1024+pending_stack_bytes &&
        heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL|MALLOC_CAP_8BIT)>=20*1024;
}
static esp_err_t weather_data(esp_http_client_event_t *event) {
    weather_response_t *r=event->user_data;
    if (event->event_id!=HTTP_EVENT_ON_DATA || event->data_len<=0) return ESP_OK;
    if ((size_t)event->data_len>4095-r->used) { r->overflow=true; return ESP_FAIL; }
    memcpy(r->body+r->used,event->data,(size_t)event->data_len);r->used+=(size_t)event->data_len;
    return ESP_OK;
}
char *vibe_weather_fetch(const char *url,bool (*allowed)(void),uint64_t (*clock_ms)(void)) {
    if (!allowed() || !vibe_weather_memory_ready(0)) return NULL;
    weather_response_t r={.body=malloc(4096)};
    if (!r.body) return NULL;
    esp_http_client_config_t cfg={.url=url,.timeout_ms=1000,.crt_bundle_attach=esp_crt_bundle_attach,
        .buffer_size=1024,.buffer_size_tx=512,.is_async=true,.disable_auto_redirect=true,
        .event_handler=weather_data,.user_data=&r};
    esp_http_client_handle_t h=esp_http_client_init(&cfg);
    if (!h) { free(r.body);return NULL; }
    uint64_t deadline=clock_ms()+15000;esp_err_t err=ESP_ERR_HTTP_EAGAIN;
    while (allowed() && clock_ms()<deadline && !r.overflow) {
        err=esp_http_client_perform(h);
        if (err!=ESP_ERR_HTTP_EAGAIN) break;
        vTaskDelay(pdMS_TO_TICKS(20));
    }
    bool ok=err==ESP_OK && !r.overflow && r.used && esp_http_client_get_status_code(h)==200 &&
        esp_http_client_is_complete_data_received(h) && allowed();
    esp_http_client_cleanup(h); /* Release TLS before cJSON allocates its tree. */
    if (!ok) { free(r.body);return NULL; }
    r.body[r.used]=0;return r.body;
}
