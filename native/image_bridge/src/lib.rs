use image::{ImageReader, Limits};
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::ptr;

const MAX_IMAGE_WIDTH: u32 = 32_768;
const MAX_IMAGE_HEIGHT: u32 = 32_768;
const MAX_DECODE_BYTES: u64 = 512 * 1024 * 1024;
const VERSION: &[u8] = b"cbss-image-bridge 0.1.0\0";

macro_rules! ffi_guard {
    ($fallback:expr, $body:block) => {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| $body)).unwrap_or($fallback)
    };
}

fn reset_outputs(
    out_pixels: *mut *mut u8,
    out_width: *mut u32,
    out_height: *mut u32,
    out_len: *mut usize,
) {
    unsafe {
        ptr::write(out_pixels, ptr::null_mut());
        ptr::write(out_width, 0);
        ptr::write(out_height, 0);
        ptr::write(out_len, 0);
    }
}

fn load_image(
    path: *const c_char,
    out_pixels: *mut *mut u8,
    out_width: *mut u32,
    out_height: *mut u32,
    out_len: *mut usize,
) -> c_int {
    if path.is_null()
        || out_pixels.is_null()
        || out_width.is_null()
        || out_height.is_null()
        || out_len.is_null()
    {
        return -1;
    }
    reset_outputs(out_pixels, out_width, out_height, out_len);

    let path = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(value) => value,
        Err(_) => return -2,
    };

    let mut reader = match ImageReader::open(path) {
        Ok(value) => value,
        Err(_) => return -3,
    };
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_IMAGE_WIDTH);
    limits.max_image_height = Some(MAX_IMAGE_HEIGHT);
    limits.max_alloc = Some(MAX_DECODE_BYTES);
    reader.limits(limits);

    let decoded = match reader.decode() {
        Ok(value) => value,
        Err(_) => return -3,
    };
    let rgba = decoded.to_rgba8();
    let width = rgba.width();
    let height = rgba.height();
    let expected_len = match (width as usize)
        .checked_mul(height as usize)
        .and_then(|value| value.checked_mul(4))
    {
        Some(value) => value,
        None => return -4,
    };
    let bytes = rgba.into_raw();
    if width == 0 || height == 0 || bytes.len() != expected_len {
        return -4;
    }

    let mut pixels = bytes.into_boxed_slice();
    let len = pixels.len();
    let data = pixels.as_mut_ptr();
    std::mem::forget(pixels);

    unsafe {
        ptr::write(out_pixels, data);
        ptr::write(out_width, width);
        ptr::write(out_height, height);
        ptr::write(out_len, len);
    }
    0
}

#[no_mangle]
pub extern "C" fn cbss_image_load(
    path: *const c_char,
    out_pixels: *mut *mut u8,
    out_width: *mut u32,
    out_height: *mut u32,
    out_len: *mut usize,
) -> c_int {
    ffi_guard!(-99, {
        load_image(path, out_pixels, out_width, out_height, out_len)
    })
}

#[no_mangle]
pub extern "C" fn cbss_image_free(pixels: *mut u8, len: usize) {
    ffi_guard!((), {
        if !pixels.is_null() && len > 0 {
            let slice = ptr::slice_from_raw_parts_mut(pixels, len);
            unsafe {
                drop(Box::from_raw(slice));
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn cbss_image_version() -> *const c_char {
    VERSION.as_ptr().cast()
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::ColorType;
    use std::ffi::CString;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temporary_png() -> std::path::PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        std::env::temp_dir().join(format!(
            "cbss-image-bridge-{}-{nonce}.png",
            std::process::id()
        ))
    }

    #[test]
    fn rejects_null_arguments() {
        assert_eq!(
            cbss_image_load(
                ptr::null(),
                ptr::null_mut(),
                ptr::null_mut(),
                ptr::null_mut(),
                ptr::null_mut()
            ),
            -1
        );
        cbss_image_free(ptr::null_mut(), 0);
    }

    #[test]
    fn reports_missing_images_and_resets_outputs() {
        let path = CString::new("/definitely/missing/cbss-image.png").unwrap();
        let mut pixels = 1usize as *mut u8;
        let mut width = 1;
        let mut height = 1;
        let mut len = 1;
        assert_eq!(
            cbss_image_load(
                path.as_ptr(),
                &mut pixels,
                &mut width,
                &mut height,
                &mut len
            ),
            -3
        );
        assert!(pixels.is_null());
        assert_eq!((width, height, len), (0, 0, 0));
    }

    #[test]
    fn decodes_rgba8_and_releases_the_owned_buffer() {
        let path = temporary_png();
        let expected = [
            255u8, 0, 0, 255, //
            0, 255, 0, 128,
        ];
        image::save_buffer(&path, &expected, 2, 1, ColorType::Rgba8).expect("write test image");

        let c_path = CString::new(path.to_string_lossy().as_bytes()).unwrap();
        let mut pixels = ptr::null_mut();
        let mut width = 0;
        let mut height = 0;
        let mut len = 0;
        assert_eq!(
            cbss_image_load(
                c_path.as_ptr(),
                &mut pixels,
                &mut width,
                &mut height,
                &mut len
            ),
            0
        );
        assert_eq!((width, height, len), (2, 1, expected.len()));
        assert_eq!(unsafe { std::slice::from_raw_parts(pixels, len) }, expected);

        cbss_image_free(pixels, len);
        fs::remove_file(path).expect("remove test image");
    }

    #[cfg(unix)]
    #[test]
    fn rejects_non_utf8_paths() {
        let invalid = CString::new(vec![0xff]).unwrap();
        let mut pixels = ptr::null_mut();
        let mut width = 0;
        let mut height = 0;
        let mut len = 0;
        assert_eq!(
            cbss_image_load(
                invalid.as_ptr(),
                &mut pixels,
                &mut width,
                &mut height,
                &mut len
            ),
            -2
        );
    }
}
