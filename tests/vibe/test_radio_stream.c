#include "radio/stream.h"
#include "adpcm.h"
#include <assert.h>
#include <stdio.h>
static void packet(uint8_t *p,uint64_t id,uint32_t seq) {
    memset(p,0,V_RADIO_PACKET);p[0]=5;p[13]=V_RADIO_FORMAT;
    for(unsigned i=0;i<8;i++)p[1+i]=(uint8_t)(id>>(i*8));
    for(unsigned i=0;i<4;i++)p[9+i]=(uint8_t)(seq>>(i*8));
}
int main(int argc,char **argv) {
    uint8_t storage[V_RADIO_WINDOW][V_RADIO_BYTES],*buffers[V_RADIO_WINDOW];
    for(unsigned i=0;i<V_RADIO_WINDOW;i++)buffers[i]=storage[i];
    vibe_radio_stream_t s;uint8_t p[V_RADIO_PACKET],frame[V_RADIO_BYTES];
    for(unsigned cycle=1;cycle<=100;cycle++) {
        vibe_radio_stream_init(&s,cycle,cycle,buffers);
        packet(p,cycle,0);
        assert(!vibe_radio_stream_receive(&s,p,sizeof(p)-1,cycle,false));
        assert(!vibe_radio_stream_receive(&s,p,sizeof(p),cycle+1,false));
        p[16]=89;assert(!vibe_radio_stream_receive(&s,p,sizeof(p),cycle,false));p[16]=0;
        p[17]=1;assert(!vibe_radio_stream_receive(&s,p,sizeof(p),cycle,false));p[17]=0;
        packet(p,cycle+1,0);assert(!vibe_radio_stream_receive(&s,p,sizeof(p),cycle,false));
        packet(p,cycle,V_RADIO_WINDOW);assert(!vibe_radio_stream_receive(&s,p,sizeof(p),cycle,false));
        packet(p,cycle,1);assert(vibe_radio_stream_receive(&s,p,sizeof(p),cycle,true));assert(!vibe_radio_stream_pop(&s,frame));
        packet(p,cycle,0);assert(vibe_radio_stream_receive(&s,p,sizeof(p),cycle,false));
        assert(vibe_radio_stream_receive(&s,p,sizeof(p),cycle,true));assert(s.mask==3 && s.next==0);
        assert(vibe_radio_stream_pop(&s,frame) && s.next==1);assert(vibe_radio_stream_pop(&s,frame) && s.next==2);
        assert(vibe_radio_stream_receive(&s,p,sizeof(p),cycle,false));assert(s.last_wifi==0 && !vibe_radio_stream_pop(&s,frame));
        for(unsigned seq=2;seq<10000;seq++) {packet(p,cycle,seq);assert(vibe_radio_stream_receive(&s,p,sizeof(p),cycle,seq%2));assert(vibe_radio_stream_pop(&s,frame));}
    }
    vibe_radio_stream_init(&s,1,1,buffers);s.next=UINT32_MAX-2;
    for(unsigned i=V_RADIO_WINDOW;i>0;i--) {uint32_t seq=s.next+i-1;packet(p,1,seq);p[14]=(uint8_t)seq;assert(vibe_radio_stream_receive(&s,p,sizeof(p),1,true));}
    for(unsigned i=0;i<V_RADIO_WINDOW;i++) {uint8_t expected=(uint8_t)s.next;assert(vibe_radio_stream_pop(&s,frame) && frame[0]==expected);}
    assert(!s.mask);
    assert(sizeof(s)<=32+V_RADIO_WINDOW*sizeof(void *));
    packet(p,1,0);p[13]=1;assert(!vibe_radio_stream_receive(&s,p,sizeof(p),1,false));
    int16_t pcm[V_RADIO_SAMPLES],decoded[V_RADIO_SAMPLES];adpcm_state_t encoder;adpcm_state_reset(&encoder);
    for(unsigned i=0;i<V_RADIO_SAMPLES;i++)pcm[i]=(int16_t)((i*7919u)%60000u-30000);
    assert(adpcm_encode_block(&encoder,pcm,V_RADIO_SAMPLES,frame,sizeof(frame))==sizeof(frame));
    assert(adpcm_decode_block(frame,sizeof(frame),V_RADIO_SAMPLES,decoded,V_RADIO_SAMPLES)==V_RADIO_SAMPLES);
    if(argc>1) {FILE *f=fopen(argv[1],"wb");assert(f);assert(fwrite(frame,1,sizeof(frame),f)==sizeof(frame));fclose(f);}
    puts("Remote radio: million dual-link frames, reorder/duplicate/window/owner/session/size/IMA checks PASS");
}
