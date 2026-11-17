#include "weather.h"
#include "cJSON.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const char *sample="{\"current\":[12,10,45,90,2,1,15,28,28800,1790000000],\"days\":[[1,15,2,20,31,40],[2,16,3,30,null,null],[3,17,61,80,10,55]],\"hours\":[[1790000000,12,20,1],[1790003600,null,0,null]],\"air\":[241,62]}";
int main(int argc,char **argv) {
 vibe_weather_t w={0};vibe_air_t air={0};cJSON *root=cJSON_Parse(sample);assert(root);
 assert(vibe_weather_cache_parse(root,&w,&air));assert(w.valid && w.temperature==12 && w.wind_ms==1.5f && w.gust_ms==2.8f && w.sampled_at==1790000000 && w.tz_seconds==28800);
 assert(w.days[0].uv_valid && w.days[0].uv_tenths==31 && !w.days[1].uv_valid && !w.days[1].wind_valid);
 assert(w.hour_count==2 && w.hours[0].fields==7 && w.hours[1].fields==V_HOUR_PROB && air.valid && air.pm25_tenths==241 && air.aqi==62);
 vibe_weather_t before=w;vibe_air_t before_air=air;
 cJSON *c=cJSON_GetObjectItemCaseSensitive(root,"current");cJSON_ReplaceItemInArray(c,2,cJSON_CreateNumber(100.5));
 assert(!vibe_weather_cache_parse(root,&w,&air) && !memcmp(&w,&before,sizeof(w)) && !memcmp(&air,&before_air,sizeof(air)));cJSON_Delete(root);
 root=cJSON_Parse(sample);c=cJSON_GetObjectItemCaseSensitive(root,"hours");cJSON_ReplaceItemInArray(cJSON_GetArrayItem(c,1),0,cJSON_CreateNumber(1790000000));assert(!vibe_weather_cache_parse(root,&w,&air));cJSON_Delete(root);
 root=cJSON_Parse(sample);c=cJSON_GetObjectItemCaseSensitive(root,"current");cJSON_ReplaceItemInArray(c,6,cJSON_CreateNumber(1501));assert(!vibe_weather_cache_parse(root,&w,&air));cJSON_Delete(root);
 root=cJSON_Parse(sample);c=cJSON_GetObjectItemCaseSensitive(root,"days");cJSON_ReplaceItemInArray(cJSON_GetArrayItem(c,0),0,cJSON_CreateNumber(16));assert(!vibe_weather_cache_parse(root,&w,&air));cJSON_Delete(root);
 root=cJSON_Parse(sample);cJSON_ReplaceItemInObjectCaseSensitive(root,"air",cJSON_CreateNull());assert(vibe_weather_cache_parse(root,&w,&air) && !air.valid);cJSON_Delete(root);
 root=cJSON_Parse(sample);c=cJSON_GetObjectItemCaseSensitive(root,"hours");for(unsigned i=0;i<12;i++)cJSON_AddItemToArray(c,cJSON_CreateArray());assert(!vibe_weather_cache_parse(root,&w,&air));cJSON_Delete(root);
 if(argc>1) {
  FILE *file=fopen(argv[1],"rb");assert(file);char text[1537];size_t n=fread(text,1,sizeof(text)-1,file);fclose(file);text[n]=0;
  root=cJSON_Parse(text);assert(root && vibe_weather_cache_parse(root,&w,&air) && w.valid && w.hour_count>0);cJSON_Delete(root);
  printf("Actual computer weather sample: hours=%u PM2.5=%d AQI=%d PASS\n",w.hour_count,air.pm25_valid,air.aqi_valid);
 }
 puts("Computer weather cache: units, optional values, timestamp order, size/range/type faults and atomic rollback PASS");
}
