# Shader Programming - Validations

## Texture Sample in Loop

### **Id**
shader-texture-loop
### **Severity**
critical
### **Type**
regex
### **Pattern**
  - for\s*\([^)]+\)\s*\{[^}]*(?:texture|tex2D|Sample)\s*\(
  - while\s*\([^)]+\)\s*\{[^}]*(?:texture|tex2D|Sample)\s*\(
### **Message**
Texture sampling inside loop causes severe performance degradation. GPU cannot parallelize dependent memory fetches.
### **Fix Action**
Unroll the loop, precompute UVs, or use texture arrays with single fetch
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.shader
  - *.frag
  - *.vert
  - *.cginc

## Excessive highp Usage (Mobile)

### **Id**
shader-mobile-highp-abuse
### **Severity**
critical
### **Type**
regex
### **Pattern**
  - precision\s+highp\s+float\s*;[\s\S]*precision\s+highp\s+float
  - highp\s+(?:vec[234]|mat[234])\s+\w+\s*=.*(?:color|Color|uv|UV|normal|Normal)
### **Message**
Using highp for colors/UVs/normals wastes mobile GPU cycles. These work fine at mediump.
### **Fix Action**
Use mediump for colors, UVs, normals. Reserve highp for positions and accumulated values.
### **Applies To**
  - *.glsl
  - *.frag
  - *.vert

## GrabPass in Mobile Shader

### **Id**
shader-grabpass-mobile
### **Severity**
critical
### **Type**
regex
### **Pattern**
  - GrabPass\s*\{
  - _GrabTexture
  - _CameraOpaqueTexture
### **Message**
GrabPass forces tile resolve on mobile TBDR GPUs. Extremely expensive and can cause visual artifacts.
### **Fix Action**
Use distortion with depth buffer, or bake effect differently. Avoid framebuffer reads on mobile.
### **Applies To**
  - *.shader

## Branching on Texture Sample

### **Id**
shader-branch-on-sample
### **Severity**
error
### **Type**
regex
### **Pattern**
  - if\s*\(.*(?:texture|tex2D|Sample)\s*\([^)]+\)\s*(?:\.[xyzwrgba]+)?\s*[<>=!]
  - (?:texture|tex2D|Sample)\s*\([^)]+\).*\?\s*
### **Message**
Branching based on texture sample creates divergent execution paths and prevents texture prefetch.
### **Fix Action**
Use mix/lerp with the sample value, or restructure to avoid the branch.
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.shader
  - *.frag
  - *.cginc

## Potential Division by Zero

### **Id**
shader-unguarded-division
### **Severity**
error
### **Type**
regex
### **Pattern**
  - /\s*(?!\d)[a-zA-Z_]\w*(?!\s*[\?\+\-\*])
  - /\s*\([^)]+\)(?!\s*[\?\+])
### **Message**
Division without zero check can cause NaN/Inf artifacts that propagate through rendering.
### **Fix Action**
Use max(denominator, epsilon) or rcp() with safe fallback.
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.shader
  - *.frag
  - *.cginc

## Normalize Potentially Zero Vector

### **Id**
shader-normalize-zero
### **Severity**
error
### **Type**
regex
### **Pattern**
  - normalize\s*\(\s*(?:[a-zA-Z_]\w*\s*-\s*[a-zA-Z_]\w*|[a-zA-Z_]\w*\s*\*\s*0)
### **Message**
normalize(zero vector) produces NaN. This commonly happens with direction vectors.
### **Fix Action**
Check length > epsilon before normalizing, or use safe_normalize that returns fallback.
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.shader
  - *.frag
  - *.cginc

## Too Many Shader Variants

### **Id**
shader-variant-explosion
### **Severity**
error
### **Type**
regex
### **Pattern**
  - (?:#pragma\s+multi_compile(?:_local)?\s+[^\n]+\n){6,}
### **Message**
More than 6 multi_compile lines creates 64+ shader variants. Build times and memory will suffer.
### **Fix Action**
Consolidate keywords, use multi_compile_local, or switch to runtime branching for minor features.
### **Applies To**
  - *.shader

## Manual sRGB Conversion

### **Id**
shader-srgb-manual-conversion
### **Severity**
warning
### **Type**
regex
### **Pattern**
  - pow\s*\([^,]+,\s*2\.2\s*\)
  - pow\s*\([^,]+,\s*0\.454
  - pow\s*\([^,]+,\s*1\.0\s*/\s*2\.2
### **Message**
Manual gamma conversion detected. This often indicates color space confusion.
### **Fix Action**
Use proper sRGB texture sampling and framebuffer settings. Let hardware handle conversion.
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.shader
  - *.frag
  - *.cginc

## Discard Without Depth Prepass

### **Id**
shader-discard-without-prepass
### **Severity**
warning
### **Type**
regex
### **Pattern**
  - discard\s*;
  - clip\s*\([^)]+\)\s*;
### **Message**
discard/clip breaks early-Z optimization. Ensure opaque pass or depth prepass handles depth.
### **Fix Action**
Use depth prepass for alpha-tested geometry, or consider alpha blending if possible.
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.shader
  - *.frag
  - *.cginc

## FragCoord Without Half-Pixel Offset

### **Id**
shader-fragcoord-no-offset
### **Severity**
warning
### **Type**
regex
### **Pattern**
  - gl_FragCoord\s*\.\s*xy\s*/\s*[a-zA-Z_]\w*(?!\s*\+)
  - _ScreenParams\s*\.\s*xy
### **Message**
Using FragCoord for UV without 0.5 offset can cause sampling at texel boundaries.
### **Fix Action**
Use (gl_FragCoord.xy + 0.5) / screenSize for pixel-center sampling.
### **Applies To**
  - *.glsl
  - *.frag

## Matrix Multiply in Fragment Shader

### **Id**
shader-matrix-in-fragment
### **Severity**
warning
### **Type**
regex
### **Pattern**
  - (?:mat[234]|float[234]x[234])\s*\*\s*(?:vec[234]|float[234]).*(?:gl_Position|SV_Position)
### **Message**
Full matrix multiplication in fragment shader is expensive. Consider vertex shader.
### **Fix Action**
Move matrix transforms to vertex shader and interpolate results.
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.frag

## Non-Separable Blur Implementation

### **Id**
shader-unrolled-blur
### **Severity**
warning
### **Type**
regex
### **Pattern**
  - (?:texture|tex2D)\s*\([^)]+(?:offset|OFFSET)[^)]+\)[\s\S]{0,200}(?:texture|tex2D)\s*\([^)]+(?:offset|OFFSET)[^)]+\)[\s\S]{0,200}(?:texture|tex2D)\s*\([^)]+(?:offset|OFFSET)
### **Message**
Blur appears non-separable. 9-tap 2D = 9 samples, separable = 6 samples (2 passes of 3).
### **Fix Action**
Use separable blur: horizontal pass + vertical pass. More efficient for larger kernels.
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.shader
  - *.frag

## Missing Precision Qualifier

### **Id**
shader-no-precision-qualifier
### **Severity**
warning
### **Type**
regex
### **Pattern**
  - ^(?!.*precision\s+(?:highp|mediump|lowp)).*(?:uniform|varying|in|out)\s+(?:vec|mat|float)
### **Message**
No precision qualifier in GLSL ES. Defaults may vary by platform.
### **Fix Action**
Explicitly set precision: mediump for most values, highp for positions.
### **Applies To**
  - *.glsl
  - *.frag
  - *.vert

## Redundant Normalize Calls

### **Id**
shader-redundant-normalize
### **Severity**
warning
### **Type**
regex
### **Pattern**
  - normalize\s*\(\s*normalize\s*\(
  - normalize\s*\([^)]*\)\s*\*\s*\w+\s*;[\s\S]{0,100}normalize\s*\(
### **Message**
Normalizing already-normalized vectors wastes GPU cycles.
### **Fix Action**
Track which vectors are already normalized. Remove redundant calls.
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.shader
  - *.frag
  - *.cginc

## Hardcoded Resolution Values

### **Id**
shader-hardcoded-resolution
### **Severity**
warning
### **Type**
regex
### **Pattern**
  - (?:1920|1080|1280|720|3840|2160)\.0
  - /\s*(?:1920|1080|1280|720|3840|2160)(?:\.0)?
### **Message**
Hardcoded resolution will break on different screen sizes and aspect ratios.
### **Fix Action**
Pass resolution as uniform. Use _ScreenParams in Unity or equivalent.
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.shader
  - *.frag

## Partial Vector Initialization

### **Id**
shader-vec4-partial
### **Severity**
warning
### **Type**
regex
### **Pattern**
  - vec[34]\s*\(\s*[a-zA-Z_]\w*\s*,\s*[a-zA-Z_]\w*\s*\)
  - float[34]\s*\(\s*[a-zA-Z_]\w*\s*,\s*[a-zA-Z_]\w*\s*\)
### **Message**
Partial vector construction may have unintended behavior. Explicit is better.
### **Fix Action**
Use vec4(x, y, z, w) or vec4(vec2, z, w) for clarity.
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.frag
  - *.vert

## Magic Numbers Without Constants

### **Id**
shader-magic-numbers
### **Severity**
warning
### **Type**
regex
### **Pattern**
  - \*\s*(?:0\.0[1-9]|0\.[2-9]\d*|[1-9]\.\d+)(?!\s*(?:\+|/|\*|\-|\)|;|,|\]))
### **Message**
Magic numbers make shaders hard to tune and understand.
### **Fix Action**
Define constants with descriptive names: const float ROUGHNESS_SCALE = 0.5;
### **Applies To**
  - *.glsl
  - *.hlsl
  - *.shader
  - *.frag