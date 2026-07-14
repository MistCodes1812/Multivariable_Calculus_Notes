--[[
  filter.lua

  Responsibilities:
    1. Validate that typed blocks (`::: {.pre-reading}` etc.) use exactly
       one class from ALLOWED_TYPES. Warn on unknown/duplicate types.
    2. Inject a shared `.block` base class, a visible label, and ARIA
       metadata — so markdown only ever needs the bare type class.
    3. Auto-generate a stable id (slug of first heading, else a short
       content hash) when the author didn't set one with {#custom-id}.
    4. Convert `.slot` divs into click-to-load HTML: no network request
       fires until the reader clicks, and a plain-link fallback exists
       for no-JS / weak-connection readers.

  Usage:
    pandoc notes.md -o notes.html --standalone --css notes.css \
      --lua-filter filter.lua
]]

-- ---------------------------------------------------------------------
-- Taxonomy config: single source of truth for allowed types + labels.
-- Add a new content type by adding one line here (and matching CSS).
-- ---------------------------------------------------------------------
local TYPE_LABELS = {
  ["course-material"] = "Course Material",
  ["pre-reading"]      = "Pre-Reading",
  ["deep-dive"]        = "Deep Dive",
}

local function slugify(text)
  text = text:lower()
  text = text:gsub("[^%w%s-]", "")
  text = text:gsub("%s+", "-")
  text = text:gsub("%-+", "-")
  text = text:gsub("^%-+", ""):gsub("%-+$", "")
  return text
end

-- Find the first Header inside a div's content, if any, for id generation.
local function first_heading_text(blocks)
  for _, b in ipairs(blocks) do
    if b.t == "Header" then
      return pandoc.utils.stringify(b.content)
    end
  end
  return nil
end

local block_counter = 0

local function generate_id(el, type_class)
  block_counter = block_counter + 1
  local heading = first_heading_text(el.content)
  if heading and #heading > 0 then
    return type_class .. "-" .. slugify(heading)
  end
  -- No heading to slug: short content hash keeps ids stable across
  -- re-builds as long as the block's text doesn't change.
  local text = pandoc.utils.stringify(pandoc.Pandoc(el.content))
  local ok, hash = pcall(function()
    return pandoc.utils.sha1(text)
  end)
  if ok and hash then
    return type_class .. "-" .. hash:sub(1, 8)
  end
  return type_class .. "-" .. block_counter
end

-- ---------------------------------------------------------------------
-- Typed content blocks
-- ---------------------------------------------------------------------
local function handle_typed_block(el)
  local matched = {}
  for _, c in ipairs(el.classes) do
    if TYPE_LABELS[c] then
      table.insert(matched, c)
    end
  end

  if #matched == 0 then
    return nil -- not a taxonomy block; leave untouched
  end

  if #matched > 1 then
    io.stderr:write(
      "[filter.lua] WARNING: block has multiple type classes ("
        .. table.concat(matched, ", ")
        .. ") — types are mutually exclusive. Using '"
        .. matched[1]
        .. "'.\n"
    )
  end

  local type_class = matched[1]
  local label = TYPE_LABELS[type_class]

  -- id: keep author-supplied id if present, else generate one
  if el.identifier == "" or el.identifier == nil then
    el.identifier = generate_id(el, type_class)
  end

  -- base class + accessibility metadata
  el.classes:insert(1, "block")
  el.attributes["role"] = "note"
  el.attributes["aria-label"] = label

  -- visible label as the first element inside the block
  local label_span = pandoc.Div(
    { pandoc.Plain({ pandoc.Str(label) }) },
    pandoc.Attr("", { "block__label" })
  )
  table.insert(el.content, 1, label_span)

  return el
end

-- ---------------------------------------------------------------------
-- Slot blocks: `::: {.slot data-slot-type="video" data-src="URL"}`
-- Optional attrs: data-slot-id, data-title, data-poster
-- Rendered as click-to-load — no request until the user clicks.
-- ---------------------------------------------------------------------
local function handle_slot(el)
  if not el.classes:includes("slot") then
    return nil
  end

  local attrs = el.attributes
  local slot_type = attrs["data-slot-type"] or "video"
  local src = attrs["data-src"]
  local title = attrs["data-title"] or "Untitled"
  local slot_id = attrs["data-slot-id"] or ("slot-" .. slugify(title))

  if not src then
    io.stderr:write(
      "[filter.lua] WARNING: .slot block '" .. slot_id .. "' has no data-src; skipping.\n"
    )
    return el
  end

  local button_text = (slot_type == "interactive") and "Load interactive content" or "Load video"
  local kind_label = (slot_type == "interactive") and "Interactive" or "Video"

  -- Per-slot opt-out: data-auto="false" means this slot never
  -- auto-loads regardless of connection quality (e.g. a heavy
  -- simulation you always want the reader to explicitly request).
  -- Default is "true" -- eligible for auto-load on a confirmed-good
  -- connection, but still click-to-load everywhere else.
  local auto = attrs["data-auto"]
  if auto ~= "false" then
    auto = "true"
  end

  local html = string.format(
    [[
<div class="slot-container" id="%s" data-slot-type="%s" data-src="%s" data-auto="%s">
  <div class="slot-placeholder">
    <span class="slot-placeholder__label">%s &middot; %s</span>
    <button class="slot-placeholder__button" type="button"
      onclick="window.__loadSlot(this.closest('.slot-container'))">
      %s
    </button>
  </div>
  <noscript>
    <p class="slot-fallback"><a href="%s">%s (opens directly -- %s)</a></p>
  </noscript>
</div>
]],
    slot_id, slot_type, src, auto, kind_label, title, button_text, src, title, src
  )

  return pandoc.RawBlock("html", html)
end

-- ---------------------------------------------------------------------
-- Shared runtime script (injected once, at the end of the document).
--
-- Behaviour:
--   1. window.__loadSlot(container) -- the actual iframe-injection
--      logic, called both by manual button clicks and by auto-load.
--   2. After the page has fully finished loading (window 'load'),
--      check the Network Information API:
--        - saveData true            -> never auto-load
--        - effectiveType not "4g"   -> never auto-load (2g/3g/slow-2g)
--        - API unsupported          -> never auto-load (Safari/Firefox;
--                                       stay conservative when unknown)
--        - otherwise                -> auto-load eligible slots
--          (data-auto="true", the default), staggered 600ms apart so
--          they don't all hit the network at once.
--   This guarantees prose is never blocked or slowed by slot loading
--   (it only starts after the page is already fully rendered), and
--   guarantees no unrequested downloads happen on a connection that is
--   confirmed slow, or on browsers where connection quality is unknown.
-- ---------------------------------------------------------------------
local SLOT_RUNTIME_SCRIPT = [[
<script>
(function () {
  function loadSlot(container) {
    if (!container || container.dataset.loaded === "true") return;
    var src = container.dataset.src;
    var iframe = document.createElement("iframe");
    iframe.src = src;
    iframe.loading = "lazy";
    iframe.allow = "autoplay; fullscreen";
    iframe.setAttribute("allowfullscreen", "");
    container.innerHTML = "";
    container.appendChild(iframe);
    container.dataset.loaded = "true";
  }
  window.__loadSlot = loadSlot;

  function connectionAllowsAutoLoad() {
    var c = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
    if (!c) return false; // API unsupported: unknown quality, stay conservative
    if (c.saveData) return false; // explicit data-saver request
    if (c.effectiveType && c.effectiveType.indexOf("4g") === -1) return false; // slow-2g/2g/3g
    return true;
  }

  function autoLoadEligibleSlots() {
    if (!connectionAllowsAutoLoad()) return;
    var slots = Array.prototype.slice.call(
      document.querySelectorAll('.slot-container[data-auto="true"]')
    );
    slots.forEach(function (container, i) {
      setTimeout(function () { loadSlot(container); }, i * 600);
    });
  }

  function schedule() {
    if ("requestIdleCallback" in window) {
      requestIdleCallback(autoLoadEligibleSlots, { timeout: 3000 });
    } else {
      setTimeout(autoLoadEligibleSlots, 500);
    }
  }

  if (document.readyState === "complete") {
    schedule();
  } else {
    window.addEventListener("load", schedule);
  }
})();
</script>
]]

function Pandoc(doc)
  table.insert(doc.blocks, pandoc.RawBlock("html", SLOT_RUNTIME_SCRIPT))
  return doc
end

-- ---------------------------------------------------------------------
function Div(el)
  local slot_result = handle_slot(el)
  if slot_result then
    return slot_result
  end
  return handle_typed_block(el)
end
