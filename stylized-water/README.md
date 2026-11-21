# Stylized Water

A water shader for Godot 4.7 3D scenes. It reads the depth buffer to tint the
water from clear shallows to deep blue and to draw foam where the water meets
rocks, posts and the shore. Four sine waves move the surface up and down, and
two scrolling normal maps add small ripples on top. Everything repeats every
4 seconds at the default speed.

Page with the full explanation: <https://godotlearning.com/shaders/stylized-water>

## What is in this folder

- `stylized_water.gdshader`: the shader.
- `stylized_water.gdshader.uid`: the shader's resource ID, which the material
  uses to find it.
- `water_material.tres`: a ShaderMaterial with the shader, both normal maps and
  the default settings.
- `water_normal_a.png` (256 x 256) and `water_normal_b.png` (512 x 512): two
  tileable normal maps made for this shader, with their `.import` files. They
  import with Compress > Normal Map set to Enable and mipmaps on.
- `demo.tscn`, `demo.gd` and `demo.gd.uid`: the demo scene. A 48 m water plane
  with 191 subdivisions, a sloped sand shore, three rocks, a jetty on posts, a
  sun and a procedural sky. The script only swings the camera; the water needs
  no script.

## Use it in your project

1. Copy `stylized_water.gdshader`, `stylized_water.gdshader.uid`,
   `water_material.tres`, both PNGs and their `.import` files into your
   project, for example into `res://water/`.
2. Add a MeshInstance3D and give it a new PlaneMesh. Set the size, and set
   Subdivide Width and Subdivide Depth so the vertices are about 0.25 m apart
   (a 48 m plane needs 191).
3. Drag `water_material.tres` into the MeshInstance3D's Surface Material
   Override slot. Leave the node's rotation at 0 and its scale at 1. Move it up
   or down to set the water level.
4. Put opaque meshes under and through the water (a sea floor, rocks, a
   shore). Foam and the depth colour come from them.
5. Tune the Shader Parameters on the material.

## Parameters

| Name | Type | Default | What it does |
| --- | --- | --- | --- |
| `shallow_color` | Color | (0.24, 0.8, 0.76, 0.45) | Colour of shallow water. Alpha is how opaque it is. |
| `deep_color` | Color | (0.02, 0.17, 0.33, 0.94) | Colour at `depth_distance` metres deep and below. |
| `depth_distance` | float, 0.1 to 10 | 2 | Metres of depth over which shallow turns into deep. |
| `foam_color` | Color | (0.96, 0.98, 1, 1) | Colour of the foam. |
| `foam_width` | float, 0 to 1 | 0.2 | Metres of water depth that still get foam. 0 turns foam off. |
| `wave_height` | float, 0 to 1 | 0.1 | Highest a crest rises above the plane, in metres. |
| `wave_length` | float, 0.5 to 20 | 4 | Length of the longest wave in metres. |
| `wave_speed` | float, 0 to 2 | 0.5 | Speed of waves and ripples. 0 freezes the water. |
| `normal_map_a`, `normal_map_b` | Texture2D | the two PNGs | Ripple normal maps. |
| `normal_scale` | float, 0 to 2 | 0.25 | Strength of the ripples. |
| `normal_tile_size` | float, 0.5 to 50 | 8 | Metres covered by one tile of `normal_map_a`. |
| `roughness` | float, 0 to 1 | 0.06 | Roughness of the water. Foam is always rough. |

## Licence

CC0 1.0 Universal. Use it in anything, commercial included. No credit required.
See LICENSE.txt.
