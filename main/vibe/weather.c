#include "weather.h"
#include "cJSON.h"
#include <math.h>
#include <string.h>

static bool number(const cJSON *object,const char *key,int index,int low,int high,int *out) {
    const cJSON *n=cJSON_GetObjectItemCaseSensitive(object,key);
    if (index>=0) n=cJSON_GetArrayItem(n,index);
    if (!cJSON_IsNumber(n) || !isfinite(n->valuedouble) || n->valuedouble<low || n->valuedouble>high) return false;
    *out=(int)lround(n->valuedouble); return true;
}
static bool scaled(const cJSON *object,const char *key,int index,double high,double scale,unsigned *out) {
    const cJSON *n=cJSON_GetObjectItemCaseSensitive(object,key);
    if (index>=0) n=cJSON_GetArrayItem(n,index);
    if (!cJSON_IsNumber(n) || !isfinite(n->valuedouble) || n->valuedouble<0 || n->valuedouble>high) return false;
    *out=(unsigned)lround(n->valuedouble*scale);return true;
}
static bool wind(const cJSON *data,const cJSON *units,const char *key,int index,float *out) {
    const cJSON *n=cJSON_GetObjectItemCaseSensitive(data,key),*unit=cJSON_GetObjectItemCaseSensitive(units,key);
    if (index>=0) n=cJSON_GetArrayItem(n,index);
    if (!cJSON_IsString(unit) || strcmp(unit->valuestring,"m/s") || !cJSON_IsNumber(n) ||
        !isfinite(n->valuedouble) || n->valuedouble<0 || n->valuedouble>150) return false;
    *out=(float)n->valuedouble;return true;
}
bool vibe_weather_parse(const char *json,vibe_weather_t *out) {
    if (!json || !out) return false;
    cJSON *root=cJSON_Parse(json);
    const cJSON *current=cJSON_GetObjectItemCaseSensitive(root,"current");
    const cJSON *daily=cJSON_GetObjectItemCaseSensitive(root,"daily");
    vibe_weather_t w={.is_day=true};
    int day=1;
    const cJSON *day_value=cJSON_GetObjectItemCaseSensitive(current,"is_day");
    if (day_value && (!number(current,"is_day",-1,0,1,&day) || day_value->valuedouble!=day)) { cJSON_Delete(root); return false; }
    w.is_day=day!=0;
    bool ok=number(current,"temperature_2m",-1,-90,65,&w.temperature) &&
        number(current,"apparent_temperature",-1,-110,80,&w.feels) &&
        number(current,"relative_humidity_2m",-1,0,100,&w.humidity) &&
        number(current,"wind_direction_10m",-1,0,360,&w.direction) &&
        number(current,"weather_code",-1,0,99,&w.code);
    for (int i=0;i<3 && ok;i++) {
        ok=number(daily,"temperature_2m_min",i,-90,65,&w.days[i].low) &&
            number(daily,"temperature_2m_max",i,-90,65,&w.days[i].high) &&
            number(daily,"weather_code",i,0,99,&w.days[i].code) &&
            number(daily,"precipitation_probability_max",i,0,100,&w.days[i].rain) &&
            w.days[i].low<=w.days[i].high;
    }
    w.wind_valid=wind(current,cJSON_GetObjectItemCaseSensitive(root,"current_units"),"wind_speed_10m",-1,&w.wind_ms);
    w.gust_valid=wind(current,cJSON_GetObjectItemCaseSensitive(root,"current_units"),"wind_gusts_10m",-1,&w.gust_ms);
    for (unsigned i=0;i<3;i++) {
        w.days[i].uv_valid=scaled(daily,"uv_index_max",(int)i,50,10,&w.days[i].uv_tenths);
        w.days[i].wind_valid=wind(daily,cJSON_GetObjectItemCaseSensitive(root,"daily_units"),"wind_speed_10m_max",(int)i,&w.days[i].wind_ms);
    }
    int stamp=0;
    if (number(current,"time",-1,1700000000,2100000000,&stamp)) w.sampled_at=stamp;
    number(root,"utc_offset_seconds",-1,-43200,50400,&w.tz_seconds);
    const cJSON *hourly=cJSON_GetObjectItemCaseSensitive(root,"hourly");
    int count=cJSON_GetArraySize(cJSON_GetObjectItemCaseSensitive(hourly,"time"));
    for (int i=0;i<count && i<VIBE_WEATHER_HOURS;i++) {
        vibe_hour_t *h=&w.hours[i];
        if (!number(hourly,"time",i,1700000000,2100000000,&stamp) ||
            (i && stamp<=w.hours[i-1].at)) break;
        h->at=stamp;w.hour_count=(unsigned)i+1;
        if (number(hourly,"temperature_2m",i,-90,65,&h->temperature)) h->fields|=V_HOUR_TEMP;
        if (number(hourly,"precipitation_probability",i,0,100,&h->probability)) h->fields|=V_HOUR_PROB;
        if (scaled(hourly,"precipitation",i,999,10,&h->rain_tenths)) h->fields|=V_HOUR_RAIN;
    }
    cJSON_Delete(root);
    if (ok) { w.valid=true; *out=w; }
    return ok;
}
bool vibe_air_parse(const char *json,vibe_air_t *out) {
    if (!json || !out) return false;
    cJSON *root=cJSON_Parse(json);
    const cJSON *pm=cJSON_GetObjectItemCaseSensitive(cJSON_GetObjectItemCaseSensitive(root,"current"),"pm2_5");
    const cJSON *unit=cJSON_GetObjectItemCaseSensitive(cJSON_GetObjectItemCaseSensitive(root,"current_units"),"pm2_5");
    bool ok=cJSON_IsString(unit) && (!strcmp(unit->valuestring,"μg/m³") || !strcmp(unit->valuestring,"µg/m³") || !strcmp(unit->valuestring,"ug/m3")) &&
        cJSON_IsNumber(pm) && isfinite(pm->valuedouble) && pm->valuedouble>=0 && pm->valuedouble<=10000;
    vibe_air_t air={.pm25_valid=ok};
    if (ok) air.pm25_tenths=(unsigned)lround(pm->valuedouble*10);
    const cJSON *units=cJSON_GetObjectItemCaseSensitive(root,"current_units");
    const cJSON *aqi_unit=cJSON_GetObjectItemCaseSensitive(units,"us_aqi");
    air.aqi_valid=cJSON_IsString(aqi_unit) && !strcmp(aqi_unit->valuestring,"USAQI") &&
        scaled(cJSON_GetObjectItemCaseSensitive(root,"current"),"us_aqi",-1,10000,1,&air.aqi);
    air.valid=air.pm25_valid || air.aqi_valid;
    if (air.valid) *out=air;
    cJSON_Delete(root); return air.valid;
}
const char *vibe_weather_text(int c) {
    switch (c) {
        case 0:return "晴";case 1:return "晴间多云";case 2:return "多云";case 3:return "阴";
        case 45:return "雾";case 48:return "雾凇";
        case 51:return "轻微毛毛雨";case 53:return "毛毛雨";case 55:return "较强毛毛雨";
        case 56:return "轻微冻毛毛雨";case 57:return "较强冻毛毛雨";
        case 61:return "小雨";case 63:return "中雨";case 65:return "大雨";
        case 66:return "轻微冻雨";case 67:return "较强冻雨";
        case 71:return "小雪";case 73:return "中雪";case 75:return "大雪";case 77:return "雪粒";
        case 80:return "小阵雨";case 81:return "阵雨";case 82:return "强阵雨";
        case 85:return "小阵雪";case 86:return "大阵雪";
        case 95:return "雷暴";case 96:return "雷暴伴冰雹";case 97:return "强雷暴";case 99:return "雷暴伴大冰雹";
        default:return "暂无天气";
    }
}
vibe_weather_icon_t vibe_weather_icon(int c,bool day) {
    switch (c) {
        case 0:return day?VW_SUN:VW_MOON;
        case 1:case 2:return day?VW_CLOUD_SUN:VW_CLOUD_MOON;
        case 3:return VW_CLOUD;case 45:case 48:return VW_FOG;
        case 51:case 53:case 55:case 56:case 57:return VW_DRIZZLE;
        case 61:case 63:case 65:case 66:case 67:case 80:case 81:case 82:return VW_RAIN;
        case 71:case 73:case 75:case 77:case 85:case 86:return VW_SNOW;
        case 95:case 97:return VW_THUNDER;case 96:case 99:return VW_HAIL;
        default:return VW_UNKNOWN;
    }
}
const char *vibe_weather_direction(int d) {
    static const char *const directions[]={"北风","东北风","东风","东南风","南风","西南风","西风","西北风"};
    return directions[((d%360+360+22)/45)%8];
}
unsigned vibe_weather_wind_level(float ms) {
    static const float boundaries[]={.3f,1.6f,3.4f,5.5f,8.0f,10.8f,13.9f,17.2f,20.8f,24.5f,28.5f,32.7f,37.f,41.5f,46.2f,51.f,56.1f};
    unsigned level=0;while (level<17 && ms>=boundaries[level]) ++level;
    return level;
}
const char *vibe_air_text(unsigned aqi) {
    return aqi<=50?"良好":aqi<=100?"中等":aqi<=150?"敏感人群不宜":aqi<=200?"不健康":aqi<=300?"很不健康":"危险";
}
vibe_uv_level_t vibe_weather_uv_level(unsigned tenths) {
    /* WHO reporting scheme: round to a whole UVI before selecting its band. */
    unsigned uvi=tenths/10+(tenths%10>=5);
    return uvi<=2?V_UV_LOW:uvi<=5?V_UV_MODERATE:uvi<=7?V_UV_HIGH:uvi<=10?V_UV_VERY_HIGH:V_UV_EXTREME;
}
const char *vibe_weather_uv_text(vibe_uv_level_t level) {
    static const char *const labels[]={"低","中等","高","很高","极高"};
    return (unsigned)level<=V_UV_EXTREME?labels[level]:"—";
}
unsigned vibe_weather_next_hour(const vibe_weather_t *w,int64_t now) {
    unsigned i=0;while (i<w->hour_count && w->hours[i].at<=now) ++i;return i;
}
void vibe_weather_plot(const int temperatures[6],const bool valid[6],int y[6]) {
    int low=65,high=-90;bool any=false;
    for (unsigned i=0;i<6;i++) if (valid[i]) { any=true;if (temperatures[i]<low) low=temperatures[i];if (temperatures[i]>high) high=temperatures[i]; }
    if (!any) low=high=0;
    int span=high-low+2;if (span<4) span=4;
    int center=low+high;
    for (unsigned i=0;i<6;i++) y[i]=valid[i]?169-(2*temperatures[i]-center)*32/(2*span):169;
}

/* Compact computer cache. Units are protocol-defined: m/s and UVI in tenths,
 * PM2.5 in tenths of micrograms/m3, AQI on the US scale. Parse atomically and
 * reject invalid optional values instead of turning them into plausible zeros. */
static bool cache_int(const cJSON *array,int index,int low,int high,int *value) {
    const cJSON *n=cJSON_GetArrayItem(array,index);
    if(!cJSON_IsNumber(n) || !isfinite(n->valuedouble) || n->valuedouble<low || n->valuedouble>high || floor(n->valuedouble)!=n->valuedouble) return false;
    *value=(int)n->valuedouble;return true;
}
static bool cache_optional(const cJSON *array,int index,int high,int *value,bool *valid) {
    const cJSON *n=cJSON_GetArrayItem(array,index);
    *valid=n && !cJSON_IsNull(n);
    if(!*valid) return true;
    return cache_int(array,index,0,high,value);
}
bool vibe_weather_cache_parse(const cJSON *sample,vibe_weather_t *out,vibe_air_t *out_air) {
    if(!sample || !out || !out_air) return false;
    const cJSON *current=cJSON_GetObjectItemCaseSensitive(sample,"current"),*days=cJSON_GetObjectItemCaseSensitive(sample,"days"),*hours=cJSON_GetObjectItemCaseSensitive(sample,"hours");
    if(!cJSON_IsArray(current) || !cJSON_IsArray(days) || cJSON_GetArraySize(current)!=10 || cJSON_GetArraySize(days)!=3 || !cJSON_IsArray(hours) || cJSON_GetArraySize(hours)>VIBE_WEATHER_HOURS) return false;
    vibe_weather_t w={0};vibe_air_t air={0};int day,stamp,value=0;
    if(!cache_int(current,0,-90,65,&w.temperature) || !cache_int(current,1,-110,80,&w.feels) ||
       !cache_int(current,2,0,100,&w.humidity) || !cache_int(current,3,0,360,&w.direction) ||
       !cache_int(current,4,0,99,&w.code) || !cache_int(current,5,0,1,&day) ||
       !cache_int(current,8,-50400,50400,&w.tz_seconds) || !cache_int(current,9,1700000000,2100000000,&stamp)) return false;
    w.is_day=day;w.sampled_at=stamp;
    if(!cache_optional(current,6,1500,&value,&w.wind_valid)) return false;
    if(w.wind_valid) w.wind_ms=value/10.0f;
    if(!cache_optional(current,7,1500,&value,&w.gust_valid)) return false;
    if(w.gust_valid) w.gust_ms=value/10.0f;
    for(int i=0;i<3;i++) {
        const cJSON *row=cJSON_GetArrayItem(days,i);vibe_forecast_t *d=&w.days[i];
        if(!cJSON_IsArray(row) || cJSON_GetArraySize(row)!=6 || !cache_int(row,0,-90,65,&d->low) || !cache_int(row,1,-90,65,&d->high) ||
           d->low>d->high || !cache_int(row,2,0,99,&d->code) || !cache_int(row,3,0,100,&d->rain) ||
           !cache_optional(row,4,500,&value,&d->uv_valid)) return false;
        if(d->uv_valid) d->uv_tenths=(unsigned)value;
        if(!cache_optional(row,5,1500,&value,&d->wind_valid)) return false;
        if(d->wind_valid) d->wind_ms=value/10.0f;
    }
    for(int i=0;i<cJSON_GetArraySize(hours);i++) {
        const cJSON *row=cJSON_GetArrayItem(hours,i);vibe_hour_t *h=&w.hours[i];bool valid;
        if(!cJSON_IsArray(row) || cJSON_GetArraySize(row)!=4 || !cache_int(row,0,1700000000,2100000000,&stamp) ||
           (i && stamp<=w.hours[i-1].at)) return false;
        h->at=stamp;
        const cJSON *temperature=cJSON_GetArrayItem(row,1);
        if(temperature && !cJSON_IsNull(temperature)) {if(!cache_int(row,1,-90,65,&h->temperature))return false;h->fields|=V_HOUR_TEMP;}
        if(!cache_optional(row,2,100,&value,&valid)) return false;
        if(valid){h->probability=value;h->fields|=V_HOUR_PROB;}
        if(!cache_optional(row,3,9990,&value,&valid)) return false;
        if(valid){h->rain_tenths=(unsigned)value;h->fields|=V_HOUR_RAIN;}
        ++w.hour_count;
    }
    const cJSON *a=cJSON_GetObjectItemCaseSensitive(sample,"air");
    if(a && !cJSON_IsNull(a)) {
        if(!cJSON_IsArray(a) || cJSON_GetArraySize(a)!=2 || !cache_optional(a,0,100000,&value,&air.pm25_valid)) return false;
        if(air.pm25_valid) air.pm25_tenths=(unsigned)value;
        if(!cache_optional(a,1,10000,&value,&air.aqi_valid)) return false;
        if(air.aqi_valid) air.aqi=(unsigned)value;
        air.valid=air.pm25_valid || air.aqi_valid;
    }
    w.valid=true;*out=w;*out_air=air;return true;
}
