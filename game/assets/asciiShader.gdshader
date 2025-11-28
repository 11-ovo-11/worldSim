shader_type canvas_item;
render_mode unshaded;
const vec3 MONOCHROME_SCALE = vec3(0.298912, 0.586611, 0.114478);

uniform sampler2D ascii_tex: filter_nearest;
uniform vec2 ascii_size = vec2(8.0, 16.0); // 字符像素大小（基于源图，不是屏幕）
uniform int available_columns = 10;
uniform int max_columns = 16;


void fragment()
{
    // -------- 1) 把 UV 转成源图像像素坐标 --------
	vec2 texture_size = vec2(1080,540);
    vec2 px = UV * texture_size;

    // 使用 ascii_size 完全基于"原图像像素"
    vec2 cell = floor(px / ascii_size);
    vec2 cell_origin_px = cell * ascii_size;

    // 转回 UV
    vec2 cell_uv = cell_origin_px / texture_size;

    // -------- 2) 对齐 TEXTURE 采样（使用 UV，不受缩放影响）--------
    vec2 d = ascii_size / texture_size;

    vec4 color = (
        texture(TEXTURE, cell_uv) +
        texture(TEXTURE, cell_uv + vec2(d.x, 0.0)) +
        texture(TEXTURE, cell_uv + vec2(0.0, d.y)) +
        texture(TEXTURE, cell_uv + d)
    ) / 4.0;

    // -------- 3) 亮度转字符列 --------
    float luminance = dot(color.rgb, MONOCHROME_SCALE);
    float col = floor(luminance * float(available_columns));
    col = clamp(col, 0.0, float(available_columns - 1));

    // -------- 4) ASCII 字符取样 --------
    // 当前像素在这一格里的 0~1 范围偏移
    vec2 offset = fract(px / ascii_size);

    vec2 ascii_uv;
    ascii_uv.y = offset.y; // 行固定
    ascii_uv.x = (offset.x + col) / float(max_columns);

    COLOR = texture(ascii_tex, ascii_uv);
}
