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
    // The /search/ page renders no <main> landmark, so anchor the live region
    // on <body> and guard against duplicate nodes across mounts with a stable id.
    const STATUS_ID = 'search-results-status';
    let statusNode = document.getElementById(STATUS_ID);
    if (!statusNode) {
      statusNode = document.createElement('div');
      statusNode.id = STATUS_ID;
      statusNode.setAttribute('role', 'status');
      statusNode.setAttribute('aria-live', 'polite');
      statusNode.setAttribute('aria-atomic', 'true');
      Object.assign(statusNode.style, srOnlyStyle);
      document.body.appendChild(statusNode);
    }
    statusNode.textContent = '';
    statusRef.current = statusNode;

    // Separate timers: one debounces recomputation, the other sets the text.
    // Sharing a single timer let the results observer keep cancelling the
    // pending announcement so it never fired.
    let syncTimer = null;
    let announceTimer = null;
    let lastMessage = null;

    const getSearchInput = () => document.querySelector('input[name="q"]');

    // Results render as <article> elements (searchResultItem); this component
    // only mounts on /search/, so counting articles is unambiguous.
    const getResultCount = () => document.querySelectorAll('article').length;

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
        statusNode.textContent = '';
        lastMessage = null;
        return;
      }
      const count = getResultCount();
      announce(count === 0
        ? 'No documents found'
        : `${count} document${count === 1 ? '' : 's'} found`);
    };

    const scheduleSync = () => {
      window.clearTimeout(syncTimer);
      syncTimer = window.setTimeout(syncStatus, 150);
    };

    const input = getSearchInput();
    if (input) {
      input.addEventListener('input', scheduleSync);
    }

    // Watch for result additions/removals. There is no stable results wrapper,
    // so observe the document body's childList/subtree (no attributes, to avoid
    // starving the announcement with noise).
    const observer = new MutationObserver(scheduleSync);
    observer.observe(document.body, { childList: true, subtree: true });

    scheduleSync();

    return () => {
      if (input) {
        input.removeEventListener('input', scheduleSync);
      }
      observer.disconnect();
      window.clearTimeout(syncTimer);
      window.clearTimeout(announceTimer);
      statusNode.remove();
    };
  }, []);

  return <SearchPage {...props} />;
}
