#!/usr/bin/env python3
"""Check Android-only symbol assets; --update rebuilds them from pinned Google Material SVGs."""
import argparse
import json
from pathlib import Path
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / "Android/MaterialIcons.json").read_text())
RESOURCES = ROOT / "Android/app/src/main/assets/spliit/ui/Resources"
CATALOG = RESOURCES / "AndroidSymbols.xcassets"
SOURCE = f"https://raw.githubusercontent.com/google/material-design-icons/{CONFIG['sourceCommit']}"


def paths(element, fill="black"):
    """Skip's symbol reader accepts filled paths only, so expand Material's basic shapes."""
    assert "transform" not in element.attrib, "Flatten transforms before importing this icon"
    fill = element.get("fill", fill)
    tag = element.tag.rsplit("}", 1)[-1]
    if tag in ("svg", "g"):
        return [path for child in element for path in paths(child, fill)]
    if fill == "none":
        return []
    assert element.get("stroke", "none") == "none", "Expand strokes before importing this icon"
    if tag == "path":
        return [element.attrib["d"]]
    if tag == "rect":
        assert not element.get("rx") and not element.get("ry"), "Rounded rect needs expansion"
        x, y = float(element.get("x", 0)), float(element.get("y", 0))
        w, h = float(element.attrib["width"]), float(element.attrib["height"])
        return [f"M{x:g},{y:g}h{w:g}v{h:g}h{-w:g}Z"]
    if tag == "circle":
        x, y, r = (float(element.attrib[key]) for key in ("cx", "cy", "r"))
        return [f"M{x-r:g},{y:g}a{r:g},{r:g} 0 1,0 {2*r:g},0a{r:g},{r:g} 0 1,0 {-2*r:g},0Z"]
    if tag == "polygon":
        return ["M" + element.attrib["points"].strip().replace(" ", "L") + "Z"]
    raise ValueError(f"Unsupported SVG element: {tag}")


def fetch(path):
    with urllib.request.urlopen(SOURCE + "/" + path, timeout=30) as response:
        return response.read()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    # Exercise the shape conversions the imported icons actually use, without network access.
    shapes = ET.fromstring('<svg><rect width="24" height="24" fill="none"/><rect x="2" y="3" width="4" height="5"/><circle cx="6" cy="7" r="2"/><polygon points="0,0 1,0 1,1"/></svg>')
    assert paths(shapes) == ["M2,3h4v5h-4Z", "M4,7a2,2 0 1,0 4,0a2,2 0 1,0 -4,0Z", "M0,0L1,0L1,1Z"]
    for symbol, source in CONFIG["symbols"].items():
        folder = CATALOG / (symbol + ".symbolset")
        if args.update:
            original = ET.fromstring(fetch(f"src/{source}/materialicons/24px.svg"))
            converted = paths(original)
            assert converted, symbol
            svg = ET.Element("svg", {"xmlns": "http://www.w3.org/2000/svg", "viewBox": "0 0 24 24"})
            svg.append(ET.Comment(f" Google Material Icons, Apache-2.0. Source: {source} at {CONFIG['sourceCommit']}. Modified: shapes expanded to paths and wrapped for Skip. "))
            group = ET.SubElement(ET.SubElement(svg, "g", {"id": "Symbols"}), "g", {"id": "Regular-M"})
            for data in converted:
                ET.SubElement(group, "path", {"d": data})
            folder.mkdir(parents=True, exist_ok=True)
            ET.ElementTree(svg).write(folder / "icon.svg", encoding="utf-8", xml_declaration=True)
            (folder / "Contents.json").write_text(json.dumps({"symbols": [{"filename": "icon.svg", "idiom": "universal"}], "info": {"author": "spliit", "version": 1}}, indent=2) + "\n")
        contents = json.loads((folder / "Contents.json").read_text())
        svg = ET.parse(folder / contents["symbols"][0]["filename"]).getroot()
        assert svg.find(".//{*}g[@id='Regular-M']") is not None, symbol
        assert any(node.get("d") for node in svg.iter() if node.tag.endswith("}path")), symbol
    if args.update:
        (RESOURCES / "MaterialIcons-LICENSE.txt").write_bytes(fetch("LICENSE"))
    assert "Apache License" in (RESOURCES / "MaterialIcons-LICENSE.txt").read_text()
    assert {p.stem for p in CATALOG.glob("*.symbolset")} == set(CONFIG["symbols"])
    print(f"PASS: {len(CONFIG['symbols'])} Android symbol assets, SVG shape conversion, and license")


if __name__ == "__main__":
    main()
