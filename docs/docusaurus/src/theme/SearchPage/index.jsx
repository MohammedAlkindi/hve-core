// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import React, { useEffect, useRef } from 'react';
import SearchPage from '@theme-original/SearchPage';

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

export default function SearchPageWrapper(props) {
  const statusRef = useRef(null);

  useEffect(() => {
    // The status region is owned by this component and rendered inside the main
    // landmark. It was previously created on <body> under a fixed id and removed
    // unconditionally on unmount, so two live instances left the survivor writing
    // to a detached node and announcements stopped with no error.
    const statusNode = statusRef.current;
    if (!statusNode) {
      return undefined;
    }
    statusNode.textContent = '';

    // Separate timers: one debounces recomputation, the other sets the text.
    // Sharing a single timer let the results observer keep cancelling the
    // pending announcement so it never fired.
    let syncTimer = null;
    let announceTimer = null;
    let zeroConfirmTimer = null;
    let lastMessage = null;

    const getSearchInput = () => document.querySelector('input[name="q"]');

    // Results render as <article> elements (searchResultItem). Scope the count
    // to the main landmark so unrelated articles elsewhere on the page cannot
    // inflate the announced result count.
    const getResultsRoot = () => document.querySelector('main, [role="main"]') ?? document.body;
    const getResultCount = () => getResultsRoot().querySelectorAll('article').length;

    const announce = (message) => {
      if (message === lastMessage) {
        return;
      }
      lastMessage = message;
      window.clearTimeout(announceTimer);
      announceTimer = window.setTimeout(() => {
        statusNode.textContent = message;
      }, 60);
    };

    const syncStatus = () => {
      const input = getSearchInput();
      const query = input?.value?.trim() ?? '';
      if (!query) {
        window.clearTimeout(announceTimer);
        window.clearTimeout(zeroConfirmTimer);
        statusNode.textContent = '';
        lastMessage = null;
        return;
      }
      const count = getResultCount();
      if (count > 0) {
        window.clearTimeout(zeroConfirmTimer);
        announce(`${count} document${count === 1 ? '' : 's'} found`);
        return;
      }

      // A zero count is ambiguous: the query may simply not have resolved yet.
      // Search results render asynchronously, so announcing "No documents
      // found" on the first pass tells a screen-reader user there are no
      // results for a query that is still running, and the later correction
      // does not undo what they already heard. Require a quiet period with the
      // count still zero before making that claim.
      window.clearTimeout(zeroConfirmTimer);
      zeroConfirmTimer = window.setTimeout(() => {
        const currentInput = getSearchInput();
        const currentQuery = currentInput?.value?.trim() ?? '';
        if (currentQuery === query && getResultCount() === 0) {
          announce('No documents found');
        }
      }, 1500);
    };

    const scheduleSync = () => {
      window.clearTimeout(syncTimer);
      syncTimer = window.setTimeout(syncStatus, 150);
    };

    const input = getSearchInput();
    if (input) {
      input.addEventListener('input', scheduleSync);
    }

    // Watch for result additions/removals. The observer must see the whole
    // document because the results container is replaced during rendering, but
    // it ignores this component's own status writes: a body-wide observer that
    // reacts to them repeatedly reschedules the debounce and starves the
    // announcement it exists to trigger.
    const observer = new MutationObserver((records) => {
      const relevant = records.some(
        (record) => record.target !== statusNode && !statusNode.contains(record.target),
      );
      if (relevant) {
        scheduleSync();
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });

    scheduleSync();

    return () => {
      if (input) {
        input.removeEventListener('input', scheduleSync);
      }
      observer.disconnect();
      window.clearTimeout(syncTimer);
      window.clearTimeout(announceTimer);
      window.clearTimeout(zeroConfirmTimer);
    };
  }, []);

  return (
    <>
      <div
        ref={statusRef}
        id="search-results-status"
        role="status"
        aria-live="polite"
        aria-atomic="true"
        style={srOnlyStyle}
      />
      <SearchPage {...props} />
    </>
  );
}
