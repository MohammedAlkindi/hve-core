// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import React from 'react';
import MDXComponents from '@theme-original/MDXComponents';

// Docusaurus renders wide markdown tables as horizontally scrollable. A
// scrollable region must be operable by keyboard so it can be scrolled without
// a pointer (WCAG 2.1.1 / axe scrollable-region-focusable). The focusable
// scroll container is the wrapping <div>, NOT the <table>: putting tabindex on
// the <table> itself makes screen readers treat it as a focusable object and
// breaks native table navigation (Ctrl+Alt+Arrow cell movement). Rendering the
// wrapper and its tabindex at build time keeps the focusable region present in
// the pre-rendered HTML, before hydration, so an on-load accessibility scan
// always sees it.
function Table(props: React.ComponentProps<'table'>): React.ReactElement {
  // The scroll container is non-interactive but must be keyboard focusable
  // (WCAG 2.1.1). jsx-a11y/no-noninteractive-tabindex does not model the
  // scrollable-region case, so it is disabled here with intent.
  return (
    // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
    <div className="tableWrapper" tabIndex={0}>
      <table {...props} />
    </div>
  );
}

export default {
  ...MDXComponents,
  table: Table,
};
