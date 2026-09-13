/* SPDX-License-Identifier: Apache-2.0 */

#include <SDL3/SDL.h>
#include <stdlib.h>

static int cbss_bgfx_demo_selected_scene = 0;
static float cbss_bgfx_demo_pointer_x = 0.0f;
static float cbss_bgfx_demo_pointer_y = 0.0f;

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
        if (SDL_EVENT_KEY_DOWN == event.type)
        {
            if (event.key.key >= SDLK_1 && event.key.key <= SDLK_5)
            {
                cbss_bgfx_demo_selected_scene =
                    (int)(event.key.key - SDLK_1);
            }
            else if (SDLK_LEFT == event.key.key)
            {
                cbss_bgfx_demo_selected_scene =
                    (cbss_bgfx_demo_selected_scene + 4) % 5;
            }
            else if (SDLK_RIGHT == event.key.key)
            {
                cbss_bgfx_demo_selected_scene =
                    (cbss_bgfx_demo_selected_scene + 1) % 5;
            }
        }
        if (SDL_EVENT_MOUSE_MOTION == event.type)
        {
            int logical_width = 0;
            int logical_height = 0;
            if (SDL_GetWindowSize((SDL_Window*)raw_window,
                    &logical_width, &logical_height) &&
                    logical_width > 0 && logical_height > 0)
            {
                cbss_bgfx_demo_pointer_x =
                    event.motion.x / (float)logical_width * 2.0f - 1.0f;
                cbss_bgfx_demo_pointer_y =
                    1.0f - event.motion.y / (float)logical_height * 2.0f;
            }
        }
        if (SDL_EVENT_MOUSE_BUTTON_UP == event.type && event.button.y <= 64.0f)
        {
            int width = 0;
            int height = 0;
            if (SDL_GetWindowSize((SDL_Window*)raw_window,
                    &width, &height) && width > 0)
            {
                int selected = (int)(event.button.x * 5.0f / (float)width);
                if (selected >= 0 && selected < 5)
                {
                    cbss_bgfx_demo_selected_scene = selected;
                }
            }
        }
    }

    return SDL_GetWindowSizeInPixels((SDL_Window*)raw_window,
        pixel_width, pixel_height) ? 1 : 0;
}

int cbss_bgfx_demo_scene(float* pointer_x, float* pointer_y)
{
    if (NULL != pointer_x)
    {
        *pointer_x = cbss_bgfx_demo_pointer_x;
    }
    if (NULL != pointer_y)
    {
        *pointer_y = cbss_bgfx_demo_pointer_y;
    }
    return cbss_bgfx_demo_selected_scene;
}

void cbss_bgfx_demo_set_title(void* raw_window, const char* title)
{
    if (NULL != raw_window && NULL != title)
    {
        SDL_SetWindowTitle((SDL_Window*)raw_window, title);
    }
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
