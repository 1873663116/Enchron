// Stub implementations for libmpv functions.
// These allow the project to compile and link without the real libmpv binary.
// Replace with actual libmpv.a/.xcframework when available.

#include "client.h"
#include "render.h"
#include <stdlib.h>
#include <string.h>

// A minimal stub handle
typedef struct mpv_handle {
    int dummy;
} mpv_handle_impl;

typedef struct mpv_render_context {
    int dummy;
} mpv_render_context_impl;

mpv_handle *mpv_create(void) {
    return (mpv_handle *)calloc(1, sizeof(mpv_handle_impl));
}

int mpv_initialize(mpv_handle *ctx) {
    (void)ctx;
    return 0;
}

void mpv_terminate_destroy(mpv_handle *ctx) {
    free(ctx);
}

void mpv_wakeup(mpv_handle *ctx) {
    (void)ctx;
}

int mpv_set_option_string(mpv_handle *ctx, const char *name, const char *data) {
    (void)ctx; (void)name; (void)data;
    return 0;
}

int mpv_set_property(mpv_handle *ctx, const char *name, mpv_format format, void *data) {
    (void)ctx; (void)name; (void)format; (void)data;
    return 0;
}

int mpv_get_property(mpv_handle *ctx, const char *name, mpv_format format, void *data) {
    (void)ctx; (void)name; (void)format; (void)data;
    return -1; // Property not found
}

int mpv_observe_property(mpv_handle *mpv, uint64_t reply_userdata, const char *name, mpv_format format) {
    (void)mpv; (void)reply_userdata; (void)name; (void)format;
    return 0;
}

int mpv_command(mpv_handle *ctx, const char **args) {
    (void)ctx; (void)args;
    return 0;
}

int mpv_command_async(mpv_handle *ctx, uint64_t reply_userdata, const char **args) {
    (void)ctx; (void)reply_userdata; (void)args;
    return 0;
}

static mpv_event stub_event = { MPV_EVENT_NONE, 0, 0, NULL };

mpv_event *mpv_wait_event(mpv_handle *ctx, double timeout) {
    (void)ctx; (void)timeout;
    return &stub_event;
}

void mpv_free(void *data) {
    (void)data;
}

int mpv_render_context_create(mpv_render_context **res, mpv_handle *mpv, mpv_render_param *params) {
    (void)mpv; (void)params;
    *res = (mpv_render_context *)calloc(1, sizeof(mpv_render_context_impl));
    return 0;
}

int mpv_render_context_render(mpv_render_context *ctx, mpv_render_param *params) {
    (void)ctx; (void)params;
    return 0;
}

void mpv_render_context_set_update_callback(mpv_render_context *ctx, mpv_render_update_fn callback, void *callback_ctx) {
    (void)ctx; (void)callback; (void)callback_ctx;
}

uint64_t mpv_render_context_update(mpv_render_context *ctx) {
    (void)ctx;
    return 0;
}

void mpv_render_context_free(mpv_render_context *ctx) {
    free(ctx);
}
