// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT

import assert from 'node:assert/strict';
import { mkdtemp, readFile, stat } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

import {
  buildVisualReviewPlan,
  buildDeterministicMeasurementEnvelope,
  captureVisualReviewEvidence,
} from '../../../scripts/runtime_a11y/runner/visual-review-executor.mjs';

test('buildVisualReviewPlan uses the homepage and configured search route for the required state matrix', () => {
  const plan = buildVisualReviewPlan({
    visualReview: {
      routes: [
        { path: '/', surfaceId: 'home' },
        { path: '/search?query=accessibility', state: 'search-results', surfaceId: 'search-results' },
      ],
    },
  });

  assert.equal(plan.routes.length, 2);
  assert.deepEqual(plan.routes.map((route) => route.path), ['/', '/search?query=accessibility']);
  assert.deepEqual(plan.states.map((entry) => entry.state), ['desktop', 'reflow-320', 'zoom-200', 'text-spacing', 'forced-colors']);
});

test('buildDeterministicMeasurementEnvelope includes geometry, overflow and focus metrics', () => {
  const envelope = buildDeterministicMeasurementEnvelope({
    viewport: { width: 1440, height: 900 },
    documentDimensions: { scrollWidth: 1600, clientWidth: 1440 },
    fixedOverlayCount: 2,
    interactiveOutsideViewport: [{ tag: 'button', text: 'Search' }],
    focusRectangleVisible: false,
    clippedTextCandidates: [{ text: 'Accessibility' }],
    overlapCandidates: [{ selector: 'header' }],
    overflowClassification: { code: 'allowed', table: 'allowed' },
  });

  assert.equal(envelope.documentDimensions.scrollWidth, 1600);
  assert.equal(envelope.metrics.rootHorizontalOverflow, true);
  assert.equal(envelope.metrics.fixedOverlayCount, 2);
  assert.equal(envelope.metrics.interactiveOutsideViewport.length, 1);
  assert.equal(envelope.metrics.focusRectangleVisible, false);
  assert.equal(envelope.metrics.allowedOverflow.code, 'allowed');
});

test('buildDeterministicMeasurementEnvelope defaults to the desktop viewport contract', () => {
  const envelope = buildDeterministicMeasurementEnvelope({});

  assert.deepEqual(envelope.viewport, { width: 1440, height: 900 });
});

test('captureVisualReviewEvidence writes a Playwright trace zip artifact and desktop measurements', async () => {
  const runRoot = await mkdtemp(path.join(os.tmpdir(), 'a11y-visual-review-'));
  process.env.RUNTIME_A11Y_VISUAL_REVIEW_RUN_ROOT = runRoot;

  try {
    const payload = await captureVisualReviewEvidence({
      visualReview: {
        routes: [{ path: '/', state: 'default', surfaceId: 'home' }],
        states: ['desktop'],
      },
      baseUrl: 'data:text/html,<html><body><h1>Visual review</h1></body></html>',
    });

    const run = payload.runs[0];
    assert.ok(run);
    const artifactDir = path.join(runRoot, 'artifacts', `${run.route.replace(/^\//, '').replace(/[^a-zA-Z0-9._-]+/g, '-')}-desktop`);
    const tracePath = path.join(artifactDir, 'trace.zip');
    const measurementPath = path.join(artifactDir, 'measurements.json');

    const traceStats = await stat(tracePath);
    const measurement = JSON.parse(await readFile(measurementPath, 'utf8'));
    assert.ok(traceStats.size > 0);
    assert.deepEqual(measurement.viewport, { width: 1440, height: 900 });
    assert.equal(run.browser.version, 'unknown');
    assert.deepEqual(run.viewport, { width: 1440, height: 900 });
  } finally {
    delete process.env.RUNTIME_A11Y_VISUAL_REVIEW_RUN_ROOT;
  }
});

test('captureVisualReviewEvidence records explicit capture failures for failed states', async () => {
  const runRoot = await mkdtemp(path.join(os.tmpdir(), 'a11y-visual-review-failure-'));
  process.env.RUNTIME_A11Y_VISUAL_REVIEW_RUN_ROOT = runRoot;

  try {
    const payload = await captureVisualReviewEvidence({
      visualReview: {
        routes: [{ path: 'http://127.0.0.1:1', state: 'default', surfaceId: 'home' }],
        states: ['desktop'],
      },
      baseUrl: 'http://127.0.0.1:1',
    });

    assert.equal(payload.runs.length, 1);
    assert.equal(payload.runs[0].probeOutcomes[0].status, 'capture-failure');
  } finally {
    delete process.env.RUNTIME_A11Y_VISUAL_REVIEW_RUN_ROOT;
  }
});
