# Jar Garden Production Art Asset Manifest

Status: production prototype asset set  
Last updated: 2026-08-14

This file records the final raster assets currently checked into assets/, how they were produced, their intended use, and their generation provenance. It is intentionally Git-readable and should be updated whenever an asset is replaced.

## Production method

1. The source artwork was generated with OpenAI ImageGen.
2. The generated output was prepared deterministically with res://tools/prepare_ai_assets.gd:
   - plant subjects were isolated to the largest visible component, fit within 420×400 pixels, placed on a 512×512 RGBA canvas, and aligned to baseline y=466;
   - portrait environment layers were normalized to 720×1280 RGBA;
   - environment thumbnails were composited locally from far + mid + front and resized to 256×455.
3. Godot imports the PNG files as Texture2D resources. Generated cache data under .godot/ is not part of this manifest.

## Consolidated production prompts

These are consolidated production prompts assembled from the production brief. They are not verbatim transcripts of individual tool calls.

Shared style clause (STYLE):

> Soft hand-painted children's picture-book watercolor/gouache; a warm cream, sage, pond-blue, coral, and deep-forest palette; gentle paper texture; cute and collectible; no text, logo, or watermark.

Plant output clause (PLANT):

> STYLE. One isolated cute blob-plant creature, transparent background, 512×512 RGBA, a single subject, unified ground baseline, and generous consistent whitespace. Subject: [SUBJECT].

Environment output clause (ENVIRONMENT):

> STYLE. Portrait 720×1280 environment for a mobile jar-garden game. Keep the central jar area calm and low-contrast. Location: [LOCATION]. Layer: [LAYER].

The per-asset prompt column below supplies the exact [SUBJECT], [LOCATION], and [LAYER] values merged with those clauses.

## Plant assets

All plant rows use the ImageGen → deterministic plant preparation method above and license record L1.

| Final asset | Purpose / silhouette | Dimensions | Consolidated prompt value (PLANT subject) | Generation ID | License |
|---|---|---:|---|---|---|
| plants/base_common.png | Default/common creature; round white dumpling family | 512×512 RGBA | White round dumpling blob, simple cute face, no leaves, hat, tool, or other accessory | exec-ebc48535-3103-4f8a-9453-b250df9b1ceb | L1 |
| plants/leaf_cap.png | Leaf Cap variant; pear family | 512×512 RGBA | Pear-shaped cream blob with a single broad green leaf cap and a cute face | exec-fbbf86bf-3117-406c-9329-f3bf5bcb3ad1 | L1 |
| plants/moss_cushion.png | Moss Cushion variant; low cushion family | 512×512 RGBA | Low, wide, soft moss cushion blob with a cute face | exec-dc70eb78-def4-4e1a-a770-34349a118cbf | L1 |
| plants/moonbell.png | Moonbell variant; bell-drop family | 512×512 RGBA | Pale moonlit bell-drop blob with a crescent detail and a cute face | exec-f74616e8-91d9-4420-9502-109470e2f279 | L1 |
| plants/blush_color.png | Blush mutation; round dumpling family | 512×512 RGBA | Coral-blush round dumpling blob with the same base silhouette and a cute face | exec-f25bba10-fecb-4dd9-8ba0-c1473055f714 | L1 |
| plants/tiny_gardener.png | Tiny Gardener variant; squat bean family | 512×512 RGBA | Tiny squat gardener bean with a soft hat, watering-can gear, and a cute face | exec-d654ae91-f523-47eb-ab8c-3867a9be2974 | L1 |
| plants/sunpatch.png | Sunpatch variant; tall pod family | 512×512 RGBA | Tall golden sunlit pod blob with a scalloped side and a cute face | exec-3615948a-af96-457e-9455-d8342255b6ce | L1 |
| plants/rainbell.png | Rainbell variant; bell-drop family | 512×512 RGBA | Clear pond-blue rain bell-drop blob with water beads and a cute face | exec-dde8d958-0d6c-464a-93d5-e0d8d04a8b1c | L1 |
| plants/fern_curl.png | Fern Curl variant; curled fiddlehead family | 512×512 RGBA | Broad green fern-curl blob forming a visible fiddlehead spiral with a cute face | exec-4004b832-86fe-4209-9e37-9bdb5e98448f | L1 |
| plants/glow_pod.png | Glow Pod variant; tall pod family | 512×512 RGBA | Slender tall deep-green pod blob with pond-blue and firefly-green glowing spots and a cute face | exec-73ea7ea7-680e-41c0-97f7-03c38d2d1c4d | L1 |

## Environment assets

The far, mid, and front rows use ImageGen → deterministic portrait preparation. Thumbnail rows are deterministic local composites of the three listed ImageGen outputs and therefore have no separate generation ID or prompt. All rows use license record L1.

| Final asset | Purpose | Dimensions | Consolidated prompt values (ENVIRONMENT) | Generation ID / derivation | License |
|---|---|---:|---|---|---|
| environments/forest/far.png | Forest complete distant scene / base layer | 720×1280 RGBA | Location: gentle forest clearing. Layer: complete distant scene, full-canvas far layer | exec-6bee31b8-69da-405b-adef-44d16093fa0e | L1 |
| environments/forest/mid.png | Forest transparent midground depth | 720×1280 RGBA | Location: gentle forest clearing. Layer: transparent midground foliage and depth accents | exec-b3bc6356-937e-4d24-8f32-128d063248e4 | L1 |
| environments/forest/front.png | Forest transparent foreground occlusion | 720×1280 RGBA | Location: gentle forest clearing. Layer: transparent foreground foliage occlusion framing the jar | exec-3ab486ac-f7d0-40a2-8583-c94cf5a05dbb | L1 |
| environments/forest/thumbnail.png | Forest shop/environment preview | 256×455 RGBA | Derived locally; exact composite of the forest far + mid + front prompts above | Derived from the three forest generation IDs above | L1 |
| environments/indoor_window/far.png | Window Nook complete distant scene / base layer | 720×1280 RGBA | Location: warm sheltered window nook. Layer: complete distant scene, full-canvas far layer | exec-716bca5d-cc18-425d-8141-87f031283771 | L1 |
| environments/indoor_window/mid.png | Window Nook transparent midground depth | 720×1280 RGBA | Location: warm sheltered window nook. Layer: transparent midground sill, curtain, and room accents | exec-1dc9f6cb-cf75-4d7f-9bc8-4d687e9365f7 | L1 |
| environments/indoor_window/front.png | Window Nook transparent foreground occlusion | 720×1280 RGBA | Location: warm sheltered window nook. Layer: transparent foreground plant and fabric occlusion framing the jar | exec-ccd1d549-6802-4db4-9b3f-5dea3038e1c3 | L1 |
| environments/indoor_window/thumbnail.png | Window Nook shop/environment preview | 256×455 RGBA | Derived locally; exact composite of the window-nook far + mid + front prompts above | Derived from the three window-nook generation IDs above | L1 |
| environments/rainforest/far.png | Rainforest complete distant scene / base layer | 720×1280 RGBA | Location: humid layered rainforest refuge. Layer: complete distant scene, full-canvas far layer | exec-cf7cae3b-9bd0-41a6-bba8-1f19b8328c59 | L1 |
| environments/rainforest/mid.png | Rainforest transparent midground depth | 720×1280 RGBA | Location: humid layered rainforest refuge. Layer: transparent midground leaves, mist, and depth accents | exec-4c81a6ec-8ea4-407f-8b36-5a8764cd15f7 | L1 |
| environments/rainforest/front.png | Rainforest transparent foreground occlusion | 720×1280 RGBA | Location: humid layered rainforest refuge. Layer: transparent foreground wet foliage occlusion framing the jar | exec-1fd8418a-c1f2-4f6e-a931-1bd6a462c922 | L1 |
| environments/rainforest/thumbnail.png | Rainforest shop/environment preview | 256×455 RGBA | Derived locally; exact composite of the rainforest far + mid + front prompts above | Derived from the three rainforest generation IDs above | L1 |

## License and provenance record

L1 — Generated for this project with OpenAI ImageGen. Usage and ownership are governed by the OpenAI terms applicable to the generating account at the time of generation. No third-party stock artwork or separately licensed visual pack was introduced in these files. The local preparation script performs technical cleanup, normalization, and compositing only. This record documents provenance and is not legal advice.

## Integration notes

- Plant PNGs are bound through PlantVisualDefinition resources in res://resources/prototype_content_catalog.tres.
- The catalog intentionally maps ten IDs in this order: base_common, leaf_cap, moss_cushion, moonbell, blush_color, tiny_gardener, sunpatch, rainbell, fern_curl, glow_pod.
- Environment definitions bind far, mid, front, and thumbnail textures independently so the game can compose depth without duplicating art.
