---
name: large-file-build
description: "Build large HTML files in chunks when a single write_file exceeds stream limits"
category: software-development
tags: [file-build, chunking, HTML, dashboard]
---

# Large-File Build (Chunked write_file Strategy)

Build large self-contained files (typically HTML dashboards, > 10KB) by splitting them into sequential `write_file` + `patch` operations. Single write calls exceed stream limits and must be avoided.

## When to Use
- Building a single-file dashboard (HTML + CSS + JS + embedded data)
- Any output > 8KB where the first `write_file` would fail
- User explicitly requests a "self-contained HTML file"

## Workflow

### 1. Calculate First, Then Embed
- Run all data/model calculations in `execute_code` (Python) to get exact numbers
- Print verification to stdout — this is your ground truth
- Only AFTER confirming values are correct, embed them

### 2. First Write — Skeleton + CSS + First Section
```bash
write_file(path=/tmp/file.html)
# Include: <html>, <head>, <style>, <body>, <header>
# First content section (e.g., the bracket/tournament)
# Target: < 8KB payload
```

### 3. Subsequent Patches — One Section Each
```bash
patch(path=/tmp/file.html)
# Match surrounding context exactly:
# old_string: closing tags from previous section
# new_string: next section's full HTML
# Keep each patch < 4KB
```

Sections to chunk (example for a World Cup dashboard):
1. Bracket data (1 section)
2. Stats tables (1 section)
3. Model/prediction with embedded data (1 section)
4. Footer (1 section)

### 4. Copy to Final Location
```bash
cp /tmp/file.html ./file.html   # the deliverable goes in the working directory
```

### 5. Verify with Browser
```bash
python3 -m http.server 8765 &
browser_navigate(url=http://localhost:8765/file.html)
browser_snapshot(full=true)  # verify all data rendered
browser_console()           # check for JS errors
```

**If browser_snapshot returns empty elements or `—` values:** the JS didn't execute or data wasn't embedded. Check for:
- HTML entity encoding issues in CSS (`&#964;` in `style` blocks)
- Script tag placement (must be after the HTML it references)
- Python `execute_code` vs HTML literal string encoding

### Pitfalls

| Pitfall | Fix |
|---|---|
| `file://` URLs don't render JS | Serve via `python3 -m http.server` |
| `&#964;` in CSS breaks JS | Use `&#964;` only in text nodes, not inside `<style>` or `<script>` |
| Patch context mismatch | Include the closing `</section>` from the previous chunk in `old_string` |
| JS syntax broken by entity encoding | Verify the script block with `node --check` (extract it to a `.js` file first); `ast.parse` is for Python only |
| Model data not embedded | Print values to Python output first, then copy-paste into HTML |
| Browser_snapshot shows `—` or empty | Check `browser_snapshot(full=true)` — if IDs like `lamArg` show "—", the JS didn't run |

### Payload Budgeting (Rule of Thumb)
- **First write**: 3-7KB (skeleton + CSS + first section)
- **Each patch**: 1-3KB (one section at a time)
- **Script section**: Separate, verify syntax first with `node --check` on the extracted script
- **Total target**: complete file with all data, no external deps

### Verification Checklist
- [ ] All model values match Python output (e.g., `2.60`, `2.25`, `46.9%`)
- [ ] No external dependencies (fonts, images, APIs)
- [ ] Mobile responsive (breakpoints at 800px and 500px)
- [ ] `browser_snapshot(full=true)` shows all content populated
- [ ] `browser_console()` shows no JS errors
- [ ] File is self-contained (works offline, no fetch failures)
