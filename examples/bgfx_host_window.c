/* SPDX-License-Identifier: Apache-2.0 */

#include <SDL3/SDL.h>
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
