# Window Borders

Window Borders draws a band around your app windows so each app is easy to find at
a glance. Every app takes its own colour from a palette and keeps it, so Mail is
always the same colour and never swaps with Notes. The band is drawn in separate,
click-through windows around the outside edge; your apps and their windows are
never changed.

## Turn it on

Enable Window Borders in Settings under Labs, or run
`ed extensions enable windowSweaters`. The extension id stays `windowSweaters` so
existing settings and scripts keep working.

**Borders on** shows or hides every border without disabling the extension. Your
choices are kept while borders are off.

## Styles

| Style | What you see |
| --- | --- |
| Solid | One flat colour per app. |
| Gradient | The app's colour flows into its neighbour in the palette around the window. |
| Knit | A textured band of stitches, with an optional motif worked in a second colour. |

Knit has two extra choices:

- **Motif** is By App, Plain, or one named motif. By App gives each app its own
  motif, Plain knits stitches only, and a named motif is worked on every window.
- **Stitch** is Smooth, Ribbed or Ridged. Smooth lays every stitch as a V, Ribbed
  alternates V columns with raised bumps, and Ridged alternates V rows with bumps.

### How motifs are made

Motifs are not drawn by hand. Each one is computed for the number of stitch rows
in the band, so it always fits the width you choose:

| Motif | Rule |
| --- | --- |
| Wave | A cosine curve, one stitch thick, swinging from edge to edge. |
| Chevron | A zigzag that climbs one row per stitch. |
| Lattice | Two mirrored zigzags that cross into diamonds. |
| Seed | Single stitches staggered every fourth column. |
| Checks | Blocks half the band tall, alternating like a chequerboard. |
| Slant | Two-stitch diagonal stripes. |
| Pulse | A flat line with one sharp peak and trough, like a heartbeat trace. |

With five or more rows, the outer and inner rows are worked in the motif colour as
a frame. Every motif repeats seamlessly, and the corners continue the stitches
along the curve.

## Palettes

Each palette holds six colours. An app's colour is picked from the palette by a
stable hash of its name, and the motif colour is the palette colour that contrasts
with it most.

| Palette | Feel |
| --- | --- |
| Harbour | Teal, sea blue, buoy orange, rope gold, sea glass and signal red. The default. |
| Ember | Brick, flame, amber and plum. |
| Meadow | Moss, leaf, lime, straw and clay. |
| Dusk | Indigo, violet, rose and apricot. |
| Glacier | Cool blues from deep water to frost. |
| Orchard | Plum, berry, terracotta, pear and olive. |
| Citrus | Bright tangerine, lemon, mint, sky and pink. |
| Graphite | Six neutral greys. |

Edith's own windows always use the accent of the app theme you picked.

## Fit

- **Border width** sets the band from 2 to 60 points.
- **Stitch size** sets how many stitch rows fit across the band. Fewer rows make
  bigger stitches. Motifs need at least five rows.
- **Sits** places the band behind the window or in front of it. In front reads
  more strongly and overlaps the window edge by up to three points.
- **Repeat starts** anchors each side's motif at its corner, so the motif stays
  still while you resize, or at the side's centre.
- **Unfocused** darkens every border except the focused window's.
- **Focused window only** draws a single border on the window you are using.

## Apps

- **Colour rules** give an app its own colour, as comma-separated `App=colour`
  pairs. A colour is a hex value or a palette name, for example
  `Mail=#2C5D8F, Notes=ember`. An exact name wins, then the longest matching
  prefix. A palette name uses that palette's first colour.
- **Never draw on** lists app names, separated by commas, that keep plain edges.
- **Follow focus through Accessibility** asks the front app which window is
  focused, which helps with apps that use panels, and follows windows moved from
  the keyboard at once. It needs Accessibility access.

## Command line

Every setting is available through `ed config`:

```sh
ed config set windowSweatersStyle gradient
ed config set windowSweatersBasket dusk
ed config set windowSweatersPattern lattice
ed config set windowSweatersAppColours "Mail=#2C5D8F, Notes=ember"
ed config set windowSweatersFocusedOnly true
```

| Key | Values |
| --- | --- |
| `windowSweatersActive` | `true` or `false` |
| `windowSweatersStyle` | `solid`, `gradient` or `knit` |
| `windowSweatersPattern` | `by-app`, `none`, or a motif name |
| `windowSweatersStitch` | `stockinette`, `rib` or `garter` |
| `windowSweatersBasket` | a palette name |
| `windowSweatersBorderWidth` | 2 to 60 |
| `windowSweatersGauge` | stitch rows, 1.5 to 40 |
| `windowSweatersAnchor` | `corner` or `centre` |
| `windowSweatersOrder` | `below` or `above` |
| `windowSweatersUnfocusedDim` | 0 to 0.9 |
| `windowSweatersFocusedOnly` | `true` or `false` |
| `windowSweatersAccessibilityFocus` | `true` or `false` |
| `windowSweatersExcludedApps` | comma-separated app names |
| `windowSweatersAppColours` | comma-separated `App=colour` rules |

Palette names from earlier versions are still accepted: `wool` reads as Harbour,
`dopamine` and `neon` as Citrus, `punch` as Ember, `sorbet` as Orchard, `forest`
as Meadow and `mono` as Graphite. A pattern name Edith no longer knows reads as
By App.

## How it stays light

Borders follow the window list rather than a timer that redraws. While nothing
moves, Window Borders checks the window list once a second and changes nothing
when it is unchanged. While a mouse button is held, and for under half a second
after an app switch, a window opening or closing, or a release, it follows windows
at the display's refresh rate, reading only the windows being moved on most frames.

Each band is eight layers: four corners and four sides. Stitch artwork is drawn
once per app colour into a long strip and a corner tile, shared by every border
with the same look, so a resize only moves layers and never redraws stitches.
