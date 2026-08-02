import std/options

import ./[color, computed_style, property, style_value]

const defaultForeground = Color(r: 0, g: 0, b: 0, a: 1)

proc inheritedForegroundColor*(env: ResolveEnv): Color =
  if env.parent.isSome and env.parent.get.text.color.isSome:
    env.parent.get.text.color.get
  else:
    defaultForeground

proc foregroundColor*(style: ComputedStyle; env: ResolveEnv): Color =
  if style.text.color.isSome:
    style.text.color.get
  else:
    env.inheritedForegroundColor()

proc resolveStyleColor*(value: StyleValue; style: ComputedStyle;
    env: ResolveEnv): Option[Color] =
  value.resolveStyleColor(style.foregroundColor(env))

proc resolveColorPair*(value: StyleValue; style: ComputedStyle;
    env: ResolveEnv): Option[tuple[first, second: Color]] =
  value.resolveColorPair(style.foregroundColor(env))

proc resolveBorderColor*(value: StyleValue; style: ComputedStyle;
    env: ResolveEnv): Option[Color] =
  value.resolveBorderColor(style.foregroundColor(env))

proc resolveShadowColor*(value: StyleValue; style: ComputedStyle;
    env: ResolveEnv): Option[Color] =
  value.resolveShadowColor(style.foregroundColor(env))
