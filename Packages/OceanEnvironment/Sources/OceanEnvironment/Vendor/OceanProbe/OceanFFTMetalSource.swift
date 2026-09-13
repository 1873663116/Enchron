enum OceanFFTMetalSource {
    static var source: String {
        #"""
        #include <metal_stdlib>
        using namespace metal;

        #define FFT_SIZE \#(OceanSimulationGrid.resolution)
        #define LOG_SIZE \#(OceanSimulationGrid.logResolution)
        #define CASCADE_COUNT 4
        constant float PI = 3.14159265358979323846f;

        constant float2 ENVELOPE_WAVE_VECTORS[3] = {
            float2(6.53113031f, 1.99676692f),
            float2(1.64968145f, 4.79102278f),
            float2(-2.19843912f, 2.9174273f),
        };
        constant float ENVELOPE_PHASES[3] = {
            0.370000005f,
            2.1099999f,
            4.73000002f,
        };

        struct OceanUniforms {
            uint resolution;
            uint seed;
            float depth;
            float gravity;
            float frameTime;
            float deltaTime;
            float repeatTime;
            float inverseFFTScale;
            float4 lengthScales;
            float4 cutoffLow;
            float4 cutoffHigh;
            float choppiness;
            float foamBias;
            float foamPower;
            float foamAdd;
            float foamDecay;
            uint activeCascadeCount;
            float detailDeltaTime;
        };

        struct WindSpectrumParameters {
            float scale;
            float angle;
            float spreadBlend;
            float alignment;
            float alpha;
            float peakOmega;
            float gamma;
            float shortWavesFade;
        };

        struct SwellSpectrumParameters {
            float height;
            float angle;
            float peakWaveNumber;
            float angularFrequencySigma;
            float directionalSigma;
            float energyScale;
            float padding0;
            float padding1;
        };

        struct SurfaceUniforms {
            uint vertexCount;
            uint resolution;
            float amplitude;
            float padding;
            float4 lengthScales;
            float envelopeAmount;
            float envelopeScaleMeters;
        };

        struct SurfacePublicationUniforms {
            uint resolution;
            float amplitude;
        };

        struct InterpolatedSurfacePublicationUniforms {
            uint resolution;
            float amplitude;
            float interpolationWeight;
            float padding;
        };

        struct OceanVertex {
            float3 position;
            float3 normal;
            float4 tangent;
            float2 uv;
            float2 baseXZ;
            float4 stitch;
        };

        float2 complexMultiply(float2 a, float2 b) {
            return float2(
                a.x * b.x - a.y * b.y,
                a.x * b.y + a.y * b.x
            );
        }

        float oceanEnvelope(
            float2 worldXZ,
            float amount,
            float scaleMeters
        ) {
            if (amount == 0.0f) {
                return 1.0f;
            }
            float2 scaledXZ = worldXZ / scaleMeters;
            float waveSum = 0.0f;
            for (uint index = 0; index < 3; ++index) {
                waveSum += sin(
                    dot(ENVELOPE_WAVE_VECTORS[index], scaledXZ)
                        + ENVELOPE_PHASES[index]
                );
            }
            return 1.0f + amount * (waveSum / 3.0f);
        }

        uint integerHash(uint value) {
            value = (value << 13u) ^ value;
            return value * (value * value * 15731u + 789221u) + 1376312589u;
        }

        float random01(uint value) {
            return float(integerHash(value) & 0x7fffffffu) / 2147483647.0f;
        }

        float2 gaussian(uint seedA, uint seedB) {
            float u1 = max(random01(seedA), 1.0e-6f);
            float u2 = random01(seedB);
            float radius = sqrt(-2.0f * log(u1));
            float theta = 2.0f * PI * u2;
            return radius * float2(cos(theta), sin(theta));
        }

        float dispersion(float waveNumber, constant OceanUniforms &uniforms) {
            float kh = min(waveNumber * uniforms.depth, 20.0f);
            return sqrt(uniforms.gravity * waveNumber * tanh(kh));
        }

        float dispersionDerivative(
            float waveNumber,
            constant OceanUniforms &uniforms
        ) {
            float kh = min(waveNumber * uniforms.depth, 20.0f);
            float tanhKH = tanh(kh);
            float coshKH = cosh(kh);
            float derivative = uniforms.depth * waveNumber / (coshKH * coshKH)
                + tanhKH;
            return uniforms.gravity * derivative
                / max(2.0f * dispersion(waveNumber, uniforms), 1.0e-6f);
        }

        float normalizationFactor(float spread) {
            float s2 = spread * spread;
            float s3 = s2 * spread;
            float s4 = s3 * spread;
            if (spread < 5.0f) {
                return -0.000564f * s4 + 0.00776f * s3
                    - 0.044f * s2 + 0.192f * spread + 0.163f;
            }
            return -4.80e-08f * s4 + 1.07e-05f * s3
                - 9.53e-04f * s2 + 5.90e-02f * spread + 0.393f;
        }

        float spreadPower(float omega, float peakOmega) {
            float ratio = abs(omega / max(peakOmega, 1.0e-6f));
            return omega <= peakOmega
                ? 6.97f * pow(ratio, 5.0f)
                : 9.77f * pow(ratio, -2.5f);
        }

        float directionSpectrum(
            float theta,
            float omega,
            device const WindSpectrumParameters &parameters
        ) {
            float spreadScale = mix(0.35f, 3.0f, parameters.alignment);
            float spread = max(
                0.25f,
                spreadPower(omega, parameters.peakOmega) * spreadScale
            );
            float cosineModel = normalizationFactor(spread)
                * pow(abs(cos(0.5f * (theta - parameters.angle))), 2.0f * spread);
            // The reference writes this endpoint as an unrotated 2/PI*cos(theta)^2
            // over the full circle, which peaks upwind as well as downwind and
            // integrates to two. It ships spreadBlend at one, so that endpoint
            // never runs there. windAlignment keeps it live here, so it carries
            // the normalised half-plane form instead.
            float delta = atan2(
                sin(theta - parameters.angle),
                cos(theta - parameters.angle)
            );
            float broadModel = abs(delta) <= 0.5f * PI
                ? 2.0f / PI * cos(delta) * cos(delta)
                : 0.0f;
            return mix(broadModel, cosineModel, parameters.spreadBlend);
        }

        float tmaCorrection(float omega, constant OceanUniforms &uniforms) {
            float omegaH = omega * sqrt(uniforms.depth / uniforms.gravity);
            if (omegaH <= 1.0f) {
                return 0.5f * omegaH * omegaH;
            }
            if (omegaH < 2.0f) {
                float difference = 2.0f - omegaH;
                return 1.0f - 0.5f * difference * difference;
            }
            return 1.0f;
        }

        float jonswap(
            float omega,
            device const WindSpectrumParameters &parameters,
            constant OceanUniforms &uniforms
        ) {
            float sigma = omega <= parameters.peakOmega ? 0.07f : 0.09f;
            float normalizedDifference = (omega - parameters.peakOmega)
                / max(sigma * parameters.peakOmega, 1.0e-6f);
            float resonance = exp(-0.5f * normalizedDifference * normalizedDifference);
            float inverseOmega = 1.0f / max(omega, 1.0e-6f);
            float peakRatio = parameters.peakOmega * inverseOmega;
            return parameters.scale
                * tmaCorrection(omega, uniforms)
                * parameters.alpha
                * uniforms.gravity * uniforms.gravity
                * pow(inverseOmega, 5.0f)
                * exp(-1.25f * pow(peakRatio, 4.0f))
                * pow(max(abs(parameters.gamma), 1.0e-6f), resonance);
        }

        float shortWaveFade(
            float waveNumber,
            device const WindSpectrumParameters &parameters
        ) {
            float fade = parameters.shortWavesFade;
            return exp(-fade * fade * waveNumber * waveNumber / 10000.0f);
        }

        float swellEnergy(
            float waveNumber,
            float omega,
            float theta,
            constant OceanUniforms &uniforms,
            constant SwellSpectrumParameters &parameters
        ) {
            if (parameters.height <= 0.0f) {
                return 0.0f;
            }
            float peakOmega = dispersion(parameters.peakWaveNumber, uniforms);
            float sigmaOmega = max(parameters.angularFrequencySigma, 1.0e-5f);
            float normalizedOmega = (omega - peakOmega) / sigmaOmega;
            float frequencyDensity = exp(-0.5f * normalizedOmega * normalizedOmega)
                / (sqrt(2.0f * PI) * sigmaOmega);
            float angleDelta = atan2(
                sin(theta - parameters.angle),
                cos(theta - parameters.angle)
            );
            float sigmaAngle = max(parameters.directionalSigma, 1.0e-4f);
            float directionDensity = exp(
                -0.5f * angleDelta * angleDelta / (sigmaAngle * sigmaAngle)
            ) / (sqrt(2.0f * PI) * sigmaAngle);
            return parameters.energyScale * frequencyDensity * directionDensity;
        }

        kernel void initializeSpectrum(
            texture2d_array<float, access::write> initialSpectrum [[texture(0)]],
            constant OceanUniforms &uniforms [[buffer(0)]],
            device const WindSpectrumParameters *windSpectra [[buffer(1)]],
            constant SwellSpectrumParameters &swell [[buffer(2)]],
            uint2 position [[thread_position_in_grid]]
        ) {
            if (position.x >= uniforms.resolution || position.y >= uniforms.resolution) {
                return;
            }

            float halfResolution = float(uniforms.resolution) * 0.5f;
            float2 centered = float2(position) - halfResolution;

            for (uint cascade = 0; cascade < CASCADE_COUNT; ++cascade) {
                float lengthScale = uniforms.lengthScales[cascade];
                float deltaK = 2.0f * PI / lengthScale;
                float2 k = centered * deltaK;
                float waveNumber = length(k);
                float4 result = 0.0f;

                if (waveNumber >= uniforms.cutoffLow[cascade]
                    && waveNumber < uniforms.cutoffHigh[cascade]) {
                    uint baseSeed = uniforms.seed
                        + position.x
                        + position.y * uniforms.resolution
                        + cascade * 0x9e3779b9u;
                    float2 gaussianA = gaussian(baseSeed + 1u, baseSeed + 2u);
                    float2 gaussianB = gaussian(baseSeed + 3u, baseSeed + 4u);
                    float omega = dispersion(waveNumber, uniforms);
                    float angle = atan2(k.y, k.x);
                    float energy = 0.0f;

                    for (uint spectrumIndex = 0; spectrumIndex < 2; ++spectrumIndex) {
                        uint index = cascade * 2 + spectrumIndex;
                        if (windSpectra[index].scale > 0.0f) {
                            energy += jonswap(omega, windSpectra[index], uniforms)
                                * directionSpectrum(angle, omega, windSpectra[index])
                                * shortWaveFade(waveNumber, windSpectra[index]);
                        }
                    }
                    energy += swellEnergy(
                        waveNumber,
                        omega,
                        angle,
                        uniforms,
                        swell
                    );

                    float scale = sqrt(
                        max(energy, 0.0f)
                        * 2.0f
                        * abs(dispersionDerivative(waveNumber, uniforms))
                        / max(waveNumber, 1.0e-6f)
                        * deltaK * deltaK
                    );
                    result.xy = float2(gaussianA.x, gaussianB.y) * scale;
                }

                initialSpectrum.write(result, position, cascade);
            }
        }

        kernel void packSpectrumConjugate(
            texture2d_array<float, access::read_write> initialSpectrum [[texture(0)]],
            constant OceanUniforms &uniforms [[buffer(0)]],
            uint2 position [[thread_position_in_grid]]
        ) {
            if (position.x >= uniforms.resolution || position.y >= uniforms.resolution) {
                return;
            }
            uint2 mirrored = uint2(
                (uniforms.resolution - position.x) % uniforms.resolution,
                (uniforms.resolution - position.y) % uniforms.resolution
            );
            for (uint cascade = 0; cascade < CASCADE_COUNT; ++cascade) {
                float2 h0 = initialSpectrum.read(position, cascade).xy;
                float2 opposite = initialSpectrum.read(mirrored, cascade).xy;
                initialSpectrum.write(
                    float4(h0, opposite.x, -opposite.y),
                    position,
                    cascade
                );
            }
        }

        kernel void updateSpectrum(
            texture2d_array<float, access::read> initialSpectrum [[texture(0)]],
            texture2d_array<float, access::write> spectrum [[texture(1)]],
            constant OceanUniforms &uniforms [[buffer(0)]],
            uint2 position [[thread_position_in_grid]]
        ) {
            if (position.x >= uniforms.resolution || position.y >= uniforms.resolution) {
                return;
            }

            float halfResolution = float(uniforms.resolution) * 0.5f;
            float2 centered = float2(position) - halfResolution;

            for (uint cascade = 0; cascade < uniforms.activeCascadeCount; ++cascade) {
                float4 initial = initialSpectrum.read(position, cascade);
                float2 h0 = initial.xy;
                float2 h0Conjugate = initial.zw;
                float2 k = centered * (2.0f * PI / uniforms.lengthScales[cascade]);
                float waveNumber = length(k);
                float inverseWaveNumber = waveNumber < 0.0001f ? 1.0f : 1.0f / waveNumber;
                float baseFrequency = 2.0f * PI / uniforms.repeatTime;
                float quantizedOmega = round(
                    dispersion(waveNumber, uniforms) / baseFrequency
                ) * baseFrequency;
                float phase = quantizedOmega * uniforms.frameTime;
                float2 exponent = float2(cos(phase), sin(phase));
                float2 h = complexMultiply(h0, exponent)
                    + complexMultiply(h0Conjugate, float2(exponent.x, -exponent.y));
                float2 ih = float2(-h.y, h.x);

                float2 displacementX = ih * k.x * inverseWaveNumber;
                float2 displacementY = h;
                float2 displacementZ = ih * k.y * inverseWaveNumber;
                float2 displacementXDX = -h * k.x * k.x * inverseWaveNumber;
                float2 displacementYDX = ih * k.x;
                float2 displacementZDX = -h * k.x * k.y * inverseWaveNumber;
                float2 displacementYDZ = ih * k.y;
                float2 displacementZDZ = -h * k.y * k.y * inverseWaveNumber;

                float2 packedDisplacementA = float2(
                    displacementX.x - displacementZ.y,
                    displacementX.y + displacementZ.x
                );
                float2 packedDisplacementB = float2(
                    displacementY.x - displacementZDX.y,
                    displacementY.y + displacementZDX.x
                );
                float2 packedSlopeA = float2(
                    displacementYDX.x - displacementYDZ.y,
                    displacementYDX.y + displacementYDZ.x
                );
                float2 packedSlopeB = float2(
                    displacementXDX.x - displacementZDZ.y,
                    displacementXDX.y + displacementZDZ.x
                );

                spectrum.write(
                    float4(packedDisplacementA, packedDisplacementB),
                    position,
                    cascade * 2
                );
                spectrum.write(
                    float4(packedSlopeA, packedSlopeB),
                    position,
                    cascade * 2 + 1
                );
            }
        }

        float4 evolvedSpectrumValue(
            texture2d_array<float, access::read> initialSpectrum,
            uint2 position,
            uint cascade,
            bool slopeValue,
            constant OceanUniforms &uniforms
        ) {
            float halfResolution = float(uniforms.resolution) * 0.5f;
            float2 centered = float2(position) - halfResolution;
            float4 initial = initialSpectrum.read(position, cascade);
            float2 h0 = initial.xy;
            float2 h0Conjugate = initial.zw;
            float2 k = centered * (2.0f * PI / uniforms.lengthScales[cascade]);
            float waveNumber = length(k);
            float inverseWaveNumber = waveNumber < 0.0001f ? 1.0f : 1.0f / waveNumber;
            float baseFrequency = 2.0f * PI / uniforms.repeatTime;
            float quantizedOmega = round(
                dispersion(waveNumber, uniforms) / baseFrequency
            ) * baseFrequency;
            float phase = quantizedOmega * uniforms.frameTime;
            float2 exponent = float2(cos(phase), sin(phase));
            float2 h = complexMultiply(h0, exponent)
                + complexMultiply(h0Conjugate, float2(exponent.x, -exponent.y));
            float2 ih = float2(-h.y, h.x);

            float2 displacementX = ih * k.x * inverseWaveNumber;
            float2 displacementY = h;
            float2 displacementZ = ih * k.y * inverseWaveNumber;
            float2 displacementXDX = -h * k.x * k.x * inverseWaveNumber;
            float2 displacementYDX = ih * k.x;
            float2 displacementZDX = -h * k.x * k.y * inverseWaveNumber;
            float2 displacementYDZ = ih * k.y;
            float2 displacementZDZ = -h * k.y * k.y * inverseWaveNumber;

            float2 packedDisplacementA = float2(
                displacementX.x - displacementZ.y,
                displacementX.y + displacementZ.x
            );
            float2 packedDisplacementB = float2(
                displacementY.x - displacementZDX.y,
                displacementY.y + displacementZDX.x
            );
            float2 packedSlopeA = float2(
                displacementYDX.x - displacementYDZ.y,
                displacementYDX.y + displacementYDZ.x
            );
            float2 packedSlopeB = float2(
                displacementXDX.x - displacementZDZ.y,
                displacementXDX.y + displacementZDZ.x
            );
            return slopeValue
                ? float4(packedSlopeA, packedSlopeB)
                : float4(packedDisplacementA, packedDisplacementB);
        }

        void butterflyValues(
            uint step,
            uint index,
            thread uint2 &indices,
            thread float2 &twiddle
        ) {
            uint span = FFT_SIZE >> (step + 1u);
            uint group = span * (index / span);
            uint first = (group + index) % FFT_SIZE;
            float angle = 2.0f * PI / float(FFT_SIZE) * float(group);
            twiddle = float2(cos(angle), sin(angle));
            indices = uint2(first, first + span);
        }

        // ROUND20_IFFT_THREADS_512
        void inverseFFTPair(
            uint threadIndex,
            float4 lowerInput,
            float4 upperInput,
            threadgroup float4 buffer[FFT_SIZE],
            thread float4 &lowerOutput,
            thread float4 &upperOutput
        ) {
            constexpr uint HALF_FFT_SIZE = FFT_SIZE / 2u;
            buffer[threadIndex] = lowerInput;
            buffer[threadIndex + HALF_FFT_SIZE] = upperInput;
            threadgroup_barrier(mem_flags::mem_threadgroup);

            for (uint step = 0; step < LOG_SIZE; ++step) {
                uint2 lowerIndices;
                uint2 upperIndices;
                float2 lowerTwiddle;
                float2 upperTwiddle;
                butterflyValues(
                    step,
                    threadIndex,
                    lowerIndices,
                    lowerTwiddle
                );
                butterflyValues(
                    step,
                    threadIndex + HALF_FFT_SIZE,
                    upperIndices,
                    upperTwiddle
                );
                float4 lowerFirst = buffer[lowerIndices.x];
                float4 lowerSecond = buffer[lowerIndices.y];
                float4 upperFirst = buffer[upperIndices.x];
                float4 upperSecond = buffer[upperIndices.y];
                threadgroup_barrier(mem_flags::mem_threadgroup);
                buffer[threadIndex] = lowerFirst + float4(
                    complexMultiply(lowerTwiddle, lowerSecond.xy),
                    complexMultiply(lowerTwiddle, lowerSecond.zw)
                );
                buffer[threadIndex + HALF_FFT_SIZE] = upperFirst + float4(
                    complexMultiply(upperTwiddle, upperSecond.xy),
                    complexMultiply(upperTwiddle, upperSecond.zw)
                );
                threadgroup_barrier(mem_flags::mem_threadgroup);
            }

            lowerOutput = buffer[threadIndex];
            upperOutput = buffer[threadIndex + HALF_FFT_SIZE];
        }

        kernel void horizontalIFFT(
            texture2d_array<float, access::read_write> spectrum [[texture(0)]],
            constant OceanUniforms &uniforms [[buffer(0)]],
            uint2 position [[thread_position_in_grid]],
            uint threadIndex [[thread_index_in_threadgroup]]
        ) {
            constexpr uint HALF_FFT_SIZE = FFT_SIZE / 2u;
            threadgroup float4 buffer[FFT_SIZE];
            uint2 upperPosition = position + uint2(HALF_FFT_SIZE, 0u);
            uint activeSliceCount = uniforms.activeCascadeCount * 2u;
            for (uint slice = 0; slice < activeSliceCount; ++slice) {
                float4 lowerOutput;
                float4 upperOutput;
                inverseFFTPair(
                    threadIndex,
                    spectrum.read(position, slice),
                    spectrum.read(upperPosition, slice),
                    buffer,
                    lowerOutput,
                    upperOutput
                );
                spectrum.write(lowerOutput, position, slice);
                spectrum.write(upperOutput, upperPosition, slice);
            }
        }

        kernel void horizontalIFFTEvolving(
            texture2d_array<float, access::read> initialSpectrum [[texture(0)]],
            texture2d_array<float, access::read_write> spectrum [[texture(1)]],
            constant OceanUniforms &uniforms [[buffer(0)]],
            uint2 position [[thread_position_in_grid]],
            uint threadIndex [[thread_index_in_threadgroup]]
        ) {
            constexpr uint HALF_FFT_SIZE = FFT_SIZE / 2u;
            threadgroup float4 buffer[FFT_SIZE];
            uint2 upperPosition = position + uint2(HALF_FFT_SIZE, 0u);
            uint activeSliceCount = uniforms.activeCascadeCount * 2u;
            for (uint slice = 0; slice < activeSliceCount; ++slice) {
                uint cascade = slice / 2u;
                bool slopeValue = (slice & 1u) != 0u;
                float4 lowerInput = float4(half4(evolvedSpectrumValue(
                    initialSpectrum,
                    position,
                    cascade,
                    slopeValue,
                    uniforms
                )));
                float4 upperInput = float4(half4(evolvedSpectrumValue(
                    initialSpectrum,
                    upperPosition,
                    cascade,
                    slopeValue,
                    uniforms
                )));
                float4 lowerOutput;
                float4 upperOutput;
                inverseFFTPair(
                    threadIndex,
                    lowerInput,
                    upperInput,
                    buffer,
                    lowerOutput,
                    upperOutput
                );
                spectrum.write(lowerOutput, position, slice);
                spectrum.write(upperOutput, upperPosition, slice);
            }
        }

        kernel void verticalIFFT(
            texture2d_array<float, access::read_write> spectrum [[texture(0)]],
            constant OceanUniforms &uniforms [[buffer(0)]],
            uint2 position [[thread_position_in_grid]],
            uint threadIndex [[thread_index_in_threadgroup]]
        ) {
            constexpr uint HALF_FFT_SIZE = FFT_SIZE / 2u;
            threadgroup float4 buffer[FFT_SIZE];
            uint2 lowerPosition = position.yx;
            uint2 upperPosition = lowerPosition + uint2(0u, HALF_FFT_SIZE);
            uint activeSliceCount = uniforms.activeCascadeCount * 2u;
            for (uint slice = 0; slice < activeSliceCount; ++slice) {
                float4 lowerOutput;
                float4 upperOutput;
                inverseFFTPair(
                    threadIndex,
                    spectrum.read(lowerPosition, slice),
                    spectrum.read(upperPosition, slice),
                    buffer,
                    lowerOutput,
                    upperOutput
                );
                spectrum.write(lowerOutput, lowerPosition, slice);
                spectrum.write(upperOutput, upperPosition, slice);
            }
        }

        float checkerboardSign(uint2 position) {
            return ((position.x + position.y) & 1u) == 0u ? 1.0f : -1.0f;
        }

        kernel void clearOutputs(
            texture2d_array<float, access::write> displacement [[texture(0)]],
            texture2d_array<float, access::write> slope [[texture(1)]],
            uint2 position [[thread_position_in_grid]]
        ) {
            if (position.x >= FFT_SIZE || position.y >= FFT_SIZE) {
                return;
            }
            for (uint cascade = 0; cascade < CASCADE_COUNT; ++cascade) {
                displacement.write(0.0f, position, cascade);
                slope.write(0.0f, position, cascade);
            }
        }

        kernel void assembleTextures(
            texture2d_array<float, access::read> spectrum [[texture(0)]],
            texture2d_array<float, access::read> previousDisplacement [[texture(1)]],
            texture2d_array<float, access::read> previousSlope [[texture(2)]],
            texture2d_array<float, access::write> displacement [[texture(3)]],
            texture2d_array<float, access::write> slope [[texture(4)]],
            constant OceanUniforms &uniforms [[buffer(0)]],
            constant uint &resetsFoam [[buffer(1)]],
            uint2 position [[thread_position_in_grid]]
        ) {
            if (position.x >= uniforms.resolution || position.y >= uniforms.resolution) {
                return;
            }

            float sign = checkerboardSign(position);
            float normalization = uniforms.inverseFFTScale * sign;
            for (uint cascade = 0; cascade < CASCADE_COUNT; ++cascade) {
                if (cascade >= uniforms.activeCascadeCount) {
                    displacement.write(
                        previousDisplacement.read(position, cascade),
                        position,
                        cascade
                    );
                    slope.write(
                        previousSlope.read(position, cascade),
                        position,
                        cascade
                    );
                    continue;
                }
                float4 packedDisplacement = spectrum.read(position, cascade * 2)
                    * normalization;
                float4 packedSlope = spectrum.read(position, cascade * 2 + 1)
                    * normalization;

                float2 dxDz = packedDisplacement.xy;
                float2 dyCross = packedDisplacement.zw;
                float2 heightSlope = packedSlope.xy;
                float2 horizontalDerivative = packedSlope.zw;

                float3 finalDisplacement = float3(
                    dxDz.x * uniforms.choppiness,
                    dyCross.x,
                    dxDz.y * uniforms.choppiness
                );
                // The reference divides by the signed horizontal jacobian factor,
                // which drops below one where the surface folds forward and is what
                // sharpens a choppy crest. Taking the magnitude instead can only
                // flatten. Keep the sign, floor the magnitude so a fold cannot send
                // one texel to a several-hundred slope spike.
                float2 jacobianFactor = 1.0f
                    + horizontalDerivative * uniforms.choppiness;
                float2 finalSlope = heightSlope
                    / copysign(max(abs(jacobianFactor), 0.1f), jacobianFactor);
                float jacobian = (
                    1.0f + uniforms.choppiness * horizontalDerivative.x
                ) * (
                    1.0f + uniforms.choppiness * horizontalDerivative.y
                ) - uniforms.choppiness * uniforms.choppiness
                    * dyCross.y * dyCross.y;
                float foamDeltaTime = cascade < 2u
                    ? uniforms.deltaTime
                    : uniforms.detailDeltaTime;
                float previousFold = resetsFoam != 0u
                    ? 0.0f
                    : previousDisplacement.read(position, cascade).a;
                float fold = max(0.0f, 1.0f - jacobian);
                fold = max(fold, previousFold - uniforms.foamDecay * foamDeltaTime);

                displacement.write(
                    float4(finalDisplacement, fold),
                    position,
                    cascade
                );
                slope.write(float4(finalSlope, 0.0f, 0.0f), position, cascade);
            }
        }

        void assembleFieldValue(
            float4 packedDisplacement,
            float4 packedSlope,
            texture2d_array<float, access::read> previousDisplacement,
            uint2 position,
            uint cascade,
            uint resetsFoam,
            constant OceanUniforms &uniforms,
            thread float4 &displacementValue,
            thread float2 &slopeValue
        ) {
            float sign = checkerboardSign(position);
            float normalization = uniforms.inverseFFTScale * sign;
            packedDisplacement *= normalization;
            packedSlope *= normalization;

            float2 dxDz = packedDisplacement.xy;
            float2 dyCross = packedDisplacement.zw;
            float2 heightSlope = packedSlope.xy;
            float2 horizontalDerivative = packedSlope.zw;
            float3 finalDisplacement = float3(
                dxDz.x * uniforms.choppiness,
                dyCross.x,
                dxDz.y * uniforms.choppiness
            );
            // The reference divides by the signed horizontal jacobian factor,
            // which drops below one where the surface folds forward and is what
            // sharpens a choppy crest. Taking the magnitude instead can only
            // flatten. Keep the sign, floor the magnitude so a fold cannot send
            // one texel to a several-hundred slope spike.
            float2 jacobianFactor = 1.0f
                + horizontalDerivative * uniforms.choppiness;
            float2 finalSlope = heightSlope
                / copysign(max(abs(jacobianFactor), 0.1f), jacobianFactor);
            float jacobian = (
                1.0f + uniforms.choppiness * horizontalDerivative.x
            ) * (
                1.0f + uniforms.choppiness * horizontalDerivative.y
            ) - uniforms.choppiness * uniforms.choppiness
                * dyCross.y * dyCross.y;
            float foamDeltaTime = cascade < 2u
                ? uniforms.deltaTime
                : uniforms.detailDeltaTime;
            float previousFold = resetsFoam != 0u
                ? 0.0f
                : previousDisplacement.read(position, cascade).a;
            float fold = max(0.0f, 1.0f - jacobian);
            fold = max(fold, previousFold - uniforms.foamDecay * foamDeltaTime);
            displacementValue = float4(finalDisplacement, fold);
            slopeValue = finalSlope;
        }

        kernel void verticalIFFTAssembling(
            texture2d_array<float, access::read> spectrum [[texture(0)]],
            texture2d_array<float, access::read> previousDisplacement [[texture(1)]],
            texture2d_array<float, access::read> previousSlope [[texture(2)]],
            texture2d_array<float, access::write> displacement [[texture(3)]],
            texture2d_array<float, access::write> slope [[texture(4)]],
            constant OceanUniforms &uniforms [[buffer(0)]],
            constant uint &resetsFoam [[buffer(1)]],
            uint2 position [[thread_position_in_grid]],
            uint threadIndex [[thread_index_in_threadgroup]]
        ) {
            constexpr uint HALF_FFT_SIZE = FFT_SIZE / 2u;
            threadgroup float4 buffer[FFT_SIZE];
            uint2 lowerPosition = position.yx;
            uint2 upperPosition = lowerPosition + uint2(0u, HALF_FFT_SIZE);
            for (uint cascade = 0; cascade < CASCADE_COUNT; ++cascade) {
                if (cascade >= uniforms.activeCascadeCount) {
                    displacement.write(
                        previousDisplacement.read(lowerPosition, cascade),
                        lowerPosition,
                        cascade
                    );
                    displacement.write(
                        previousDisplacement.read(upperPosition, cascade),
                        upperPosition,
                        cascade
                    );
                    slope.write(
                        previousSlope.read(lowerPosition, cascade),
                        lowerPosition,
                        cascade
                    );
                    slope.write(
                        previousSlope.read(upperPosition, cascade),
                        upperPosition,
                        cascade
                    );
                    continue;
                }

                float4 lowerPackedDisplacement;
                float4 upperPackedDisplacement;
                inverseFFTPair(
                    threadIndex,
                    spectrum.read(lowerPosition, cascade * 2u),
                    spectrum.read(upperPosition, cascade * 2u),
                    buffer,
                    lowerPackedDisplacement,
                    upperPackedDisplacement
                );
                lowerPackedDisplacement = float4(half4(lowerPackedDisplacement));
                upperPackedDisplacement = float4(half4(upperPackedDisplacement));

                float4 lowerPackedSlope;
                float4 upperPackedSlope;
                inverseFFTPair(
                    threadIndex,
                    spectrum.read(lowerPosition, cascade * 2u + 1u),
                    spectrum.read(upperPosition, cascade * 2u + 1u),
                    buffer,
                    lowerPackedSlope,
                    upperPackedSlope
                );
                lowerPackedSlope = float4(half4(lowerPackedSlope));
                upperPackedSlope = float4(half4(upperPackedSlope));

                float4 lowerDisplacement;
                float2 lowerSlope;
                assembleFieldValue(
                    lowerPackedDisplacement,
                    lowerPackedSlope,
                    previousDisplacement,
                    lowerPosition,
                    cascade,
                    resetsFoam,
                    uniforms,
                    lowerDisplacement,
                    lowerSlope
                );
                float4 upperDisplacement;
                float2 upperSlope;
                assembleFieldValue(
                    upperPackedDisplacement,
                    upperPackedSlope,
                    previousDisplacement,
                    upperPosition,
                    cascade,
                    resetsFoam,
                    uniforms,
                    upperDisplacement,
                    upperSlope
                );
                displacement.write(lowerDisplacement, lowerPosition, cascade);
                displacement.write(upperDisplacement, upperPosition, cascade);
                slope.write(float4(lowerSlope, 0.0f, 0.0f), lowerPosition, cascade);
                slope.write(float4(upperSlope, 0.0f, 0.0f), upperPosition, cascade);
            }
        }

        constexpr sampler oceanSampler(
            coord::normalized,
            address::repeat,
            filter::linear
        );

        float3 sampleDisplacement(
            float2 worldXZ,
            texture2d_array<float, access::sample> displacement,
            constant SurfaceUniforms &uniforms
        ) {
            float3 result = 0.0f;
            for (uint cascade = 0; cascade < CASCADE_COUNT; ++cascade) {
                float2 uv = fract(worldXZ / uniforms.lengthScales[cascade]);
                result += displacement.sample(oceanSampler, uv, cascade).xyz;
            }
            return result;
        }

        kernel void projectSurface(
            texture2d_array<float, access::sample> displacement [[texture(0)]],
            device OceanVertex *vertices [[buffer(0)]],
            constant SurfaceUniforms &uniforms [[buffer(1)]],
            const device OceanVertex *gridVertices [[buffer(2)]],
            uint vertexIndex [[thread_position_in_grid]]
        ) {
            if (vertexIndex >= uniforms.vertexCount) {
                return;
            }

            float2 baseXZ = gridVertices[vertexIndex].baseXZ;
            float3 fieldDisplacement = sampleDisplacement(
                baseXZ, displacement, uniforms
            );
            if (gridVertices[vertexIndex].stitch.z > 0.5f) {
                float2 stitchOffset = gridVertices[vertexIndex].stitch.xy;
                float3 previousDisplacement = sampleDisplacement(
                    baseXZ - stitchOffset, displacement, uniforms
                );
                float3 nextDisplacement = sampleDisplacement(
                    baseXZ + stitchOffset, displacement, uniforms
                );
                fieldDisplacement = (previousDisplacement + nextDisplacement)
                    * 0.5f;
            }
            fieldDisplacement *= oceanEnvelope(
                baseXZ,
                uniforms.envelopeAmount,
                uniforms.envelopeScaleMeters
            );

            float horizonFade = 1.0f - smoothstep(
                4096.0f,
                6144.0f,
                max(abs(baseXZ.x), abs(baseXZ.y))
            );
            float displacementScale = uniforms.amplitude * horizonFade;
            OceanVertex outputVertex;
            outputVertex.position = float3(baseXZ.x, 0.0f, baseXZ.y)
                + fieldDisplacement * displacementScale;
            outputVertex.normal = float3(0.0f, 1.0f, 0.0f);
            outputVertex.tangent = float4(1.0f, 0.0f, 0.0f, 1.0f);
            outputVertex.uv = baseXZ;
            outputVertex.baseXZ = baseXZ;
            outputVertex.stitch = gridVertices[vertexIndex].stitch;
            vertices[vertexIndex] = outputVertex;
        }

        kernel void publishSurfaceFields(
            texture2d_array<float, access::read> slope [[texture(0)]],
            texture2d_array<float, access::read> displacement [[texture(1)]],
            texture2d<float, access::write> cascade0 [[texture(2)]],
            texture2d<float, access::write> cascade1 [[texture(3)]],
            texture2d<float, access::write> cascade2 [[texture(4)]],
            texture2d<float, access::write> cascade3 [[texture(5)]],
            constant SurfacePublicationUniforms &uniforms [[buffer(0)]],
            uint2 position [[thread_position_in_grid]]
        ) {
            if (position.x >= uniforms.resolution
                || position.y >= uniforms.resolution) {
                return;
            }
            uint2 sourcePosition = uint2(
                position.x,
                uniforms.resolution - 1u - position.y
            );
            cascade0.write(float4(
                slope.read(sourcePosition, 0).xy * uniforms.amplitude,
                displacement.read(sourcePosition, 0).a,
                length(displacement.read(sourcePosition, 0).xz)
            ), position);
            cascade1.write(float4(
                slope.read(sourcePosition, 1).xy * uniforms.amplitude,
                displacement.read(sourcePosition, 1).a,
                length(displacement.read(sourcePosition, 1).xz)
            ), position);
            cascade2.write(float4(
                slope.read(sourcePosition, 2).xy * uniforms.amplitude,
                displacement.read(sourcePosition, 2).a,
                length(displacement.read(sourcePosition, 2).xz)
            ), position);
            cascade3.write(float4(
                slope.read(sourcePosition, 3).xy * uniforms.amplitude,
                displacement.read(sourcePosition, 3).a,
                length(displacement.read(sourcePosition, 3).xz)
            ), position);
        }

        kernel void publishPrimarySurfaceFields(
            texture2d_array<float, access::read> slope [[texture(0)]],
            texture2d_array<float, access::read> displacement [[texture(1)]],
            texture2d<float, access::write> cascade0 [[texture(2)]],
            texture2d<float, access::write> cascade1 [[texture(3)]],
            constant SurfacePublicationUniforms &uniforms [[buffer(0)]],
            uint2 position [[thread_position_in_grid]]
        ) {
            if (position.x >= uniforms.resolution
                || position.y >= uniforms.resolution) {
                return;
            }
            uint2 sourcePosition = uint2(
                position.x,
                uniforms.resolution - 1u - position.y
            );
            cascade0.write(float4(
                slope.read(sourcePosition, 0).xy * uniforms.amplitude,
                displacement.read(sourcePosition, 0).a,
                length(displacement.read(sourcePosition, 0).xz)
            ), position);
            cascade1.write(float4(
                slope.read(sourcePosition, 1).xy * uniforms.amplitude,
                displacement.read(sourcePosition, 1).a,
                length(displacement.read(sourcePosition, 1).xz)
            ), position);
        }

        """#
    }
}
