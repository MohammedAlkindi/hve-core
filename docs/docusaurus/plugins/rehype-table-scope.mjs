// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
// @ts-check
// Build-time table accessibility for the rendered HAST:
//   * scope="col" on every <thead> header cell and scope="row" on <tbody>
//     header cells (WAI H63), so screen readers announce header associations.
//   * a real <caption> (WAI H39) when the `:::table{caption="…"}` directive
//     supplied one, otherwise an aria-labelledby name derived from the nearest
//     preceding heading, so every data table exposes an accessible name.
// Row headers are opt-in: first-column body cells are promoted to
// <th scope="row"> only when the directive set the row-header flag.
import { visit } from 'unist-util-visit';

function isElement(node, tagName) {
  return Boolean(node && node.type === 'element' && node.tagName === tagName);
}

function isDataTable(node) {
  const children = node.children ?? [];
  return children.some((child) => isElement(child, 'thead'))
    || children.some((child) => isElement(child, 'th'))
    || children.some(
      (child) => (child.tagName === 'thead' || child.tagName === 'tbody')
        && (child.children ?? []).some((row) => (row.children ?? []).some((cell) => cell.tagName === 'th')),
    );
}

function isPresentationTable(node) {
  return node.properties?.role === 'presentation';
}

function hasCaption(node) {
  return (node.children ?? []).some((child) => isElement(child, 'caption'));
}

function readDataAttribute(properties, name) {
  if (!properties) {
    return undefined;
  }

  // hProperties preserve the literal `data-*` key; hast may also expose the
  // camelCased form depending on the pipeline, so read both.
  const camel = `data${name.charAt(0).toUpperCase()}${name.slice(1)}`;
  const value = properties[`data-${name}`] ?? properties[camel];
  delete properties[`data-${name}`];
  delete properties[camel];
  return value;
}

function eachRowCell(section, callback) {
  for (const row of section.children ?? []) {
    if (!isElement(row, 'tr')) {
      continue;
    }
    for (const cell of row.children ?? []) {
      callback(cell, row);
    }
  }
}

function processTable(node, headingId) {
  node.properties ??= {};
  const captionText = readDataAttribute(node.properties, 'caption');
  const rowheader = readDataAttribute(node.properties, 'rowheader') === 'true';

  // Header associations: thead cells are column headers, tbody header cells
  // are row headers.
  for (const section of node.children ?? []) {
    if (isElement(section, 'thead')) {
      eachRowCell(section, (cell) => {
        if (cell.tagName === 'th') {
          cell.properties ??= {};
          cell.properties.scope = 'col';
        }
      });
    } else if (isElement(section, 'tbody')) {
      eachRowCell(section, (cell) => {
        if (cell.tagName === 'th') {
          cell.properties ??= {};
          cell.properties.scope = 'row';
        }
      });
    }
  }

  // Opt-in row headers: promote each tbody row's first cell to a row header.
  if (rowheader) {
    for (const section of node.children ?? []) {
      if (!isElement(section, 'tbody')) {
        continue;
      }
      for (const row of section.children ?? []) {
        const firstCell = (row.children ?? []).find(
          (cell) => cell.tagName === 'td' || cell.tagName === 'th',
        );
        if (firstCell && firstCell.tagName === 'td') {
          firstCell.tagName = 'th';
          firstCell.properties ??= {};
          firstCell.properties.scope = 'row';
        }
      }
    }
  }

  // Accessible name: explicit caption wins; otherwise fall back to the nearest
  // preceding heading via aria-labelledby.
  if (captionText && !hasCaption(node)) {
    node.children = [
      {
        type: 'element',
        tagName: 'caption',
        properties: {},
        children: [{ type: 'text', value: captionText }],
      },
      ...(node.children ?? []),
    ];
  } else if (!captionText && !hasCaption(node) && headingId) {
    node.properties['aria-labelledby'] = headingId;
  }
}

export default function rehypeTableScope() {
  return (tree) => {
    let lastHeadingId;
    visit(tree, 'element', (node) => {
      if (/^h[1-6]$/.test(node.tagName) && node.properties?.id) {
        lastHeadingId = node.properties.id;
        return;
      }
      if (node.tagName === 'table' && isDataTable(node) && !isPresentationTable(node)) {
        processTable(node, lastHeadingId);
      }
    });
  };
}
