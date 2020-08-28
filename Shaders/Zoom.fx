//#region Preprocessor

#include "ReShade.fxh"
#include "BadFX/KeyCodes.fxh"

// Alt key.
#ifndef ZOOM_HOTKEY
#define ZOOM_HOTKEY VK_MENU
#endif

#ifndef ZOOM_USE_MOUSE_BUTTON
#define ZOOM_USE_MOUSE_BUTTON 0
#endif

#ifndef ZOOM_MOUSE_BUTTON
#define ZOOM_MOUSE_BUTTON 1
#endif

#ifndef ZOOM_TOGGLE
#define ZOOM_TOGGLE 0
#endif

#if ZOOM_TOGGLE < 0 || ZOOM_TOGGLE > 1
	#error "Invalid value for ZOOM_TOGGLE, it should be 0 for off or 1 for on"
#endif

#ifndef ZOOM_SMOOTH_ZOOM
#define ZOOM_SMOOTH_ZOOM 0
#endif

#if ZOOM_SMOOTH_ZOOM < 0 || ZOOM_SMOOTH_ZOOM > 1
	#error "Invalid value for ZOOM_SMOOTH_ZOOM, it should be 0 for off or 1 for on"
#endif

#ifndef ZOOM_USE_LINEAR_FILTERING
#define ZOOM_USE_LINEAR_FILTERING 1
#endif

#if ZOOM_USE_LINEAR_FILTERING < 0 || ZOOM_USE_LINEAR_FILTERING > 1
	#error "Invalid value for ZOOM_USE_LINEAR_FILTERING, it should be 0 for off or 1 for on"
#endif

//#endregion

//#region Constants

// static const bool SmoothZoom = ZOOM_SMOOTH_ZOOM != 0;

static const int Mode_Normal = 0;
static const int Mode_Reversed = 1;
static const int Mode_AlwaysEnabled = 2;

//#endregion

//#region Uniforms

uniform int _Help
<
	ui_text =
		"To use this effect, set the ZOOM_HOTKEY to the virtual key code of "
		"the keyboard key you'd like to use for zooming.\n"
		"You can check for the available keys in the \"KeyCodes.fxh\" file.\n"
		"\n"
		"Alternatively you can set ZOOM_USE_MOUSE_BUTTON to 1 to use a mouse "
		"button instead of a keyboard key, setting ZOOM_MOUSE_BUTTON to the "
		"number of the button you want to use.\n"
		"The available mouse buttons are:\n"
		" 0 - Left.\n"
		" 1 - Right.\n"
		" 2 - Middle.\n"
		" 3 - Extra 1.\n"
		" 4 - Extra 2.\n"
		"\n"
		"Setting ZOOM_TOGGLE to 1 will make the effect toggle when the hotkey/"
		"mouse button is pressed, instead of only being in effect while it's "
		"held down.\n"
		"\n"
		"Setting ZOOM_USE_LINEAR_FILTERING to 0 will cause the zoomed image to "
		"be pixelated, instead of being smooth filtered.\n"
		"Note that this filter is a native hardware feature, usually enabled "
		"by default, and shouldn't impact performance.\n"
		;
	ui_category = "Help";
	ui_category_closed = true;
	ui_label = " ";
	ui_type = "radio";
>;

uniform int Mode
<
	ui_label = "Mode";
	ui_tooltip =
		"Determines the mode in which the effect operates.\n"
		" - Normal\n"
		"     The effect zooms while the hotkey is held/toggled on.\n"
		" - Reversed\n"
		"     The effect zooms while the hotkey is released/toggled off.\n"
		" - Always Enabled\n"
		"     The effect always zooms.\n"
		"     This mode can be used in combination with ReShade's own built-in "
		"     hotkey system to turn the effect on or off entirely.\n"
		"\nDefault: Normal";
	ui_type = "combo";
	ui_items = "Normal\0Reversed\0Always Enabled\0";
> = Mode_Normal;

uniform float ZoomAmount
<
	ui_label = "Zoom Amount";
	ui_tooltip =
		"Amount of zoom applied to the image.\n"
		"\nDefault: 10.0";
	ui_type = "slider";
	ui_min = 1.0;
	ui_max = 10.0;
> = 3.0;

uniform float ZoomAreaSize
<
	ui_label = "Zoom Area Size";
	ui_tooltip =
		"Defines the size of a small circular area to display the zoomed image "
		"within.\n"
		"Set to 0.0 to disable this.\n"
		"\nDefault: 0.0";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.0;

uniform float2 ZoomAreaPosition
<
	ui_label = "Zoom Area Position";
	ui_tooltip =
		"Position of the zoomed area in the screen.\n"
		"0.5 represents the screen center.\n"
		"\nDefault: 0.5 0.5";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.5;

uniform float2 CenterPoint
<
	ui_label = "Center Point";
	ui_tooltip =
		"The center point of zoom in the screen.\n"
		"Viewport scale is used, thus:\n"
		" (0.5, 0.5) - Center.\n"
		" (0.0, 0.0) - Top left.\n"
		" (1.0, 0.0) - Top right.\n"
		" (1.0, 1.0) - Bottom right.\n"
		" (0.0, 1.0) - Bottom left.\n"
		"\nDefault: 0.5 0.5";
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.001;
> = float2(0.5, 0.5);

uniform bool FollowMouse
<
	ui_label = "Follow Mouse";
	ui_tooltip =
		"When enabled, the center point becomes the mouse cursor position.\n"
		"May not work with certain games due to how they may handle mouse "
		"input.\n"
		"\nDefault: Off";
> = false;

uniform float2 MousePoint < source = "mousepoint"; >;

uniform bool ShouldZoom
<
	#if ZOOM_USE_MOUSE_BUTTON
		source = "mousebutton";
		keycode = ZOOM_MOUSE_BUTTON;
	#else
		source = "key";
		keycode = ZOOM_HOTKEY;
	#endif

	#if ZOOM_TOGGLE
		mode = "toggle";
	#endif
>;

//#endregion

//#region Textures

sampler BackBuffer
{
	Texture = ReShade::BackBufferTex;

	#if !ZOOM_USE_LINEAR_FILTERING
		MagFilter = POINT;
	#endif
};

//#endregion

//#region Functions

float2 ScaleCoord(float2 uv, float2 scale, float2 pivot)
{
	return mad((uv - pivot), scale, pivot);
}

/*
	An area is defined as:
		x: Left coordinate.
		y: Bottom coordinate.
		z: Right coordinate.
		w: Top coordinate.
*/
float Contains(float4 area, float2 uv)
{
	return
		step(area.x, uv.x) *
		step(uv.x, area.z) *
		step(area.y, uv.y) *
		step(uv.y, area.w);
}

//#endregion

//#region Shaders

float4 MainPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	float zoom = rcp(ZoomAmount);
	float2 pivot;

	if (FollowMouse)
	{
		pivot = MousePoint * BUFFER_PIXEL_SIZE;
		pivot = saturate(pivot);
	}
	else if (ZoomAreaSize > 0.0)
	{
		pivot = (1.0 - ZoomAreaPosition);
		pivot = ScaleCoord(pivot, zoom, 0.5);
		pivot = saturate(pivot);
	}
	else
	{
		pivot = 0.5;
	}

	float2 zoomUv = ScaleCoord(uv, zoom, pivot);

	if (
		Mode == Mode_Normal && !ShouldZoom ||
		Mode == Mode_Reversed && ShouldZoom)
	{
		zoomUv = uv;
	}

	if (ZoomAreaSize > 0.0)
	{
		float2 areaUv = ScaleCoord(zoomUv, float2(BUFFER_ASPECT_RATIO, 1.0), 0.5);
		float inArea = step(distance(areaUv, 0.5), ZoomAreaSize * zoom);

		uv = lerp(uv, zoomUv, inArea);
	}
	else
	{
		uv = zoomUv;
	}

	float4 color = tex2D(BackBuffer, uv);

	return color;
}

//#endregion

//#region Technique

technique Zoom
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = MainPS;
	}
}

//#endregion
