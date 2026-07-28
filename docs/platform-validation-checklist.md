# Platform Validation Checklist

Use this checklist when validating CBSS on a platform that is not maintained as
the primary Linux x86_64 target.

## Environment

- OS:
- OS version:
- CPU architecture:
- Display server or window system:
- GPU:
- Display scale / DPI:
- Nim version:
- SDL3 source:
- SDL3 version:
- Dynamic or static linking:

## Build

- `nimble test` passes:
- `nimble buildSdl3Demo` passes:
- SDL3 library is loaded from the expected path:
- No system SDL3 is accidentally used when vendored SDL3 is expected:

## Runtime

- Window opens:
- Window closes cleanly:
- Resize works:
- Pointer movement updates hover style:
- Text is visible:
- Fill rectangles render:
- Borders render:
- Clipping works:
- No crash after 60 seconds idle:

## Platform Details

- High DPI behavior:
- X11 behavior, if applicable:
- Wayland behavior, if applicable:
- IME behavior, if text input is involved:
- Accessibility bridge connects to the expected platform channel:
- Semantic names, roles, states, bounds, focus, and activation work in a real assistive technology:
- Library packaging notes:
- Known limitations:

## Required Evidence

Attach or include:

- Build command
- Runtime command
- Screenshot or short capture
- Any required `config.nim` changes
- Any required vendor file layout changes
