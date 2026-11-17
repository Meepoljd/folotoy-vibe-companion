#include "ble_links.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    vibe_ble_parameters_t p;vibe_ble_parameters_start(&p,100);
    assert(!vibe_ble_parameters_due(&p,1099));assert(vibe_ble_parameters_due(&p,1100));assert(p.waiting && p.attempts==1);
    /* A 0 command return does not imply success: actual LL collision leaves
     * the Mac's initial 360 ms timeout unchanged. Retry after a settle period. */
    vibe_ble_parameters_observe(&p,1150,36);assert(!p.waiting && p.due==2150);
    assert(!vibe_ble_parameters_due(&p,2149));assert(vibe_ble_parameters_due(&p,2150));
    vibe_ble_parameters_observe(&p,2200,600);assert(!p.due && !p.waiting);
    assert(!vibe_ble_parameters_due(&p,999999));
    /* Central later chooses a short timeout: use remaining bounded attempts. */
    vibe_ble_parameters_observe(&p,3000,36);assert(vibe_ble_parameters_due(&p,5000));
    vibe_ble_parameters_observe(&p,5010,36);assert(vibe_ble_parameters_due(&p,9010));
    vibe_ble_parameters_observe(&p,9020,36);assert(!p.due && p.attempts==4);
    assert(!vibe_ble_parameters_due(&p,999999));
    /* A lost completion event also cannot keep an idle periodic timer alive. */
    vibe_ble_parameters_start(&p,100);
    for(unsigned i=0;i<4;i++){assert(vibe_ble_parameters_due(&p,1100+i*VIBE_BLE_PARAMETER_WAIT_MS));assert(p.attempts==i+1);}
    assert(!vibe_ble_parameters_due(&p,1100+4*VIBE_BLE_PARAMETER_WAIT_MS) && !p.due);
    vibe_ble_links_t links;vibe_ble_links_init(&links);
    vibe_ble_link_t *a=vibe_ble_link_ensure(&links,1),*b=vibe_ble_link_ensure(&links,2);assert(a && b);
    vibe_ble_parameters_start(&a->parameters,0);vibe_ble_parameters_start(&b->parameters,500);
    assert(vibe_ble_parameters_due(&a->parameters,1000) && !vibe_ble_parameters_due(&b->parameters,1000));
    vibe_ble_link_remove(&links,1);a=vibe_ble_link_ensure(&links,1);assert(!a->parameters.due && !a->parameters.attempts);
    assert(b->parameters.due==1500);
    vibe_ble_links_init(&links);assert(!links.links[0].parameters.due && !links.links[1].parameters.due);
    puts("BLE parameters: deferred LL procedures, actual supervision check, collision/backoff, bounded missing completion, independent links and handle reuse PASS");
}
