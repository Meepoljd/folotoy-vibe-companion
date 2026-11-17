/* First-use pages share the root draw layer: no second widget tree or heap
 * allocation during discovery, Wi-Fi setup or a connection confirmation. */
typedef struct {
    bool active,from_menu,wifi_guide,already_connected;
    vibe_page_t page;
    char name[40],hotspot[33],notice[96];
} onboarding_surface_t;
static onboarding_surface_t onboarding_surface;
static void onboarding_text(lv_layer_t *layer,int x,int y,int width,int height,
                            const lv_font_t *font,uint32_t color,const char *text) {
    lv_draw_label_dsc_t label;lv_draw_label_dsc_init(&label);
    label.font=font;label.color=lv_color_hex(color);label.text=text;label.text_static=1;
    label.letter_space=(font==&body || font==&small)?-1:0;
#ifdef VIBE_UI_PREVIEW
    if (onboarding_surface.page==V_PROVISION && x==12 && text[0]) {
        lv_point_t size;lv_text_get_size(&size,text,font,label.letter_space,0,width,LV_TEXT_FLAG_NONE);
        assert(size.x<=width && size.y<=height);
    }
#endif
    lv_area_t area={x,y,x+width-1,y+height-1};lv_draw_label(layer,&label,&area);
}
static void onboarding_draw(lv_event_t *event) {
    if (!onboarding_surface.active) return;
    lv_layer_t *layer=lv_event_get_layer(event);
    lv_draw_rect_dsc_t rect;lv_draw_rect_dsc_init(&rect);
    rect.bg_opa=LV_OPA_COVER;rect.bg_color=lv_color_hex(BG);
    const lv_area_t area={0,HOME_TOP,239,319};lv_draw_rect(layer,&rect,&area);
    const char *keys[3]={"","","返\n回"};
    const char *title=onboarding_surface.page==V_CONNECT_GUIDE?"连接电脑":
        onboarding_surface.page==V_PROVISION?"连接 Wi-Fi":onboarding_surface.already_connected?"连接另一台电脑":onboarding_surface.wifi_guide?"Wi-Fi 已连接":"等待电脑连接";
    onboarding_text(layer,12,32,198,33,&body,INK,title);
    if (onboarding_surface.page==V_CONNECT_GUIDE) {
        onboarding_text(layer,12,68,198,24,&small,MUTED,"选择蓝牙或 Wi-Fi 配对");
        onboarding_text(layer,12,103,198,30,&body,INK,"蓝牙连接");
        onboarding_text(layer,12,135,198,25,&small,MUTED,"直接连接电脑 App");
        onboarding_text(layer,12,183,198,30,&body,INK,"Wi-Fi 连接");
        onboarding_text(layer,12,215,198,25,&small,MUTED,"与电脑连接同一 Wi-Fi");
        keys[0]="蓝\n牙";keys[1]="Wi\nFi";
        keys[2]=onboarding_surface.from_menu?"返\n回":"稍\n后";
    } else if (onboarding_surface.page==V_COMPUTER_GUIDE) {
        onboarding_text(layer,12,88,198,30,&small,MUTED,onboarding_surface.already_connected?"打开另一台电脑上的":"打开电脑上的");
        onboarding_text(layer,12,120,198,32,&body,INK,"Vibe 伴侣");
        onboarding_text(layer,12,158,198,25,&small,MUTED,"选择这台设备");
        if (onboarding_surface.already_connected) onboarding_text(layer,12,255,198,25,&small,MUTED,"原电脑保持连接");
        keys[1]="Wi\nFi";
    } else {
        onboarding_text(layer,12,80,198,25,&small,MUTED,"1 手机连接设备热点");
        onboarding_text(layer,12,112,198,28,&lv_font_montserrat_16,ACCENT,onboarding_surface.hotspot);
        onboarding_text(layer,12,150,198,25,&small,MUTED,"2 等待手机弹出配置页");
        onboarding_text(layer,12,184,198,24,&small,MUTED,"10 秒仍未弹出，");
        onboarding_text(layer,12,208,198,24,&small,MUTED,"请在浏览器打开");
        onboarding_text(layer,12,236,198,28,&lv_font_montserrat_20,ACCENT,VIBE_PORTAL_URL);
        onboarding_text(layer,12,268,198,49,&small,MUTED,onboarding_surface.notice);
        keys[0]="蓝\n牙";
    }
    if (onboarding_surface.page!=V_PROVISION) {
        onboarding_text(layer,12,onboarding_surface.page==V_CONNECT_GUIDE?264:207,198,30,&numbers16,ACCENT,onboarding_surface.name);
    }
    const int y[]={30,135,272};
    for (unsigned i=0;i<3;i++) if (keys[i][0]) {
        onboarding_text(layer,KEY_RAIL_X-1,y[i],20,44,i==1&&onboarding_surface.page!=V_PROVISION?&lv_font_montserrat_14:&small,
                        i?MUTED:ACCENT,keys[i]);
        rect.bg_color=lv_color_hex(i?MUTED:ACCENT);
        lv_area_t mark={KEY_RAIL_X+7,y[i]-6,KEY_RAIL_X+9,y[i]-4};lv_draw_rect(layer,&rect,&mark);
    }
}
static void onboarding_refresh(const vibe_model_t *m,const vibe_status_t *s) {
    onboarding_surface_t next={0};
    next.active=vibe_model_connection_page(m->page) || m->page==V_PROVISION;
    if (next.active) {
        next.page=m->page;next.from_menu=m->connection_from_menu;next.wifi_guide=m->guide_wifi && s->wifi;
        next.already_connected=m->connection_from_menu && s->peer && s->token[0];
        size_t length=strlen(s->device_id);
        snprintf(next.name,sizeof(next.name),"FoloToy · %s",length>=4?s->device_id+length-4:s->device_id);
        size_t name_length=strlen(next.name);
        for (size_t i=name_length>=4?name_length-4:0;i<name_length;i++)
            if (next.name[i]>='a' && next.name[i]<='f') next.name[i]-='a'-'A';
        snprintf(next.hotspot,sizeof(next.hotspot),"%s",s->ap_name);
        if (strcmp(s->notice,"选择 Wi-Fi")) snprintf(next.notice,sizeof(next.notice),"%s",s->notice);
    }
    if (memcmp(&next,&onboarding_surface,sizeof(next))) {
        onboarding_surface=next;const lv_area_t area={0,HOME_TOP,239,319};lv_obj_invalidate_area(screen,&area);
    }
}
