// Pocket LCD dot matrix: every game pixel is one LCD cell with a gap around
// it, drawn on the game's own grid at any resolution (shaders.md, Native
// lines). Dena.emu GB lays it over every game (docs/specs/dot-matrix.md).
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 Dena.emu contributors

#pragma parameter intensity "LCD intensity" 0.8 0.0 1.0 0.05
#pragma parameter gap "Cell gap" 0.14 0.0 0.45 0.01
#pragma parameter gap_light "Gap shows the screen (1) or darkens (0)" 1.0 0.0 1.0 1.0
#pragma parameter tint "Monochrome LCD tint" 0.0 0.0 1.0 1.0
#pragma parameter palette "LCD palette (0 olive, 1 grey, 2 amber, 3 inverted)" 0.0 0.0 3.0 1.0
#pragma parameter shadow "Cell shadow" 0.0 0.0 1.0 0.05

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec2 vTex;
uniform mat4 MVPMatrix;

void main() {
  gl_Position = MVPMatrix * VertexCoord;
  vTex = TexCoord.xy;
}

#elif defined(FRAGMENT)

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

uniform sampler2D Texture;
uniform vec2 TextureSize;
uniform vec2 InputSize;
uniform vec2 OutputSize;
COMPAT_VARYING vec2 vTex;

#ifdef PARAMETER_UNIFORM
uniform float intensity;
uniform float gap;
uniform float gap_light;
uniform float tint;
uniform float palette;
uniform float shadow;
#else
#define intensity 0.8
#define gap 0.14
#define gap_light 1.0
#define tint 0.0
#define palette 0.0
#define shadow 0.0
#endif

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// Four shades from dark to light, blended smoothly (Pocket LCD palettes).
vec3 shade(float l) {
  vec3 s0, s1, s2, s3;
  if (palette < 0.5) {  // Olive: green-grey reflective screen
    s0 = vec3(0.106, 0.180, 0.090); s1 = vec3(0.275, 0.396, 0.180);
    s2 = vec3(0.553, 0.635, 0.290); s3 = vec3(0.773, 0.831, 0.541);
  } else if (palette < 1.5) {  // Pocket grey
    s0 = vec3(0.137, 0.141, 0.125); s1 = vec3(0.353, 0.361, 0.333);
    s2 = vec3(0.592, 0.600, 0.565); s3 = vec3(0.804, 0.808, 0.773);
  } else if (palette < 2.5) {  // Backlit amber
    s0 = vec3(0.180, 0.063, 0.000); s1 = vec3(0.502, 0.200, 0.000);
    s2 = vec3(0.847, 0.451, 0.031); s3 = vec3(1.000, 0.714, 0.231);
  } else {  // Inverted: light cells on a dark screen
    s0 = vec3(0.773, 0.831, 0.541); s1 = vec3(0.553, 0.635, 0.290);
    s2 = vec3(0.275, 0.396, 0.180); s3 = vec3(0.106, 0.180, 0.090);
  }
  float t = clamp(l, 0.0, 1.0) * 3.0;
  vec3 c = mix(s0, s1, clamp(t, 0.0, 1.0));
  c = mix(c, s2, clamp(t - 1.0, 0.0, 1.0));
  return mix(c, s3, clamp(t - 2.0, 0.0, 1.0));
}

vec3 cell_color(vec2 uv) {
  vec3 c = COMPAT_TEXTURE(Texture, uv).rgb;
  return mix(c, shade(luma(c)), tint);
}

void main() {
  // Position on the game's native grid: InputSize is the native picture
  // size even when the source is upscaled.
  vec2 cell = vTex * TextureSize;
  vec2 f = fract(cell);
  // One output pixel measured in cells, for a soft edge without fwidth.
  vec2 aa = clamp(InputSize / max(OutputSize, vec2(1.0)), vec2(0.001), vec2(0.5));
  // At least about one screen pixel, so small scales keep every gap.
  vec2 half_gap = max(vec2(gap * 0.5), aa * 0.55);
  vec2 lo = smoothstep(half_gap - aa * 0.5, half_gap + aa * 0.5, f);
  vec2 hi = smoothstep(half_gap - aa * 0.5, half_gap + aa * 0.5, 1.0 - f);
  float lit = lo.x * lo.y * hi.x * hi.y;

  vec3 raw = COMPAT_TEXTURE(Texture, vTex).rgb;
  vec3 px = cell_color(vTex);
  // The empty screen behind the cells: the palette's lightest shade on a
  // monochrome LCD, a pale reflective panel on a colour one. gap_light 0
  // darkens the gaps instead, like a backlit grid.
  vec3 screen = tint > 0.5 ? shade(palette > 2.5 ? 0.0 : 1.0)
                           : mix(px, vec3(0.92, 0.93, 0.88), 0.45);
  vec3 gap_col = mix(px * 0.55, mix(px, screen, 0.7), gap_light);
  // Cells cast a faint shadow down and right onto the screen.
  vec2 back = (floor(cell - vec2(0.3)) + 0.5) / TextureSize;
  float dark = 1.0 - luma(cell_color(back));
  gap_col *= 1.0 - shadow * 0.35 * dark;
  vec3 lcd = mix(gap_col, px, lit);
  FragColor = vec4(mix(raw, lcd, intensity), 1.0);
}
#endif
