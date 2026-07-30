---
title: HVE Core docs accessibility manual validation
description: Per-behavior manual validation steps for the HVE Core documentation site accessibility fixes, paired with the shared real screen reader testing procedure.
author: Microsoft
ms.date: 2026-07-16
ms.topic: how-to
sidebar_position: 2
keywords:
  - accessibility
  - manual validation
  - screen reader
  - WCAG 2.2
  - runbook
---

## Purpose

Use this runbook to manually validate the accessibility behavior of the HVE Core documentation site against WCAG 2.2 AA. It pairs with the shared [real screen reader testing runbook](../planning/runbooks/accessibility/real-screen-reader-testing): that runbook is the reusable procedure and evidence format (the how), while this runbook lists the specific surfaces, states, and expected behavior to confirm (the what).

Each item below is grouped into a validation workstream, names the WCAG success criteria it exercises, and gives the exact keyboard, screen reader, and zoom steps a tester runs. Record every result with the shared runbook's result vocabulary and evidence fields.

> [!IMPORTANT]
> **Human review required.** This runbook supports evidence collection, not conformance certification. A qualified accessibility engineer confirms each result before any closure or attestation.
>
> * [ ] Reviewed and validated by a qualified human reviewer

## Scope and environment

* Target surface: the HVE Core documentation site (landing page, documentation pages, search, navbar, sidebar, footer, and data tables).
* Assistive technology: NVDA on Windows with a supported browser. JAWS remains a human-led path per the shared runbook. VoiceOver is out of current scope.
* Recommended browser: Microsoft Edge for keyboard, zoom, and reflow checks.
* Local validation: build and serve the site locally, then browse the served URL. Text zoom and reflow checks use browser zoom and responsive viewport tooling.
* Record the NVDA version, browser and version, OS version, viewport or zoom level, and the exact target URL in every evidence note.

## Bug traceability

Use the register below to connect each public-safe bug to its WCAG success criterion, the workstream or workstreams that exercise it, the automation coverage status, and the manual result recorded for each workstream.

| Bug | WCAG SC | Workstream(s) | Automated lock status | Per-workstream manual result |
| --- | --- | --- | --- | --- |
| 14399 | 2.1.1 | W1 | Existing keyboard lock | Record per run |
| 14396 | 2.4.3 | W4 | Existing focus-order lock | Record per run |
| 14400 | 1.4.4 | W3 | Automated lock: zoom matrix at 100-250 percent; Edge remains manual-authoritative | Record per run |
| 14401 | 1.4.10 | W3 | Existing reflow lock | Record per run |
| 14404 | 1.3.1 | W5, W7 | Existing table and structure lock | Record per run for each workstream |
| 14409 | 4.1.2 | W1, W5 | Existing keyboard and manual AT boundary | Record per run for each workstream |
| 14410 | 4.1.3 | W2 | Existing live-region lock | Record per run |
| 14462 | 1.3.1 | W6 | Existing heading-outline lock | Record per run |
| 14528 | 1.3.1 | W5 | Existing structure boundary; spoken association remains manual | Record per run |
| 14531 | 1.3.1 | W5 | Existing structure boundary; spoken group label remains manual | Record per run |
| 14398 | 1.4.1 | W6 | Automated lock: every prose link carries a non-color cue | Record per run |
| 14402 | 2.4.7 | W6 | Automated lock: focus indicator at least 2 CSS px on every focusable | Record per run |

## Evidence results template

Copy the template below for each workstream item. Capture the environment metadata, the observed output, and the result classification without writing back to any automation matrix.

```text
Workstream: W1-W7
Bug or behavior:
NVDA version:
Browser and version:
OS version:
Viewport or zoom:
Target URL:
Observed output:
Result: verified pass | verified fail | not verified | unsupported
Notes:
```

Use the four-value vocabulary exactly as shown above. Do not write manual results back to any automation matrix.

## Result vocabulary

Use the shared runbook's manual result vocabulary and keep results as evidence-only entries:

* verified pass
* verified fail
* not verified
* unsupported

Do not write manual results back to any automated matrix. A downstream human review decides whether a result influences coverage or release gating.

## Validation workstreams

### W1: Keyboard access to search results (WCAG 2.1.1, 4.1.2)

* Surface and state: landing page, search suggestions open.
* Expected behavior: keyboard focus stays on the search input while `aria-activedescendant` moves the highlight through options; the highlight reaches the "See all results" footer only after the last option; the announced position count matches the visible list; `Enter` navigates; `Esc` and `Shift+Tab` return sanely; `Tab` does not navigate the page away.
* Steps:
  1. Open search, type a query that returns several results.
  2. Press `ArrowDown` repeatedly and confirm the highlight moves one option at a time and reaches "See all results".
  3. Confirm `Enter` activates the highlighted item.
  4. Confirm `Shift+Tab` and `Esc` return focus predictably and that `Tab` does not change the page.
  5. Repeat with NVDA and confirm each option plus its "x of y" position is announced correctly.
* Pass criteria: the footer is reachable, focus never escapes the combobox, `Tab` does not navigate, and NVDA announces correct positions.

### W2: Search result count announcement on the search page (WCAG 4.1.3)

* Surface and state: the dedicated search results page with an active query.
* Expected behavior: a live status region in the main content announces the deterministic result count when the query changes, including the no-match case.
* Steps:
  1. With NVDA running, open the search results page for a query that returns matches.
  2. Edit the query and confirm NVDA announces the count (for example, "N documents found").
  3. Change to a query with no matches and confirm NVDA announces the no-results message.
* Pass criteria: a live region in main content announces both the match count and the no-match message.

### W3: Reflow at 320px and text resize to 200% (WCAG 1.4.10, 1.4.4)

* Surface and state: landing page, navbar search expanded.
* Expected behavior: at a 320 pixel width the expanded search re-lays out and does not overlap the site brand, with no horizontal scrolling; at 200 percent text zoom the search placeholder and controls are not clipped and images remain intact.
* Steps:
  1. Set a 320 pixel wide viewport, open search, and confirm no overlap with the brand and no horizontal scroll.
  2. In real Edge at a standard desktop width, apply 200 percent text zoom and confirm the placeholder is not truncated and controls do not overlap.
* Pass criteria: no overlap or horizontal scroll at 320 pixels; no truncation or overlap at 200 percent.

### W4: Focus order for navbar dropdown and docs sidebar (WCAG 2.4.3)

* Surface and state: navbar topics menu and documentation left sidebar.
* Expected behavior: activating a top navigation link moves focus to page content rather than back to the skip link; the topics control behaves as a menu button with focus entering the first item and arrow, home, and end cycling within it, and `Esc` returning to the toggle; the sidebar uses a roving tab model with one tab stop per category and arrow navigation within.
* Steps:
  1. Keyboard only, activate a top navigation link and confirm focus lands on page content.
  2. Open the topics menu, confirm focus enters the first item, arrow and home and end cycle, and `Esc` returns to the toggle.
  3. Move through the sidebar and confirm one tab stop per category header with arrow navigation inside.
* Pass criteria: post-activation focus lands on content, the menu follows the expected keyboard model, and the sidebar exposes a single tab stop per category.

### W5: Screen reader announcements (WCAG 1.3.1, 4.1.2)

* Surface and state: search field clear button, footer column groups, and the search field heading and shortcut association.
* Expected behavior: the clear button announces an accessible name; each footer column announces its title before its list; the search field announces its associated heading and keyboard shortcut, and the association persists across open, close, and refocus.
* Steps:
  1. With NVDA, move to the clear button and confirm it announces a clear accessible name.
  2. Navigate the footer and confirm each column announces its title before "list with N items".
  3. Focus the search field, confirm the heading and shortcut are announced, then open, close, and refocus and confirm the association persists.
* Pass criteria: the clear button is named, footer groups announce their titles, and the search field association survives the open and close cycle.

### W6: Merged fixes to re-verify (WCAG 1.4.1, 2.4.7, 1.3.1)

* Surface and state: links, focusable controls including cards, and heading structure across pages.
* Expected behavior: links remain distinguishable without relying on color alone; the keyboard focus indicator is visible on all four sides for every focusable control including cards; the heading outline has no gaps and includes in-page and footer headings.
* Steps:
  1. In gray scale, confirm links are distinguishable from body text.
  2. Keyboard only, confirm a four-sided focus ring on every control including cards.
  3. With NVDA, review the heading outline and confirm it is gap free and includes in-page and footer headings.
* Pass criteria: color is not the sole link cue, focus is visible on all sides, and the heading outline is complete.

### W7: Accessible tables site-wide (WCAG 1.3.1)

* Surface and state: data tables across documentation pages.
* Expected behavior: every data table has header cells with scope, an accessible name, and correct header associations, and the build fails if any table lacks a header scope or a name.
* Steps:
  1. With NVDA, navigate to a documentation table and confirm it announces its name and header associations.
  2. Run the build and confirm the table accessibility gate passes.
* Pass criteria: tables announce their name and header associations, and the automated table gate passes.

## Regression coverage

Manual validation confirms behavior once; permanent regression coverage prevents recurrence. As each workstream passes, confirm a corresponding end-to-end specification exists under the site's end-to-end test suite and that it fails before the fix and passes after. Keyboard operability, live-region announcements, reflow and resize, focus order, and table structure each need explicit assertions because static rule engines do not cover them.

## Evidence and closure

* Capture the observed output, focus location, viewport or zoom level, and any unexpected behavior for each item.
* Record one of the four result classifications per item and store the evidence reference.
* A qualified human reviewer confirms the recorded results before any closure or public attestation.

---

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.*
