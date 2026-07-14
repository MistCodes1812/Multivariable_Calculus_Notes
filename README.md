# Notes pipeline

One markdown source file → one HTML page, typed content blocks via
fenced divs, media/interactive content as click-to-load slots.

## Build

```
./build.sh example.md
```

Or directly:

```
pandoc example.md -o example.html --standalone --css notes.css --lua-filter filter.lua
```

## Authoring content blocks

```markdown
::: {.pre-reading}
Content here.
:::

::: {.course-material}
## A heading works fine inside a block
Content here.
:::

::: {.deep-dive}
Content here.
:::
```

Rules:
- Exactly one type class per block (`pre-reading`, `course-material`,
  `deep-dive`). The filter warns and picks the first one if you
  accidentally give a block two.
- No `id` needed — the filter generates one from the first heading, or
  a short content hash if there isn't one. Set `{#my-id .pre-reading}`
  yourself if you want a specific anchor.

## Adding a new content type

1. `notes.css` — add a `--color-<type>` / `--color-<type>-bg` pair and a
   `.block.<type>` rule.
2. `filter.lua` — add one line to the `TYPE_LABELS` table.

That's the whole surface area.

## Authoring slots (video / interactive)

```markdown
::: {.slot data-slot-type="video" data-src="https://..." data-title="Optional title"}
:::
```

- `data-slot-type`: `video` (16:9 box) or `interactive` (4:3 box, light
  background instead of a dark video poster look).
- `data-src`: required. Whatever the reader clicks loads this URL in an
  iframe.
- `data-title`, `data-slot-id`: optional.

**Why click-to-load instead of lazy-load:** `loading="lazy"` still
auto-fetches once the element nears the viewport — on a poor connection
that's still an unwanted download. Click-to-load means the iframe
request only fires on an explicit tap (or an eligible auto-load, below),
so the page is fully readable, lightweight, and fast with the network
off entirely. If JavaScript is unavailable, a plain link to the source
is still present via `<noscript>`.

**Connection-aware auto-load.** A single shared script (injected once,
at the end of the document by the filter) can load slots automatically
instead of waiting for a click, but only when it's safe to assume that's
welcome:

1. It waits for the page's `load` event — text, CSS, everything else is
   already fully rendered before any slot is even considered. Slots are
   always loaded *last*, never in competition with prose.
2. It then checks the [Network Information API]
   (`navigator.connection`). If the browser reports `saveData: true`,
   or `effectiveType` other than `4g` (i.e. slow-2g/2g/3g), nothing
   auto-loads — it stays click-to-load.
3. If the API isn't available at all (Safari, Firefox), the default is
   also to stay click-to-load — an unknown connection is treated as a
   slow one, not a fast one.
4. Only on a confirmed-good connection do eligible slots auto-load, and
   even then they're staggered 600ms apart rather than firing all at
   once.

Every slot is auto-load-eligible by default. To force a specific slot to
always require an explicit click regardless of connection (e.g. a large
interactive simulation), add `data-auto="false"`:

```markdown
::: {.slot data-slot-type="interactive" data-src="https://..." data-auto="false"}
:::
```

## Non-goals (deliberately out of scope right now)

- No manifest / fragment-assembly layer — content doesn't arrive
  asynchronously, so one file per page is enough.
- No fragment IDs for patching a single piece independently — the
  auto-generated ids exist for anchors, not for a patch workflow.
- No difficulty/time-estimate/prerequisite metadata — add fields to the
  `TYPE_LABELS`-adjacent logic later if you actually need them.
- No LaTeX/PDF target mapping — CSS classes only affect HTML output;
  revisit if a PDF export is ever needed.
