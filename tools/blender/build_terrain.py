"""
build_terrain.py — Procedural Triad Chess battlefield for Blender 4.2+.

Generates a gameplay-first diorama (board + plateau + island + props) whose
coordinates match the LÖVE/Menori client exactly, then optionally exports a
.glb that Menori's glTFLoader can read.

Usage
  • Blender MCP  : ask Claude to run this file with `execute_blender_code`
                   (paste the file content; tweak CONFIG first).
  • Headless     : blender --background --python tools/blender/build_terrain.py -- \
                     --layout single --export client/assets/models/terrain_single.glb
  • Text editor  : open in Blender's Scripting tab, Run Script.

Coordinate contract (see client/src/rendering/scene.lua)
  Menori (Y-up)  : cell(col,row) = ((col-3)*CELL, 0, (row-4)*CELL)
  Blender (Z-up) : cell(col,row) = ((col-3)*CELL, -(row-4)*CELL, 0)
  The glTF exporter (+Y up) maps Blender (x, y, z) -> glTF (x, z, -y), so the
  exported file lands on the client's grid with no extra transform.
  Tile tops sit at exactly z = 0: the client's mouse picking intersects y = 0.

Design rules enforced here (docs/terrain_design.md)
  R1  Nothing overlaps the playable footprint above z = 0.
  R2  Zones are readable from colour alone: south base / row 4 / north base.
  R3  Every gameplay-relevant object has a stable name + glTF extras so the
      client can find and restyle it (highlight, anti-stagnation closure…).
  R4  Deterministic: same CONFIG + seed -> same scene.
"""

from __future__ import annotations

import math
import random
import sys

import bpy  # must precede bmesh when run via the standalone `bpy` wheel
import bmesh
from mathutils import Vector, noise

# ─── CONFIG ──────────────────────────────────────────────────────────────────
CONFIG = {
    "layout": "single",   # "single" (Phase 1) | "triad_ring" | "triad_line"
    "seed": 7,
    "cell": 1.1,          # world units between cell centres (scene.lua CELL)
    "cols": 5,
    "rows": 7,
    "tile_size": 0.96,    # visual tile width; gap = cell - tile_size
    "tile_thickness": 0.14,
    "plateau_margin": 0.55,
    "island_radius": 9.0,     # per board, in world units
    "prop_count": 26,         # rocks per board
    "export_path": "",        # "" = no export; absolute or //relative path
}

# Colours mirror client/src/rendering/models.lua so the .glb reads the same
# as the primitive renderer until a real art pass happens.
PALETTE = {
    "tile_south": (0.65, 0.72, 0.85),
    "tile_north": (0.85, 0.65, 0.62),
    "tile_neutral": (0.60, 0.72, 0.60),
    "tile_light_mix": 0.12,       # checker contrast inside each zone
    "plateau": (0.28, 0.20, 0.16),
    "trim_south": (0.20, 0.45, 0.80),
    "trim_north": (0.85, 0.25, 0.20),
    "rune": (0.55, 0.95, 0.70),
    "grass": (0.23, 0.33, 0.19),
    "dirt": (0.32, 0.26, 0.19),
    "cliff": (0.30, 0.28, 0.27),
    "rock": (0.42, 0.40, 0.38),
    "bridge": (0.40, 0.33, 0.25),
}

FILES = "abcde"
COLLECTION_ROOT = "TriadTerrain"


# ─── Small helpers ───────────────────────────────────────────────────────────
def parse_cli(cfg: dict) -> dict:
    """Allow `blender ... --python build_terrain.py -- --layout x --export y`."""
    if "--" not in sys.argv:
        return cfg
    args = sys.argv[sys.argv.index("--") + 1:]
    out = dict(cfg)
    for flag, key, cast in (("--layout", "layout", str), ("--seed", "seed", int),
                            ("--export", "export_path", str)):
        if flag in args:
            out[key] = cast(args[args.index(flag) + 1])
    return out


def clear_previous() -> None:
    root = bpy.data.collections.get(COLLECTION_ROOT)
    if root is None:
        return
    for coll in list(root.children_recursive) + [root]:
        for obj in list(coll.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(coll)
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def make_collection(name: str, parent: bpy.types.Collection) -> bpy.types.Collection:
    coll = bpy.data.collections.new(name)
    parent.children.link(coll)
    return coll


_materials: dict[str, bpy.types.Material] = {}


def material(name: str, rgb: tuple[float, float, float], *, roughness: float = 0.8,
             emission: float = 0.0) -> bpy.types.Material:
    key = f"TC_{name}"
    if key in _materials:
        return _materials[key]
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    mat.diffuse_color = (*rgb, 1.0)  # viewport solid mode
    _materials[key] = mat
    return mat


def box_object(name: str, size: tuple[float, float, float], center: Vector,
               mat: bpy.types.Material, coll: bpy.types.Collection,
               bevel: float = 0.0) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = center
    obj.data.materials.append(mat)
    coll.objects.link(obj)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    return obj


def tag(obj: bpy.types.Object, **extras) -> None:
    """Custom properties become glTF `extras` (export_extras=True)."""
    for k, v in extras.items():
        obj[k] = v


# ─── Board geometry ──────────────────────────────────────────────────────────
def cell_local(col: int, row: int, cfg: dict) -> Vector:
    """Blender-space centre of (col,row) for a board at the origin."""
    return Vector(((col - 3) * cfg["cell"], -(row - 4) * cfg["cell"], 0.0))


def zone_of(row: int, rows: int) -> str:
    mid = (rows + 1) // 2
    if row < mid:
        return "south"
    if row > mid:
        return "north"
    return "neutral"


def tile_color(col: int, row: int, cfg: dict) -> tuple[str, tuple[float, float, float]]:
    zone = zone_of(row, cfg["rows"])
    base = PALETTE[f"tile_{zone}"]
    light = (col + row) % 2 == 0
    k = PALETTE["tile_light_mix"] * (1 if light else -1)
    rgb = tuple(min(1.0, max(0.0, c + k)) for c in base)
    return f"tile_{zone}_{'light' if light else 'dark'}", rgb


def build_board(board_id: str, cfg: dict, parent: bpy.types.Collection,
                origin: Vector, yaw: float) -> bpy.types.Object:
    """One 5x7 board + plateau + zone trims, parented to an empty."""
    coll = make_collection(f"Board_{board_id}", parent)
    anchor = bpy.data.objects.new(f"board_{board_id}", None)
    anchor.empty_display_type = "PLAIN_AXES"
    anchor.location = origin
    anchor.rotation_euler = (0.0, 0.0, yaw)
    coll.objects.link(anchor)
    tag(anchor, tc_kind="board", board_id=board_id)

    cell, cols, rows = cfg["cell"], cfg["cols"], cfg["rows"]
    t = cfg["tile_thickness"]

    # R1: tile tops at z = 0 exactly.
    for col in range(1, cols + 1):
        for row in range(1, rows + 1):
            mat_name, rgb = tile_color(col, row, cfg)
            obj = box_object(
                f"{board_id}_tile_{FILES[col - 1]}{row}",
                (cfg["tile_size"], cfg["tile_size"], t),
                cell_local(col, row, cfg) + Vector((0, 0, -t / 2)),
                material(mat_name, rgb, roughness=0.65), coll, bevel=0.02,
            )
            obj.parent = anchor
            tag(obj, tc_kind="tile", board_id=board_id, col=col, row=row,
                file=FILES[col - 1], zone=zone_of(row, rows),
                flank=col in (1, cols))

    # Plateau slab under the tiles.
    w = cols * cell + 2 * cfg["plateau_margin"]
    d = rows * cell + 2 * cfg["plateau_margin"]
    slab_h = 0.45
    slab = box_object(f"{board_id}_plateau", (w, d, slab_h),
                      Vector((0, 0, -t - slab_h / 2 + 0.02)),
                      material("plateau", PALETTE["plateau"]), coll, bevel=0.06)
    slab.parent = anchor
    tag(slab, tc_kind="plateau", board_id=board_id)

    # Team trims on the plateau rim: south half blue, north half red,
    # split at row 4 -> side ownership readable at a glance (R2).
    trim_h, trim_w = 0.06, 0.18
    half_d = rows * cell / 2
    for side, sign in (("south", 1), ("north", -1)):
        y_mid = sign * (half_d / 2 + cell / 4)
        length = half_d - cell / 2
        for flank, x in (("west", -(w / 2 - trim_w / 2)), ("east", w / 2 - trim_w / 2)):
            rail = box_object(f"{board_id}_rail_{flank}_{side}", (trim_w, length, trim_h),
                              Vector((x, y_mid, -t + trim_h / 2 - 0.02)),
                              material(f"trim_{side}", PALETTE[f"trim_{side}"], roughness=0.4),
                              coll, bevel=0.015)
            rail.parent = anchor
            # Rails beside columns a/e: client hook for the 12-turn closure.
            tag(rail, tc_kind="rail", board_id=board_id, side=side,
                flank_col=FILES[0] if flank == "west" else FILES[cols - 1])
        # Back-edge trim behind row 1 / row 7.
        y_back = sign * (d / 2 - trim_w / 2)
        back = box_object(f"{board_id}_trim_{side}", (w, trim_w, trim_h),
                          Vector((0, y_back, -t + trim_h / 2 - 0.02)),
                          material(f"trim_{side}", PALETTE[f"trim_{side}"]), coll, bevel=0.015)
        back.parent = anchor
        tag(back, tc_kind="trim", board_id=board_id, side=side)

    # Row 4 rune markers at both flanks: the Invocateur's summoning line and,
    # in 3-board layouts, where the bridges to adjacent boards attach.
    mid_row = (rows + 1) // 2
    for flank, x in (("west", -(w / 2 - 0.15)), ("east", w / 2 - 0.15)):
        rune = box_object(f"{board_id}_rune_{flank}", (0.22, cell * 0.8, 0.08),
                          Vector((x, cell_local(3, mid_row, cfg).y, -t + 0.02)),
                          material("rune", PALETTE["rune"], roughness=0.3, emission=1.5),
                          coll, bevel=0.02)
        rune.parent = anchor
        tag(rune, tc_kind="summon_line_marker", board_id=board_id, flank=flank)

    return anchor


# ─── Island / heightfield ────────────────────────────────────────────────────
def rect_sdf(p: Vector, half_w: float, half_d: float) -> float:
    q = Vector((abs(p.x) - half_w, abs(p.y) - half_d))
    outside = Vector((max(q.x, 0.0), max(q.y, 0.0))).length
    return outside + min(max(q.x, q.y), 0.0)


def build_island(cfg: dict, coll: bpy.types.Collection,
                 boards: list[bpy.types.Object]) -> bpy.types.Object:
    """Floating-island heightfield: flat near boards, low hills further out,
    cliff drop into the void past the island edge (Underlords-style framing)."""
    noise.seed_set(cfg["seed"])
    half_w = cfg["cols"] * cfg["cell"] / 2 + cfg["plateau_margin"]
    half_d = cfg["rows"] * cfg["cell"] / 2 + cfg["plateau_margin"]

    centers = [b.matrix_world.translation.copy() for b in boards]
    inv = [b.matrix_world.inverted() for b in boards]
    lo = Vector((min(c.x for c in centers), min(c.y for c in centers)))
    hi = Vector((max(c.x for c in centers), max(c.y for c in centers)))
    r = cfg["island_radius"]
    size = max(hi.x - lo.x, hi.y - lo.y) + 2 * r + 4
    res = int(size / 0.25)

    mesh = bpy.data.meshes.new("island")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=res, y_segments=res, size=size / 2)
    offset = (lo + hi) / 2
    ground_z = -cfg["tile_thickness"] - 0.30

    for v in bm.verts:
        p = Vector((v.co.x + offset.x, v.co.y + offset.y, 0))
        # Distance to the nearest board footprint (in that board's frame).
        d_board = min(rect_sdf(m @ p, half_w, half_d) for m in inv)
        # Distance to the island outline (union of discs around boards),
        # wobbled by noise so it doesn't read as a perfect circle.
        d_island = min((p - c).length for c in centers) - r
        d_island += 1.4 * noise.noise(p * 0.18)

        z = ground_z
        if d_board > 1.2:
            # R1: hills only well away from the board, capped low.
            ramp = min(1.0, (d_board - 1.2) / 3.0)
            z += ramp * max(0.0, 0.55 * noise.noise(p * 0.22 + Vector((0, 0, 3.1))))
        z += 0.04 * noise.noise(p * 1.3)  # micro-relief
        if d_island > 0:
            z -= min(6.0, d_island * 3.5) + 0.5 * abs(noise.noise(p * 0.6))
        v.co.z = z

    # Remove void cells so the island has a clean silhouette.
    bm.verts.ensure_lookup_table()
    doomed = [f for f in bm.faces if all(v.co.z < ground_z - 5.0 for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("island", mesh)
    obj.location = (offset.x, offset.y, 0)
    coll.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True

    # Two materials: grass on top, dirt/cliff on the steep or low parts.
    obj.data.materials.append(material("grass", PALETTE["grass"], roughness=0.95))
    obj.data.materials.append(material("cliff", PALETTE["cliff"], roughness=0.9))
    for poly in mesh.polygons:
        steep = poly.normal.z < 0.75
        low = poly.center.z < ground_z - 0.4
        poly.material_index = 1 if (steep or low) else 0
    tag(obj, tc_kind="island")
    return obj


# ─── Props ───────────────────────────────────────────────────────────────────
def build_props(cfg: dict, coll: bpy.types.Collection,
                boards: list[bpy.types.Object]) -> None:
    rng = random.Random(cfg["seed"])
    half_w = cfg["cols"] * cfg["cell"] / 2 + cfg["plateau_margin"]
    half_d = cfg["rows"] * cfg["cell"] / 2 + cfg["plateau_margin"]
    inv = [b.matrix_world.inverted() for b in boards]
    rock_mat = material("rock", PALETTE["rock"], roughness=0.9)
    ground_z = -cfg["tile_thickness"] - 0.30

    placed = 0
    attempts = 0
    target = cfg["prop_count"] * len(boards)
    while placed < target and attempts < target * 40:
        attempts += 1
        b = rng.choice(boards)
        ang = rng.uniform(0, math.tau)
        dist = rng.uniform(2.0, cfg["island_radius"] - 1.5)
        p = b.matrix_world.translation + Vector((math.cos(ang), math.sin(ang), 0)) * (half_d + dist - 3)
        d_board = min(rect_sdf(m @ p, half_w, half_d) for m in inv)
        if d_board < 1.0:  # R1: keep the footprint + a walkway clear
            continue
        scale = rng.uniform(0.18, 0.45) * min(1.0, d_board / 3.0 + 0.4)
        mesh = bpy.data.meshes.new(f"rock_{placed:03d}")
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        for v in bm.verts:
            v.co *= 1.0 + 0.35 * noise.noise(v.co * 1.7 + Vector((placed, 0, 0)))
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(f"rock_{placed:03d}", mesh)
        obj.location = (p.x, p.y, ground_z + scale * 0.3)
        obj.scale = (scale * rng.uniform(0.9, 1.5), scale * rng.uniform(0.9, 1.4), scale)
        obj.rotation_euler = (0, 0, rng.uniform(0, math.tau))
        obj.data.materials.append(rock_mat)
        coll.objects.link(obj)
        tag(obj, tc_kind="prop")
        placed += 1


# ─── Multi-board layouts (open design question §8.3 — proposals only) ────────
def board_placements(cfg: dict) -> list[tuple[str, Vector, float]]:
    cell, cols, rows = cfg["cell"], cfg["cols"], cfg["rows"]
    board_w = cols * cell + 2 * cfg["plateau_margin"]
    board_d = rows * cell + 2 * cfg["plateau_margin"]
    layout = cfg["layout"]
    if layout == "single":
        return [("P1", Vector((0, 0, 0)), 0.0)]
    if layout == "triad_line":
        gap = board_w + 2.4
        return [(f"P{i + 1}", Vector(((i - 1) * gap, 0, 0)), 0.0) for i in range(3)]
    if layout == "triad_ring":
        # Boards radial, north ends (row 7) pointing at a shared centre.
        # Adjacent boards' row-4 flanks face each other across a bridge.
        radius = board_d / 2 + board_w * 0.9
        out = []
        for i in range(3):
            a = math.radians(-90 + i * 120)  # P1 south of centre
            pos = Vector((math.cos(a), math.sin(a), 0)) * radius
            yaw = a - math.pi / 2  # local +Y (row 1 side) points outward
            out.append((f"P{i + 1}", pos, yaw))
        return out
    raise ValueError(f"unknown layout {layout!r}")


def build_bridges(cfg: dict, coll: bpy.types.Collection,
                  boards: list[bpy.types.Object]) -> None:
    """Cosmetic links between row-4 rune markers of adjacent boards
    (P1<->P2, P2<->P3, P3<->P1). Pieces never cross them (rules v2);
    they signpost board adjacency for summons and Ultimate Teleportation."""
    if len(boards) < 3:
        return
    names = {b.name: b for b in boards}
    half_w = cfg["cols"] * cfg["cell"] / 2 + cfg["plateau_margin"]
    half_d = cfg["rows"] * cfg["cell"] / 2 + cfg["plateau_margin"]
    for a, b in (("P1", "P2"), ("P2", "P3"), ("P3", "P1")):
        ba, bb = names[f"board_{a}"], names[f"board_{b}"]
        # Pick the closest pair of rune markers between the two boards.
        runes_a = [o for o in ba.children if o.get("tc_kind") == "summon_line_marker"]
        runes_b = [o for o in bb.children if o.get("tc_kind") == "summon_line_marker"]
        pa, pb = min(((ra.matrix_world.translation, rb.matrix_world.translation)
                      for ra in runes_a for rb in runes_b),
                     key=lambda pair: (pair[0] - pair[1]).length)
        mid = (pa + pb) / 2
        vec = pb - pa
        # triad_line: P3<->P1 would run under P2 — no honest straight bridge.
        others = [o for o in boards if o not in (ba, bb)]
        if any(rect_sdf(o.matrix_world.inverted() @ mid, half_w, half_d) < 0 for o in others):
            continue
        obj = box_object(f"bridge_{a}_{b}", (0.5, vec.length, 0.08),
                         Vector((mid.x, mid.y, pa.z - 0.02)),
                         material("bridge", PALETTE["bridge"]), coll, bevel=0.02)
        obj.rotation_euler = (0, 0, math.atan2(vec.y, vec.x) - math.pi / 2)
        tag(obj, tc_kind="bridge", boards=f"{a}-{b}")


# ─── Export ──────────────────────────────────────────────────────────────────
def export_glb(path: str, root: bpy.types.Collection) -> None:
    path = bpy.path.abspath(path)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in root.all_objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,        # Menori is Y-up
        export_apply=True,      # bake bevel modifiers
        export_extras=True,     # custom props -> node extras (R3)
        export_cameras=False,
        export_lights=False,
    )
    print(f"[triad-terrain] exported {path}")


# ─── Entry point ─────────────────────────────────────────────────────────────
def build(cfg: dict) -> bpy.types.Collection:
    _materials.clear()
    clear_previous()
    root = bpy.data.collections.new(COLLECTION_ROOT)
    bpy.context.scene.collection.children.link(root)
    boards_coll = make_collection("Boards", root)
    terrain_coll = make_collection("Terrain", root)
    props_coll = make_collection("Props", root)

    boards = [build_board(bid, cfg, boards_coll, pos, yaw)
              for bid, pos, yaw in board_placements(cfg)]
    bpy.context.view_layer.update()  # resolve matrix_world before sampling
    build_bridges(cfg, boards_coll, boards)
    build_island(cfg, terrain_coll, boards)
    build_props(cfg, props_coll, boards)

    if cfg["export_path"]:
        export_glb(cfg["export_path"], root)
    print(f"[triad-terrain] layout={cfg['layout']} seed={cfg['seed']} "
          f"objects={len(root.all_objects)}")
    return root


build(parse_cli(CONFIG))
