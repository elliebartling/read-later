#!/usr/bin/env python3
"""Generate ReadLater's Phosphor symbol set.

    python3 tools/phosphor_symbols.py

Pulls the handful of Phosphor SVGs the app actually uses out of the MIT-licensed
`phosphor-icons/core` repository and rewrites each one as a **custom SF Symbol**
(`.symbolset`) plus the Swift `Icon` enum that names it. One command, no manual
step in the SF Symbols app, no vendored 71 MB SPM package.

WHY A SYMBOL SET AND NOT AN IMAGE SET
    §5.4 criterion 3 of docs/design-language.md: a plain asset-catalog image
    loses Dynamic Type scaling, `.imageScale`, text-baseline alignment inside a
    label run, weight response and `symbolRenderingMode`. A `.symbolset` keeps
    every one of them, so `Image(.trash)` behaves exactly like the SF Symbol it
    replaced and `uiGlyph()` keeps working unchanged.

THE TEMPLATE
    An SF Symbol template is an 800x600 SVG with a `Guides` layer and a
    `Symbols` layer holding one group per variant. Only three variants are
    required — `Ultralight-M`, `Regular-M`, `Black-M`; the system interpolates
    the other 24 (six intermediate weights x three scales).

    Inside a variant group the cap band runs from y=76 (Capline-S) to y=146
    (Baseline-S) — 70 units, which is SF Pro's cap height at a 100pt em, so
    template units are points-at-100pt. The group is then translated down 200
    to sit in the M row.

    We feed the weight axis from Phosphor's own weights: Thin -> Ultralight-M,
    Regular -> Regular-M, Bold -> Black-M. That is the argument §5.4 recorded
    for choosing Phosphor over Tabler ("six weights map cleanly onto SF Pro's
    weight range"), and it is what makes the set degrade properly under Bold
    Text and at accessibility sizes. Fill icons have no weight axis, so all
    three slots take the Fill artwork.

THE SCALE FACTOR
    Phosphor draws on a 256-unit grid; we map that grid to a 128-unit box
    centred on the cap band, i.e. `scale(0.5)`. That number is measured, not
    picked: rendering thirteen SF Symbols at a 100pt em and comparing their ink
    boxes against the matching Phosphor glyph gives a per-icon ratio whose
    median is 127.6 units. 128 is that median, and it means Phosphor's own
    optical sizing (a check is wide, a bookmark is narrow) survives the port
    instead of being flattened by a per-icon fit.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from svgpath import bbox  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "Shared" / "Resources" / "PhosphorSymbols.xcassets"
SWIFT_OUT = REPO / "ReadLater" / "UI" / "Icon.swift"
LICENSE_OUT = REPO / "LICENSES" / "Phosphor-LICENSE.txt"

PHOSPHOR_REPO = "https://github.com/phosphor-icons/core.git"

# ---------------------------------------------------------------------------
# The manifest — the single source of truth for the swap.
#
# (Swift case, Phosphor icon, weight, what it replaced). The fourth column is
# kept so the SF Symbol a glyph descends from stays greppable after the swap;
# it is emitted into Icon.swift as documentation and is not used at runtime.
#
# Weights follow the ratified rule: Regular for idle, Fill for selected/active
# (and for the transport controls, where filled is the shape itself — I3).
# ---------------------------------------------------------------------------
ICONS = [
    ("archive",             "archive",              "regular", "archivebox"),
    ("arrowCircleRight",    "arrow-circle-right",   "regular", "arrow.right.circle"),
    ("arrowClockwise",      "arrow-clockwise",      "regular", "arrow.clockwise"),
    ("arrowsClockwise",     "arrows-clockwise",     "regular", "arrow.triangle.2.circlepath"),
    ("bookmark",            "bookmark",             "regular", "bookmark"),
    # Ellen on #81: "let's use cards-three instead of books for library since
    # this isn't a book app." `books` is retired — nothing else named it.
    ("cardsThree",          "cards-three",          "regular", "books.vertical"),
    ("caretLeft",           "caret-left",           "regular", "chevron.left"),
    ("caretRight",          "caret-right",          "regular", "chevron.right"),
    ("chats",               "chats",                "regular", "bubble.left.and.bubble.right"),
    ("check",               "check",                "regular", "checkmark"),
    ("checkCircle",         "check-circle",         "regular", "checkmark.circle"),
    ("checkCircleFill",     "check-circle",         "fill",    "checkmark.circle.fill"),
    ("circle",              "circle",               "regular", "circle"),
    ("circleDashed",        "circle-dashed",        "regular", "circle.dashed"),
    ("compass",             "compass",              "regular", "safari"),
    ("dotsThree",           "dots-three",           "regular", "ellipsis"),
    ("downloadSimple",      "download-simple",      "regular", "square.and.arrow.down"),
    ("export",              "export",               "regular", "square.and.arrow.up"),
    ("fastForwardFill",     "fast-forward",         "fill",    "forward.fill"),
    ("gear",                "gear",                 "regular", "gearshape"),
    ("highlighter",         "highlighter",          "regular", "highlighter"),
    ("identificationBadge", "identification-badge", "regular", "person.badge.key"),
    ("link",                "link",                 "regular", "link"),
    ("listChecks",          "list-checks",          "regular", "checklist"),
    ("lockFill",            "lock",                 "fill",    "lock.fill"),
    ("magnifyingGlass",     "magnifying-glass",     "regular", "magnifyingglass"),
    ("pauseFill",           "pause",                "fill",    "pause.fill"),
    ("photo",               "image",                "regular", "photo"),
    ("playCircle",          "play-circle",          "regular", "play.rectangle"),
    ("playFill",            "play",                 "fill",    "play.fill"),
    ("plus",                "plus",                 "regular", "plus"),
    ("rewindFill",          "rewind",               "fill",    "backward.fill"),
    ("stopFill",            "stop",                 "fill",    "stop.fill"),
    ("tagFill",             "tag",                  "fill",    "tag.fill"),
    ("textAa",              "text-aa",              "regular", "textformat.size"),
    ("trash",               "trash",                "regular", "trash"),
    ("tray",                "tray",                 "regular", "tray / tray.full"),
    ("userCircle",          "user-circle",          "regular", "person.crop.circle"),
    ("usersThree",          "users-three",          "regular", "person.2.slash"),
    ("warning",             "warning",              "regular", "exclamationmark.triangle"),
    ("wifiSlash",           "wifi-slash",           "regular", "wifi.exclamationmark"),
    ("xCircleFill",         "x-circle",             "fill",    "xmark.circle.fill"),
    ("xMark",               "x",                    "regular", "xmark"),
]

# ---------------------------------------------------------------------------
# Template geometry
# ---------------------------------------------------------------------------

GRID = 256.0          # Phosphor's viewBox
SCALE = 0.5           # 256 -> 128 units; see the module docstring
BOX = GRID * SCALE
CAP_TOP, CAP_BOTTOM = 76.0, 146.0
BAND_CENTRE = (CAP_TOP + CAP_BOTTOM) / 2.0   # 111
ROW_M = 200.0                                 # the M row's vertical offset

# (variant id, column centre x, Phosphor weight directory for outline icons)
VARIANTS = [
    ("Ultralight-M", 265.0, "thin"),
    ("Regular-M", 465.0, "regular"),
    ("Black-M", 665.0, "bold"),
]

# Apple's cap-height reference glyph, verbatim from an exported template.
H_REFERENCE = (
    "M85,145.755 L87.685,145.755 L113.369,79.287 L114.052,79.287 L114.052,76 "
    "L112.148,76 L85,145.755 Z M95.693,121.536 L130.996,121.536 L130.263,119.313 "
    "L96.474,119.313 L95.693,121.536 Z M139.15,145.755 L141.787,145.755 "
    "L114.638,76 L113.466,76 L113.466,79.287 L139.15,145.755 Z"
)


def phosphor_file(name: str, weight: str) -> str:
    """Phosphor names the Regular weight bare and suffixes every other one."""
    return f"{name}.svg" if weight == "regular" else f"{name}-{weight}.svg"


def read_paths(assets: Path, name: str, weight: str) -> list:
    svg = (assets / weight / phosphor_file(name, weight)).read_text()
    paths = re.findall(r'<path[^>]*\sd="([^"]+)"', svg)
    if not paths:
        raise SystemExit(f"no <path> in {weight}/{name}")
    return paths


def variant_group(variant: str, centre_x: float, paths: list) -> str:
    """One `<g id="Weight-M">` holding the artwork, transformed into place."""
    tx = centre_x - BOX / 2.0
    ty = ROW_M + BAND_CENTRE - BOX / 2.0
    body = "\n".join(f'            <path d="{d}"/>' for d in paths)
    return (
        f'        <g id="{variant}" transform="translate({tx:g},{ty:g}) '
        f'scale({SCALE:g})">\n{body}\n        </g>'
    )


def margins(centre_x: float, paths: list) -> tuple:
    """Left/right margin guides, hugging the scaled artwork like Apple's do."""
    x0, _, x1, _ = bbox(paths)
    left = centre_x - BOX / 2.0 + x0 * SCALE
    right = centre_x - BOX / 2.0 + x1 * SCALE
    return left, right


def build_template(assets: Path, name: str, weight: str) -> str:
    groups, guides = [], []
    for variant, centre_x, outline_weight in VARIANTS:
        src_weight = "fill" if weight == "fill" else outline_weight
        paths = read_paths(assets, name, src_weight)
        groups.append(variant_group(variant, centre_x, paths))
        left, right = margins(centre_x, paths)
        guides.append(f'        <path id="left-margin-{variant}" d="M{left:.3f},256 l0,110"/>')
        guides.append(f'        <path id="right-margin-{variant}" d="M{right:.3f},256 l0,110"/>')

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!-- Generated by tools/phosphor_symbols.py from phosphor-icons/core ({name}, {weight}). -->
<!-- Phosphor Icons, MIT — see LICENSES/Phosphor-LICENSE.txt. Do not hand-edit. -->
<svg height="600" width="800" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
    <g id="Notes" font-family="LucidaGrande, 'Lucida Grande', sans-serif" font-size="13">
        <rect fill="white" height="600.0" width="800.0" x="0.0" y="0.0"/>
        <g font-size="13">
            <text x="18.0" y="176.0">Small</text>
            <text x="18.0" y="376.0">Medium</text>
            <text x="18.0" y="576.0">Large</text>
        </g>
        <g font-size="9">
            <text x="250.0" y="30.0">Ultralight</text>
            <text x="450.0" y="30.0">Regular</text>
            <text x="650.0" y="30.0">Black</text>
            <text id="template-version" fill="#505050" text-anchor="end" x="785.0" y="575.0">Template v.3.0</text>
        </g>
    </g>
    <g id="Guides" stroke="rgb(39, 170, 225)" stroke-width="0.5">
        <path id="Capline-S" d="M18,76 l800,0"/>
        <path id="H-reference" d="{H_REFERENCE}" stroke="none" transform="translate(0,200)"/>
        <path id="Baseline-S" d="M18,146 l800,0"/>
{chr(10).join(guides)}
        <path id="Capline-M" d="M18,276 l800,0"/>
        <path id="Baseline-M" d="M18,346 l800,0"/>
        <path id="Capline-L" d="M18,476 l800,0"/>
        <path id="Baseline-L" d="M18,546 l800,0"/>
    </g>
    <g id="Symbols">
{chr(10).join(groups)}
    </g>
</svg>
"""


def asset_name(name: str, weight: str) -> str:
    return f"ph.{name}" if weight == "regular" else f"ph.{name}.{weight}"


def write_catalog(assets: Path) -> list:
    if CATALOG.exists():
        shutil.rmtree(CATALOG)
    CATALOG.mkdir(parents=True)
    (CATALOG / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )
    written = []
    for _case, name, weight, _was in ICONS:
        asset = asset_name(name, weight)
        folder = CATALOG / f"{asset}.symbolset"
        folder.mkdir()
        (folder / f"{asset}.svg").write_text(build_template(assets, name, weight))
        (folder / "Contents.json").write_text(
            json.dumps(
                {
                    "info": {"author": "xcode", "version": 1},
                    "symbols": [{"filename": f"{asset}.svg", "idiom": "universal"}],
                },
                indent=2,
            )
            + "\n"
        )
        written.append(asset)
    return written


def write_swift() -> None:
    lines = [
        "// GENERATED by tools/phosphor_symbols.py — do not edit by hand.",
        "// Re-run that script to add, remove or re-weight an icon.",
        "",
        "import SwiftUI",
        "",
        "// §5 — the icon substrate is **Phosphor** (ratified by Ellen on the",
        "// wave-5 build: \"Use phosphor\"). Every glyph the app draws comes from",
        "// this enum, and every glyph in this enum is a custom SF Symbol compiled",
        "// from Phosphor's MIT-licensed artwork by tools/phosphor_symbols.py.",
        "//",
        "// The symbols are real `.symbolset`s, not images, so §5.4's criterion 3",
        "// holds: Dynamic Type, `.imageScale`, `.font()`, baseline alignment in a",
        "// label run, weight response and `symbolRenderingMode` all behave exactly",
        "// as they did under SF Symbols. `uiGlyph()` is unchanged and still the one",
        "// place I2/I4 are decided.",
        "//",
        "// **This enum is the whole surface.** No call site names an asset string,",
        "// so swapping an icon — or the whole set again — is a one-line change here",
        "// plus a re-run of the generator.",
        "// `CaseIterable` is not decoration: IconCatalogTests walks `allCases`",
        "// so a newly generated icon is covered by the bundle tripwire automatically.",
        "enum Icon: String, CaseIterable {",
    ]
    width = max(len(c) for c, _, _, _ in ICONS)
    for case, name, weight, was in ICONS:
        lines.append(f"    /// Phosphor `{name}` ({weight}) — was `{was}`.")
        lines.append(f'    case {case.ljust(width)} = "{asset_name(name, weight)}"')
    lines += [
        "}",
        "",
        "extension Image {",
        "    /// The only way an icon enters the app (§5, I1).",
        "    init(_ icon: Icon) {",
        "        self.init(icon.rawValue)",
        "    }",
        "}",
        "",
        "/// `Label`'s own generic parameter is called `Icon`, which shadows the enum",
        "/// inside the extension below. This alias is how the initialiser still names it.",
        "typealias IconName = Icon",
        "",
        "extension Label where Title == Text, Icon == Image {",
        "    /// `Label(\"Delete\", icon: .trash)` — the Phosphor counterpart of",
        "    /// `Label(_:systemImage:)`, used by menus, swipe actions and list rows.",
        "    init(_ titleKey: LocalizedStringKey, icon: IconName) {",
        "        self.init(titleKey, image: icon.rawValue)",
        "    }",
        "",
        "    init(_ title: some StringProtocol, icon: IconName) {",
        "        self.init(title, image: icon.rawValue)",
        "    }",
        "}",
        "",
    ]
    SWIFT_OUT.write_text("\n".join(lines))


def fetch_assets(tmp: Path) -> Path:
    """Sparse-clone just the four weight directories we draw from."""
    repo = tmp / "core"
    subprocess.run(
        ["git", "clone", "--depth", "1", "--filter=blob:none", "--sparse", PHOSPHOR_REPO, str(repo)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        # Cone mode always keeps the repo's root files, so LICENSE arrives too.
        ["git", "sparse-checkout", "set", "assets/thin", "assets/regular", "assets/bold", "assets/fill"],
        cwd=repo,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    LICENSE_OUT.parent.mkdir(parents=True, exist_ok=True)
    LICENSE_OUT.write_text((repo / "LICENSE").read_text())
    return repo / "assets"


def main() -> None:
    source = None
    if len(sys.argv) > 2 and sys.argv[1] == "--source":
        source = Path(sys.argv[2])
    with tempfile.TemporaryDirectory() as tmp:
        assets = source or fetch_assets(Path(tmp))
        written = write_catalog(assets)
    write_swift()
    print(f"{len(written)} symbolsets -> {CATALOG.relative_to(REPO)}")
    print(f"Icon enum      -> {SWIFT_OUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
