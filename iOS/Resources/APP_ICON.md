# WatchBeat App icon

The production icon is stored at
`Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`. It is a 1024×1024 opaque RGB PNG; iOS applies
the platform corner mask at runtime.

## Final production prompt

```text
Use case: precise-object-edit
Asset type: replacement production iOS app icon for WatchBeat
Primary request: rebuild the icon as a strict two-color flat design: a full-bleed pure-white
`#FFFFFF` background, one large centered solid-pink `#F04F87` heart, and a pure-white ECG waveform
cut through the heart.
Waveform geometry: use exactly three upward peaks and exactly two downward troughs, with no extra
bumps or extrema: low Peak 1, Trough 1, dramatically taller narrow central Peak 2, deep narrow
Trough 2, low Peak 3, then return directly to the baseline. Peak 1 and Peak 3 should match; each
side peak is about 20–25% of the central peak's height, creating a clear LOW–HIGH–LOW hierarchy and
a compact WatchBeat “W” rhythm without drawing a literal letter.
Negative-space treatment: extend the white horizontal baseline through the heart's left and right
boundaries so both ends connect seamlessly to the white background. The waveform is one open
negative-space channel through the pink heart, not a separate white object with visible endpoints.
Composition/framing: centered, balanced and readable at 40 px; large simple heart, compact active
waveform, uniform stroke thickness, smooth rounded joins and generous outer safe margins.
Style/medium: crisp flat vector-like iOS icon using proportion and spacing only.
Constraints: exactly two visible colors; no gradient, highlight, gloss, reflection, shadow, inner
shadow, glow, bloom, bevel, translucency, texture, outline, lighting effect, color variation,
rounded-square tile, text, standalone letters, numbers, labels, Apple logo, medical cross,
watermark, border frame, device mockup, transparency, extra symbols or tiny details.
```

The image was generated with the built-in OpenAI image-generation tool, refined to the strict
pink-and-white flat palette, the open negative-space waveform, and the compact exact
three-peak/two-trough geometry, then resized once with high-quality bicubic interpolation from the
generated square master to the required 1024×1024 opaque RGB app icon canvas. No external logo or
trademark source was used.
