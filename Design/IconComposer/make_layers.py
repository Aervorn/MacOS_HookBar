"""Calques de l'icône de HookBar pour Icon Composer (macOS 26).

Tous sur le même canevas de 1024 × 1024 : ils se superposent sans réglage.
Écrit les SVG ici, copie dans HookBar/AppIcon.icon/Assets ceux qu'utilise l'icône,
et assemble Design/HookBar-icon.svg (icône complète, pour le README).

    python3 Design/IconComposer/make_layers.py
"""
import shutil
from pathlib import Path

HERE = Path(__file__).parent
ICON_ASSETS = HERE.parent.parent / "HookBar" / "AppIcon.icon" / "Assets"
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'

GRADIENT = """    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#4F46E5"/><stop offset="1" stop-color="#A855F7"/>
    </linearGradient>
"""

# Bulle de discussion : rectangle arrondi et sa pointe en bas à gauche
BUBBLE_PATH = (
    "M 342 252 H 702 A 110 110 0 0 1 812 362 V 582 A 110 110 0 0 1 702 692"
    " H 452 L 318 792 L 342 692 A 110 110 0 0 1 232 582 V 362 A 110 110 0 0 1 342 252 Z"
)

LAYERS = {}

# Fond : référence seulement (dans l'icône, c'est le dégradé de fond d'Icon Composer)
LAYERS["1-fond.svg"] = HEAD + "  <defs>\n" + GRADIENT + """  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
</svg>
"""

LAYERS["2-bulle.svg"] = HEAD + f'  <path d="{BUBBLE_PATH}" fill="#FFFFFF"/>\n</svg>\n'

# Lignes de texte dans la bulle : les messages
lines = HEAD + '  <g fill="#6D5AE6">\n'
for y, width in [(372, 360), (452, 360), (532, 230)]:
    lines += f'    <rect x="332" y="{y}" width="{width}" height="40" rx="20"/>\n'
lines += "  </g>\n</svg>\n"
LAYERS["3-lignes.svg"] = lines

# Pastille de notification
LAYERS["4-pastille.svg"] = HEAD + '  <circle cx="790" cy="262" r="96" fill="#F43F5E"/>\n</svg>\n'


def body(svg):
    """Contenu d'un calque, sans la balise <svg> qui l'entoure."""
    return svg.split("\n", 1)[1].rsplit("</svg>", 1)[0]


if __name__ == "__main__":
    for name, svg in LAYERS.items():
        (HERE / name).write_text(svg)
    ICON_ASSETS.mkdir(parents=True, exist_ok=True)
    for name in ["2-bulle.svg", "3-lignes.svg", "4-pastille.svg"]:
        shutil.copy(HERE / name, ICON_ASSETS / name)

    # Icône complète pour le README : fond arrondi, ombre légère sous la bulle
    full = HEAD + "  <defs>\n" + GRADIENT + """  </defs>
  <rect x="0" y="0" width="1024" height="1024" rx="230" fill="url(#bg)"/>
"""
    full += f'  <path d="{BUBBLE_PATH}" fill="#1E1B4B" opacity="0.18" transform="translate(0 14)"/>\n'
    for name in ["2-bulle.svg", "3-lignes.svg", "4-pastille.svg"]:
        full += body(LAYERS[name])
    full += "</svg>\n"
    (HERE.parent / "HookBar-icon.svg").write_text(full)
    print("Calques écrits dans", HERE)
