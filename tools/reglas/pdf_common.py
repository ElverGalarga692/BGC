"""Piezas comunes para maquetar los reglamentos en PDF (ReportLab).

Cada juego tiene su propio script (p. ej. build_archipelago.py) que usa
estas utilidades: estilos, portada, figuras con captura y tablas.
"""

import io
import os

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Frame, Image, KeepTogether, PageTemplate, Paragraph,
    Spacer, Table, TableStyle,
)

FONT_DIR = "/usr/share/fonts/truetype/dejavu"
pdfmetrics.registerFont(TTFont("Sans", os.path.join(FONT_DIR, "DejaVuSans.ttf")))
pdfmetrics.registerFont(TTFont("Sans-Bold", os.path.join(FONT_DIR, "DejaVuSans-Bold.ttf")))

pdfmetrics.registerFontFamily("Sans", normal="Sans", bold="Sans-Bold", italic="Sans",
                              boldItalic="Sans-Bold")

# Colores de la interfaz del juego (ui_common/bgc_theme.gd y las pantallas).
NAVY = colors.HexColor("#163246")
NAVY_DARK = colors.HexColor("#0f2433")
# Color principal de cada reglamento (portada, cabeceras, títulos). Por
# defecto, el azul de Archipiélago; cada juego lo cambia con set_theme().
THEME = {"primary": NAVY, "dark": NAVY_DARK, "cover_text": colors.HexColor("#cfe0ec"),
         "cover_note": colors.HexColor("#8fb0c6")}
GOLD = colors.HexColor("#ffd166")
INK = colors.HexColor("#1d2731")
MUTED = colors.HexColor("#5b6773")
SOFT = colors.HexColor("#eef3f7")
LINE = colors.HexColor("#c9d4dd")

PAGE_W, PAGE_H = A4
MARGIN = 18 * mm
CONTENT_W = PAGE_W - 2 * MARGIN

BODY = ParagraphStyle("body", fontName="Sans", fontSize=10, leading=14.5, textColor=INK, spaceAfter=6)
SMALL = ParagraphStyle("small", parent=BODY, fontSize=8.5, leading=11.5, textColor=MUTED)
CAPTION = ParagraphStyle("caption", parent=SMALL, alignment=TA_CENTER, spaceBefore=3, spaceAfter=10)
H1 = ParagraphStyle("h1", fontName="Sans-Bold", fontSize=19, leading=24, textColor=NAVY,
                    spaceBefore=4, spaceAfter=8)
H2 = ParagraphStyle("h2", fontName="Sans-Bold", fontSize=12.5, leading=16, textColor=NAVY,
                    spaceBefore=8, spaceAfter=4)
BULLET = ParagraphStyle("bullet", parent=BODY, leftIndent=12, bulletIndent=2, spaceAfter=3)
CELL = ParagraphStyle("cell", parent=BODY, fontSize=9, leading=12, spaceAfter=0)
CELL_B = ParagraphStyle("cellb", parent=CELL, fontName="Sans-Bold")
NOTE = ParagraphStyle("note", parent=BODY, fontSize=9.5, leading=13.5, spaceAfter=0)


def set_theme(primary, dark, cover_text, cover_note, heading=None):
    """Cambia el color principal del reglamento (llamar antes de maquetar)."""
    THEME.update(primary=colors.HexColor(primary), dark=colors.HexColor(dark),
                 cover_text=colors.HexColor(cover_text), cover_note=colors.HexColor(cover_note))
    H1.textColor = H2.textColor = colors.HexColor(heading or primary)


def p(text, style=BODY):
    return Paragraph(text, style)


def bullets(items, style=BULLET):
    return [Paragraph(item, style, bulletText="•") for item in items]


def screenshot(path, caption=None, width=CONTENT_W, crop=None, keep=True):
    """Captura como JPEG (para que el PDF no pese demasiado) con pie de foto.
    `crop` = (izq, arriba, der, abajo) en píxeles de la captura original."""
    img = PILImage.open(path).convert("RGB")
    if crop:
        img = img.crop(crop)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=88, optimize=True)
    buf.seek(0)
    height = width * img.height / img.width
    framed = Table([[Image(buf, width=width, height=height)]], colWidths=[width])
    framed.setStyle(TableStyle([
        ("BOX", (0, 0), (-1, -1), 0.8, THEME["dark"]),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    parts = [framed]
    if caption:
        parts.append(Paragraph(caption, CAPTION))
    return KeepTogether(parts) if keep else parts


def note(text, title="Consejo"):
    """Recuadro destacado (consejos, aclaraciones)."""
    box = Table([[Paragraph(f"<b>{title}.</b> {text}", NOTE)]], colWidths=[CONTENT_W])
    box.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#fff6dc")),
        ("LINEBEFORE", (0, 0), (0, -1), 3, GOLD),
        ("LEFTPADDING", (0, 0), (-1, -1), 9), ("RIGHTPADDING", (0, 0), (-1, -1), 9),
        ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return KeepTogether([Spacer(1, 2), box, Spacer(1, 8)])


def table(rows, col_widths, header=True, swatches=None):
    """Tabla con cabecera azul. `swatches` = {fila: color} pinta la 1.ª celda."""
    data = []
    for i, row in enumerate(rows):
        is_header = header and i == 0
        cells = []
        for c in row:
            if isinstance(c, str):
                c = Paragraph(f'<font color="white">{c}</font>' if is_header else c,
                              CELL_B if is_header else CELL)
            cells.append(c)
        data.append(cells)
    t = Table(data, colWidths=col_widths, repeatRows=1 if header else 0)
    cmds = [
        ("GRID", (0, 0), (-1, -1), 0.5, LINE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("ROWBACKGROUNDS", (0, 1 if header else 0), (-1, -1), [colors.white, SOFT]),
    ]
    if header:
        cmds.append(("BACKGROUND", (0, 0), (-1, 0), THEME["primary"]))
    for row, color in (swatches or {}).items():
        cmds.append(("BACKGROUND", (0, row), (0, row), colors.HexColor(color)))
    t.setStyle(TableStyle(cmds))
    return t


class RulesDoc(BaseDocTemplate):
    """A4 con portada a sangre y cabecera/pie en el resto de páginas."""

    def __init__(self, path, title, subtitle, cover_image, tagline):
        super().__init__(path, pagesize=A4, leftMargin=MARGIN, rightMargin=MARGIN,
                         topMargin=MARGIN + 6 * mm, bottomMargin=MARGIN,
                         title=f"{title}: reglamento", author="BGC: Board Game Collection",
                         subject=subtitle)
        self.game_title = title
        self.subtitle = subtitle
        self.cover_image = cover_image
        self.tagline = tagline
        frame = Frame(MARGIN, MARGIN, CONTENT_W, PAGE_H - 2 * MARGIN - 6 * mm, id="body")
        self.addPageTemplates([
            PageTemplate(id="cover", frames=[frame], onPage=self._cover),
            PageTemplate(id="page", frames=[frame], onPage=self._page),
        ])

    def _cover(self, canvas, doc):
        canvas.saveState()
        canvas.setFillColor(THEME["primary"])
        canvas.rect(0, 0, PAGE_W, PAGE_H, stroke=0, fill=1)
        canvas.setFillColor(GOLD)
        canvas.setFont("Sans-Bold", 11)
        canvas.drawString(MARGIN, PAGE_H - 26 * mm, "BGC · BOARD GAME COLLECTION")
        canvas.setFillColor(colors.white)
        canvas.setFont("Sans-Bold", 44)
        canvas.drawString(MARGIN, PAGE_H - 48 * mm, self.game_title)
        canvas.setFont("Sans", 15)
        canvas.setFillColor(THEME["cover_text"])
        canvas.drawString(MARGIN, PAGE_H - 59 * mm, self.subtitle)
        canvas.setStrokeColor(GOLD)
        canvas.setLineWidth(2)
        canvas.line(MARGIN, PAGE_H - 66 * mm, MARGIN + 40 * mm, PAGE_H - 66 * mm)
        img = PILImage.open(self.cover_image).convert("RGB")
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=90)
        buf.seek(0)
        from reportlab.lib.utils import ImageReader
        w = CONTENT_W
        h = w * img.height / img.width
        y = PAGE_H - 80 * mm - h
        canvas.drawImage(ImageReader(buf), MARGIN, y, w, h)
        canvas.setStrokeColor(GOLD)
        canvas.setLineWidth(1)
        canvas.rect(MARGIN, y, w, h, stroke=1, fill=0)
        canvas.setFillColor(colors.white)
        canvas.setFont("Sans", 11)
        ty = y - 14 * mm
        for line in self.tagline:
            canvas.drawString(MARGIN, ty, line)
            ty -= 6 * mm
        canvas.setFillColor(THEME["cover_note"])
        canvas.setFont("Sans", 8.5)
        canvas.drawString(MARGIN, 14 * mm, "Reglamento con capturas de la versión digital.")
        canvas.restoreState()

    def _page(self, canvas, doc):
        canvas.saveState()
        canvas.setFillColor(THEME["primary"])
        canvas.rect(0, PAGE_H - 12 * mm, PAGE_W, 12 * mm, stroke=0, fill=1)
        canvas.setFillColor(GOLD)
        canvas.rect(0, PAGE_H - 12.8 * mm, PAGE_W, 0.8 * mm, stroke=0, fill=1)
        canvas.setFillColor(colors.white)
        canvas.setFont("Sans-Bold", 10)
        canvas.drawString(MARGIN, PAGE_H - 7.8 * mm, self.game_title)
        canvas.setFont("Sans", 9)
        canvas.drawRightString(PAGE_W - MARGIN, PAGE_H - 7.8 * mm, "Reglamento")
        canvas.setFillColor(MUTED)
        canvas.setFont("Sans", 8.5)
        canvas.drawCentredString(PAGE_W / 2, 10 * mm, str(doc.page))
        canvas.restoreState()


def side_by_side(left, right, gap=6 * mm):
    """Dos capturas en paralelo: cada una es (ruta, pie, recorte o None)."""
    width = (CONTENT_W - gap) / 2
    cells = [screenshot(path, caption, width=width, crop=crop, keep=False) for path, caption, crop in (left, right)]
    t = Table([cells], colWidths=[width + gap / 2, width + gap / 2])
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("ALIGN", (0, 0), (0, 0), "LEFT"), ("ALIGN", (1, 0), (1, 0), "RIGHT"),
    ]))
    return t
