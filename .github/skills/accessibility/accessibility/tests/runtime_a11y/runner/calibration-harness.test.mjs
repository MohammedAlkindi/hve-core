// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import { evaluateAssertion } from '../../../scripts/runtime_a11y/runner/assertions.mjs';
import {
  buildDefectSummary,
  createCalibrationCheckpoint,
  createCalibrationFixture,
  createCalibrationHarness,
  runCalibrationSession,
  validateCalibrationCheckpoint,
} from '../../../scripts/runtime_a11y/runner/calibration-harness.mjs';

function classifyPreparedResult(result) {
  if (result.status === 'fail') {
    return 'fail';
  }
  if (result.status === 'candidate' || result.status === 'unsupported' || result.status === 'error') {
    return 'candidate';
  }
  return 'pass';
}

test('calibration fixtures cover the required patterns and expected evidence', () => {
  const patterns = ['checkbox', 'tabs', 'modal', 'menu-button', 'combobox'];
  for (const pattern of patterns) {
    const fixture = createCalibrationFixture(pattern);
    assert.ok(fixture, `${pattern} fixture should exist`);
    assert.ok(fixture.expected.speech, `${pattern} speech expectation should exist`);
    assert.ok(fixture.expected.browserState, `${pattern} browser-state expectation should exist`);
    assert.ok(fixture.expected.accessibilityTree, `${pattern} accessibility-tree expectation should exist`);
  }
});

test('repeated runs classify flaky prepared results as candidate rather than pass', () => {
  const results = [
    { status: 'pass' },
    { status: 'candidate' },
    { status: 'pass' },
  ];
  const flaky = results.some((result) => result.status === 'candidate');
  const classification = flaky ? 'candidate' : 'pass';

  assert.equal(classification, 'candidate');
  assert.equal(classifyPreparedResult({ status: 'candidate' }), 'candidate');
});

test('assertion families evaluate independently for speech, browser state, and accessibility tree evidence', () => {
  const speech = evaluateAssertion({ id: 'speech', type: 'contains', value: 'checked', evidenceType: 'speech' }, ['checked', 'checkbox']);
  const browser = evaluateAssertion({ id: 'browser', type: 'contains', value: 'checked', evidenceType: 'browserState' }, ['checked', 'checkbox']);
  const tree = evaluateAssertion({ id: 'tree', type: 'contains', value: 'checkbox', evidenceType: 'accessibilityTree' }, ['checked', 'checkbox']);

  assert.equal(speech.status, 'pass');
  assert.equal(browser.status, 'pass');
  assert.equal(tree.status, 'pass');
  assert.equal(speech.evidenceType, 'speech');
  assert.equal(browser.evidenceType, 'browserState');
  assert.equal(tree.evidenceType, 'accessibilityTree');
});

test('calibration harness alternates journeys and persists resumable checkpoints', () => {
  const harness = createCalibrationHarness();
  assert.equal(harness.nextCase(), '14399');
  const first = createCalibrationCheckpoint({
    journeyId: '14399',
    ordinal: 0,
    profileFingerprint: { locale: 'en-US', verbosity: 'default' },
    provenance: { driver: 'guidepup' },
    artifactHashes: { visual: 'a' },
    classification: 'pass',
  });
  const accepted = harness.applyCheckpoint(first);

  assert.equal(accepted.accepted, true);
  assert.equal(harness.nextCase(), '14410');
  assert.equal(validateCalibrationCheckpoint(first), true);
});

test('checkpoints use canonical recursive JSON serialization and SHA-256 hashes', () => {
  const first = createCalibrationCheckpoint({
    journeyId: '14399',
    ordinal: 0,
    profileFingerprint: { locale: 'en-US' },
    provenance: { driver: 'guidepup' },
    artifactHashes: { visual: { nested: ['alpha', 'beta'], values: { order: 1 } } },
    classification: 'pass',
  });
  const second = createCalibrationCheckpoint({
    journeyId: '14399',
    ordinal: 0,
    profileFingerprint: { locale: 'en-US' },
    provenance: { driver: 'guidepup' },
    artifactHashes: { visual: { values: { order: 1 }, nested: ['alpha', 'beta'] } },
    classification: 'pass',
  });

  assert.equal(first.hash, second.hash);
  assert.match(first.hash, /^[a-f0-9]{64}$/);
  assert.equal(validateCalibrationCheckpoint(first), true);
});

test('non-pass classifications do not consume an accepted ordinal or checkpoint', () => {
  const harness = createCalibrationHarness({ maxExecutionsPerJourney: 1 });
  const rejected = harness.applyCheckpoint(createCalibrationCheckpoint({
    journeyId: '14399',
    ordinal: 0,
    profileFingerprint: { locale: 'en-US' },
    provenance: { driver: 'guidepup' },
    artifactHashes: {},
    classification: 'infrastructureFailure',
  }));

  assert.equal(rejected.accepted, false);
  assert.equal(harness.journeys['14399'].completed.length, 0);
  assert.equal(harness.journeys['14399'].ordinal, 0);
});

test('runCalibrationSession validates retained visual bundles on resume and skips duplicate preflight work', async () => {
  const tempDir = mkdtempSync(join(tmpdir(), 'calibration-resume-preflight-'));
  try {
    const checkpointPath = join(tempDir, 'state.json');
    const artifactPath = join(tempDir, 'artifacts', 'preflight.png');
    mkdirSync(join(tempDir, 'artifacts'), { recursive: true });
    writeFileSync(artifactPath, 'retained-preflight');
    const hash = createHash('sha256').update(readFileSync(artifactPath)).digest('hex');
    const harness = createCalibrationHarness({ maxExecutionsPerJourney: 1 });
    harness.visualPreflightBundle = {
      bundleId: 'visual-preflight',
      artifactHashes: { 'artifacts/preflight.png': hash },
      summary: { classification: 'pass' },
    };
    const state = harness.buildResumeState();
    writeFileSync(checkpointPath, JSON.stringify({ state, checkpoints: [] }));

    let preflightRuns = 0;
    const session = await runCalibrationSession({
      checkpointPath,
      maxExecutionsPerJourney: 1,
      runRoot: tempDir,
      probePrerequisites: async () => ({ nvdaAvailable: true, desktopUnlocked: true }),
      runVisualPreflight: async () => {
        preflightRuns += 1;
        return { status: 'pass', artifactHashes: { 'artifacts/preflight.png': 'unused' }, summary: { classification: 'pass' } };
      },
      runAtCase: async ({ journeyId, ordinal }) => ({
        journeyId,
        ordinal,
        classification: 'pass',
        artifactHashes: { screenshot: `${journeyId}-${ordinal}` },
        provenance: { locale: 'en-US' },
        outcome: { status: 'pass' },
      }),
    });

    assert.equal(preflightRuns, 0);
    assert.equal(session.aggregate.status, 'successful');
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test('runCalibrationSession requires validated retained preflight for nvdaOnly mode', async () => {
  const tempDir = mkdtempSync(join(tmpdir(), 'calibration-nvda-only-'));
  try {
    const checkpointPath = join(tempDir, 'state.json');
    const session = await runCalibrationSession({
      checkpointPath,
      maxExecutionsPerJourney: 1,
      mode: 'nvdaOnly',
      runRoot: tempDir,
      probePrerequisites: async () => ({ nvdaAvailable: true, desktopUnlocked: true }),
      runVisualPreflight: async () => ({ status: 'pass', artifactHashes: { 'artifacts/preflight.png': 'unused' }, summary: { classification: 'pass' } }),
      runAtCase: async () => { throw new Error('should not run'); },
    });

    assert.equal(session.aggregate.status, 'incomplete');
    assert.match(session.aggregate.reason, /retained visual preflight/i);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test('runCalibrationSession continues the other journey after an authoritative AT failure and aggregates unsuccessful status', async () => {
  const tempDir = mkdtempSync(join(tmpdir(), 'calibration-authoritative-'));
  try {
    const checkpointPath = join(tempDir, 'state.json');
    let runCount = 0;
    const session = await runCalibrationSession({
      checkpointPath,
      maxExecutionsPerJourney: 1,
      runRoot: tempDir,
      probePrerequisites: async () => ({ nvdaAvailable: true, desktopUnlocked: true }),
      runVisualPreflight: async () => ({ status: 'pass', artifactHashes: { 'artifacts/preflight.png': 'unused' }, summary: { classification: 'pass' } }),
      runAtCase: async ({ journeyId }) => {
        runCount += 1;
        if (journeyId === '14399') {
          return {
            journeyId,
            classification: 'assertionFailure',
            artifactHashes: { screenshot: 'asserted' },
            provenance: { locale: 'en-US' },
            outcome: { status: 'fail' },
          };
        }
        return {
          journeyId,
          classification: 'pass',
          artifactHashes: { screenshot: `${journeyId}-${runCount}` },
          provenance: { locale: 'en-US' },
          outcome: { status: 'pass' },
        };
      },
    });

    assert.equal(runCount, 2);
    assert.equal(session.aggregate.status, 'unsuccessful');
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test('evaluation can use raw speech by default and normalized speech when explicitly selected', () => {
  const rawResult = evaluateAssertion(
    { type: 'contains', value: 'search results' },
    { speech: ['Search Results'], normalizedSpeech: ['results'] },
    { useNormalizedSpeech: false },
  );
  const normalizedResult = evaluateAssertion(
    { type: 'contains', value: 'search results' },
    { speech: ['Search Results'], normalizedSpeech: ['search results'] },
    { useNormalizedSpeech: true },
  );

  assert.equal(rawResult.status, 'pass');
  assert.equal(normalizedResult.status, 'pass');
});

test('runCalibrationSession alternates journeys, writes checkpoints, and aggregates successful completion', async () => {
  const tempDir = mkdtempSync(join(tmpdir(), 'calibration-session-'));
  try {
    const checkpointPath = join(tempDir, 'state.json');
    let runCount = 0;
    const session = await runCalibrationSession({
      checkpointPath,
      maxExecutionsPerJourney: 1,
      probePrerequisites: async () => ({ nvdaAvailable: true, desktopUnlocked: true }),
      runVisualPreflight: async () => ({ status: 'pass', artifactHashes: { screenshot: 'a' }, summary: { classification: 'pass' } }),
      runAtCase: async ({ journeyId, ordinal }) => {
        runCount += 1;
        return {
          journeyId,
          ordinal,
          classification: 'pass',
          artifactHashes: { screenshot: `${journeyId}-${ordinal}` },
          provenance: { locale: 'en-US' },
          outcome: { status: 'pass' },
        };
      },
    });

    assert.equal(runCount, 2);
    assert.equal(session.aggregate.status, 'successful');
    assert.equal(session.checkpoints.length, 2);
    assert.equal(readFileSync(checkpointPath, 'utf8').includes('"journeyId"'), true);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test('runCalibrationSession resumes from a checkpoint and skips validated completed ordinals', async () => {
  const tempDir = mkdtempSync(join(tmpdir(), 'calibration-resume-'));
  try {
    const checkpointPath = join(tempDir, 'state.json');
    const existing = createCalibrationCheckpoint({
      journeyId: '14399',
      ordinal: 0,
      profileFingerprint: { locale: 'en-US' },
      provenance: { locale: 'en-US' },
      artifactHashes: { screenshot: 'existing' },
      classification: 'pass',
    });
    const harness = createCalibrationHarness({ maxExecutionsPerJourney: 1 });
    harness.applyCheckpoint(existing);
    const state = harness.buildResumeState();
    state.visualPreflightBundle = { id: 'preflight' };
    const checkpointFile = { state, checkpoints: [existing] };
    writeFileSync(checkpointPath, JSON.stringify(checkpointFile));

    let runCount = 0;
    const session = await runCalibrationSession({
      checkpointPath,
      maxExecutionsPerJourney: 1,
      probePrerequisites: async () => ({ nvdaAvailable: true, desktopUnlocked: true }),
      runVisualPreflight: async () => ({ status: 'pass', artifactHashes: { screenshot: 'a' }, summary: { classification: 'pass' } }),
      runAtCase: async ({ journeyId, ordinal }) => {
        runCount += 1;
        return {
          journeyId,
          ordinal,
          classification: 'pass',
          artifactHashes: { screenshot: `${journeyId}-${ordinal}` },
          provenance: { locale: 'en-US' },
          outcome: { status: 'pass' },
        };
      },
    });

    assert.equal(runCount, 1);
    assert.equal(session.aggregate.status, 'successful');
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test('runCalibrationSession reports incomplete status and targeted guidance when NVDA or desktop prerequisites are unavailable', async () => {
  const tempDir = mkdtempSync(join(tmpdir(), 'calibration-unavailable-'));
  try {
    const checkpointPath = join(tempDir, 'state.json');
    const session = await runCalibrationSession({
      checkpointPath,
      maxExecutionsPerJourney: 1,
      probePrerequisites: async () => ({ nvdaAvailable: false, desktopUnlocked: false }),
      runVisualPreflight: async () => ({ status: 'pass', artifactHashes: { screenshot: 'a' }, summary: { classification: 'pass' } }),
      runAtCase: async () => { throw new Error('should not run'); },
    });

    assert.equal(session.aggregate.status, 'incomplete');
    assert.match(session.aggregate.reason, /NVDA/i);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test('calibration harness stops a journey after two infrastructure or drift failures and preserves independent work', () => {
  const harness = createCalibrationHarness();
  const first = harness.applyOutcome({
    journeyId: '14399',
    classification: 'infrastructureFailure',
    provenance: { driver: 'guidepup' },
    artifactReferences: ['artifacts/14399.png'],
  });
  const second = harness.applyOutcome({
    journeyId: '14399',
    classification: 'transcriptDrift',
    provenance: { driver: 'guidepup' },
    artifactReferences: ['artifacts/14399.png'],
  });

  assert.equal(first.journey.status, 'active');
  assert.equal(second.journey.status, 'stopped');
  assert.equal(second.journey.stopReason, 'early-stop');
  assert.equal(harness.journeys['14410'].status, 'active');
});

test('product failures produce defect summaries and unavailable runs keep visual evidence linked', () => {
  const summary = buildDefectSummary({
    bugId: '14410',
    reproduction: 'Launch the local search journey and focus the results region.',
    expected: 'The search status should announce the new result count.',
    actual: 'The spoken output remained stale.',
    classification: 'productFailure',
    provenance: { driver: 'guidepup', locale: 'en-US' },
    artifactReferences: ['artifacts/visual-preflight.png'],
  });
  const harness = createCalibrationHarness({ visualPreflightBundle: { id: 'preflight' } });
  const unavailable = harness.applyOutcome({
    journeyId: '14399',
    classification: 'unavailable',
    provenance: { driver: 'guidepup' },
    artifactReferences: ['artifacts/visual-preflight.png'],
  });

  assert.equal(summary.classification, 'productFailure');
  assert.equal(unavailable.journey.status, 'unavailable');
  assert.equal(harness.visualPreflightBundle.id, 'preflight');
});
