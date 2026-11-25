// Liquid glass (docs/A-界面设计/A01-设计系统/A01.6-液态玻璃折射): a pane of glass over the page,
// drawn as a backdrop filter. The pane and the selection drop are rounded
// rectangles worked out here from their signed distance fields, in the
// screen's physical pixels (a backdrop filter's coordinates, checked on the
// K90). Near an edge the page behind is bent inwards like the rim of a
// thick lens (a circle's profile, A01.8), with a little colour split; the
// drop magnifies what is under it; a defined edge line (iOS 27) and a thin
// rim that catches the light from the top left.
//
// The refraction and the distance fields follow the approach of
// liquid_glass_renderer (MIT, Tim Lehmann for whynotmake.it) and
// https://iquilezles.org/articles/distfunctions2d/.
#version 460 core
// highp: the screen is 2608 pixels tall, more than mediump can place
// exactly (its rows came out as stripes along the edges on the K90).
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // the backdrop, set by the engine
uniform vec4 uPane;        // left, top, width, height
uniform vec4 uDrop;        // left, top, width, height
uniform vec4 uShape;       // pane radius, drop radius, drop visibility, drop magnification
uniform vec4 uOptics;      // edge band, refraction, rim width, colour split
uniform vec4 uTint;        // rgb, strength
uniform vec4 uLight;       // light x, light y, rim strength, saturation
uniform vec3 uEdge;        // edge line width, darken, lighten

uniform sampler2D uTexture;

out vec4 fragColor;

float roundRect(vec2 p, vec2 centre, vec2 half_, float r) {
  vec2 q = abs(p - centre) - half_ + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec2 roundRectNormal(vec2 p, vec2 centre, vec2 half_, float r) {
  vec2 e = vec2(1.0, 0.0);
  vec2 g = vec2(
    roundRect(p + e.xy, centre, half_, r) - roundRect(p - e.xy, centre, half_, r),
    roundRect(p + e.yx, centre, half_, r) - roundRect(p - e.yx, centre, half_, r)
  );
  return g / max(length(g), 1e-4);
}

vec3 backdrop(vec2 px) {
  vec2 uv = clamp(px / uSize, vec2(0.0), vec2(1.0));
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTexture, uv).rgb;
}

// The page through the glass at [p], bent by [shift] with a colour split.
vec3 refracted(vec2 p, vec2 shift, float split) {
  return vec3(
    backdrop(p + shift * (1.0 + split)).r,
    backdrop(p + shift).g,
    backdrop(p + shift * (1.0 - split)).b
  );
}

void main() {
  vec2 p = FlutterFragCoord().xy;

  vec2 paneHalf = uPane.zw * 0.5;
  vec2 paneCentre = uPane.xy + paneHalf;
  float paneRadius = min(uShape.x, min(paneHalf.x, paneHalf.y));
  float d = roundRect(p, paneCentre, paneHalf, paneRadius);
  float inside = 1.0 - smoothstep(-0.75, 0.75, d);

  // The drop: clearer glass that magnifies, only while held (A01.7). Held,
  // it grows past the pane's top and bottom, so it is drawn there too.
  vec2 dropHalf = uDrop.zw * 0.5;
  vec2 dropCentre = uDrop.xy + dropHalf;
  float dropRadius = min(uShape.y, min(dropHalf.x, dropHalf.y));
  float dd = roundRect(p, dropCentre, dropHalf, dropRadius);
  float drop = (1.0 - smoothstep(-0.75, 0.75, dd)) * uShape.z;
  float cover = max(inside, drop);
  // Keep the sampler path in one exit block: Flutter's Windows shader
  // translator cannot reliably lower early returns next to texture samples.
  if (cover > 0.0) {
    float band = uOptics.x;
    float depth = clamp(-d / band, 0.0, 1.0);
    vec2 normal = roundRectNormal(p, paneCentre, paneHalf, paneRadius);
    // Steep at the rim, flat inside: a thick lens's round edge.
    float rimward = 1.0 - depth;
    float bend = 1.0 - sqrt(max(1.0 - rimward * rimward, 0.0));
    vec3 colour = refracted(p, -normal * bend * uOptics.y, uOptics.w);

    vec2 dropNormal = roundRectNormal(p, dropCentre, dropHalf, dropRadius);
    float dropDepth = clamp(-dd / (band * 0.8), 0.0, 1.0);
    if (drop > 0.0) {
      float dropRimward = 1.0 - dropDepth;
      float dropBend = 1.0 - sqrt(max(1.0 - dropRimward * dropRimward, 0.0));
      vec2 magnified = dropCentre + (p - dropCentre) / uShape.w;
      // A stronger colour split at the drop's rim: the rainbow edge of a
      // held lens.
      vec3 seen = refracted(magnified, -dropNormal * dropBend * uOptics.y * 1.4, uOptics.w * 2.5);
      colour = mix(colour, seen, drop);
    }

    // Tint, less on the drop, and a touch more colour.
    colour = mix(colour, uTint.rgb, uTint.a * (1.0 - 0.6 * drop));
    float grey = dot(colour, vec3(0.299, 0.587, 0.114));
    colour = mix(vec3(grey), colour, uLight.w);

    // The defined edge: a thin line just inside the outline.
    float line = (1.0 - smoothstep(0.0, uEdge.x, -d)) * inside;
    colour = mix(colour, colour * (1.0 - uEdge.y) + uEdge.z, line);

    // Rims: thin and bright where the edge faces the light, faint opposite.
    vec2 light = normalize(uLight.xy);
    float rimWidth = uOptics.z;
    float rim = (1.0 - smoothstep(0.0, rimWidth, -d)) * inside;
    float facing = max(dot(normal, light), 0.0);
    float away = max(dot(normal, -light), 0.0);
    colour += rim * (0.6 * facing + 0.22 * away) * uLight.z;
    // A soft sheen along the lit edge, inside.
    colour += (1.0 - depth) * 0.07 * facing * uLight.z * inside;
    if (drop > 0.0) {
      float dropRim = 1.0 - smoothstep(0.0, rimWidth, -dd);
      float dropFacing = max(dot(dropNormal, light), 0.0);
      float dropAway = max(dot(dropNormal, -light), 0.0);
      colour += drop * dropRim * (0.75 * dropFacing + 0.3 * dropAway) * uLight.z;
    }

    colour = clamp(colour, 0.0, 1.0);
    fragColor = vec4(colour * cover, cover);
  } else {
    fragColor = vec4(0.0);
  }
}
