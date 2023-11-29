Shader "Unlit/DisplacementTexture"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Transparency("Transparency", Range(0.0, 1.0)) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "IgnoreProjector"="True" "Queue"="Transparent" }
        LOD 100

        //Disables depth writing
        ZWrite Off
        //Enables alpha blending
        Blend SrcAlpha OneMinusSrcAlpha
        //Culls back-facing triangles
        Cull Back

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            //input data
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            //vertex to gragment
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float rotation : TEXCOORD1;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float _Transparency;

            float2 rotate(float2 UV, float2 Center, float Rotation)
            {
                //Translate uv coords to origin
                UV -= Center;
                //Compute sin and cos of rotation angle
                float s = sin(Rotation);
                float c = cos(Rotation);
                //Create rot matrix
                float2x2 rMatrix = float2x2(c, -s, s, c);
                //Scale and shift matrix
                rMatrix *= 0.5;
                rMatrix += 0.5;
                rMatrix = rMatrix * 2 - 1;
                //Apply rotation
                UV.xy = mul(UV.xy, rMatrix);
                //Translate back to world space
                UV += Center;
                return UV;
            }


            v2f vert (appdata v)
            {
                v2f o;
                //Transform from object space to clip space
                o.vertex = UnityObjectToClipPos(v.vertex);
                //Transform uv coords
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                //Get dir vector for right dir (1,0,0)
                float3 x = mul(unity_ObjectToWorld, float3(1, 0, 0));
                //Calculate rotation angle
                o.rotation = atan2(x.x, x.z) - 1.57079633; //pi/2
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                //fixed4 rgba
                //Get original color
                fixed4 ogCol = tex2D(_MainTex, rotate(i.uv, float2(0.5, 0.5), i.rotation));
                //Create new tex
                fixed4 col = fixed4(ogCol.rgb, lerp(0, ogCol.a, 1 - _Transparency));
                return col;
            }
            ENDCG
        }
    }
}
