"""Generate AEO VSC Claude Sessions extension icon at 256x256."""
from PIL import Image, ImageDraw, ImageFont

SIZE = 256
BG = "#1a1a2e"
ANTHROPIC_ORANGE = "#C15F3C"
WHITE = "#FFFFFF"
GREEN = "#3fb950"
YELLOW = "#d29922"
BLUE = "#58a6ff"
RED = "#f85149"
GREY = "#484f58"

img = Image.new("RGBA", (SIZE, SIZE), ANTHROPIC_ORANGE)
draw = ImageDraw.Draw(img)

# Rounded rectangle background
draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=32, fill=ANTHROPIC_ORANGE)

# "CC" text in white — large, centered upper area
try:
    font_cc = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 88)
except OSError:
    font_cc = ImageFont.load_default()

# Measure all elements to compute total content height, then center vertically
try:
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 24)
except OSError:
    font_sm = ImageFont.load_default()

bbox_cc = draw.textbbox((0, 0), "CC", font=font_cc)
cc_h = bbox_cc[3] - bbox_cc[1]

bbox_sess = draw.textbbox((0, 0), "SESSIONS", font=font_sm)
sess_h = bbox_sess[3] - bbox_sess[1]

dot_r = 12
dot_h = dot_r * 2

bbox_aeo = draw.textbbox((0, 0), "AEO", font=font_sm)
aeo_h = bbox_aeo[3] - bbox_aeo[1]

gap = 20
total_h = cc_h + gap + sess_h + gap + dot_h + gap + aeo_h
top = (SIZE - total_h) // 2

# Draw CC
cc_w = bbox_cc[2] - bbox_cc[0]
draw.text(((SIZE - cc_w) // 2, top - bbox_cc[1]), "CC", fill=WHITE, font=font_cc)

# Draw SESSIONS
sess_y = top + cc_h + gap
sess_w = bbox_sess[2] - bbox_sess[0]
draw.text(((SIZE - sess_w) // 2, sess_y - bbox_sess[1]), "SESSIONS", fill=WHITE, font=font_sm)

# Draw dots
dot_top = sess_y + sess_h + gap
colors = [GREEN, YELLOW, BLUE, RED]
total_width = len(colors) * (dot_r * 2) + (len(colors) - 1) * 16
start_x = (SIZE - total_width) // 2
for i, color in enumerate(colors):
    cx = start_x + i * (dot_r * 2 + 16) + dot_r
    cy = dot_top + dot_r
    draw.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=color)

# Draw AEO
aeo_y = dot_top + dot_h + gap
aeo_w = bbox_aeo[2] - bbox_aeo[0]
draw.text(((SIZE - aeo_w) // 2, aeo_y - bbox_aeo[1]), "AEO", fill=WHITE, font=font_sm)

# Save at 256x256 (recommended) and 128x128 (minimum)
img.save("/opt/aeo/ai-essentials/claude-sessions-vsix/media/icon.png")

img_128 = img.resize((128, 128), Image.LANCZOS)
img_128.save("/opt/aeo/ai-essentials/claude-sessions-vsix/media/icon-128.png")

print(f"Generated icon.png (256x256) and icon-128.png (128x128)")
