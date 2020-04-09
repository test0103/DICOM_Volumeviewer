Shader "Ray Marching/Volume"
{
	Properties
	{
		_Color ("Color", Color) = (1, 1, 1, 1)
		[HideInInspector] _Volume ("Volume", 3D) = "" {}
		[NoScaleOffset] _TFTex("Transfer Function Texture (Generated)", 2D) = "" {}
		_Intensity ("Intensity", Range(1.0, 5.0)) = 1.3
		_Threshold ("Render Threshold", Range(0,1)) = 0.5
		_RaySteps ("Raycasting Steps", Range(1,1000)) = 64
		_WinWidth("Window Width", Range(1, 2500)) = 500
		_WinCenter("Window Center", Range(-200, 2000)) = 120
		[HideInInspector]_HoundLow ("Lower Houndsfield", Float) = 50
		[HideInInspector]_HoundMax ("Upper Houndsfield", Float) = 500
		_SliceMin ("Slice min", Vector) = (0.0, 0.0, 0.0, -1.0)
		_SliceMax ("Slice max", Vector) = (1.0, 1.0, 1.0, -1.0)		
		_IntMove("Intensity Movement",Range(-2000,2000)) = 0
		_LightDir ("Light Direction", Vector) = (0.0, 0.0, 0.0, 1.0)
		_IsoMin("Min Isovalue", Range(0,1)) = 0.2
		_IsoMax("Max Isovalue", Range(0,1)) = 0.8
		_Direction("Render Direction",Range(0,1)) = 0.0
	}
	
	SubShader
	{
		Blend SrcAlpha OneMinusSrcAlpha
		Cull Front
		ZWrite Off
		Fog { Mode off }
		Tags { "Queue" = "Transparent" "RenderType" = "Transparent" }
		Pass
		{
			CGPROGRAM
			#include "UnityCG.cginc"
			#include "Lighting.cginc"
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 3.0
			#pragma multi_compile MODE_DVR MODE_MIP MODE_SURF
			#pragma multi_compile LIGHT_ON LIGHT_OFF
			#pragma enable_d3d11_debug_symbols
			half4 _Color;
			float _RaySteps;
			sampler3D _Volume;
			sampler2D _TFTex;
			float _RenderMode, _WinWidth, _WinCenter, _IntMove, _Intensity, _Threshold, _HoundLow, _HoundMax, _IsoMin, _IsoMax,_Direction;
			half3 _SliceMin, _SliceMax,_LightDir;
		    float _MinVal;
            float _MaxVal;

			float4 getTF1DColour(float density) {
				return tex2Dlod(_TFTex, float4(density, 0.0f, 0.0f, 0.0f));
			}

			float map(float value, float fromLow, float fromHigh, float toLow, float toHigh) {
				return ((value - fromLow) / (fromHigh - fromLow)) * (toHigh - toLow) + toLow;
			}

			float getWindow(float intens) {
				float yMin = _HoundLow;
				float yMax = _HoundMax;
				float targetInt = 0;
				//intens=intens * yMax;
				if (intens <= _WinCenter - 0.5 - (_WinWidth - 1) / 2) {
					targetInt = yMin;
				}
				else if (intens > _WinCenter - 0.5 + (_WinWidth - 1) / 2) {
					targetInt = yMax;
				}
				else {
					targetInt = (float)((((intens - (_WinCenter - 0.5f)) / (_WinWidth - 1) + 0.5f)) * ((yMax - yMin) + yMin));
				}
				//return targetInt;
				return map(targetInt, yMin, yMax, 0.0f, 1.0f);
			}

			float get_data(float3 pos) {
				float alpha = 1.0f;
				float4 data4 = tex3Dlod(_Volume, float4(pos, 0));
				float voxel = data4.r; // [0-1]
				float fl2h = map(voxel, 0.0f, 1.0f, _HoundLow, _HoundMax); //[-1024-- 2048]
				fl2h = fl2h + _IntMove;
				fl2h = getWindow(fl2h);
				fl2h *= step(_SliceMin.x, pos.x);
				fl2h *= step(pos.x,_SliceMax.x);
				fl2h *= step(_SliceMin.y, pos.y);
				fl2h *= step(pos.y, _SliceMax.y);
				fl2h *= step(_SliceMin.z, pos.z);
				fl2h *= step(pos.z, _SliceMax.z);
				return fl2h; // [0-300]
			}



			struct appdata {
			  float4 vertex : POSITION;
			  float4 normal : NORMAL;
			  float2 uv : TEXCOORD0;
			};

			struct v2f {
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;
                float3 vertexLocal : TEXCOORD1;
                float3 normal : NORMAL;
			};

			v2f vert(appdata v) {
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                o.vertexLocal = v.vertex;
				o.normal = UnityObjectToWorldNormal(v.normal);
				return o;
			}

			float4 frag(v2f i) : SV_Target {
				const float stepSize = 1.732f/*greatest distance in box*/ / _RaySteps;
				float4 ray_col = float4(i.vertexLocal.x, i.vertexLocal.y, i.vertexLocal.z, 1.0f);
				float3 rayStartPos = i.vertexLocal + float3(0.5f, 0.5f, 0.5f);
                float3 rayDir = ObjSpaceViewDir(float4(i.vertexLocal, 0.0f));
                rayDir = normalize(rayDir);
				rayStartPos = rayStartPos + (2.0f * rayDir / _RaySteps);

				ray_col = float4(0.0f, 0.0f, 0.0f, 0.0f);
				float maxDens = 0.0f;
				float3 lightDirection = normalize(_LightDir);
				for (int k = 0; k < _RaySteps; k++) {
					const float t = k * stepSize;
                    const float3 currPos = rayStartPos + rayDir * t;
					
					
					float voxel_dens = get_data(currPos);
					float4 voxel_col = getTF1DColour(voxel_dens);
					if (voxel_dens <= _Threshold) {
						voxel_col.a = 0.0f;
					}
					//////////////////////////////////// Conditional-Compiling wird verwendet
					#if MODE_MIP 
						if (voxel_dens > maxDens) {
							maxDens = voxel_dens;
						}
					////////////////////////////////////
					#elif MODE_DVR
					ray_col.rgb =  ray_col.rgb + (1 - ray_col.a) * voxel_col.a * voxel_col.rgb;
					ray_col.a = ray_col.a  + (1 - ray_col.a) * voxel_col.a;
					////////////////////////////////////					
					#elif MODE_SURF
					
					#endif
					////////////////////////////////////
					
				}
				
				////////////////////////////////////
				#if MODE_MIP
					ray_col.rgb = _Color.rgb;
					ray_col.a = maxDens;
				////////////////////////////////////
				#elif MODE_DVR
				//	if(_Direction>0.5){
				//		ray_col = getTF1DColour(ray_col);
				//	}
				////////////////////////////////////
				#elif MODE_SURF
					ray_col.a = 1.0f;
				#endif
					
					ray_col *= _Intensity;
					ray_col = clamp(ray_col, 0, 1);
					
				return ray_col;
			}
			ENDCG
		}
	}
	FallBack Off
}