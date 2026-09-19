/* SPDX-License-Identifier: Apache-2.0 */

#include <stdint.h>
#include <string.h>

static char driver_name[32];
static int driver_available;
static uint32_t properties_id;
static void* display_handle;
static void* window_handle;
static int64_t x11_window;

void cbss_sdl3_platform_stub_configure(const char* driver, uint32_t properties,
    void* display, void* window, int64_t x11)
{
    driver_available = NULL != driver;
    driver_name[0] = '\0';
    if (driver_available)
    {
        strncpy(driver_name, driver, sizeof(driver_name) - 1);
        driver_name[sizeof(driver_name) - 1] = '\0';
    }
    properties_id = properties;
    display_handle = display;
    window_handle = window;
    x11_window = x11;
}

uint32_t SDL_GetWindowProperties(void* window)
{
    (void)window;
    return properties_id;
}

const char* SDL_GetCurrentVideoDriver(void)
{
    return driver_available ? driver_name : NULL;
}

void* SDL_GetPointerProperty(uint32_t properties, const char* name,
    void* default_value)
{
    if (properties != properties_id || 0 == properties_id)
    {
        return default_value;
    }
    if (0 == strcmp(name, "SDL.window.x11.display") ||
        0 == strcmp(name, "SDL.window.wayland.display"))
    {
        return NULL != display_handle ? display_handle : default_value;
    }
    if (0 == strcmp(name, "SDL.window.wayland.surface") ||
        0 == strcmp(name, "SDL.window.win32.hwnd") ||
        0 == strcmp(name, "SDL.window.cocoa.window"))
    {
        return NULL != window_handle ? window_handle : default_value;
    }
    return default_value;
}

int64_t SDL_GetNumberProperty(uint32_t properties, const char* name,
    int64_t default_value)
{
    if (properties == properties_id && 0 != properties_id &&
        0 == strcmp(name, "SDL.window.x11.window"))
    {
        return x11_window;
    }
    return default_value;
}
