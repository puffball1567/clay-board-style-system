$input v_texcoord0

#include "bgfx_shader.sh"

uniform vec4 u_scene;
uniform vec4 u_pointer;

#define u_time u_scene.x
#define u_sceneIndex u_scene.y
#define u_aspect u_scene.z

float hash21(vec2 p)
{
  p = fract(p * vec2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return fract(p.x * p.y);
}

float circleMask(vec2 p, float radius)
{
  return 1.0 - smoothstep(radius - 0.008, radius + 0.008, length(p));
}

float roundedBoxMask(vec2 p, vec2 halfSize, float radius)
{
  vec2 q = abs(p) - halfSize + radius;
  float distanceValue = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
  return 1.0 - smoothstep(-0.004, 0.004, distanceValue);
}

float heartMask(vec2 p, float scaleValue)
{
  p /= scaleValue;
  p.y += 0.05;
  float x = p.x;
  float y = p.y;
  float a = x * x + y * y - 0.30;
  float value = a * a * a - x * x * y * y * y;
  return 1.0 - smoothstep(-0.004, 0.004, value);
}

vec3 fluidScene(vec2 uv)
{
  vec2 p = uv * 2.0 - 1.0;
  p.x *= u_aspect;
  float wave = 0.0;
  wave += sin(p.x * 3.2 + u_time * 0.78);
  wave += sin(p.y * 4.6 - u_time * 0.61);
  wave += sin((p.x + p.y) * 5.1 + u_time * 0.43);
  wave += sin(length(p - vec2(sin(u_time * 0.25), cos(u_time * 0.21))) * 8.0 - u_time);
  wave *= 0.25;
  vec3 deep = vec3(0.015, 0.045, 0.16);
  vec3 aqua = vec3(0.05, 0.83, 0.82);
  vec3 pearl = vec3(0.87, 0.98, 1.0);
  vec3 color = mix(deep, aqua, smoothstep(-0.72, 0.62, wave));
  color = mix(color, pearl, smoothstep(0.58, 0.86, wave) * 0.72);
  float pointerWave = circleMask(p - vec2(u_pointer.x * u_aspect, u_pointer.y), 0.17 + sin(u_time * 2.0) * 0.025);
  return color + pointerWave * vec3(0.10, 0.28, 0.30);
}

vec3 heartScene(vec2 uv)
{
  vec2 p = uv * 2.0 - 1.0;
  p.x *= u_aspect;
  vec3 color = mix(vec3(0.21, 0.025, 0.20), vec3(0.72, 0.08, 0.38), uv.y);
  for (int index = 0; index < 18; ++index)
  {
    float fi = float(index);
    float lane = hash21(vec2(fi, 2.7));
    float speed = 0.10 + hash21(vec2(fi, 8.1)) * 0.18;
    float y = fract(hash21(vec2(fi, 4.3)) + u_time * speed) * 2.5 - 1.25;
    float x = (lane * 2.0 - 1.0) * u_aspect;
    float sway = sin(u_time * 1.3 + fi * 2.1) * 0.06;
    float size = 0.13 + hash21(vec2(fi, 1.2)) * 0.12;
    float heart = heartMask(p - vec2(x + sway, -y), size);
    vec3 heartColor = mix(vec3(1.0, 0.32, 0.57), vec3(1.0, 0.91, 0.26), hash21(vec2(fi, 9.4)));
    color = mix(color, heartColor, heart);
  }
  float glow = 0.04 / max(0.03, length(p - vec2(0.0, 0.04)));
  return color + glow * vec3(0.42, 0.08, 0.22);
}

vec3 mechanicalScene(vec2 uv)
{
  vec2 p = uv * 2.0 - 1.0;
  p.x *= u_aspect;
  vec2 cell = fract((p + 2.0) * vec2(3.1, 4.0)) - 0.5;
  float seam = smoothstep(0.47, 0.49, max(abs(cell.x), abs(cell.y)));
  vec3 metal = mix(vec3(0.055, 0.07, 0.085), vec3(0.19, 0.23, 0.25), uv.y);
  metal -= seam * 0.075;
  vec2 coreP = p - vec2(0.0, 0.02);
  float outer = circleMask(coreP, 0.39);
  float inner = circleMask(coreP, 0.25);
  float pulse = 0.5 + 0.5 * sin(u_time * 2.8);
  metal = mix(metal, vec3(0.12, 0.17, 0.19), outer);
  metal = mix(metal, vec3(0.12, 0.82, 0.95) + pulse * vec3(0.10, 0.16, 0.12), inner);
  for (int boltIndex = 0; boltIndex < 8; ++boltIndex)
  {
    float angle = float(boltIndex) * 0.785398 + u_time * 0.08;
    vec2 boltPosition = vec2(cos(angle), sin(angle)) * vec2(0.72, 0.62);
    float bolt = circleMask(p - boltPosition, 0.055);
    metal = mix(metal, vec3(0.58, 0.66, 0.68), bolt);
  }
  float scan = exp(-abs(p.y - sin(u_time * 0.72) * 0.72) * 34.0);
  return metal + scan * vec3(0.04, 0.38, 0.45);
}

vec3 imageLabScene(vec2 uv)
{
  vec2 pixelUv = floor(uv * vec2(96.0, 54.0)) / vec2(96.0, 54.0);
  vec2 p = pixelUv * 2.0 - 1.0;
  p.x *= u_aspect;
  float lens = circleMask(p - vec2(sin(u_time * 0.33) * 0.45, cos(u_time * 0.28) * 0.20), 0.47);
  float red = 0.5 + 0.5 * sin((p.x + 0.035 * lens) * 6.0 + u_time);
  float green = 0.5 + 0.5 * sin(p.y * 7.0 - u_time * 0.74);
  float blue = 0.5 + 0.5 * sin((p.x + p.y - 0.035 * lens) * 5.0 + u_time * 0.42);
  vec3 color = vec3(red, green, blue);
  float vignette = smoothstep(1.55, 0.26, length(p));
  color *= 0.40 + vignette * 0.78;
  float divider = 1.0 - smoothstep(0.002, 0.012, abs(p.x));
  vec3 monochrome = vec3(dot(color, vec3(0.22, 0.70, 0.08)));
  color = mix(monochrome, color, step(0.0, p.x));
  return mix(color, vec3(1.0), divider * 0.72);
}

vec3 materialScene(vec2 uv)
{
  vec2 p = uv * 2.0 - 1.0;
  p.x *= u_aspect;
  vec3 background = mix(vec3(0.018, 0.025, 0.055), vec3(0.08, 0.025, 0.12), uv.y);
  float button = roundedBoxMask(p, vec2(0.68, 0.21), 0.10);
  float inner = roundedBoxMask(p, vec2(0.65, 0.18), 0.085);
  vec3 material = mix(vec3(0.12, 0.23, 0.96), vec3(0.92, 0.16, 0.72), uv.x);
  float shimmer = 0.5 + 0.5 * sin(p.x * 8.0 - u_time * 2.2 + sin(p.y * 10.0));
  material += shimmer * vec3(0.12, 0.05, 0.14);
  float rippleDistance = length(p - vec2(u_pointer.x * u_aspect, u_pointer.y));
  float ripple = exp(-abs(rippleDistance - fract(u_time * 0.32) * 0.85) * 32.0);
  material += ripple * vec3(0.32, 0.22, 0.36);
  vec3 color = mix(background, material, inner);
  color = mix(color, vec3(0.58, 0.79, 1.0), max(0.0, button - inner));
  float glow = button * (1.0 - inner) + 0.018 / max(0.02, abs(length(vec2(p.x * 0.62, p.y)) - 0.46));
  return color + glow * vec3(0.06, 0.08, 0.18);
}

void main()
{
  vec3 color;
  if (u_sceneIndex < 0.5)
  {
    color = fluidScene(v_texcoord0);
  }
  else if (u_sceneIndex < 1.5)
  {
    color = heartScene(v_texcoord0);
  }
  else if (u_sceneIndex < 2.5)
  {
    color = mechanicalScene(v_texcoord0);
  }
  else if (u_sceneIndex < 3.5)
  {
    color = imageLabScene(v_texcoord0);
  }
  else
  {
    color = materialScene(v_texcoord0);
  }
  gl_FragColor = vec4(pow(clamp(color, 0.0, 1.0), vec3_splat(1.0 / 2.2)), 1.0);
}
