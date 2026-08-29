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
static uint32_t cbss_texture_create_count;
static uint32_t cbss_texture_destroy_count;
static uint32_t cbss_texture_name_count;
static uint32_t cbss_texture_data_bytes;
static uint32_t cbss_vertex_buffer_create_count;
static uint32_t cbss_vertex_buffer_destroy_count;
static uint32_t cbss_index_buffer_create_count;
static uint32_t cbss_index_buffer_destroy_count;
static uint32_t cbss_dynamic_vertex_buffer_create_count;
static uint32_t cbss_dynamic_vertex_buffer_destroy_count;
static uint32_t cbss_dynamic_index_buffer_create_count;
static uint32_t cbss_dynamic_index_buffer_destroy_count;
static uint32_t cbss_dynamic_vertex_buffer_update_count;
static uint32_t cbss_dynamic_index_buffer_update_count;
static uint32_t cbss_buffer_name_count;
static uint32_t cbss_last_buffer_data_bytes;
static uint32_t cbss_last_buffer_update_start;
static uint16_t cbss_last_buffer_flags;
static uint16_t cbss_last_vertex_stride;
static uint16_t cbss_texture_width;
static uint16_t cbss_texture_height;
static uint64_t cbss_texture_flags;
static bgfx_texture_format_t cbss_texture_format;
static uint32_t cbss_width;
static uint32_t cbss_height;
static bgfx_memory_t cbss_texture_memory;
static uint8_t cbss_texture_memory_data[4096];

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

bgfx_vertex_layout_t* bgfx_vertex_layout_begin(
    bgfx_vertex_layout_t* layout, bgfx_renderer_type_t renderer_type)
{
    (void)renderer_type;
    if (NULL != layout)
    {
        memset(layout, 0, sizeof(*layout));
    }
    return layout;
}

bgfx_vertex_layout_t* bgfx_vertex_layout_add(
    bgfx_vertex_layout_t* layout, bgfx_attrib_t attrib, uint8_t num,
    bgfx_attrib_type_t type, bool normalized, bool as_int)
{
    (void)normalized;
    (void)as_int;
    if (NULL == layout || attrib >= BGFX_ATTRIB_COUNT || num < 1 || num > 4)
    {
        return layout;
    }
    uint16_t component_size = 0;
    switch (type)
    {
    case BGFX_ATTRIB_TYPE_UINT8: component_size = 1; break;
    case BGFX_ATTRIB_TYPE_INT16:
    case BGFX_ATTRIB_TYPE_HALF: component_size = 2; break;
    case BGFX_ATTRIB_TYPE_FLOAT: component_size = 4; break;
    default: return layout;
    }
    layout->offset[attrib] = layout->stride;
    layout->attributes[attrib] = 1;
    layout->stride = (uint16_t)(layout->stride + component_size * num);
    return layout;
}

void bgfx_vertex_layout_end(bgfx_vertex_layout_t* layout)
{
    (void)layout;
}

const bgfx_memory_t* bgfx_copy(const void* data, uint32_t size)
{
    if (NULL == data || 0 == size || size > sizeof(cbss_texture_memory_data))
    {
        return NULL;
    }
    memcpy(cbss_texture_memory_data, data, size);
    cbss_texture_memory.data = cbss_texture_memory_data;
    cbss_texture_memory.size = size;
    return &cbss_texture_memory;
}

bgfx_texture_handle_t bgfx_create_texture_2d(
    uint16_t width, uint16_t height, bool has_mips, uint16_t num_layers,
    bgfx_texture_format_t format, uint64_t flags, const bgfx_memory_t* memory,
    uint64_t external)
{
    (void)has_mips;
    (void)external;
    bgfx_texture_handle_t handle = { UINT16_MAX };
    if (!cbss_initialized || 0 == width || 0 == height || 1 != num_layers)
    {
        return handle;
    }
    ++cbss_texture_create_count;
    cbss_texture_width = width;
    cbss_texture_height = height;
    cbss_texture_format = format;
    cbss_texture_flags = flags;
    cbss_texture_data_bytes = NULL == memory ? 0 : memory->size;
    handle.idx = (uint16_t)(30 + cbss_texture_create_count);
    return handle;
}

void bgfx_set_texture_name(bgfx_texture_handle_t handle, const char* name,
                           int32_t len)
{
    if (UINT16_MAX != handle.idx && NULL != name && len > 0)
    {
        ++cbss_texture_name_count;
    }
}

void bgfx_destroy_texture(bgfx_texture_handle_t handle)
{
    if (UINT16_MAX != handle.idx)
    {
        ++cbss_texture_destroy_count;
    }
}

bgfx_vertex_buffer_handle_t bgfx_create_vertex_buffer(
    const bgfx_memory_t* memory, const bgfx_vertex_layout_t* layout,
    uint16_t flags)
{
    bgfx_vertex_buffer_handle_t handle = { UINT16_MAX };
    if (!cbss_initialized || NULL == memory || NULL == layout
        || 0 == layout->stride)
    {
        return handle;
    }
    ++cbss_vertex_buffer_create_count;
    cbss_last_buffer_data_bytes = memory->size;
    cbss_last_buffer_flags = flags;
    cbss_last_vertex_stride = layout->stride;
    handle.idx = (uint16_t)(100 + cbss_vertex_buffer_create_count);
    return handle;
}

void bgfx_set_vertex_buffer_name(bgfx_vertex_buffer_handle_t handle,
                                 const char* name, int32_t len)
{
    if (UINT16_MAX != handle.idx && NULL != name && len > 0)
    {
        ++cbss_buffer_name_count;
    }
}

void bgfx_destroy_vertex_buffer(bgfx_vertex_buffer_handle_t handle)
{
    if (UINT16_MAX != handle.idx)
    {
        ++cbss_vertex_buffer_destroy_count;
    }
}

bgfx_index_buffer_handle_t bgfx_create_index_buffer(
    const bgfx_memory_t* memory, uint16_t flags)
{
    bgfx_index_buffer_handle_t handle = { UINT16_MAX };
    if (!cbss_initialized || NULL == memory)
    {
        return handle;
    }
    ++cbss_index_buffer_create_count;
    cbss_last_buffer_data_bytes = memory->size;
    cbss_last_buffer_flags = flags;
    handle.idx = (uint16_t)(120 + cbss_index_buffer_create_count);
    return handle;
}

void bgfx_set_index_buffer_name(bgfx_index_buffer_handle_t handle,
                                const char* name, int32_t len)
{
    if (UINT16_MAX != handle.idx && NULL != name && len > 0)
    {
        ++cbss_buffer_name_count;
    }
}

void bgfx_destroy_index_buffer(bgfx_index_buffer_handle_t handle)
{
    if (UINT16_MAX != handle.idx)
    {
        ++cbss_index_buffer_destroy_count;
    }
}

bgfx_dynamic_vertex_buffer_handle_t bgfx_create_dynamic_vertex_buffer(
    uint32_t num, const bgfx_vertex_layout_t* layout, uint16_t flags)
{
    bgfx_dynamic_vertex_buffer_handle_t handle = { UINT16_MAX };
    if (!cbss_initialized || 0 == num || NULL == layout || 0 == layout->stride)
    {
        return handle;
    }
    ++cbss_dynamic_vertex_buffer_create_count;
    cbss_last_buffer_data_bytes = num * layout->stride;
    cbss_last_buffer_flags = flags;
    cbss_last_vertex_stride = layout->stride;
    handle.idx = (uint16_t)(140 + cbss_dynamic_vertex_buffer_create_count);
    return handle;
}

bgfx_dynamic_vertex_buffer_handle_t bgfx_create_dynamic_vertex_buffer_mem(
    const bgfx_memory_t* memory, const bgfx_vertex_layout_t* layout,
    uint16_t flags)
{
    bgfx_dynamic_vertex_buffer_handle_t handle = { UINT16_MAX };
    if (!cbss_initialized || NULL == memory || NULL == layout
        || 0 == layout->stride)
    {
        return handle;
    }
    ++cbss_dynamic_vertex_buffer_create_count;
    cbss_last_buffer_data_bytes = memory->size;
    cbss_last_buffer_flags = flags;
    cbss_last_vertex_stride = layout->stride;
    handle.idx = (uint16_t)(140 + cbss_dynamic_vertex_buffer_create_count);
    return handle;
}

void bgfx_update_dynamic_vertex_buffer(
    bgfx_dynamic_vertex_buffer_handle_t handle, uint32_t start_vertex,
    const bgfx_memory_t* memory)
{
    if (UINT16_MAX != handle.idx && NULL != memory)
    {
        ++cbss_dynamic_vertex_buffer_update_count;
        cbss_last_buffer_update_start = start_vertex;
        cbss_last_buffer_data_bytes = memory->size;
    }
}

void bgfx_destroy_dynamic_vertex_buffer(
    bgfx_dynamic_vertex_buffer_handle_t handle)
{
    if (UINT16_MAX != handle.idx)
    {
        ++cbss_dynamic_vertex_buffer_destroy_count;
    }
}

bgfx_dynamic_index_buffer_handle_t bgfx_create_dynamic_index_buffer(
    uint32_t num, uint16_t flags)
{
    bgfx_dynamic_index_buffer_handle_t handle = { UINT16_MAX };
    if (!cbss_initialized || 0 == num)
    {
        return handle;
    }
    ++cbss_dynamic_index_buffer_create_count;
    cbss_last_buffer_data_bytes = num * ((flags & BGFX_BUFFER_INDEX32) ? 4 : 2);
    cbss_last_buffer_flags = flags;
    handle.idx = (uint16_t)(160 + cbss_dynamic_index_buffer_create_count);
    return handle;
}

bgfx_dynamic_index_buffer_handle_t bgfx_create_dynamic_index_buffer_mem(
    const bgfx_memory_t* memory, uint16_t flags)
{
    bgfx_dynamic_index_buffer_handle_t handle = { UINT16_MAX };
    if (!cbss_initialized || NULL == memory)
    {
        return handle;
    }
    ++cbss_dynamic_index_buffer_create_count;
    cbss_last_buffer_data_bytes = memory->size;
    cbss_last_buffer_flags = flags;
    handle.idx = (uint16_t)(160 + cbss_dynamic_index_buffer_create_count);
    return handle;
}

void bgfx_update_dynamic_index_buffer(
    bgfx_dynamic_index_buffer_handle_t handle, uint32_t start_index,
    const bgfx_memory_t* memory)
{
    if (UINT16_MAX != handle.idx && NULL != memory)
    {
        ++cbss_dynamic_index_buffer_update_count;
        cbss_last_buffer_update_start = start_index;
        cbss_last_buffer_data_bytes = memory->size;
    }
}

void bgfx_destroy_dynamic_index_buffer(bgfx_dynamic_index_buffer_handle_t handle)
{
    if (UINT16_MAX != handle.idx)
    {
        ++cbss_dynamic_index_buffer_destroy_count;
    }
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
    cbss_texture_create_count = 0;
    cbss_texture_destroy_count = 0;
    cbss_texture_name_count = 0;
    cbss_texture_data_bytes = 0;
    cbss_texture_width = 0;
    cbss_texture_height = 0;
    cbss_texture_flags = 0;
    cbss_texture_format = BGFX_TEXTURE_FORMAT_COUNT;
    cbss_vertex_buffer_create_count = 0;
    cbss_vertex_buffer_destroy_count = 0;
    cbss_index_buffer_create_count = 0;
    cbss_index_buffer_destroy_count = 0;
    cbss_dynamic_vertex_buffer_create_count = 0;
    cbss_dynamic_vertex_buffer_destroy_count = 0;
    cbss_dynamic_index_buffer_create_count = 0;
    cbss_dynamic_index_buffer_destroy_count = 0;
    cbss_dynamic_vertex_buffer_update_count = 0;
    cbss_dynamic_index_buffer_update_count = 0;
    cbss_buffer_name_count = 0;
    cbss_last_buffer_data_bytes = 0;
    cbss_last_buffer_update_start = 0;
    cbss_last_buffer_flags = 0;
    cbss_last_vertex_stride = 0;
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
uint32_t cbss_bgfx_stub_texture_create_count(void)
{
    return cbss_texture_create_count;
}
uint32_t cbss_bgfx_stub_texture_destroy_count(void)
{
    return cbss_texture_destroy_count;
}
uint32_t cbss_bgfx_stub_texture_name_count(void)
{
    return cbss_texture_name_count;
}
uint32_t cbss_bgfx_stub_texture_data_bytes(void)
{
    return cbss_texture_data_bytes;
}
uint16_t cbss_bgfx_stub_texture_width(void) { return cbss_texture_width; }
uint16_t cbss_bgfx_stub_texture_height(void) { return cbss_texture_height; }
uint64_t cbss_bgfx_stub_texture_flags(void) { return cbss_texture_flags; }
uint32_t cbss_bgfx_stub_texture_format(void)
{
    return (uint32_t)cbss_texture_format;
}
uint32_t cbss_bgfx_stub_vertex_buffer_create_count(void)
{
    return cbss_vertex_buffer_create_count;
}
uint32_t cbss_bgfx_stub_vertex_buffer_destroy_count(void)
{
    return cbss_vertex_buffer_destroy_count;
}
uint32_t cbss_bgfx_stub_dynamic_index_buffer_create_count(void)
{
    return cbss_dynamic_index_buffer_create_count;
}
uint32_t cbss_bgfx_stub_dynamic_index_buffer_destroy_count(void)
{
    return cbss_dynamic_index_buffer_destroy_count;
}
uint32_t cbss_bgfx_stub_dynamic_index_buffer_update_count(void)
{
    return cbss_dynamic_index_buffer_update_count;
}
uint32_t cbss_bgfx_stub_buffer_name_count(void)
{
    return cbss_buffer_name_count;
}
uint32_t cbss_bgfx_stub_last_buffer_data_bytes(void)
{
    return cbss_last_buffer_data_bytes;
}
uint32_t cbss_bgfx_stub_last_buffer_update_start(void)
{
    return cbss_last_buffer_update_start;
}
uint16_t cbss_bgfx_stub_last_buffer_flags(void)
{
    return cbss_last_buffer_flags;
}
uint16_t cbss_bgfx_stub_last_vertex_stride(void)
{
    return cbss_last_vertex_stride;
}
