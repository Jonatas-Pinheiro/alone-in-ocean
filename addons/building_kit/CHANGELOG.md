# Changelog

## 1.0.0 (2026-10-28)

First release.

- Buildables (stable ids, categories, 2D or 3D scenes, size in cells, costs, refunds, rotation steps, flip, tilt in 6 directions, stacking, layers) and catalogs.
- Snapping: sockets (typed snap points with a facing, nearest compatible one, rotation between overlapping sockets, free rotation steps on a socket), grid (2D and 3D, TileMapLayer and GridMap, footprints that stay aligned when turned, levels, bounds), free placement on surfaces (aligned to the normal, optional position step).
- Green / red ghosts (tinted transparent material in 3D, shader tint in 2D), amber when barely stable, footprints, grid lines, automatic catalog icons.
- Drags: lines, L paths, rectangles and outlines with the total cost; one payment, one undo step.
- Rules: overlap, bounds, zones, slope, surface kind, stacking, foundations, limits per piece and tag, "within N cells of", stability, function rules; your own in a few lines.
- Costs: Inventory Kit containers (atomic, several containers), wallet, callbacks, free; refunds by percent, full refunds on undo, refusal or leftovers when the bag is full.
- Modes: build, move, demolish (with what would fall), select (click, Shift + click, box), upgrade, repair; undo of every action (stale actions skipped).
- Structural integrity, upgrades in place, health / damage / destruction / loot / repairs, blueprints, autotiling, floor levels, navigation rebakes.
- Saves by stable id with a format version, unknown pieces kept aside.
- Ready-to-use interface (catalog with greyed-out pieces and a Blueprints tab, mode bar, info box, messages) for mouse, keyboard, gamepad and touch; English and French.
- Feel: pop-in animation, generated sounds, dust.
- Performance: spatial hash, count and support indexes, MultiMesh rendering; load tests with 5 000 pieces.
- Three demos: survival base (3D), city builder (2D), interior design (3D, two floors). 81 tests.
