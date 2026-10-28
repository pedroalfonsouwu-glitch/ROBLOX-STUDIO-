"""Convert the included CC0 tree to Roblox WedgeParts using only the standard library."""
from pathlib import Path
import json
import sys
import math
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/original/tree_pineSmallD.obj"
OUTPUT = ROOT / "assets/roblox/Tree.rbxmx"

def add(a, b): return tuple(x + y for x, y in zip(a, b))
def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def scale(a, k): return tuple(x * k for x in a)
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def norm(a): return math.sqrt(dot(a, a))
def unit(a): return scale(a, 1 / norm(a))

def read_obj(path):
    vertices, faces, material = [], [], ""
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        fields = raw.strip().split()
        if not fields: continue
        if fields[0] == "v": vertices.append(tuple(map(float, fields[1:4])))
        elif fields[0] == "usemtl": material = fields[1]
        elif fields[0] == "f":
            ids = [int(v.split("/")[0]) for v in fields[1:]]
            points = [vertices[i - 1 if i > 0 else i] for i in ids]
            faces.extend((points[0], points[i], points[i+1], material) for i in range(1, len(points)-1))
    colors, current = {}, ""
    for raw in path.with_suffix(".mtl").read_text(encoding="utf-8-sig").splitlines():
        fields = raw.strip().split()
        if not fields: continue
        if fields[0] == "newmtl": current = fields[1]
        elif fields[0] == "Kd": colors[current] = tuple(map(float, fields[1:4]))
    return vertices, faces, colors

def wedges_for_triangle(a, b, c):
    # The longest edge is the base; its perpendicular projection splits the triangle.
    pairs = [(norm(sub(b,c)), a,b,c), (norm(sub(a,c)), b,a,c), (norm(sub(a,b)), c,a,b)]
    _, apex, left, right = max(pairs, key=lambda row: row[0])
    along = unit(sub(right, left))
    outward = cross(sub(right, apex), sub(left, apex))
    if norm(outward) < 1e-7: return []
    normal = unit(outward)
    vertical = unit(cross(along, normal))
    height = abs(dot(sub(left, apex), vertical))
    result = []
    for endpoint, sign in ((left, 1), (right, -1)):
        length = abs(dot(sub(endpoint, apex), along))
        if height < 0.001 or length < 0.001: continue
        center = scale(add(apex, endpoint), 0.5)
        result.append((center, (0.05, height, length),
                       scale(normal, sign), vertical, scale(along, sign)))
    return result

def property_value(parent, tag, name, value):
    node = ET.SubElement(parent, tag, name=name)
    node.text = str(value)
    return node

def vector_property(parent, tag, name, value, axes):
    node = ET.SubElement(parent, tag, name=name)
    for axis, number in zip(axes, value): ET.SubElement(node, axis).text = f"{number:.9g}"
    return node

def convert():
    vertices, faces, colors = read_obj(SOURCE)
    low_y, high_y = min(v[1] for v in vertices), max(v[1] for v in vertices)
    factor = 20 / (high_y - low_y)
    doc = ET.Element("roblox", version="4")
    tree = ET.SubElement(doc, "Item", {"class": "Model", "referent": "TreeCC0"})
    props = ET.SubElement(tree, "Properties")
    property_value(props, "string", "Name", "Tree")
    triangle_count, wedge_count, removed = 0, 0, 0
    for original_a, original_b, original_c, material in faces:
        face_normal = cross(sub(original_b, original_a), sub(original_c, original_a))
        if norm(face_normal) < 1e-10: continue
        # Omit downward interior caps; these cannot be seen from a walking camera.
        if unit(face_normal)[1] < -0.98:
            removed += 1
            continue
        points = [scale((v[0], v[1]-low_y, v[2]), factor)
                  for v in (original_a, original_b, original_c)]
        triangle_count += 1
        for center, dimensions, axis_x, axis_y, axis_z in wedges_for_triangle(*points):
            wedge_count += 1
            item = ET.SubElement(tree, "Item", {"class": "WedgePart", "referent": f"W{wedge_count}"})
            props = ET.SubElement(item, "Properties")
            property_value(props, "string", "Name", material)
            for name, value in (("Anchored","true"),("CanCollide","false"),("CanTouch","false"),("CanQuery","false"),("CastShadow","true")):
                property_value(props, "bool", name, value)
            vector_property(props, "Vector3", "Size", dimensions, ("X","Y","Z"))
            vector_property(props, "Color3", "Color", colors.get(material,(0.2,0.5,0.3)), ("R","G","B"))
            property_value(props, "token", "Material", 256)
            property_value(props, "token", "TopSurface", 0)
            property_value(props, "token", "BottomSurface", 0)
            frame = ET.SubElement(props, "CoordinateFrame", name="CFrame")
            for name, value in zip(("X","Y","Z"), center):
                ET.SubElement(frame, name).text = f"{value:.9g}"
            for row in range(3):
                for col, axis in enumerate((axis_x,axis_y,axis_z)):
                    ET.SubElement(frame, f"R{row}{col}").text = f"{axis[row]:.9g}"
            # Validate orthonormal, right-handed rotations before serializing.
            assert abs(dot(axis_x,axis_y)) < 1e-6
            assert abs(dot(axis_y,axis_z)) < 1e-6
            assert abs(dot(cross(axis_x,axis_y),axis_z)-1) < 1e-6
    ET.indent(doc)
    report = {"source":str(SOURCE.relative_to(ROOT)), "source_triangles":len(faces),
              "visible_triangles":triangle_count, "omitted_caps":removed,
              "wedge_parts":wedge_count, "height_studs":20,
              "output":str(OUTPUT.relative_to(ROOT))}
    xml = ET.tostring(doc, encoding="unicode")
    if "--stdout" in sys.argv:
        print(json.dumps({"xml": xml, "report": report}))
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(xml, encoding="utf-8")
        (ROOT / "assets/conversion.json").write_text(json.dumps(report,indent=2)+"\n", encoding="utf-8")
        print(json.dumps(report,indent=2))

if __name__ == "__main__": convert()
