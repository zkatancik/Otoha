"""Compose the design board from the Blender still and the app's exported portraits (Pillow)."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

DESIGN = Path(__file__).resolve().parent
ART = DESIGN.parent / "public/assets"
PAPER = "#F5F3EC"
INK = "#222520"
MUTED = "#575C53"
W = 1800
MARGIN = 54


def face(size, bold=False):
    options = (
        ["/System/Library/Fonts/Supplemental/Arial Bold.ttf", "DejaVuSans-Bold.ttf"]
        if bold
        else ["/System/Library/Fonts/Supplemental/Arial.ttf", "DejaVuSans.ttf"]
    )
    for font in options:
        try:
            return ImageFont.truetype(font, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def row(sheet, y, height, title, items):
    draw = ImageDraw.Draw(sheet)
    draw.line((MARGIN, y, W - MARGIN, y), fill="#BFC0B5", width=2)
    draw.text((MARGIN, y + 18), title, font=face(32, True), fill=INK)
    cell = (W - 2 * MARGIN) / len(items)
    for i, (key, label) in enumerate(items):
        x = round(MARGIN + (i + 0.5) * cell)
        img = Image.open(ART / "hardware" / (key + ".webp")).convert("RGBA")
        img = img.crop(img.getchannel("A").getbbox())
        img.thumbnail((round(cell * 0.84), height - 107), Image.Resampling.LANCZOS)
        sheet.paste(img, (x - img.width // 2, y + height - 43 - img.height), img)
        draw.text((x, y + height - 26), label, font=face(20), anchor="mm", fill=INK)


def main():
    sheet = Image.new("RGB", (W, 1280), PAPER)
    draw = ImageDraw.Draw(sheet)
    icon = Image.open(ART / "icon.png").convert("RGBA").resize((48, 48), Image.Resampling.LANCZOS)
    sheet.paste(icon, (MARGIN, 25), icon)
    draw.text((MARGIN + 61, 49), "Otoha", font=face(45, True), anchor="lm", fill=INK)
    draw.text((W - MARGIN, 50), "Equipment library", font=face(25), anchor="rm", fill=MUTED)
    hero = Image.open(DESIGN / "linked-equipment.png").convert("RGB")
    sheet.paste(hero, (0, 98))
    draw.text((MARGIN, 236), "Linked equipment", font=face(29), fill=INK)
    draw.text((MARGIN - 4, 274), "HK 3770", font=face(108, True), fill=INK)
    draw.text((MARGIN, 408), "+ RM mini 3", font=face(54), fill=INK)
    row(
        sheet,
        710,
        264,
        "Receivers and speakers",
        [
            ("AVR3700", "AVR 3700"),
            ("BDS580", "BDS 580"),
            ("BDS577W", "BDS 7773W"),
            ("AuraPlus", "Aura Plus"),
            ("Onyx", "Onyx"),
        ],
    )
    row(
        sheet,
        991,
        258,
        "Infrared",
        [
            ("RM4pro", "BroadLink RM4 pro"),
            ("WF2IR", "iTach WF2IR"),
            ("FlexIP", "iTach Flex Ethernet"),
            ("IRKit", "IRKit"),
            ("Remo3", "Nature Remo 3"),
            ("TasmotaIR", "Tasmota IR"),
        ],
    )
    sheet.save(DESIGN / "equipment-board.jpg", quality=94, subsampling=0, optimize=True)


if __name__ == "__main__":
    main()
