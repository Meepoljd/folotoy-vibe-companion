#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
/* Controller state, protected by v_mutex. Retries never extend the deadline. */
typedef enum { V_CONNECT_NONE,V_CONNECT_PENDING,V_CONNECT_ACCEPTED,V_CONNECT_DENIED,V_CONNECT_EXPIRED,V_CONNECT_CANCELLED } vibe_connect_phase_t;
typedef struct {
    vibe_connect_phase_t phase;
    uint64_t until;
    char client[37],request[37],digest[65],name[49];
    bool replacing;
} vibe_connection_request_t;
static inline bool vibe_connect_identity(const char *s) {
    if (!s || strlen(s)!=36) return false;
    for (unsigned i=0;i<36;i++) {
        if (i==8 || i==13 || i==18 || i==23) { if (s[i]!='-') return false; }
        else if (!strchr("0123456789abcdef",s[i])) return false;
    }
    return true;
}
static inline bool vibe_connect_digest(const char *s) { return s && strlen(s)==64 && strspn(s,"0123456789abcdef")==64; }
static inline void vibe_connect_tick(vibe_connection_request_t *r,uint64_t now) {
    if ((r->phase==V_CONNECT_PENDING || r->phase==V_CONNECT_ACCEPTED) && now>=r->until) r->phase=V_CONNECT_EXPIRED;
}
static inline bool vibe_connect_matches(const vibe_connection_request_t *r,const char *client,const char *request,const char *digest) {
    return client && request && digest && !strcmp(r->client,client) && !strcmp(r->request,request) && !strcmp(r->digest,digest);
}
static inline const char *vibe_connect_state(const vibe_connection_request_t *r) {
    switch (r->phase) {
    case V_CONNECT_PENDING:return "pending";case V_CONNECT_ACCEPTED:return "accepted";
    case V_CONNECT_DENIED:return "denied";case V_CONNECT_EXPIRED:return "expired";
    case V_CONNECT_CANCELLED:return "cancelled";default:return "idle";
    }
}
static inline bool vibe_connect_begin(vibe_connection_request_t *r,const char *client,const char *request,const char *digest,const char *name,bool replacing,uint64_t now) {
    if (!vibe_connect_identity(client) || !vibe_connect_identity(request) || !vibe_connect_digest(digest) || !name || !name[0] || strlen(name)>48) return false;
    /* The desktop sends a printable ASCII alias, avoiding absent CJK glyphs and control characters. */
    for (const unsigned char *p=(const unsigned char *)name;*p;p++) if (*p<32 || *p>126) return false;
    vibe_connect_tick(r,now);
    if (vibe_connect_matches(r,client,request,digest)) return true;
    if (r->phase==V_CONNECT_PENDING || r->phase==V_CONNECT_ACCEPTED) return false;
    memset(r,0,sizeof(*r));r->phase=V_CONNECT_PENDING;r->until=now+45000;r->replacing=replacing;
    strcpy(r->client,client);strcpy(r->request,request);strcpy(r->digest,digest);strcpy(r->name,name);return true;
}
static inline void vibe_connect_decide(vibe_connection_request_t *r,bool accept,uint64_t now) {
    vibe_connect_tick(r,now);if (r->phase!=V_CONNECT_PENDING) return;
    r->phase=accept?V_CONNECT_ACCEPTED:V_CONNECT_DENIED;r->until=now+20000;
}
