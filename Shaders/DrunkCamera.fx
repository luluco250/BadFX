//#region Includes

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

//#endregion

//#region Uniforms

uniform float Speed
<
	__UNIFORM_DRAG_FLOAT1

	ui_tooltip = "Default: 1.0";
	ui_min = 0.0;
	ui_max = 3.0;
	ui_step = 0.01;
> = 1.0;

uniform float Timer <source = "timer";>;

//#endregion

//#region Functions

float2 scale_uv(float2 uv, float2 scale, float2 pivot)
{
	return (uv - pivot) * scale + pivot;
}

float2 rotate_uv(float2 uv, float angle, float2 pivot)
{
	float s, c;
	sincos(angle, s, c);

	uv = mul(float2x2(c, s, -s, c), uv - pivot) + pivot;

	return uv;
}

//#endregion

//#region Shaders

float4 MainPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	float2 uv_org = uv;
	float time = Timer * 0.001 * Speed;

	float2 dir;
	dir.x = (sin(time) + sin(time * -0.8) + sin(time * 1.7)) * 0.333;
	dir.y = (sin(-time) + sin(time * 1.3) + sin(time * -0.4)) * 0.333;
	dir = pow(abs(dir), 2.5) * sign(dir);

	float whiteout = length(dir);
	whiteout += 0.9;
	whiteout = whiteout * whiteout;

	dir *= ReShade::PixelSize * 30.0;

	float4 zoom = float4(0.5, 0.5, 1.0, 1.0);
	zoom.x = (sin(time * 0.2) + sin(time * -1.1)) * 0.5;
	zoom.y = (sin(time * -0.1) + sin(time * 0.6)) * 0.5;
	zoom.xy = zoom.xy * 0.5 + 0.5;
	zoom.zw = (sin(time * 1.3) + sin(time * -0.3) + sin(time * 0.4)) * 0.333;
	zoom.zw = 0.8 - lerp(0.0, zoom.zw, 0.2);

	uv = scale_uv(uv, zoom.zw, zoom.xy);

	float rotation =
		(sin(time * 0.3) + sin(time * -0.45) + sin(time * 1.5)) * 0.333;
	rotation = lerp(0.0, rotation, 0.1);
	rotation *= pow(length(zoom.zw), 3.0);

	uv *= ReShade::ScreenSize;
	uv = rotate_uv(uv, rotation, ReShade::ScreenSize * 0.5);
	uv *= ReShade::PixelSize;

	float2 ar = 1.0;
	#if BUFFER_WIDTH > BUFFER_HEIGHT
		ar.y = BUFFER_HEIGHT * BUFFER_RCP_WIDTH;
	#else
		ar.x = ReShade::AspectRatio;
	#endif

	float distort = distance(scale_uv(uv, ar, 0.5), 0.5);
	distort = lerp(1.0, distort, 0.75);
	//distort = smoothstep(0.1, 0.2, distort);
	uv = scale_uv(uv, distort * 3.0, 0.5);

	float2 uv1 = uv + dir;
	float2 uv2 = uv - dir;

	float4 color =
		tex2D(ReShade::BackBuffer, uv1) + tex2D(ReShade::BackBuffer, uv2);
	color *= 0.5 * whiteout;

	float vignette = 1.0 - distance(uv, 0.5);
	vignette = smoothstep(0.4, 0.7, vignette);
	vignette = min(vignette, smoothstep(0.3, 0.8, 1.0 - distance(uv_org, 0.5)));

	color *= vignette;

	//color = max(color, color * whiteout);

	return color;
}

//#endregion

//#region Technique

technique DrunkCamera
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = MainPS;
	}
}

//#endregion