﻿Shader "Custom/GeometryGrassShader" {
    Properties {
        _TranslucentGain("Translucent Gain", Range(0,1)) = 0.5

        _GroundTexture ("Ground Texture", 2D) = "white" {}

        _DisplacementTexture("Displacement Texture", 2D) = "grey" {}
        _DisplacementFactor("Displacement Factor", Float) = 2

        _GrassMask("Grass Mask", 2D) = "white" {}
        _GrassMaskThreshold("Mask Threshold", Range(0,1)) = 0.1

        _BendRotationRandom("Bend Rotation Random", Range(0, 1)) = 0.2

        _BladeWidth("Blade Width", Float) = 0.05
        _BladeWidthRandom("Blade Width Random", Float) = 0.02

        _BladeHeight("Blade Height", Float) =0.5
        _BladeHeightRandom("Blade Height Random", Float) = 0.3

        _TessellationUniform("Tessellation Uniform", Range(1, 64)) = 1

        _WindDistortionMap("Wind Distortion Map", 2D) = "white" {}
        _WindFrequency("Wind Frequency", Vector) = (0.05, 0.05, 0, 0)
        _WindStrength("Wind Strength", Float) = 1

        _BladeForward("Blade Forward Amount", Float) = 0.38
        _BladeCurve("Blade Curvature Amount", Range(1, 4)) = 2
    }

    CGINCLUDE

    #include "UnityCG.cginc"
    #include "AutoLight.cginc"
    #include "CustomTessellation.cginc"
    
    #define BLADE_SEGMENTS 3

    struct geometryOutput
    {
        float4 pos : SV_POSITION;
        float4 uv : TEXCOORD0;
        
        float3 world : TEXCOORD1;
        float3 normal : NORMAL;

        UNITY_SHADOW_COORDS(5)

        #ifdef VERTEXLIGHT_ON
            float3 vertexLighting : TEXCOORD3;
        #endif
    };

    //pseudo rand
    float rand(float3 co)
    {
        return frac(sin( dot(co.xyz ,float3(12.9898,78.233,45.5432) )) * 43758.5453);
    }

    //Create 3x3 rot matrix around a specific axis by a given angle
    float3x3 AngleAxis3x3(float angle, float3 axis)
    {
        float c, s;
        sincos(angle, s, c);

        float t = 1 - c;
        float x = axis.x;
        float y = axis.y;
        float z = axis.z;

        return float3x3(
        t * x * x + c, t * x * y - s * z, t * x * z + s * y,
        t * x * y + s * z, t * y * y + c, t * y * z - s * x,
        t * x * z - s * y, t * y * z + s * x, t * z * z + c
        );
    }

    float _BendRotationRandom;

    float _BladeHeight;
    float _BladeHeightRandom;

    float _BladeWidth;
    float _BladeWidthRandom;

    sampler2D _WindDistortionMap;
    float4 _WindDistortionMap_ST;

    float2 _WindFrequency;
    float _WindStrength;

    float _BladeForward;
    float _BladeCurve;

    float _GrassMaskThreshold;

    sampler2D _GrassMask;

    sampler2D _DisplacementTexture;
    sampler2D _GroundTexture;

    float _DisplacementFactor;

    float3 _DisplacementLocation;
    float _DisplacementSize;

    float _TranslucentGain;

    geometryOutput VertexOutput(float3 pos, float4 uv, float3 normal, float3 world, float4 tangent)
    {
        geometryOutput o;

        // Transform the vertex position to clip space
        o.pos = UnityObjectToClipPos(pos);

        // Pass world position, UV coordinates, and transformed normal to output struct
        o.world = world;
        o.uv = uv;
        o.normal = UnityObjectToWorldNormal(normal);

        // Calculate screen coordinates for shadow mapping
        o._ShadowCoord = ComputeScreenPos(o.pos);

        // Transfer shadow coordinates
        UNITY_TRANSFER_SHADOW(o, o.uv);

        #if UNITY_PASS_SHADOWCASTER
            // Apply linear shadow bias
            o.pos = UnityApplyLinearShadowBias(o.pos);
        #endif

        #ifdef VERTEXLIGHT_ON
            o.vertexLighting = float3(0.0, 0.0, 0.0);
            for (int index = 0; index < 4; index++)
            {
                // Get light position 
                float4 lightPosition = float4(unity_4LightPosX0[index], unity_4LightPosY0[index], unity_4LightPosZ0[index], 1.0);
                // Calculate vector from vertex to light source
                float3 vertexToLightSource = lightPosition.xyz - o.world.xyz;

                // Normalize the light direction vector
                float3 lightDirection = normalize(vertexToLightSource);
                // Calculate squared distance from vertex to light source
                float squaredDistance = dot(vertexToLightSource, vertexToLightSource);

                // Calculate light attenuation
                float attenuation = 1.0 / (1.0 + unity_4LightAtten0[index] * squaredDistance);

                // Calculate diffuse reflection using attenuation, light color, normal, and light direction
                float3 diffuseReflection = attenuation 
                * unity_LightColor[index].rgb * max(0.0, dot(lerp(o.normal, -normalize(o.world.xyz - lightPosition.xyz), _TranslucentGain), lightDirection));

                // Accumulate diffuse reflections for all lights
                o.vertexLighting = o.vertexLighting + diffuseReflection;
            }
        #endif

        return o;
    }

    geometryOutput GenerateGrassVertex(float3 vertexPosition, float width, float height, float forward, float4 uv, float3x3 transformMatrix, float3 world, float4 tangent)
    {
        //Create tangent point
        float3 tangentPoint = float3(width, forward, height);
        //Create tangent normal pointing in -y (down)
        float3 tangentNormal = normalize(float3(0, -1, forward));
        //Transform tangent normal to local space
        float3 localNormal = mul(transformMatrix, tangentNormal);
        //Transform vertex position to local space
        float3 localPosition = vertexPosition + mul(transformMatrix, tangentPoint);

        return VertexOutput(localPosition, uv, localNormal, world, tangent);
    }

    [maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
    void geo(triangle vertexOutput IN[3] : SV_POSITION, inout TriangleStream<geometryOutput> triStream)
    {
        float3 pos = IN[0].vertex;

        //Calculate tangent and binormal vectors
        float3 vNormal = IN[0].normal;
        float4 vTangent = IN[0].tangent;
        float3 vBinormal = cross(vNormal, vTangent) * vTangent.w;

        //Construct a tangent-to-local space matrix
        float3x3 tangentToLocal = float3x3(
        vTangent.x, vBinormal.x, vNormal.x,
        vTangent.y, vBinormal.y, vNormal.y,
        vTangent.z, vBinormal.z, vNormal.z
        );

        // Calculate UV coordinates for wind distortion
        float2 uv = pos.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;

        // Sample wind distortion map and calculate wind vector
        float2 windSample = (tex2Dlod(_WindDistortionMap, float4(uv, 0, 0)).xy * 2 - 1) * _WindStrength;
        float3 wind = normalize(float3(windSample.x, windSample.y, 0));

        // Construct a rotation matrix for wind based on wind vector
        float3x3 windRotation = AngleAxis3x3(UNITY_PI * windSample, wind);

        // Calculate displacement location in world space
        float4 dispLocation = float4((IN[0].world.xz - _DisplacementLocation.xz) / _DisplacementSize, 0, 0);

        // Counteract the Clamp functionality of Unity for displacement map
        float2 dispMaskUv = max(saturate(dispLocation), saturate(1.0 - dispLocation));
        float dispMask = floor(max(dispMaskUv.x, dispMaskUv.y));

        // Sample and normalize displacement map
        float2 dispSample = lerp((tex2Dlod(_DisplacementTexture, dispLocation).xz - 0.5), float2(0.001, 0.001), dispMask);
        float3 displacement = normalize(float3(dispSample.x, dispSample.y, 0));

        // Construct a rotation matrix for displacement based on displacement vector
        float3x3 dispRotation = AngleAxis3x3(float2(-_DisplacementFactor * abs(dispSample.x + dispSample.y), 0), displacement);

        // Construct rotation matrices for facing and bending
        float3x3 facingRotationMatrix = AngleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1));
        float3x3 bendRotationMatrix = AngleAxis3x3(rand(pos.zzx) * _BendRotationRandom * UNITY_PI * 0.5, float3(-1, 0, 0));

        // Construct transformation matrices
        float3x3 transformationMatrix = mul(mul(mul(tangentToLocal, mul(windRotation, dispRotation)), facingRotationMatrix), bendRotationMatrix);
        float3x3 transformationMatrixFacing = mul(tangentToLocal, facingRotationMatrix);

        // Sample grass mask to determine visibility
        float mask = tex2Dlod(_GrassMask, float4(IN[0].uv, 0, 0)).x;

        // Calculate randomized height, width, and forward displacement
        float height = ((rand(pos.zyx) * 2 - 1) * _BladeHeightRandom + _BladeHeight) * mask;
        float width = ((rand(pos.xzy) * 2 - 1) * _BladeWidthRandom + _BladeWidth) * mask;
        float forward = rand(pos.yyz) * _BladeForward;

        // Determine the number of segments based on the grass mask
        int segments = mask > _GrassMaskThreshold ? BLADE_SEGMENTS : 0;

        // Generate grass vertices and append to the stream
        for(int i = 0; i < segments; i++)
        {
            float t = i / (float)BLADE_SEGMENTS;
            
            float segmentHeight = height * t;
            float segmentWidth = width * (1 - t);

            float segmentForward = pow(t, _BladeCurve) * forward;

             // Choose the appropriate transformation matrix for the segment
            float3x3 transformMatrix = i == 0 ? transformationMatrixFacing : transformationMatrix;

            // Append two vertices for each segment (for the blade)
            triStream.Append(GenerateGrassVertex(pos, segmentWidth, segmentHeight, segmentForward, float4(0, t, IN[0].uv), transformMatrix, IN[0].world, IN[0].tangent));
            triStream.Append(GenerateGrassVertex(pos, -segmentWidth, segmentHeight, segmentForward, float4(1, t, IN[0].uv), transformMatrix, IN[0].world, IN[0].tangent));
        }

        // Append a central vertex for the blade
        triStream.Append(GenerateGrassVertex(pos, 0, height, forward, float4(0.5, 1, IN[0].uv), transformationMatrix, IN[0].world, IN[0].tangent));
    }
    
    ENDCG

    SubShader {
        //Base rendering of the grass. It calculates lighting/shadows
        Pass {

            Tags
            {
                "LightMode" = "ForwardBase"
            }

            Cull Off

            CGPROGRAM

            #pragma hull hull
            #pragma domain domain

            #pragma multi_compile_fwdbase 
            #pragma multi_compile _ VERTEXLIGHT_ON

            #pragma target 4.6

            #pragma vertex vert
            #pragma geometry geo
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "AutoLight.cginc"
            #include "UnityLightingCommon.cginc"

            fixed4 frag(geometryOutput i, fixed facing : VFACE) : SV_Target 
            {
                // Calculate the normal based on facing direction
                float3 normal = facing > 0 ? i.normal : -i.normal;

                // Calculate shadow attenuation
                float shadow = SHADOW_ATTENUATION(i);

                // Calculate NdotL (dot product of normal and light direction)
                float NdotL = saturate(saturate(dot(normal, _WorldSpaceLightPos0)) + _TranslucentGain) * shadow;

                // Calculate ambient lighting using spherical harmonics
                float3 ambient = ShadeSH9(float4(normal, 1));
                // Calculate total light intensity
                float4 lightIntensity = NdotL * _LightColor0 + float4(ambient, 1) + 0.01;

                // Sample ground texture and apply lighting
                float4 col = tex2D(_GroundTexture, i.uv.zw);
                col *= lightIntensity;

                float3 ambientLight = UNITY_LIGHTMODEL_AMBIENT.rgb * col;

                #ifdef VERTEXLIGHT_ON
                // If vertex lighting is enabled, add it to the final color
                    return float4(i.vertexLighting + col.rgb, col.a);
                #else
                // Otherwise, return the final color without vertex lighting
                    return float4(col);
                #endif
            }

            ENDCG
        }

        Pass {
            Tags 
            {
                "LightMode" = "ForwardAdd"
            }

            Cull Off
            Blend One One

            CGPROGRAM

            #pragma multi_compile_fwdadd_fullshadows

            #pragma hull hull
            #pragma domain domain

            #pragma target 4.6

            #pragma vertex vert
            #pragma geometry geo
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            fixed4 frag(geometryOutput i, fixed facing: VFACE) : COLOR
            {
                // Calculate light attenuation for forward-add pass
                UNITY_LIGHT_ATTENUATION(attenuation, i, i.world.xyz);
                // Calculate diffuse reflection using light color and ground texture
                float3 diffuseReflection = attenuation * _LightColor0.rgb * tex2D(_GroundTexture, i.uv.zw);
                
                // Return the final color with the calculated diffuse reflection
                return float4(diffuseReflection, 1.0);
            }

            ENDCG
        }

        Pass
        {
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geo
            #pragma fragment frag

            #pragma hull hull
            #pragma domain domain

            #pragma multi_compile_shadowcaster 

            #pragma target 4.6

            float4 frag(geometryOutput i) : SV_Target
            {
                // Fragment shader for shadow caster pass
                SHADOW_CASTER_FRAGMENT(i)
            }

            ENDCG
        }
    }
}
