shader_type canvas_item;
render_mode unshaded; // 不受灯光影响，便于效果合成

// 屏幕纹理
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;

// 控制参数
uniform float threshold : hint_range(0.0, 4.0) = 0.8; // 提取高亮的阈值（线性亮度）
uniform float intensity : hint_range(0.0, 5.0) = 1.5; // 高亮放大（提取后乘的系数）
uniform float bloom_strength : hint_range(0.0, 4.0) = 0.9; // 最终合成到原图的强度
uniform float sample_scale : hint_range(0.1, 4.0) = 1.0; // 采样偏移缩放，用于控制模糊半径

// 请通过脚本把视口分辨率传进来（见下方示例）
uniform vec2 resolution = vec2(1024.0, 768.0);

// 常量：人眼感知亮度权重（sRGB linear 下）
const vec3 LUM_COEFF = vec3(0.2126, 0.7152, 0.0722);

// 从屏幕在偏移处采样并只返回“高光部分”
vec3 sample_bright(vec2 uv, vec2 offset) {
    vec3 c = texture(SCREEN_TEXTURE, uv + offset).rgb;
    float lum = dot(c, LUM_COEFF);
    // simple threshold (可改 soft-knee)
    vec3 bright = max(c - vec3(threshold), vec3(0.0));
    // 放大亮度更明显
    return bright * intensity;
}

void fragment() {
    vec2 uv = SCREEN_UV;

    // 以像素为单位的偏移（根据分辨率）
    vec2 px = (1.0 / max(resolution, vec2(1.0))) * sample_scale;

    // 3x3 Gaussian-like kernel weights (sum = 1)
    // [0.0625 0.125 0.0625]
    // [0.125  0.25  0.125 ]
    // [0.0625 0.125 0.0625]
    float w_center = 0.25;
    float w_side = 0.125;
    float w_diag = 0.0625;

    vec3 bloom = vec3(0.0);

    bloom += sample_bright(uv, vec2(-px.x, -px.y)) * w_diag;
    bloom += sample_bright(uv, vec2(    0.0, -px.y)) * w_side;
    bloom += sample_bright(uv, vec2( px.x, -px.y)) * w_diag;

    bloom += sample_bright(uv, vec2(-px.x,  0.0)) * w_side;
    bloom += sample_bright(uv, vec2(    0.0,  0.0)) * w_center;
    bloom += sample_bright(uv, vec2( px.x,  0.0)) * w_side;

    bloom += sample_bright(uv, vec2(-px.x,  px.y)) * w_diag;
    bloom += sample_bright(uv, vec2(    0.0,  px.y)) * w_side;
    bloom += sample_bright(uv, vec2( px.x,  px.y)) * w_diag;

    // 可选：再做一次轻微扩散（增强模糊感）——用更远的采样
    // 下面两行非必须，注释掉可节省一次采样。
    bloom += sample_bright(uv, vec2(-2.0 * px.x, 0.0)) * 0.06;
    bloom += sample_bright(uv, vec2( 2.0 * px.x, 0.0)) * 0.06;

    // 合成：原色 + bloom（并用 bloom_strength 控制）
    vec3 base = texture(SCREEN_TEXTURE, uv).rgb;
    vec3 out_col = base + bloom * bloom_strength;

    // 可做简单颜色守恒或曝光压制（可选）
    // out_col = 1.0 - exp(-out_col); // filmic tone mapping（取消注释试试）

    COLOR = vec4(out_col, 1.0);
}
