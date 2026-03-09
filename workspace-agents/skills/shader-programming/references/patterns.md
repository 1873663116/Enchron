# Shader Programming

## Patterns


---
  #### **Name**
Efficient Texture Sampling
  #### **Description**
Minimize texture samples and use appropriate filtering
  #### **When**
Shader requires multiple texture lookups
  #### **Example**
    // BAD: Multiple samples for blur
    vec4 blur = texture(tex, uv + vec2(-1,0)*offset) +
                texture(tex, uv + vec2(1,0)*offset) +
                texture(tex, uv + vec2(0,-1)*offset) +
                texture(tex, uv + vec2(0,1)*offset);
    
    // GOOD: Use separable blur passes
    // Horizontal pass
    vec4 blur = texture(tex, uv - offset*2.0) * 0.06
              + texture(tex, uv - offset) * 0.24
              + texture(tex, uv) * 0.40
              + texture(tex, uv + offset) * 0.24
              + texture(tex, uv + offset*2.0) * 0.06;
    

---
  #### **Name**
Branching Avoidance
  #### **Description**
Replace conditionals with math operations when possible
  #### **When**
Shader has simple if/else conditions
  #### **Example**
    // BAD: Dynamic branching
    if (isLit) {
      color = litColor;
    } else {
      color = shadowColor;
    }
    
    // GOOD: Branchless with mix/lerp
    color = mix(shadowColor, litColor, float(isLit));
    
    // GOOD: Using step for thresholds
    float mask = step(threshold, value);
    color = mix(colorA, colorB, mask);
    

---
  #### **Name**
Pack Data Efficiently
  #### **Description**
Use all components of vectors and textures
  #### **When**
Passing multiple values between shader stages
  #### **Example**
    // BAD: Wasting interpolators
    out float metallic;
    out float roughness;
    out float ao;
    out float height;
    
    // GOOD: Pack into single vec4
    out vec4 materialParams; // (metallic, roughness, ao, height)
    
    // Textures: Use all RGBA channels
    // R: Metallic, G: Roughness, B: AO, A: Height
    

---
  #### **Name**
Precompute in Vertex Shader
  #### **Description**
Move calculations from fragment to vertex shader when possible
  #### **When**
Value doesn't change per-pixel or changes slowly
  #### **Example**
    // BAD: Computing view direction per-pixel
    // (fragment shader)
    vec3 viewDir = normalize(cameraPos - worldPos);
    
    // GOOD: Compute in vertex, interpolate
    // (vertex shader)
    v_viewDir = cameraPos - worldPos;
    // (fragment shader)
    vec3 viewDir = normalize(v_viewDir); // Only normalize per-pixel
    

---
  #### **Name**
Normal Map Unpacking
  #### **Description**
Correctly unpack normal maps with proper format handling
  #### **When**
Using normal maps for lighting
  #### **Example**
    // DXT5nm / BC5 format (RG channels only)
    vec3 unpackNormalRG(vec2 rg) {
      vec3 n;
      n.xy = rg * 2.0 - 1.0;
      n.z = sqrt(1.0 - saturate(dot(n.xy, n.xy)));
      return n;
    }
    
    // Standard tangent space normal map
    vec3 unpackNormal(vec4 packednormal) {
      return packednormal.rgb * 2.0 - 1.0;
    }
    

---
  #### **Name**
Signed Distance Field Rendering
  #### **Description**
Use SDFs for resolution-independent shapes
  #### **When**
Rendering UI elements, text, or procedural shapes
  #### **Example**
    // Circle SDF
    float sdCircle(vec2 p, float r) {
      return length(p) - r;
    }
    
    // Rounded box SDF
    float sdRoundedBox(vec2 p, vec2 b, float r) {
      vec2 q = abs(p) - b + r;
      return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
    }
    
    // Anti-aliased edge
    float sdf = sdCircle(uv - 0.5, 0.3);
    float aa = fwidth(sdf) * 0.5;
    float alpha = 1.0 - smoothstep(-aa, aa, sdf);
    

---
  #### **Name**
Post-Processing Stack
  #### **Description**
Chain post-processing effects efficiently
  #### **When**
Building screen-space effects pipeline
  #### **Example**
    // Order matters for quality:
    // 1. HDR effects (bloom, exposure) - work in linear space
    // 2. Color grading - apply LUT
    // 3. Anti-aliasing (FXAA/TAA) - before UI
    // 4. Tonemapping - HDR to LDR
    // 5. Gamma correction - last before display
    
    // Ping-pong buffers for multi-pass
    // Frame 1: Read A, Write B
    // Frame 2: Read B, Write A
    

---
  #### **Name**
Compute Shader Thread Groups
  #### **Description**
Size thread groups for optimal GPU occupancy
  #### **When**
Writing compute shaders for parallel processing
  #### **Example**
    // Common thread group sizes:
    // Image processing: [8,8,1] or [16,16,1] (256 threads)
    // 1D data: [256,1,1] or [64,1,1]
    // 3D volumes: [4,4,4] or [8,8,8]
    
    // HLSL
    [numthreads(8, 8, 1)]
    void CSMain(uint3 id : SV_DispatchThreadID) {
      // Check bounds for non-power-of-2 textures
      if (id.x >= _Width || id.y >= _Height) return;
    
      // Use shared memory for data reuse
      groupshared float cache[8][8];
      cache[id.x % 8][id.y % 8] = inputTexture[id.xy].r;
      GroupMemoryBarrierWithGroupSync();
    }
    

## Anti-Patterns


---
  #### **Name**
Unbounded Loops
  #### **Description**
Using loops with variable iteration count
  #### **Why**
GPU can't unroll, causes divergence, terrible for occupancy
  #### **Instead**
Use fixed loop counts known at compile time, or unroll manually

---
  #### **Name**
Texture Sampling in Loops
  #### **Description**
Sampling textures inside dynamic loops
  #### **Why**
Catastrophic for performance due to memory latency and cache thrashing
  #### **Instead**
Precompute UVs, use texture arrays, or restructure algorithm

---
  #### **Name**
Discard/Clip Abuse
  #### **Description**
Using discard/clip for effects that could use alpha blending
  #### **Why**
Breaks early-Z optimization, causes overdraw
  #### **Instead**
Use alpha blending when possible, or at least write depth in opaque pass

---
  #### **Name**
Float Precision Everywhere
  #### **Description**
Using highp/float for all calculations
  #### **Why**
Mobile GPUs are significantly slower with full precision
  #### **Instead**
Use mediump/half for colors, UVs, normals. Reserve highp for positions

---
  #### **Name**
Dependent Texture Reads
  #### **Description**
Computing UV coordinates based on previous texture samples
  #### **Why**
Creates sequential dependency, prevents parallel texture fetches
  #### **Instead**
Restructure to compute all UVs upfront when possible

---
  #### **Name**
Per-Pixel Matrix Multiplication
  #### **Description**
Doing full matrix transforms in fragment shader
  #### **Why**
Expensive and usually unnecessary per-pixel
  #### **Instead**
Transform in vertex shader, interpolate results

---
  #### **Name**
Ignoring Shader Variants
  #### **Description**
Using many keywords/toggles without considering compilation
  #### **Why**
Exponential explosion of shader variants, long build times, memory bloat
  #### **Instead**
Use multi_compile_local, consolidate features, use uber-shaders wisely

---
  #### **Name**
Branching on Uniforms
  #### **Description**
Assuming uniform-based branching is free
  #### **Why**
Even uniform branches have setup cost, may not skip work
  #### **Instead**
Use shader variants for major feature toggles