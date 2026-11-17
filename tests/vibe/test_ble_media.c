#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
static unsigned live,peak;static bool fail_allocate;
static void *allocate(size_t n,size_t size) {if(fail_allocate)return NULL;void *p=calloc(n,size);assert(p);++live;if(live>peak)peak=live;return p;}
static void release(void *p) {if(p){assert(live);--live;free(p);}}
#define calloc allocate
#define free release
#include "ble_media.h"
#undef calloc
#undef free
int main(void) {
 uint8_t packet[V_RADIO_PACKET]={5};packet[13]=V_RADIO_FORMAT;
 vibe_ble_media_t media={0};vibe_ble_frame_t control={0};
 for(unsigned cycle=0;cycle<100;cycle++)for(unsigned mtu=20;mtu<=244;mtu+=8) {
  unsigned cap=mtu-7;vibe_ble_frame_t *complete=NULL;
  for(unsigned offset=0;offset<sizeof(packet);offset+=cap) {
   unsigned length=sizeof(packet)-offset;if(length>cap)length=cap;
   uint8_t frame[244]={0x56,(uint8_t)cycle,4|(offset==0?1:0)|(offset+length==sizeof(packet)?2:0),(uint8_t)V_RADIO_PACKET,(uint8_t)(V_RADIO_PACKET>>8),(uint8_t)offset,(uint8_t)(offset>>8)};
   memcpy(frame+7,packet+offset,length);
   complete=vibe_ble_media_feed(&media,frame,length+7,cycle*10);
   /* A complete control packet between every pair of audio fragments must
    * neither corrupt the radio packet nor lose its own reply. */
   uint8_t c[]={0x56,9,3,2,0,0,0,2,123};assert(vibe_ble_frame_feed(&control,c,sizeof(c),cycle*10));
   assert(control.used==2 && control.bytes[0]==2 && control.bytes[1]==123);
  }
  assert(complete && complete->used==sizeof(packet) && !memcmp(complete->bytes,packet,sizeof(packet)));
  vibe_ble_media_clear(&media);assert(!live);
 }
 uint8_t first[244]={0x56,1,5,(uint8_t)V_RADIO_PACKET,(uint8_t)(V_RADIO_PACKET>>8),0,0,5};first[20]=V_RADIO_FORMAT;
 fail_allocate=true;assert(!vibe_ble_media_feed(&media,first,sizeof(first),1) && !media.frame);fail_allocate=false;
 assert(!vibe_ble_media_feed(&media,first,sizeof(first),10) && media.frame && live==1);
 vibe_ble_media_expire(&media,2010);assert(media.frame);vibe_ble_media_expire(&media,2011);assert(!media.frame && !live && peak==1);
 puts("BLE media: interleaved ATT control/audio, every short-write size, 2,900 sessions, allocation failure, expiry and scratch cleanup PASS");
}
