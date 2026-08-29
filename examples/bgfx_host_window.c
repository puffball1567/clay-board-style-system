/* SPDX-License-Identifier: Apache-2.0 */

#include <SDL3/SDL.h>
#include <stdint.h>
#include <stdlib.h>

void* cbss_bgfx_demo_create_window(const char* title, int width, int height)
{
    if (!SDL_Init(SDL_INIT_VIDEO))
    {
        return NULL;
    }

    SDL_Window* window = SDL_CreateWindow(title, width, height,
        SDL_WINDOW_RESIZABLE);
    if (NULL == window)
    {
        SDL_Quit();
    }
    return window;
}

const char* cbss_bgfx_demo_sdl_error(void)
{
    return SDL_GetError();
}

int cbss_bgfx_demo_platform_data(void* raw_window, void** display,
    void** window, int* native_window_type)
{
    SDL_PropertiesID properties = SDL_GetWindowProperties((SDL_Window*)raw_window);
    if (0 == properties)
    {
        return 0;
    }

    void* x11_display = SDL_GetPointerProperty(properties,
        SDL_PROP_WINDOW_X11_DISPLAY_POINTER, NULL);
    Sint64 x11_window = SDL_GetNumberProperty(properties,
        SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
    if (NULL != x11_display && 0 != x11_window)
    {
        *display = x11_display;
        *window = (void*)(uintptr_t)x11_window;
        *native_window_type = 0;
        return 1;
    }

    void* wayland_display = SDL_GetPointerProperty(properties,
        SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, NULL);
    void* wayland_surface = SDL_GetPointerProperty(properties,
        SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, NULL);
    if (NULL != wayland_display && NULL != wayland_surface)
    {
        *display = wayland_display;
        *window = wayland_surface;
        *native_window_type = 1;
        return 1;
    }

    SDL_SetError("the CBSS bgfx demo currently requires SDL X11 or Wayland");
    return 0;
}

int cbss_bgfx_demo_poll(void* raw_window, int* pixel_width, int* pixel_height)
{
    SDL_Event event;
    while (SDL_PollEvent(&event))
    {
        if (SDL_EVENT_QUIT == event.type)
        {
            return 0;
        }
        if (SDL_EVENT_KEY_DOWN == event.type && SDLK_ESCAPE == event.key.key)
        {
            return 0;
        }
    }

    return SDL_GetWindowSizeInPixels((SDL_Window*)raw_window,
        pixel_width, pixel_height) ? 1 : 0;
}

void cbss_bgfx_demo_delay(uint32_t milliseconds)
{
    SDL_Delay(milliseconds);
}

void cbss_bgfx_demo_destroy_window(void* raw_window)
{
    if (NULL != raw_window)
    {
        SDL_DestroyWindow((SDL_Window*)raw_window);
    }
    SDL_Quit();
}
