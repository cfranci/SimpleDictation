#!/usr/bin/env python3
"""SimpleDictation app icon: a bold multicolor (red/blue/green/purple) waveform
with a clean white microphone overlaid, on a dark rounded square."""
import math

S = 1024
R = int(S * 0.2237)
cx, cy = S / 2, S / 2

# --- bold multicolor waveform, mirrored around the vertical center ---
n = 29
margin = S * 0.115
usable = S - margin * 2
gap = usable / n
bar_w = gap * 0.60
band_h = S * 0.66
bars = []
for i in range(n):
    t = i / (n - 1)
    # undulating envelope: tall shoulders, swirly ripple
    env = (0.60
           + 0.40 * math.sin(t * math.pi) ** 0.7
           * (0.65 + 0.35 * math.sin(t * math.pi * 4.0 + 0.5)))
    env = max(0.16, min(1.0, env))
    h = band_h * env
    x = margin + gap * i + (gap - bar_w) / 2
    bars.append((x, cy - h / 2, bar_w, h))

def bars_svg(fill):
    return "\n".join(
        f'<rect x="{x:.1f}" y="{y:.1f}" width="{bar_w:.1f}" height="{h:.1f}" '
        f'rx="{bar_w/2:.1f}" fill="{fill}"/>'
        for (x, y, w, h) in bars)

# --- white microphone: capsule + U-cradle + stand + base ---
cw = S * 0.150          # capsule width
ch = S * 0.250          # capsule height
lw = S * 0.030
cap_top = cy - S * 0.170
cap_bottom = cap_top + ch
cradle_cy = cap_top + ch * 0.60
cr = cw * 0.88
stand_top = cradle_cy + cr
stand_bot = stand_top + S * 0.080
base_half = S * 0.070

def arc(cxp, cyp, r, a0, a1):
    x0 = cxp + r * math.cos(math.radians(a0)); y0 = cyp + r * math.sin(math.radians(a0))
    x1 = cxp + r * math.cos(math.radians(a1)); y1 = cyp + r * math.sin(math.radians(a1))
    return f'M {x0:.1f} {y0:.1f} A {r:.1f} {r:.1f} 0 0 0 {x1:.1f} {y1:.1f}'

mic = f'''
  <rect x="{cx-cw/2:.1f}" y="{cap_top:.1f}" width="{cw:.1f}" height="{ch:.1f}"
        rx="{cw/2:.1f}" fill="#ffffff"/>
  <path d="{arc(cx, cradle_cy, cr, 360, 180)}" stroke="#ffffff"
        stroke-width="{lw:.1f}" fill="none" stroke-linecap="round"/>
  <line x1="{cx:.1f}" y1="{stand_top:.1f}" x2="{cx:.1f}" y2="{stand_bot:.1f}"
        stroke="#ffffff" stroke-width="{lw:.1f}" stroke-linecap="round"/>
  <line x1="{cx-base_half:.1f}" y1="{stand_bot:.1f}" x2="{cx+base_half:.1f}" y2="{stand_bot:.1f}"
        stroke="#ffffff" stroke-width="{lw:.1f}" stroke-linecap="round"/>'''

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.3" y2="1">
      <stop offset="0" stop-color="#232838"/>
      <stop offset="1" stop-color="#080A10"/>
    </linearGradient>
    <linearGradient id="wave" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0.00" stop-color="#FF453A"/>
      <stop offset="0.20" stop-color="#FF9F0A"/>
      <stop offset="0.42" stop-color="#0A84FF"/>
      <stop offset="0.66" stop-color="#30D158"/>
      <stop offset="0.86" stop-color="#BF5AF2"/>
      <stop offset="1.00" stop-color="#FF375F"/>
    </linearGradient>
    <radialGradient id="scrim" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#080A10" stop-opacity="0.82"/>
      <stop offset="0.62" stop-color="#080A10" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#080A10" stop-opacity="0"/>
    </radialGradient>
    <filter id="soft" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="{S*0.02:.1f}"/>
    </filter>
    <filter id="micshadow" x="-40%" y="-40%" width="180%" height="180%">
      <feDropShadow dx="0" dy="{S*0.006:.1f}" stdDeviation="{S*0.012:.1f}" flood-color="#000000" flood-opacity="0.45"/>
    </filter>
  </defs>

  <rect x="0" y="0" width="{S}" height="{S}" rx="{R}" ry="{R}" fill="url(#bg)"/>

  <!-- glow of the waveform for depth -->
  <g opacity="0.45" filter="url(#soft)">{bars_svg('url(#wave)')}</g>
  <!-- crisp multicolor waveform -->
  {bars_svg('url(#wave)')}

  <!-- radial scrim keeps the white mic legible; feathered so bars still peek -->
  <circle cx="{cx}" cy="{cy}" r="{S*0.30:.1f}" fill="url(#scrim)"/>
  <g filter="url(#micshadow)">{mic}</g>
</svg>'''

html = ('<!doctype html><html><head><meta charset="utf-8">'
        '<style>html,body{margin:0;padding:0;background:transparent}</style></head>'
        f'<body>{svg}</body></html>')

with open("tools/icon.html", "w") as f: f.write(html)
with open("tools/icon.svg", "w") as f: f.write(svg)
print("wrote tools/icon.html + tools/icon.svg")
