#version 460 core
#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;      // canvas size in px
uniform float uTime;     // seconds (loops)
uniform float uCoverage; // lower = more cloud
uniform float uOpacity;  // overall alpha
uniform vec3 uColor;     // cloud tint
uniform float uScale;    // domain frequency; lower = bigger clouds

out vec4 fragColor;

// Value noise + fbm — the procedural-noise analogue of SVG feTurbulence.
float hash(vec2 p) {
  p = fract(p * vec2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
  float v = 0.0;
  float amp = 0.5;
  for (int i = 0; i < 6; i++) {
    v += amp * noise(p);
    p *= 2.0;
    amp *= 0.5;
  }
  return v;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  // uScale sets cloud size: lower = bigger. Continuous horizontal drift.
  vec2 p = uv * vec2(uScale, uScale * 0.57);
  p.x += uTime * 0.05;

  // Domain warp (feDisplacementMap analogue) for billowy, organic edges.
  vec2 warp = vec2(fbm(p + vec2(0.0, 1.7)), fbm(p + vec2(4.2, 0.0)));
  float n = fbm(p * 1.6 + warp * 0.7);

  // Narrow band above threshold => discrete puffs with sky between them.
  float c = smoothstep(uCoverage, uCoverage + 0.16, n);
  // Present everywhere, a little denser toward the top.
  c *= mix(0.6, 1.0, smoothstep(1.2, 0.0, uv.y));

  fragColor = vec4(uColor, clamp(c * uOpacity, 0.0, 1.0));
}
