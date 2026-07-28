#ifndef CBSS_IMAGE_BRIDGE_H
#define CBSS_IMAGE_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Decodes an image into an owned RGBA8 buffer.
 *
 * Returns 0 on success and a negative status on failure:
 *   -1: null argument
 *   -2: path is not valid UTF-8
 *   -3: open or decode failed
 *   -4: decoded dimensions or buffer length are invalid
 *  -99: panic contained at the ABI boundary
 *
 * A successful buffer must be released with cbss_image_free().
 */
int32_t cbss_image_load(
    const char *path,
    uint8_t **out_pixels,
    uint32_t *out_width,
    uint32_t *out_height,
    size_t *out_len
);

void cbss_image_free(uint8_t *pixels, size_t len);

const char *cbss_image_version(void);

#ifdef __cplusplus
}
#endif

#endif
