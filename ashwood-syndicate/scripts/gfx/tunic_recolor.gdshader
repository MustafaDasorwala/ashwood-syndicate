shader_type canvas_item;

// Recolours one villager sheet into ten distinguishable people.
//
// The sheet is drawn so the tunic is the only desaturated bright region on the
// character: skin, hair, belt, trousers and boots are all warm and saturated,
// and the outline is near black. So "low saturation and bright" isolates the
// tunic without needing a second mask texture, and every inhabitant can share
// one 100x200 PNG.
//
// The multiply by mx / TUNIC_BASE keeps the tunic's own shading ramp instead of
// flooding it flat, which is what makes the folds survive the swap.

uniform vec3 tint : source_color = vec3(1.0);

// Value of the tunic's lit midtone in the source art. Dividing by it maps that
// midtone onto the tint exactly, and leaves highlights and shadows relative.
const float TUNIC_BASE = 0.68;

// Above this saturation a pixel is coloured cloth, skin or leather, not tunic.
const float TUNIC_MAX_SAT = 0.14;

// Below this brightness a pixel is outline or hair.
const float TUNIC_MIN_VALUE = 0.35;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float mx = max(source.r, max(source.g, source.b));
	float mn = min(source.r, min(source.g, source.b));
	float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;

	if (source.a > 0.5 && sat < TUNIC_MAX_SAT && mx > TUNIC_MIN_VALUE) {
		source.rgb = clamp(tint * (mx / TUNIC_BASE), vec3(0.0), vec3(1.0));
	}

	COLOR = source;
}
