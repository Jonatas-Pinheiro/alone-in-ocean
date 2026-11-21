# Building & Placement Kit for Godot 4

Let your players build, in 2D or 3D: **on a grid** (city builders, farms, Minecraft-like blocks, compatible with **TileMapLayer** and **GridMap**), **freely on any surface** (furniture, decorations, props on walls), and with **snap points** (Valheim / Rust style walls, floors and roofs that click together). One API for all of it, with green / red ghosts, rotation, flip, drags, placement rules, costs and refunds, move / demolish / undo, **structural integrity**, **upgrades in place**, **health and repairs**, **blueprints**, **autotiling**, **floor levels**, navigation rebakes and saves.

**Pay what you want, from $0.** Code under MIT. Made by Benny, with AI tools. Official page, downloads and playable web demo: https://banc-essai.site-testeurs.workers.dev/building-kit/
More kits, and our game prototypes waiting for testers: https://banc-essai.site-testeurs.workers.dev/

Godot 4.5 or later (tested on 4.7). Pure GDScript, no `@tool` script, nothing runs in the editor. 81 automated tests, load-tested with 5 000 pieces. Works alone; uses [Inventory Kit](https://banc-essai.site-testeurs.workers.dev/inventory-kit/) for costs when it is there (included in this download).

## Contents

1. [What is inside](#what-is-inside)
2. [Five-minute setup](#five-minute-setup)
3. [How it fits together](#how-it-fits-together)
4. [Tutorial 1: a survival base (sockets, costs, stability)](#tutorial-1-a-survival-base)
5. [Tutorial 2: a city builder on a TileMapLayer (drags, autotiling, influence)](#tutorial-2-a-city-builder-on-a-tilemaplayer)
6. [Tutorial 3: furnishing a house (free placement, fine rotation, floors)](#tutorial-3-furnishing-a-house)
7. [More recipes](#more-recipes): your own rule, upgrades, health, blueprints, navigation, saves, MultiMesh
8. [Inventory Kit and Crafting Kit](#inventory-kit-and-crafting-kit)
9. [Controls](#controls)
10. [Performance](#performance)
11. [API reference](#api-reference)
12. [FAQ](#faq)
13. [Licenses](#licenses)

## What is inside

- **Buildables** (`PKBuildable`, a resource per kind of piece): stable id, name, category, icon (or rendered automatically), 2D or 3D scene, size in cells, cost, refund %, rotation step, flip, tilt (6 directions), stacking, layers, sockets, drag mode, rules, structure, upgrade, health.
- **Three ways to snap**, per piece, tried in order: **sockets** (`PKSocket`: typed snap points with a facing; the nearest compatible one wins, the player's rotation picks between sockets that overlap), **grid** (`PKGrid`: N × M footprints that stay aligned and under the cursor when turned; levels in height), **surface** (free placement where the cursor hits, optionally turned to the surface normal: paintings on walls).
- **Ghosts**: a real tinted transparent material in 3D (shader tint in 2D), green / red, amber when barely stable, footprint on the ground, grid lines around the cursor.
- **Rotation** by steps you choose (90°, 45°, 15°, fine 5° with Ctrl), tilt through the 6 directions, flip for left / right pieces. On sockets, rotation keeps the snap point (a wall flips to face the other way on the same edge).
- **Drag building**: lines (walls, fences), L-shaped paths (roads), filled rectangles (floors, fields) and outlines (enclosures), with the total cost shown and only the free cells built, in one payment and one undo step.
- **Placement rules** (`PKPlacementRule`, add your own in 5 lines): overlap (per layer), bounds, zones (TileMapLayer custom data, GridMap item names, or your function), slope, surface kind (floor / wall / ceiling), stacking, needs a foundation, limits per piece or tag, "must be within N cells of" (roads, markets, wells), **structural stability**, and a function rule. Every refusal has a reason id and a player text (English and French included).
- **Costs** (`PKCost`): Inventory Kit containers in one atomic transaction (`PKInventoryCost`, nothing ever lost or duplicated), a plain wallet (`PKWalletCost`), your own functions (`PKCallableCost`), or free. Refunds when demolishing (% per piece), full refunds on undo, refusals when the bag is full (or leftovers reported to drop them in the world).
- **Modes**: build, move, demolish (with what would collapse highlighted), select (click, Shift + click, drag a box), upgrade, repair. **Undo** of every action.
- **Structural integrity** (optional, Valheim / Rust style): stability flows up from the ground; weaker materials carry less; too weak is refused; demolishing a support brings down what becomes too weak; a stability view colours every piece.
- **Upgrades in place** (wood → stone → iron): same uid, pose and sockets, what rests on it stays, cost paid, refunds and undo follow.
- **Health**: damage, destruction with a share refunded and optional loot, cascades, repairs that cost a share of the price; signals `damaged`, `destroyed`, `repaired`.
- **Blueprints** (`PKBlueprint`): select pieces, save them, put the whole group down again turned by quarter turns, for its total cost; JSON or .tres.
- **Autotiling** (`PKAutotile`): roads, fences, pipes pick their straight / corner / T / cross / end scene from their neighbours.
- **Floor levels**: Page Up / Page Down, upper floors hidden (and let through by the cursor) below.
- **Navigation**: NavigationRegion3D / 2D rebaked on a thread after building, once for a burst of changes.
- **Saves**: `to_data()` / `load_data()` (JSON-friendly) by stable buildable id, with a format version; pieces whose buildable was removed are kept aside and written back, so nothing is lost when you rename or remove a piece for a while.
- **Interface** (`PKBuildHUD`): catalog by category with costs and unavailable pieces greyed out, a Blueprints tab, mode bar, info box (cost or drag total, why it is red, health, stability, controls), messages. Mouse, keyboard, gamepad (virtual cursor) and touch.
- **Feel**: pieces pop in, sounds for place / refuse / demolish / upgrade / repair / rotate (generated by `tools/gen_sounds.py`, ours, MIT), dust when pieces come down.
- **Performance**: spatial hashing for overlaps, picking and sockets; indexes for counts and supports; nothing walks every piece each frame; optional **MultiMesh** rendering of repeated pieces.

## Five-minute setup

1. Copy `addons/building_kit/` into your project (and `addons/inventory_kit/` if you want Inventory Kit costs). Enable the plugin if you like (Project > Project Settings > Plugins); the classes work without it.
2. Make a piece: a scene whose origin is the centre of its footprint, on the ground (add a collision shape in 3D so other pieces can rest on it).
3. Make its buildable (Inspector: New Resource > PKBuildable), or in code:

```gdscript
var crate := PKBuildable.make(&"crate", "Crate", Vector2i(1, 1), {&"wood_log": 2})
crate.scene = preload("res://pieces/crate.tscn")
crate.category = &"storage"
var catalog := PKCatalog.make([crate])
```

4. Add the build system and the interface to your level (3D here; `PKBuildSystem2D` works the same):

```gdscript
var system := PKBuildSystem3D.new()
system.catalog = catalog
system.grid_cell_size = Vector3(1, 1, 1)
add_child(system)                       # it finds the current camera by itself
var layer := CanvasLayer.new()
add_child(layer)
var hud := PKBuildHUD.new()
layer.add_child(hud)
hud.bind(system)
```

5. Put your ground on physics layer 1 (pieces go on layer 2; both are settings). Run: pick the crate at the bottom, click to build, R to turn, 3 then click to demolish, Ctrl+Z to undo.

For costs from a bag: `system.set_cost_handler(PKInventoryCost.make([bag]))`. Without it, building is free.

## How it fits together

```
PKCatalog ── PKBuildable (scene, cells, cost, sockets, rules...)
    │
PKBuilder (no node: works in tests, on a server)
    ├── PKLayout      placed pieces (PKPlacement) + spatial index
    ├── PKGrid        cells, levels, bounds
    ├── rules         PKPlacementRule ... (first refusal wins)
    ├── cost_handler  PKCost / PKInventoryCost / PKWalletCost / PKCallableCost
    └── undo, saves, stability, upgrades, health, blueprints
PKBuildController   mode, chosen piece, rotation, ghost, drag, selection, level (no node)
PKBuildSystem3D / PKBuildSystem2D   input -> PKAim, ghosts, scenes, MultiMesh, levels, sounds, dust
PKBuildHUD          PKCatalogPanel + PKModeBar + info box
```

- **The core never touches nodes.** `PKBuilder.preview(buildable, aim, angle)` answers "where would it go and may it be built?" with a `PKPreview` (pose, valid, reason, cost). `place()`, `place_many()`, `remove()`, `move()`, `upgrade()`, `damage()`, `repair()`, `undo()` do the work and emit signals.
- **Coordinates are the same in 2D and 3D**: X and Z are the ground (2D X and Y), Y is up, angles are degrees clockwise seen from above. A 2D piece at (x, y) is stored at (x, 0, y), so rules, saves and tests are shared.
- **A `PKAim`** is "where the player points": a point, the surface normal, the piece under it. The nodes make them from the mouse, the stick or a touch; your code can make them too (bots, VR, scripted building).

## Tutorial 1: a survival base

Foundations on the ground, walls on their edges, floors on wall tops, roofs on top. Costs come from an Inventory Kit bag. See the "Survival base" demo (`demo/survival/`).

**1. Sockets.** A socket is a point of a piece with a facing (degrees, 0 = +Z). Sockets with `snaps_to` let their own piece attach onto placed sockets of those types.

```gdscript
# Foundation 2 × 2: four edges at the top (y = 0.4), facing out. They let walls attach,
# and other foundations attach edge to edge (OPPOSITE facing). holds = false: a foundation
# beside another stands by itself (demolishing one does not bring the other down).
var foundation := PKBuildable.make(&"foundation", "Foundation", Vector2i.ONE, {&"stone": 6})
foundation.size = Vector3(2, 0.4, 2)
foundation.tags = [&"foundation"]
foundation.snap = PKBuildable.Snap.SOCKET | PKBuildable.Snap.GRID   # sockets first, then the grid
for side in [[Vector3(0, 0.4, 1), 0.0], [Vector3(1, 0.4, 0), 270.0], [Vector3(0, 0.4, -1), 180.0], [Vector3(-1, 0.4, 0), 90.0]]:
	var edge := PKSocket.make(&"foundation_edge", side[0], side[1], [&"foundation_edge"], PKSocket.Facing.OPPOSITE)
	edge.holds = false
	foundation.sockets.append(edge)

# Wall: 1.8 long (not 2, so two walls meeting at a corner do not overlap), its bottom
# attaches onto foundation edges and wall tops facing the same way; the player can flip it.
var wall := PKBuildable.make(&"wall", "Wall", Vector2i.ONE, {&"wood_log": 4})
wall.size = Vector3(1.8, 3, 0.2)
wall.snap = PKBuildable.Snap.SOCKET
wall.needs_foundation = true
var bottom := PKSocket.make(&"wall_bottom", Vector3.ZERO, 0.0, [&"foundation_edge", &"wall_top"])
bottom.free_rotation_step = 180.0
wall.sockets = [bottom, PKSocket.make(&"wall_top", Vector3(0, 3, 0))]

# Roof: its eave attaches on a wall top; two roofs from opposite walls meet at the ridge.
var roof := PKBuildable.make(&"roof", "Roof", Vector2i.ONE, {&"wood_log": 3})
roof.size = Vector3(1.8, 1, 1)
roof.snap = PKBuildable.Snap.SOCKET
roof.sockets = [PKSocket.make(&"roof_eave", Vector3(0, 0, 0.5), 0.0, [&"wall_top"])]
```

When several sockets are near the cursor (the shared edge of two foundations has one on each side), the nearest wins, then the one turned closest to the player's rotation, preferring a free one: the player turns the piece to choose.

**2. The system and the bag.**

```gdscript
var system := PKBuildSystem3D.new()
system.catalog = PKCatalog.make([foundation, wall, roof])
system.grid_cell_size = Vector3(2, 3, 2)
add_child(system)
system.set_cost_handler(PKInventoryCost.make([bag]))   # IKContainer(s): taken at once or not at all
```

**3. Stability (optional).**

```gdscript
system.builder.stability_enabled = true
system.builder.min_stability = 0.15
wall.stability_loss = 0.2     # each wall on a wall keeps 80 % of the stability below it
wall.strength = 0.9           # a wooden wall never carries more than 90 %
```

The ghost turns amber as it gets weak and red under the minimum ("Too far from a support"). `system.stability_view = true` colours every piece.

## Tutorial 2: a city builder on a TileMapLayer

Roads dragged as L-shaped paths that join up, houses that must touch a road, shops within 6 cells of a market, bridges only over water. See `demo/city/`.

**1. Zones from the tiles.** Add a custom data layer named `zone` (String) to your TileSet and fill it ("grass", "water", "sand"). Give the layer to the system:

```gdscript
var system := PKBuildSystem2D.new()
system.tile_map = $Ground          # cell size, origin and zones come from it
system.bounds = Rect2i(0, 0, 44, 30)
system.catalog = catalog
add_child(system)
system.set_cost_handler(PKWalletCost.make({&"gold": 2500}))
```

**2. Drags and autotiling.**

```gdscript
var road := PKBuildable.make(&"road", "Road", Vector2i.ONE, {&"gold": 10})
road.tags = [&"road"]
road.drag = PKBuildable.Drag.PATH          # along X, then along Z
road.allowed_zones = [&"grass", &"sand"]
road.autotile_tag = &"road"
for shape in PKAutotile.SHAPES:            # single, end, straight, corner, t, cross
	road.variant_scenes[shape] = load("res://city/road_%s.tscn" % shape)
```

Draw each shape with its connections towards +X (end), along X (straight), +X and +Y (corner), +X, +Y and -X (T); the system turns them. `PKAutotile.mask_of()` and `shape_of()` let you do your own.

**3. Influence.**

```gdscript
house.needs_nearby_tag = &"road"           # touching a road (1 cell)
shop.rules = [PKNearbyRule.make(&"market", 6, &"needs_market")]   # and within 6 cells of a market
PKText.reason_texts[&"needs_market"] = "Must be within 6 cells of a plaza."
```

While a shop is placed, the areas around every market are drawn.

## Tutorial 3: furnishing a house

Free placement with fine rotation, lamps on tables, rugs under furniture, paintings on walls, two floors. See `demo/interior/`.

```gdscript
var sofa := PKBuildable.make(&"sofa", "Sofa")
sofa.snap = PKBuildable.Snap.SURFACE
sofa.size = Vector3(1.9, 0.85, 0.85)
sofa.rotation_step = 15.0                  # Ctrl + R: system.controller.fine_rotation_step (5°)

var lamp := PKBuildable.make(&"table_lamp", "Table lamp")
lamp.snap = PKBuildable.Snap.SURFACE
lamp.stackable = true                      # may go on other pieces
lamp.supports_on_top = false               # nothing goes on a lamp

var rug := PKBuildable.make(&"rug", "Rug")
rug.layer = 1                              # pieces only collide with their own layer

var painting := PKBuildable.make(&"painting", "Painting")
painting.surface = PKBuildable.Surface.WALL
painting.align_to_normal = true            # modelled flat, facing +Y: it hangs upright

system.builder.world_bounds = AABB(Vector3(-4.1, -0.1, -3.1), Vector3(8.2, 6.2, 6.2))   # stay in the room
system.builder.surface_snap = 0.25        # optional: positions on a 25 cm step
system.max_level = 1                      # Page Up / Page Down
system.level_height = 3.0                 # floors above the current one are hidden
```

## More recipes

**Your own rule.**

```gdscript
class_name FarFromFireRule extends PKPlacementRule
func check(context: PKPlacementContext) -> StringName:
	for piece in context.get_layout().overlapping(context.placement.get_box().grown(3.0)):
		if piece.buildable.has_tag(&"fire"):
			return &"too_close_to_fire"
	return &""
# builder.rules.append(FarFromFireRule.new()), or buildable.rules for one piece.
# PKText.reason_texts[&"too_close_to_fire"] = "Too close to the fire."
```

Quick checks: `builder.rules.append(PKCallableRule.make(func(context): return &"" if ok else &"nope"))`.

**Upgrades.** `wood_wall.upgrade_to = stone_wall` and `wood_wall.upgrade_cost = {&"stone": 4}`. Mode 5 (or `builder.upgrade(uid)`) turns the wall into stone where it stands: same uid and pose, the roof on it stays, `paid` grows (refunds cover the upgrade), health keeps its ratio, undo gives the cost back. Give each tier the same sockets.

**Health.** `wall.max_health = 150`, `destroy_refund_percent = 25`, `loot = {&"nails": 2}`, `repair_cost_percent = 50`. `builder.damage(uid, 40)` from your weapons, storms or raids; at 0 the piece is destroyed (what it holds may collapse) and `destroyed` gives what it left. Mode 6 or `builder.repair(uid)` repairs for `repair_cost(uid)`.

**Blueprints.** Mode 4, drag a box (or Shift + click), then B (or the "Save as blueprint" button): the group appears in the catalog's Blueprints tab. In code: `var bp := builder.make_blueprint(uids, "Hut")`, `system.select_blueprint(bp)`, or `builder.place_many(builder.blueprint_preview(bp, aim, 90.0))`. Save them with `bp.to_data()` / `PKBlueprint.from_data()` or `ResourceSaver.save(bp, "user://hut.tres")`.

**Navigation.** Set `system.navigation_region` (NavigationRegion3D or 2D) and put the pieces under it (the system's `pieces_root`, or groups). After building, it rebakes on a thread a moment later, once for a burst of changes. Use collision shapes as source geometry (`NavigationMesh.geometry_parsed_geometry_type = PARSED_GEOMETRY_STATIC_COLLIDERS`): parsing meshes at run time is slow.

**Saves.**

```gdscript
var text := JSON.stringify(system.to_data())            # pieces by id, what was paid, health
system.load_data(JSON.parse_string(text))               # result.skipped_ids lists unknown ids
```

Keep buildable ids stable once your game is out. Saves carry `"format": "building_kit"` and a `"version"`; newer versions are refused, unknown pieces are kept aside (`keep_unknown_pieces`) and written back.

**MultiMesh.** `buildable.batch_render = true` draws every copy of that piece in one MultiMesh per mesh (fences, floor tiles, walls by the thousand). Each copy keeps a box collision for the cursor; scripts and lights of its scene do not run.

**Without nodes.** Everything works on a `PKBuilder` alone: tests, a dedicated server, procedural villages (`builder.place_at(buildable, position, angle)`).

## Inventory Kit and Crafting Kit

- **Inventory Kit** (included): `PKInventoryCost.make([bag, hotbar])` takes from several containers in one `IKTransaction` and gives refunds back only when everything fits (else the demolition is refused with "No room in your bag", or with `builder.refund_overflow = true` what fits is given and `refund_left_behind(items, position)` lets you drop the rest with Inventory Kit's world items). Icons and names in the catalog come from the item database. The kit does not need Inventory Kit to load: `PKInventoryCost` finds it by name.
- **Crafting Kit** (not included, [free page](https://banc-essai.site-testeurs.workers.dev/crafting-kit/)): it makes the materials buildings cost (logs to planks at a sawmill). To keep one list of recipes, read a building's cost from a crafting recipe:

```gdscript
# A "recipe" per building in your Crafting Kit book, whose ingredients are the cost.
for buildable in catalog.buildables:
	var recipe: CKRecipe = recipe_book.get_recipe(StringName("build_" + buildable.id))
	if recipe != null:
		buildable.cost = recipe.ingredients.duplicate()
```

  Tag ingredients ("#planks", any planks) are Crafting Kit's: for those, build with plain item ids, or wrap your consumption in a `PKCallableCost`. A workbench can also be a buildable with `max_count = 1` whose node opens Crafting Kit's window when selected (`system.selection_changed`).

## Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Build / confirm | Left click, Enter | A |
| Cancel, put back, put the tool away | Right click, Esc | B |
| Rotate / back | R / Shift+R, Shift + wheel (Ctrl: fine) | RB / LB |
| Flip / tilt | F / T | Y / R3 |
| Modes: build, move, demolish, select, upgrade, repair | 1 – 6 | X cycles |
| Undo | Ctrl+Z | Back |
| Previous / next piece, next category | [ / ], Tab | D-pad left / right, down |
| Floor up / down | Page Up / Page Down | D-pad up |
| Save the selection as a blueprint | B | the button |
| Cursor | mouse, arrows | left stick |

Every action is in the Input Map as `pk_*` (added only if your project does not define it): rebind freely. Touch: tap to build, drag for drags, and the Undo / Rotate / Flip / Cancel buttons of the mode bar.

## Performance

Measured by the tests (`tests/building_kit/test_perf.gd`, `test_nodes_advanced.gd`), headless, Godot 4.7, a desktop PC:

| | 1 100 pieces | 5 500 pieces |
|---|---|---|
| Place one piece (rules + cost + index) | 0.07 ms | 0.07 ms |
| Preview under the cursor (sockets + every rule) | 0.58 ms | 0.47 ms |
| Save to JSON | 7 ms | 33 – 43 ms |
| Load from JSON (stability included) | 17 ms | 91 – 102 ms |
| Demolish one piece (support index) | 0.05 ms | 0.07 ms |

With nodes and MultiMesh: loading 5 000 batched foundations (bodies + one MultiMesh) 135 ms, first MultiMesh update 5 ms, aiming with a ghost 0.56 ms per frame. Costs do not grow with the size of the base: overlaps, picking and sockets use a spatial hash (4 m buckets), counts and supports have their own indexes, and nothing walks every piece each frame (the stability view and the repair mode do, when they are on).

## API reference

**Resources**

| Class | What it is |
|---|---|
| `PKBuildable` | A kind of piece. Identity (`id`, `display_name`, `category`, `icon`, `tags`, `in_catalog`), look (`scene`, `cells`, `height`, `size`, `box_offset`, `layer`, `batch_render`, `autotile_tag`, `variant_scenes`), placement (`snap` flags, `can_rotate`, `rotation_step`, `can_tilt`, `can_flip`, `stackable`, `supports_on_top`, `align_to_normal`, `surface`, `max_slope_degrees`, `sockets`, `drag`, `drag_align`), rules (`needs_foundation`, `foundation_tags`, `max_count`, `allowed_zones`, `forbidden_zones`, `needs_nearby_tag`, `nearby_cells`, `rules`), structure (`strength`, `stability_loss`), upgrade (`upgrade_to`, `upgrade_cost`), health (`max_health`, `repair_cost_percent`, `destroy_refund_percent`, `loot`), cost (`cost`, `refund_percent`), `properties`. |
| `PKSocket` | `type`, `position`, `angle`, `snaps_to`, `facing` (SAME, OPPOSITE, ANY), `free_rotation_step`, `holds`. |
| `PKCatalog` | `buildables`, `category_names`; `get_buildable(id)`, `get_categories()`, `in_category()`, `validate()`. |
| `PKGrid` | `cell_size`, `origin`, `snap_height`, `bounds`; `snap()`, `cell_of()`, `cell_center()`, `position_at()`, `footprint()`, `contains()`. |
| `PKBlueprint` | `title`, `entries`; `get_cost(catalog)`, `missing_ids(catalog)`, `to_data()`, `from_data()`. |
| `PKPlacementRule` | `check(context) -> StringName`. Built in: `PKOverlapRule`, `PKBoundsRule`, `PKZoneRule`, `PKSlopeRule`, `PKSurfaceRule`, `PKSupportRule`, `PKStabilityRule`, `PKLimitRule` (`tag_limits`), `PKNearbyRule` (`make(tag, cells, reason)`), `PKCallableRule`. |

**Core objects**

| Class | Main members |
|---|---|
| `PKBuilder` | `catalog`, `layout`, `grid`, `rules`, `cost_handler`, `zone_provider`, `ground_provider`, `world_bounds`, `socket_radius`, `default_rotation_step`, `surface_snap`, `demolish_cascade`, `refund_overflow`, `undo_limit`, `max_drag_pieces`, `keep_unknown_pieces`, `stability_enabled`, `min_stability`. `preview()`, `check()`, `drag_preview()`, `blueprint_preview()`, `place()`, `place_at()`, `place_many()`, `remove()`, `move()`, `upgrade()`, `can_upgrade()`, `damage()`, `repair()`, `repair_cost()`, `refund_for()`, `dependents_of()`, `stability_of()`, `refresh_stability()`, `make_blueprint()`, `undo()`, `can_undo()`, `clear()`, `to_data()`, `load_data()`, `to_json()`, `load_json()`. Signals `placed`, `removed`, `moved`, `upgraded`, `damaged`, `destroyed`, `repaired`, `rejected(reason, buildable)`, `undone`, `reset`, `refund_left_behind`. |
| `PKLayout` | `get_piece()`, `get_all()`, `count_of()`, `count_tagged()`, `dependents_of()`, `near()`, `overlapping()`, `piece_at()`, `piece_at_plane()`, `raycast()`, `sockets_near()`. |
| `PKPlacement` | `uid`, `buildable`, `buildable_id`, `position`, `angle`, `flipped`, `up`, `cell`, `on_grid`, `parent_uid`, `supports`, `grounded`, `paid`, `stability`, `health`, `data`; `get_transform()`, `get_box()`, `to_world()`, `get_health()`, `is_damaged()`. |
| `PKPreview` / `PKDragPreview` | `placement`, `valid`, `reason`, `cost`, `snapped_to_socket` / `previews`, `total_cost`, `valid_count`, `affordable`, `blueprint`. |
| `PKResult` | `ok`, `reason`, `placements`, `cost`, `refund`, `left_behind`, `skipped_ids`. |
| `PKCost` | `can_pay()`, `pay()`, `refund()`, `refund_partial()`, `count()`, `item_name()`, `item_icon()`, `missing()`, signal `changed`. `PKInventoryCost.make(containers)`, `PKWalletCost.make(amounts)`, `PKCallableCost`. |
| `PKBuildController` | `mode`, `buildable`, `blueprint`, `angle`, `flipped`, `level`, `max_level`, `blueprints`; `select_buildable()`, `select_blueprint()`, `set_mode()`, `rotate()`, `flip()`, `tilt()`, `set_level()`, `aim()`, `press()`, `release()`, `cancel()`, `undo()`, `select_piece()`, `toggle_selection()`, `select_area()`, `get_selection()`, `save_selection_as_blueprint()`. |
| `PKAutotile` | `mask_of(layout, placement, tag, step)`, `shape_of(mask)`, `rotate_mask()`. |
| `PKText` | `reason_texts`, `mode_names`, `reason()`, `cost_text()`, `t()`. |

**Nodes and interface**

| Class | Main members |
|---|---|
| `PKBuildSystem3D` | `catalog`, `camera`, `grid_cell_size`, `grid_origin`, `snap_height`, `grid_map`, `show_grid`, `max_level`, `level_height`, `hide_upper_levels`, `terrain_mask`, `piece_layer`, `fallback_plane`, `navigation_region`, `input_enabled`, `aim_from_screen_center`, colours, `place_animation`, `dust`, `pieces_root`, `stability_view`, `builder`, `controller`, `feedback`, `rebaker`. `select_buildable()`, `select_blueprint()`, `set_cost_handler()`, `set_mode()`, `set_level()`, `rotate_piece()`, `flip_piece()`, `undo()`, `cancel()`, `get_node_of()`, `uid_of()`, `aim_at_screen()`, `aim_along()`, `to_data()`, `load_data()`. Signals: the builder's plus `mode_changed`, `buildable_changed`, `blueprint_changed`, `selection_changed`, `level_changed`, `message`, `costs_changed`. Piece scenes may define `pk_placed(system, placement)` and `pk_neighbors_changed(system)`. |
| `PKBuildSystem2D` | The same, with `tile_map`, `zone_layer_name`, `grid_cell_size` (Vector2), `bounds`, `show_lower_levels`, `show_influence`, `get_variant(uid)`. |
| `PKBuildHUD` | `catalog_panel` (`PKCatalogPanel`), `mode_bar` (`PKModeBar`), `info_panel`, `show_message()`; `bind(system)`. `PKThumbnails` renders icons of pieces without one. `PKUIStyle` holds the colours. |
| `PKFeedback`, `PKNavigationRebaker`, `PKInput` | Sounds (`sounds`, `volume_db`, `enabled`), navigation rebakes (`delay`, `request()`), input actions (`ensure_actions()`). |

The full documentation of each member is in the scripts (Godot shows it in the editor help: search for "PK").

## FAQ

**Does it need Inventory Kit?** No. Building is free by default; use `PKWalletCost` for money or `PKCallableCost` for your own economy. With Inventory Kit, `PKInventoryCost` makes costs atomic.

**My pieces float or sink.** The origin of a piece scene must be the centre of its footprint, at the bottom. Check `size` / `box_offset` with the default box (remove `scene` for a moment).

**Grid pieces snap onto other pieces instead of the ground.** Non-stackable grid pieces aim through placed pieces to `terrain_mask`. Put your ground on that layer and keep pieces on `piece_layer`.

**Two walls at a corner refuse each other.** Make walls a bit shorter than the module (1.8 for 2 m), or shrink their boxes: overlaps use the boxes, not the meshes.

**Can I use my GridMap / TileMapLayer?** Yes: set `grid_map` or `tile_map`; cells, origin and zones come from it. Pieces stay separate nodes (so they can have scripts, health, sockets).

**Is anything done in the editor?** No `@tool` script, no scan at load: the plugin script is empty, the classes come from `class_name`.

**How do I translate it?** Every player text goes through `TranslationServer` (`addons/building_kit/translations/building_kit.csv`, English and French). Add a column, or reword `PKText.reason_texts`.

**Multiplayer?** The core is deterministic data: run `PKBuilder` on the server, send aims or `place_at()` calls, replicate `placed` / `removed` signals or the saves.

## Licenses

- Code (`addons/building_kit/`, demos, tests, tools): MIT, see `LICENSE.txt`.
- Sounds of the kit: generated by `tools/gen_sounds.py`, MIT like the code.
- Inventory Kit (`addons/inventory_kit/`): its own licenses inside its folder.
- Demo art: see `demo/LICENSE_ART.txt` and `CREDITS.md` (primitives drawn in code are MIT; the village props, the woodcutter and the item icons are Benny's assets: free in your games, not to be re-uploaded on their own).
