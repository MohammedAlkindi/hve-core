// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import React, { useEffect, useRef } from 'react';
import SearchBar from '@theme-original/SearchBar';

const srOnlyStyle = {
  position: 'absolute',
  width: '1px',
  height: '1px',
  padding: 0,
  margin: '-1px',
  overflow: 'hidden',
  clip: 'rect(0, 0, 0, 0)',
  whiteSpace: 'nowrap',
  border: 0,
};

// WI-07 accessibility wrapper for the local search input.
//
// The upstream @easyops-cn/autocomplete.js (via @easyops-cn/docusaurus-search-local)
// already promotes the navbar search input to the WAI-ARIA APG Combobox pattern at
// runtime: it sets role="combobox", aria-autocomplete, aria-expanded (toggled on
// open/close), aria-activedescendant (on arrow navigation), and aria-owns pointing at
// the generated role="listbox" element. The popup items receive role="option".
//
// Two divergences from the current APG Combobox pattern remain, and this wrapper
// closes both without ejecting the upstream component (keeping the swizzle resilient
// to package upgrades):
//   1. The popup is wired with the legacy aria-owns attribute instead of aria-controls,
//      so we mirror aria-owns onto aria-controls and keep them in sync.
//   2. The "See all results" footer link is rendered as a bare interactive child of the
//      role="listbox" element, which is not an allowed listbox child (WCAG 1.3.1 / axe
//      aria-required-children). We tag the footer's anchor itself with role="option" so
//      the listbox only owns valid leaf options; tagging the wrapping div instead would
//      leave the focusable anchor as a nested interactive descendant (axe nested-interactive).
export default function SearchBarWrapper(props) {
  const containerRef = useRef(null);
  const statusRef = useRef(null);

  useEffect(() => {
    const root = containerRef.current;
    const statusNode = statusRef.current;
    if (!root || !statusNode) {
      return undefined;
    }

    let lastResultCount = null;
    let lastQuery = '';
    let lastOpenState = false;
    let announceTimer = null;
    let currentInput = null;
    // The upstream widget owns a hashed CSS-module "cursor" class for the
    // highlighted option. When focus roves onto the external "See all results"
    // footer we borrow that class so the footer shows the same highlight; this
    // remembers the discovered token across state changes.
    let footerActiveClass = null;
    // How long to defend a Tab destination against the widget restoring focus
    // to its input while the popup tears down.
    const FOCUS_GUARD_MS = 600;
    // Active focus guards, so an unmount mid-guard cannot leave a listener
    // attached to the document.
    const focusGuardCleanups = [];

    const clearStatusMessage = () => {
      window.clearTimeout(announceTimer);
      statusNode.textContent = '';
    };

    const announceResultCount = (count, query) => {
      const message = count === 0
        ? `No results for "${query}". Try a broader term or browse the documentation.`
        : `${count} result${count === 1 ? '' : 's'}`;
      clearStatusMessage();
      announceTimer = window.setTimeout(() => {
        statusNode.textContent = message;
      }, 120);
    };

    const getSearchInput = () => root.querySelector('input.navbar__search-input');
    const getListbox = () => root.querySelector('[role="listbox"]');
    const getFooterLink = (listboxNode) => (listboxNode ? listboxNode.querySelector('[class*="hitFooter"] a') : null);
    const getResultOptions = (listboxNode) => Array.from(listboxNode?.querySelectorAll('[role="option"]') ?? []).filter(
      (option) => !option.closest('[class*="hitFooter"]'),
    );
    // Locate whichever element currently carries the upstream "cursor" highlight
    // class (a hashed CSS-module token such as `cursor_xxxx`) so it can be cleared
    // from the options while the footer shows its own highlight.
    const findCursor = (listboxNode) => {
      const holder = listboxNode ? listboxNode.querySelector('[class*="cursor"]') : null;
      const cls = holder
        ? Array.from(holder.classList).find((name) => /cursor/i.test(name))
        : null;
      return { holder, cls: cls ?? footerActiveClass };
    };

    // Returns focusable candidates in document order that sit outside the
    // search widget, nearest first. Callers must confirm a candidate actually
    // takes focus: matching the selector and having layout boxes does not make
    // an element focusable. Docusaurus's back-to-top button is the concrete
    // case here - it is the next control after the navbar search, it has layout
    // boxes, and it is visibility:hidden until the page scrolls, so focus() on
    // it is a silent no-op.
    const collectFocusTargetsOutsideWidget = (input, backwards) => {
      const focusableSelector = [
        'a[href]',
        'button:not([disabled])',
        'input:not([disabled])',
        'select:not([disabled])',
        'textarea:not([disabled])',
        '[tabindex]:not([tabindex="-1"])',
      ].join(',');
      const all = Array.from(document.querySelectorAll(focusableSelector))
        .filter((element) => element.getClientRects().length > 0)
        .filter((element) => element.getAttribute('tabindex') !== '-1');
      const index = all.indexOf(input);
      if (index === -1) {
        return [];
      }
      const step = backwards ? -1 : 1;
      const candidates = [];
      for (let cursor = index + step; cursor >= 0 && cursor < all.length; cursor += step) {
        const candidate = all[cursor];
        if (root && root.contains(candidate)) {
          continue;
        }
        if (typeof candidate.focus === 'function') {
          candidates.push(candidate);
        }
      }
      return candidates;
    };

    // Moves focus to the nearest candidate that genuinely accepts it, and
    // returns that element, or null when nothing outside the widget can take
    // focus.
    const focusOutsideWidget = (input, backwards) => {
      for (const candidate of collectFocusTargetsOutsideWidget(input, backwards)) {
        candidate.focus();
        if (document.activeElement === candidate) {
          return candidate;
        }
      }
      return null;
    };

    const clearFooterHighlight = (footerLink) => {
      if (footerLink) {
        footerLink.classList.remove('search-footer-active');
      }
      // The borrowed upstream class can also be left on the footer, so clear any
      // stray copy site-wide rather than only the class this repository adds.
      if (footerActiveClass && footerLink) {
        footerLink.classList.remove(footerActiveClass);
      }
    };

    // Exactly one option may claim the active and selected state. APG requires
    // aria-selected on the option the active descendant points at, and requires
    // it to be false (or absent) everywhere else, so a screen reader announces
    // one current choice rather than none or many.
    const setActiveOption = (input, option, listboxNode) => {
      const listbox = listboxNode ?? getListbox();
      const candidates = [
        ...getResultOptions(listbox),
        ...(getFooterLink(listbox) ? [getFooterLink(listbox)] : []),
      ];
      for (const candidate of candidates) {
        candidate.setAttribute('aria-selected', candidate === option ? 'true' : 'false');
      }
      if (option?.id) {
        input.setAttribute('aria-activedescendant', option.id);
      } else {
        input.removeAttribute('aria-activedescendant');
      }
    };

    const clearActiveOption = (input, listboxNode) => {
      const listbox = listboxNode ?? getListbox();
      for (const candidate of getResultOptions(listbox)) {
        candidate.setAttribute('aria-selected', 'false');
      }
      const footerLink = getFooterLink(listbox);
      if (footerLink) {
        footerLink.setAttribute('aria-selected', 'false');
      }
      input.removeAttribute('aria-activedescendant');
    };

    const handleInputKeyDown = (event) => {
      const input = getSearchInput();
      const listbox = getListbox();
      const footerLink = getFooterLink(listbox);
      if (!input) {
        return;
      }

      // Tab must escape unconditionally. Two mechanisms conspire to trap focus,
      // and both are handled here.
      //
      // First, the upstream handler cancels Tab to keep focus inside the
      // combobox, which is a WCAG 2.1.2 keyboard trap under a screen reader
      // whose focus mode keeps the popup open. Gating this on a listbox or
      // footer link would leave the trap intact in exactly the states where it
      // bites, including the zero-results state where no footer link exists.
      //
      // Second, and confirmed by measurement: the next element in native focus
      // order is the search clear button, which lives inside this widget. A
      // native Tab therefore lands inside the widget, the widget then tears the
      // popup down, and focus falls to <body>. Moving focus explicitly to the
      // first candidate outside the widget avoids handing focus to an element
      // that is about to be removed. The move is re-asserted asynchronously
      // because the widget restores focus to the input while closing.
      //
      // The default move is cancelled only after a destination is confirmed.
      // Cancelling first and then discovering no target leaves focus pinned on
      // the input with the native move already suppressed, which is itself the
      // keyboard trap this handler exists to prevent.
      if (event.key === 'Tab') {
        // Resolve against the element the user is actually on. Reading the
        // input from the container can return a different (or stale) node than
        // the focused one, which yields no index in the focus order and no
        // target.
        const focusedInput = document.activeElement instanceof HTMLElement
          ? document.activeElement
          : input;
        const shift = event.shiftKey;

        // Move focus first, then decide whether to cancel the native Tab. A
        // handler that cancels Tab and then fails to place focus leaves the
        // user pinned on the input with no way out by keyboard, which is the
        // WCAG 2.1.2 trap this exists to prevent. Attempting the move first
        // makes cancelling conditional on having actually succeeded.
        const target = focusOutsideWidget(focusedInput, shift);
        if (!target) {
          // Nothing outside the widget can take focus: let the browser do
          // whatever it would normally do rather than swallowing the key.
          return;
        }

        event.stopImmediatePropagation();
        event.preventDefault();
        clearFooterHighlight(footerLink);
        input.removeAttribute('aria-activedescendant');

        // The widget tears its popup down asynchronously and restores focus to
        // the input on the way, so the move above can be undone a few frames
        // later. Guard the destination by re-claiming focus if it returns to
        // the widget, rather than polling a fixed number of frames.
        const guard = (guardEvent) => {
          const landed = guardEvent.target;
          if (landed === target) {
            return;
          }
          // Only contest focus the widget itself reclaimed. A deliberate move
          // elsewhere (the user tabbing onward) is left alone.
          if (landed === input || (root && root.contains(landed))) {
            target.focus();
          }
        };
        const stopGuard = () => {
          document.removeEventListener('focusin', guard, true);
          window.clearTimeout(guardTimer);
        };
        const guardTimer = window.setTimeout(stopGuard, FOCUS_GUARD_MS);
        document.addEventListener('focusin', guard, true);
        focusGuardCleanups.push(stopGuard);
        return;
      }

      if (!listbox || !footerLink) {
        return;
      }

      const options = getResultOptions(listbox);
      const lastOption = options[options.length - 1];
      const activeDescendantId = input.getAttribute('aria-activedescendant');
      const isOnFooter = activeDescendantId === footerLink.id;
      const isOnLastOption = Boolean(lastOption) && activeDescendantId === lastOption.id;

      // Last option -> footer. The upstream handler would wrap the selection back
      // to the first option, so stop it and move the active descendant onto the
      // "See all results" footer ourselves. Clear the upstream option highlight
      // and apply our own stable highlight class to the footer.
      if ((event.key === 'ArrowDown' || event.key === 'End') && lastOption && isOnLastOption) {
        event.preventDefault();
        event.stopImmediatePropagation();
        const { holder, cls } = findCursor(listbox);
        if (holder && cls) {
          footerActiveClass = cls;
          holder.classList.remove(cls);
        }
        footerLink.classList.add('search-footer-active');
        setActiveOption(input, footerLink, listbox);
        footerLink.scrollIntoView({ block: 'nearest' });
        return;
      }

      // Footer -> last option. Stop upstream (its internal cursor still points at
      // the last option) and restore the highlight there.
      if (event.key === 'ArrowUp' && isOnFooter && lastOption) {
        event.preventDefault();
        event.stopImmediatePropagation();
        clearFooterHighlight(footerLink);
        if (footerActiveClass) {
          lastOption.classList.add(footerActiveClass);
        }
        setActiveOption(input, lastOption, listbox);
        lastOption.scrollIntoView({ block: 'nearest' });
        return;
      }

      // Footer -> first option (wrap). Let upstream advance from the last option
      // to the first; only clear the footer's highlight first.
      if (event.key === 'ArrowDown' && isOnFooter) {
        clearFooterHighlight(footerLink);
        return;
      }

      // Escape collapses the popup. Clear the roving position and the borrowed
      // highlight so a later re-open does not resume pointing at an option that
      // is no longer rendered.
      if (event.key === 'Escape') {
        clearFooterHighlight(footerLink);
        clearActiveOption(input, listbox);
        return;
      }

      // Enter on the footer follows the "See all results" link instead of
      // activating the upstream widget's last selected option.
      if (event.key === 'Enter' && isOnFooter) {
        event.preventDefault();
        event.stopImmediatePropagation();
        footerLink.click();
      }
    };

    const sync = () => {
      const input = getSearchInput();
      if (input && input !== currentInput) {
        if (currentInput) {
          currentInput.removeEventListener('keydown', handleInputKeyDown, true);
        }
        currentInput = input;
        currentInput.addEventListener('keydown', handleInputKeyDown, { capture: true });
      }

      if (input) {
        const owns = input.getAttribute('aria-owns');
        if (owns) {
          if (input.getAttribute('aria-controls') !== owns) {
            input.setAttribute('aria-controls', owns);
          }
        } else if (input.hasAttribute('aria-controls')) {
          input.removeAttribute('aria-controls');
        }
      }

      const listbox = getListbox();
      const footerLink = getFooterLink(listbox);
      const query = input ? input.value.trim() : '';
      // The upstream widget hides (rather than removes) the popup on Escape, so
      // presence alone is not "open"; require the listbox to be rendered/visible.
      const listboxVisible = Boolean(listbox) && listbox.getClientRects().length > 0;
      const isOpen = listboxVisible && query.length > 0;

      if (input) {
        // Only claim the combobox role once the widget can actually behave as
        // one. Upstream attaches lazily on first interaction and only then adds
        // aria-autocomplete and the popup wiring; advertising role="combobox"
        // before that point announces "combobox, collapsed" for a control that
        // owns nothing, which is worse than the native searchbox semantics the
        // input already has.
        const upstreamAttached = input.hasAttribute('aria-autocomplete');
        if (upstreamAttached) {
          if (input.getAttribute('role') !== 'combobox') {
            input.setAttribute('role', 'combobox');
          }
          const nextExpanded = isOpen ? 'true' : 'false';
          if (input.getAttribute('aria-expanded') !== nextExpanded) {
            input.setAttribute('aria-expanded', nextExpanded);
          }
        } else {
          if (input.hasAttribute('role')) {
            input.removeAttribute('role');
          }
          if (input.hasAttribute('aria-expanded')) {
            input.removeAttribute('aria-expanded');
          }
        }

        // A collapsed popup owns no options, so a retained active descendant
        // points at an element that is gone or hidden.
        if (!isOpen && input.hasAttribute('aria-activedescendant')) {
          clearActiveOption(input, listbox);
        }

        if (footerLink) {
          if (footerLink.getAttribute('role') !== 'option') {
            footerLink.setAttribute('role', 'option');
          }
          if (footerLink.getAttribute('tabindex') !== '-1') {
            footerLink.setAttribute('tabindex', '-1');
          }
          if (!footerLink.id) {
            footerLink.id = 'search-footer-link';
          }
        }

        const resultOptions = getResultOptions(listbox);
        const totalOptions = resultOptions.length + (footerLink ? 1 : 0);
        resultOptions.forEach((option, index) => {
          option.setAttribute('aria-posinset', String(index + 1));
          option.setAttribute('aria-setsize', String(totalOptions));
        });
        if (footerLink) {
          footerLink.setAttribute('aria-posinset', String(totalOptions));
          footerLink.setAttribute('aria-setsize', String(totalOptions));
        }

        // The theme renders the clear control with a camelCase CSS-module class
        // (searchClearButton_xxxx) and no type attribute. CSS attribute
        // substring matching is case-sensitive, so the `i` flag is required to
        // match it; without the flag the control never receives its name and is
        // announced only as its glyph.
        const clearButton = root.querySelector('button[type="reset"], button[class*="clear" i]');
        if (clearButton && clearButton.getAttribute('aria-label') !== 'Clear search') {
          clearButton.setAttribute('aria-label', 'Clear search');
        }

        const descriptionId = 'search-shortcut-description';
        let descriptionNode = root.querySelector(`#${descriptionId}`);
        if (!descriptionNode) {
          descriptionNode = document.createElement('div');
          descriptionNode.id = descriptionId;
          // HTMLElement.style is [PutForwards=cssText]; assigning an object is a
          // silent no-op, so copy each declaration onto the live style object to
          // keep the node visually hidden (sr-only) rather than rendered.
          Object.assign(descriptionNode.style, srOnlyStyle);
          descriptionNode.textContent = 'Keyboard shortcut: Control plus K';
          root.prepend(descriptionNode);
        }

        const currentDescribedBy = input.getAttribute('aria-describedby');
        const describedByIds = currentDescribedBy ? currentDescribedBy.split(/\s+/) : [];
        if (!describedByIds.includes(descriptionId)) {
          input.setAttribute('aria-describedby', [...describedByIds, descriptionId].join(' ').trim());
        }

        const headingId = 'search-input-heading';
        let headingNode = root.querySelector(`#${headingId}`);
        if (!headingNode) {
          headingNode = document.createElement('h2');
          headingNode.id = headingId;
          // Same [PutForwards=cssText] caveat as the description node above: the
          // sr-only styles must be copied onto the live style object, otherwise
          // this heading renders visibly and injects a stray h2 into the banner.
          Object.assign(headingNode.style, srOnlyStyle);
          headingNode.textContent = 'Search';
          root.prepend(headingNode);
        }

        if (input.getAttribute('aria-labelledby') !== headingId) {
          input.setAttribute('aria-labelledby', headingId);
        }
        if (!input.hasAttribute('aria-label')) {
          input.setAttribute('aria-label', 'Search');
        }
      }

      let resultCount = 0;
      if (listbox) {
        const options = Array.from(listbox.querySelectorAll('[role="option"]')).filter(
          (option) => !option.closest('[class*="hitFooter"]'),
        );
        resultCount = options.length;
      }

      if (!query || !isOpen) {
        clearStatusMessage();
        lastQuery = query;
        lastResultCount = resultCount;
        lastOpenState = isOpen;
        return;
      }

      const shouldAnnounce =
        query !== lastQuery || resultCount !== lastResultCount || isOpen !== lastOpenState;

      if (shouldAnnounce) {
        announceResultCount(resultCount, query);
      }

      lastQuery = query;
      lastResultCount = resultCount;
      lastOpenState = isOpen;
    };

    // The combobox attributes are applied lazily, the first time the input is
    // focused and the search index loads, and the popup contents are rebuilt on
    // every keystroke, so observe the whole search container rather than reading
    // the initial state once.
    //
    // sync() mutates attributes/DOM inside `root`, which would otherwise be
    // re-observed and re-trigger sync() in an unbounded microtask loop that
    // freezes the main thread once results (and the footer link) render. Wrap
    // every run so the observer is disconnected while our own mutations are
    // applied and reconnected afterward; only genuine upstream mutations then
    // schedule another run.
    let observer;
    const observerConfig = { subtree: true, childList: true, attributes: true };
    const runSync = () => {
      if (observer) {
        observer.disconnect();
      }
      try {
        sync();
      } finally {
        if (observer) {
          observer.observe(root, observerConfig);
        }
      }
    };

    runSync();
    observer = new MutationObserver(runSync);
    observer.observe(root, observerConfig);

    return () => {
      if (currentInput) {
        currentInput.removeEventListener('keydown', handleInputKeyDown, true);
      }
      for (const stopGuard of focusGuardCleanups.splice(0)) {
        stopGuard();
      }
      observer.disconnect();
      clearStatusMessage();
    };
  }, []);

  return (
    <div ref={containerRef} style={{ display: 'contents' }}>
      <div ref={statusRef} role="status" aria-live="polite" aria-atomic="true" style={srOnlyStyle} />
      <SearchBar {...props} />
    </div>
  );
}
