/* SPDX-License-Identifier: Apache-2.0 */

#include <SDL3/SDL.h>

void* cbss_bgfx_pixel_create_window(int width, int height)
{
    if (!SDL_Init(SDL_INIT_VIDEO))
    {
        return NULL;
    }

    SDL_WindowFlags flags = SDL_WINDOW_HIDDEN;
    const char* visible = SDL_getenv("CBSS_GPU_PIXEL_WINDOW_VISIBLE");
    if (NULL != visible && '1' == visible[0] && '\0' == visible[1])
    {
        flags = 0;
    }

    SDL_Window* window = SDL_CreateWindow(
        "CBSS GPU pixel conformance",
        width,
        height,
        flags
    );
    if (NULL == window)
    {
        SDL_Quit();
    }
    return window;
}

const char* cbss_bgfx_pixel_sdl_error(void)
{
    return SDL_GetError();
}

void cbss_bgfx_pixel_pump(void)
{
    SDL_Event event;
    while (SDL_PollEvent(&event))
    {
    }
}

void cbss_bgfx_pixel_destroy_window(void* raw_window)
{
    if (NULL != raw_window)
    {
        SDL_DestroyWindow((SDL_Window*)raw_window);
    }
    SDL_Quit();
}
