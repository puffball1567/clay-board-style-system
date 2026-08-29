/* SPDX-License-Identifier: Apache-2.0 */

#include <stddef.h>
#include <stdint.h>
#include <bgfx/c99/bgfx.h>

#include <string.h>

static bool cbss_initialized;
static uint32_t cbss_shutdown_count;
static uint32_t cbss_frame_count;
static uint32_t cbss_reset_count;
static uint32_t cbss_submit_count;
static uint32_t cbss_dispatch_count;
static uint32_t cbss_program_destroy_count;
static uint32_t cbss_shader_destroy_count;
static uint32_t cbss_width;
static uint32_t cbss_height;

void bgfx_init_ctor(bgfx_init_t* init)
{
    memset(init, 0, sizeof(*init));
    init->type = BGFX_RENDERER_TYPE_COUNT;
    init->vendorId = BGFX_PCI_ID_NONE;
    init->resolution.formatColor = BGFX_TEXTURE_FORMAT_BGRA8;
    init->resolution.formatDepthStencil = BGFX_TEXTURE_FORMAT_D24S8;
    init->resolution.numBackBuffers = 2;
}

bool bgfx_init(const bgfx_init_t* init)
{
    if (NULL == init || cbss_initialized || 0 == init->resolution.width
        || 0 == init->resolution.height
        || BGFX_TEXTURE_FORMAT_BGRA8 != init->resolution.formatColor
        || BGFX_TEXTURE_FORMAT_D24S8 != init->resolution.formatDepthStencil
        || 2 != init->resolution.numBackBuffers)
    {
        return false;
    }
    cbss_initialized = true;
    cbss_width = init->resolution.width;
    cbss_height = init->resolution.height;
    return true;
}

void bgfx_shutdown(void)
{
    cbss_initialized = false;
    ++cbss_shutdown_count;
}

const char* bgfx_get_renderer_name(bgfx_renderer_type_t type)
{
    (void)type;
    return "CBSS bgfx stub";
}

bgfx_renderer_type_t bgfx_get_renderer_type(void)
{
    return BGFX_RENDERER_TYPE_NOOP;
}

const bgfx_caps_t* bgfx_get_caps(void)
{
    static bgfx_caps_t caps;
    memset(&caps, 0, sizeof(caps));
    caps.rendererType = BGFX_RENDERER_TYPE_NOOP;
    caps.supported = BGFX_CAPS_COMPUTE;
    caps.homogeneousDepth = true;
    caps.limits.maxTextureSize = 16384;
    return &caps;
}

uint32_t bgfx_frame(uint8_t flags)
{
    (void)flags;
    return ++cbss_frame_count;
}

void bgfx_reset(uint32_t width, uint32_t height, uint32_t flags,
                bgfx_texture_format_t format)
{
    (void)flags;
    (void)format;
    ++cbss_reset_count;
    cbss_width = width;
    cbss_height = height;
}

bgfx_shader_handle_t bgfx_create_shader(const bgfx_memory_t* memory)
{
    bgfx_shader_handle_t handle = { UINT16_MAX };
    if (NULL != memory && NULL != memory->data && 0 != memory->size)
    {
        handle.idx = 10;
    }
    return handle;
}

void bgfx_destroy_shader(bgfx_shader_handle_t handle)
{
    if (UINT16_MAX != handle.idx)
    {
        ++cbss_shader_destroy_count;
    }
}

bgfx_program_handle_t bgfx_create_program(bgfx_shader_handle_t vertex,
                                          bgfx_shader_handle_t fragment,
                                          bool destroy_shaders)
{
    (void)destroy_shaders;
    bgfx_program_handle_t handle = { UINT16_MAX };
    if (UINT16_MAX != vertex.idx && UINT16_MAX != fragment.idx)
    {
        handle.idx = 20;
    }
    return handle;
}

bgfx_program_handle_t bgfx_create_compute_program(bgfx_shader_handle_t shader,
                                                  bool destroy_shader)
{
    (void)destroy_shader;
    bgfx_program_handle_t handle = { UINT16_MAX };
    if (UINT16_MAX != shader.idx)
    {
        handle.idx = 21;
    }
    return handle;
}

void bgfx_destroy_program(bgfx_program_handle_t handle)
{
    if (UINT16_MAX != handle.idx)
    {
        ++cbss_program_destroy_count;
    }
}

void bgfx_submit(bgfx_view_id_t id, bgfx_program_handle_t program,
                 uint32_t depth, uint8_t flags)
{
    (void)id;
    (void)depth;
    (void)flags;
    if (UINT16_MAX != program.idx)
    {
        ++cbss_submit_count;
    }
}

void bgfx_dispatch(bgfx_view_id_t id, bgfx_program_handle_t program,
                   uint32_t num_x, uint32_t num_y, uint32_t num_z,
                   uint8_t flags)
{
    (void)id;
    (void)num_x;
    (void)num_y;
    (void)num_z;
    (void)flags;
    if (UINT16_MAX != program.idx)
    {
        ++cbss_dispatch_count;
    }
}

void cbss_bgfx_stub_reset_counters(void)
{
    cbss_shutdown_count = 0;
    cbss_frame_count = 0;
    cbss_reset_count = 0;
    cbss_submit_count = 0;
    cbss_dispatch_count = 0;
    cbss_program_destroy_count = 0;
    cbss_shader_destroy_count = 0;
}

uint32_t cbss_bgfx_stub_shutdown_count(void) { return cbss_shutdown_count; }
uint32_t cbss_bgfx_stub_frame_count(void) { return cbss_frame_count; }
uint32_t cbss_bgfx_stub_reset_count(void) { return cbss_reset_count; }
uint32_t cbss_bgfx_stub_width(void) { return cbss_width; }
uint32_t cbss_bgfx_stub_height(void) { return cbss_height; }
uint32_t cbss_bgfx_stub_submit_count(void) { return cbss_submit_count; }
uint32_t cbss_bgfx_stub_dispatch_count(void) { return cbss_dispatch_count; }
uint32_t cbss_bgfx_stub_program_destroy_count(void)
{
    return cbss_program_destroy_count;
}
uint32_t cbss_bgfx_stub_shader_destroy_count(void)
{
    return cbss_shader_destroy_count;
}
