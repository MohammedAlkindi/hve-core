// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT

import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { basename, dirname, isAbsolute, relative, resolve } from 'node:path';

const JOURNEY_ORDER = ['14399', '14410'];
const DEFAULT_MAX_PER_JOURNEY = 20;
const DEFAULT_MAX_VISUAL_CASES = 10;

function stableStringify(value) {
  if (value === null || value === undefined) {
    return 'null';
  }
  if (typeof value !== 'object') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableStringify(entry)).join(',')}]`;
  }
  const entries = Object.entries(value)
    .filter(([, entryValue]) => entryValue !== undefined)
    .sort(([leftKey], [rightKey]) => leftKey.localeCompare(rightKey));
  return `{${entries.map(([key, entryValue]) => `${JSON.stringify(key)}:${stableStringify(entryValue)}`).join(',')}}`;
}

function hashCheckpoint(checkpoint) {
  return createHash('sha256').update(stableStringify(checkpoint)).digest('hex');
}

function hashFile(filePath) {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}

function normalizeArtifactReference(reference, runRoot = null) {
  if (typeof reference !== 'string' || reference.trim().length === 0) {
    return null;
  }
  const normalized = reference.replace(/\\/g, '/');
  if (/^(https?:|data:)/i.test(normalized)) {
    return normalized;
  }
  const resolvedRoot = resolve(runRoot || process.cwd());
  const absoluteTarget = isAbsolute(normalized) ? resolve(normalized) : resolve(resolvedRoot, normalized);
  const relativeTarget = relative(resolvedRoot, absoluteTarget);
  if (!relativeTarget || relativeTarget.startsWith('..') || relativeTarget === '.') {
    return basename(absoluteTarget);
  }
  return relativeTarget.replace(/\\/g, '/');
}

function validateRetainedBundle(bundle, runRoot = null) {
  if (!bundle || typeof bundle !== 'object') {
    return false;
  }
  const artifactHashes = bundle.artifactHashes || {};
  if (!artifactHashes || typeof artifactHashes !== 'object') {
    return false;
  }
  const resolvedRoot = resolve(runRoot || process.cwd());
  return Object.entries(artifactHashes).every(([artifactRef, expectedHash]) => {
    if (typeof expectedHash !== 'string' || expectedHash.length === 0) {
      return false;
    }
    const normalized = artifactRef.replace(/\\/g, '/');
    if (/^(https?:|data:)/i.test(normalized)) {
      return false;
    }
    const absoluteTarget = isAbsolute(normalized) ? resolve(normalized) : resolve(resolvedRoot, normalized);
    const relativeTarget = relative(resolvedRoot, absoluteTarget);
    if (!relativeTarget || relativeTarget.startsWith('..') || relativeTarget === '.') {
      return false;
    }
    if (!existsSync(absoluteTarget)) {
      return false;
    }
    return hashFile(absoluteTarget) === expectedHash;
  });
}

function createJourneyState(journeyId, state = {}) {
  return {
    journeyId,
    bugId: journeyId === '14399' ? '14399' : '14410',
    completed: [],
    status: 'active',
    stopReason: null,
    infraFailures: 0,
    driftFailures: 0,
    maxExecutions: state.maxExecutions || DEFAULT_MAX_PER_JOURNEY,
    ordinal: 0,
  };
}

export function createCalibrationHarness({ maxExecutionsPerJourney = DEFAULT_MAX_PER_JOURNEY, visualPreflightBundle = null } = {}) {
  return {
    visualPreflightBundle,
    journeys: JOURNEY_ORDER.reduce((accumulator, journeyId) => {
      accumulator[journeyId] = createJourneyState(journeyId, { maxExecutions: maxExecutionsPerJourney });
      return accumulator;
    }, {}),
    completedCount() {
      return Object.values(this.journeys).reduce((count, journey) => count + journey.completed.length, 0);
    },
    nextCase() {
      const activeJourneys = Object.values(this.journeys).filter((journey) => journey.status === 'active');
      if (activeJourneys.length === 0) {
        return null;
      }
      const totalCompleted = this.completedCount();
      const preferred = totalCompleted % 2 === 0 ? '14399' : '14410';
      const preferredJourney = activeJourneys.find((journey) => journey.journeyId === preferred);
      if (preferredJourney && preferredJourney.completed.length < preferredJourney.maxExecutions) {
        return preferredJourney.journeyId;
      }
      return activeJourneys.find((journey) => journey.completed.length < journey.maxExecutions)?.journeyId || null;
    },
    applyCheckpoint(checkpoint) {
      const journey = this.journeys[checkpoint.journeyId];
      if (!journey) {
        throw new Error(`Unknown journey: ${checkpoint.journeyId}`);
      }
      if (checkpoint.classification !== 'pass') {
        return { accepted: false, reason: 'non-pass' };
      }
      const expectedHash = checkpoint.hash;
      const { hash: _hash, ...payload } = checkpoint;
      const actualHash = hashCheckpoint(payload);
      if (expectedHash && expectedHash !== actualHash) {
        return { accepted: false, reason: 'hash-mismatch' };
      }
      const existing = journey.completed.find((entry) => entry.ordinal === checkpoint.ordinal);
      if (existing) {
        return { accepted: true, skipped: true, reason: 'duplicate' };
      }
      journey.completed.push({
        ...checkpoint,
        hash: expectedHash || actualHash,
      });
      journey.ordinal = Math.max(journey.ordinal, checkpoint.ordinal + 1);
      return { accepted: true, skipped: false };
    },
    applyOutcome({ journeyId, classification, outcome, provenance, artifactReferences, seededFailure = false, environment = {}, runRoot = null }) {
      const journey = this.journeys[journeyId];
      if (!journey) {
        throw new Error(`Unknown journey: ${journeyId}`);
      }
      if (classification === 'unavailable') {
        journey.status = 'unavailable';
        journey.stopReason = 'environment-unavailable';
        return {
          journey: { ...journey },
          summary: buildDefectSummary({
            bugId: journey.bugId,
            reproduction: 'Targeted NVDA calibration could not start because the desktop or NVDA prerequisites were unavailable.',
            expected: 'Local AT evidence should be captured under the pinned profile.',
            actual: 'Calibration stopped before AT execution and retained visual preflight evidence only.',
            classification,
            provenance,
            artifactReferences,
            runRoot,
          }),
        };
      }
      if (classification === 'productFailure' || classification === 'assertionFailure') {
        journey.status = 'stopped';
        journey.stopReason = 'authoritative-failure';
        return {
          journey: { ...journey },
          summary: buildDefectSummary({
            bugId: journey.bugId,
            reproduction: outcome?.reproduction || 'Reproduce the local AT journey using the current profile and site build.',
            expected: outcome?.expected || 'Expected spoken-output order should match the calibrated transcript.',
            actual: outcome?.actual || 'Observed output diverged from the calibrated expectation.',
            classification,
            provenance,
            artifactReferences,
            runRoot,
          }),
        };
      }
      if (classification === 'infrastructureFailure' || classification === 'transcriptDrift') {
        if (classification === 'infrastructureFailure') {
          journey.infraFailures += 1;
        } else {
          journey.driftFailures += 1;
        }
        if (journey.infraFailures + journey.driftFailures >= 2) {
          journey.status = 'stopped';
          journey.stopReason = 'early-stop';
        }
      }
      return { journey: { ...journey }, summary: null };
    },
    createVisualPreflight() {
      return {
        bundleId: 'visual-preflight',
        cases: Array.from({ length: DEFAULT_MAX_VISUAL_CASES }, (_, index) => ({ id: `visual-${index + 1}` })),
        linkedJourneys: Object.keys(this.journeys),
      };
    },
    buildResumeState() {
      return {
        journeys: Object.fromEntries(Object.entries(this.journeys).map(([journeyId, journey]) => [journeyId, {
          completed: journey.completed,
          status: journey.status,
          stopReason: journey.stopReason,
          ordinal: journey.ordinal,
          infraFailures: journey.infraFailures,
          driftFailures: journey.driftFailures,
        }])),
        visualPreflightBundle: this.visualPreflightBundle,
      };
    },
  };
}

export function buildDefectSummary({ bugId, reproduction, expected, actual, classification, provenance, artifactReferences, runRoot = null }) {
  return {
    bugId,
    reproduction,
    expected,
    actual,
    classification,
    provenance,
    artifactReferences: Array.isArray(artifactReferences)
      ? artifactReferences.map((reference) => normalizeArtifactReference(reference, runRoot)).filter(Boolean)
      : [],
  };
}

export function createCalibrationCheckpoint({ journeyId, ordinal, profileFingerprint, provenance, artifactHashes, classification }) {
  const checkpoint = {
    journeyId,
    ordinal,
    profileFingerprint,
    provenance,
    artifactHashes,
    classification,
  };
  return {
    ...checkpoint,
    hash: hashCheckpoint(checkpoint),
  };
}

export function validateCalibrationCheckpoint(checkpoint) {
  if (!checkpoint || typeof checkpoint !== 'object') {
    return false;
  }
  if (!checkpoint.journeyId || typeof checkpoint.ordinal !== 'number' || checkpoint.ordinal < 0) {
    return false;
  }
  if (!checkpoint.provenance || !checkpoint.profileFingerprint || !checkpoint.artifactHashes) {
    return false;
  }
  const { hash: _hash, ...payload } = checkpoint;
  return checkpoint.hash === hashCheckpoint(payload);
}

function normalizeCheckpointPayload(payload) {
  if (!payload || typeof payload !== 'object') {
    return [];
  }
  if (Array.isArray(payload)) {
    return payload;
  }
  if (Array.isArray(payload.checkpoints)) {
    return payload.checkpoints;
  }
  return [];
}

function persistCalibrationSession(checkpointPath, harness, checkpoints) {
  if (!checkpointPath) {
    return;
  }
  const payload = {
    state: harness.buildResumeState(),
    checkpoints,
  };
  mkdirSync(dirname(checkpointPath), { recursive: true });
  const tempPath = `${checkpointPath}.tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  try {
    writeFileSync(tempPath, JSON.stringify(payload, null, 2), 'utf8');
    if (existsSync(checkpointPath)) {
      unlinkSync(checkpointPath);
    }
    renameSync(tempPath, checkpointPath);
  } catch (error) {
    if (existsSync(tempPath)) {
      unlinkSync(tempPath);
    }
    throw error;
  }
}

function loadCalibrationSession(checkpointPath, harness) {
  if (!checkpointPath || !existsSync(checkpointPath)) {
    return { checkpoints: [], state: harness.buildResumeState() };
  }
  try {
    const payload = JSON.parse(readFileSync(checkpointPath, 'utf8'));
    const checkpoints = normalizeCheckpointPayload(payload);
    for (const checkpoint of checkpoints) {
      if (checkpoint && checkpoint.journeyId) {
        harness.applyCheckpoint(checkpoint);
      }
    }
    const persistedState = payload?.state || {};
    if (persistedState.journeys) {
      Object.entries(persistedState.journeys).forEach(([journeyId, journeyState]) => {
        const journey = harness.journeys[journeyId];
        if (!journey) {
          return;
        }
        journey.completed = Array.isArray(journeyState?.completed) ? journeyState.completed : [];
        journey.status = journeyState?.status || journey.status;
        journey.stopReason = journeyState?.stopReason || journey.stopReason;
        journey.ordinal = typeof journeyState?.ordinal === 'number' ? journeyState.ordinal : journey.ordinal;
        journey.infraFailures = typeof journeyState?.infraFailures === 'number' ? journeyState.infraFailures : journey.infraFailures;
        journey.driftFailures = typeof journeyState?.driftFailures === 'number' ? journeyState.driftFailures : journey.driftFailures;
      });
    }
    if (persistedState.visualPreflightBundle) {
      harness.visualPreflightBundle = persistedState.visualPreflightBundle;
    }
    return { checkpoints, state: persistedState };
  } catch {
    return { checkpoints: [], state: harness.buildResumeState() };
  }
}

function buildAggregate({ harness, visualPreflightFailure, missingRequiredEvidence = false }) {
  const journeys = Object.values(harness.journeys);
  const hasUnavailable = journeys.some((journey) => journey.status === 'unavailable');
  const hasAuthoritativeFailure = journeys.some((journey) => journey.stopReason === 'authoritative-failure');
  const hasEarlyStop = journeys.some((journey) => journey.stopReason === 'early-stop');
  const reachedTarget = journeys.every((journey) => journey.completed.length >= journey.maxExecutions);
  const everyAcceptedPass = journeys.every((journey) => journey.completed.every((entry) => entry.classification === 'pass'));

  if (visualPreflightFailure || hasAuthoritativeFailure || hasEarlyStop) {
    return {
      status: 'unsuccessful',
      reason: 'Calibration did not complete successfully because preflight or AT evidence was not accepted.',
      completedCount: harness.completedCount(),
    };
  }
  if (hasUnavailable || missingRequiredEvidence) {
    return {
      status: 'incomplete',
      reason: 'Calibration is incomplete because the run is missing required evidence or prerequisites.',
      completedCount: harness.completedCount(),
    };
  }
  if (reachedTarget && everyAcceptedPass) {
    return {
      status: 'successful',
      reason: 'Calibration completed for the requested journeys.',
      completedCount: harness.completedCount(),
    };
  }
  return {
    status: 'unsuccessful',
    reason: 'Calibration did not meet the required sample completion target.',
    completedCount: harness.completedCount(),
  };
}

export async function runCalibrationSession({
  checkpointPath = null,
  maxExecutionsPerJourney = DEFAULT_MAX_PER_JOURNEY,
  mode = 'full',
  runRoot = null,
  probePrerequisites = async () => ({ nvdaAvailable: true, desktopUnlocked: true }),
  runVisualPreflight = async () => null,
  runAtCase = async () => ({ classification: 'pass', outcome: { status: 'pass' } }),
} = {}) {
  const harness = createCalibrationHarness({
    maxExecutionsPerJourney,
    visualPreflightBundle: null,
  });
  const existing = loadCalibrationSession(checkpointPath, harness);
  const checkpoints = [...existing.checkpoints];

  let prerequisites = { nvdaAvailable: true, desktopUnlocked: true };
  if (probePrerequisites) {
    prerequisites = await probePrerequisites();
  }
  if (!prerequisites?.nvdaAvailable || !prerequisites?.desktopUnlocked) {
    const reasonParts = [];
    if (!prerequisites?.nvdaAvailable) {
      reasonParts.push('NVDA is not available on the host.');
    }
    if (!prerequisites?.desktopUnlocked) {
      reasonParts.push('The desktop session is not unlocked for AT interaction.');
    }
    const aggregate = {
      status: 'incomplete',
      reason: `Calibration could not start because ${reasonParts.join(' ')} ` +
        'Run the local AT loop again once the prerequisites are available.',
      completedCount: harness.completedCount(),
    };
    persistCalibrationSession(checkpointPath, harness, checkpoints);
    return { harness, checkpoints, aggregate, state: harness.buildResumeState() };
  }

  const retainedPreflight = existing.state?.visualPreflightBundle || harness.visualPreflightBundle;
  const retainedPreflightValid = validateRetainedBundle(retainedPreflight, runRoot);
  let visualPreflight = null;
  let visualPreflightFailure = false;
  let visualPreflightExecuted = false;
  let missingRequiredEvidence = false;

  if (retainedPreflightValid) {
    harness.visualPreflightBundle = {
      ...(harness.visualPreflightBundle || {}),
      ...(retainedPreflight || {}),
      retainedBundleValidated: true,
    };
  } else if (mode === 'nvdaOnly') {
    missingRequiredEvidence = true;
    const aggregate = {
      status: 'incomplete',
      reason: 'NVDA-only mode requires a validated retained visual preflight bundle under the supplied runRoot.',
      completedCount: harness.completedCount(),
    };
    persistCalibrationSession(checkpointPath, harness, checkpoints);
    return { harness, checkpoints, aggregate, state: harness.buildResumeState() };
  } else if (runVisualPreflight) {
    visualPreflightExecuted = true;
    visualPreflight = await runVisualPreflight({ harness, checkpointPath, runRoot });
    if (visualPreflight?.artifactHashes) {
      harness.visualPreflightBundle = {
        ...(harness.visualPreflightBundle || {}),
        ...visualPreflight,
      };
    }
    if (visualPreflight?.status === 'fail' || visualPreflight?.summary?.classification === 'fail' || visualPreflight?.summary?.classification === 'deterministicFailure') {
      visualPreflightFailure = true;
    }
  }

  while (true) {
    const nextJourneyId = harness.nextCase();
    if (!nextJourneyId) {
      break;
    }

    const journey = harness.journeys[nextJourneyId];
    if (journey.completed.length >= journey.maxExecutions) {
      break;
    }

    const result = await runAtCase({
      journeyId: nextJourneyId,
      ordinal: journey.completed.length,
      harness,
      checkpointPath,
      runRoot,
    });
    const classification = result?.classification || 'pass';
    let checkpoint = null;
    if (classification === 'pass') {
      checkpoint = createCalibrationCheckpoint({
        journeyId: nextJourneyId,
        ordinal: journey.completed.length,
        profileFingerprint: result?.profileFingerprint || { locale: 'en-US' },
        provenance: result?.provenance || { driver: 'guidepup' },
        artifactHashes: result?.artifactHashes || {},
        classification,
      });
      const accepted = harness.applyCheckpoint(checkpoint);
      if (!accepted.accepted) {
        break;
      }
      checkpoints.push(checkpoint);
      persistCalibrationSession(checkpointPath, harness, checkpoints);
    }

    const outcome = harness.applyOutcome({
      journeyId: nextJourneyId,
      classification,
      outcome: result?.outcome || { status: 'pass' },
      provenance: result?.provenance || { driver: 'guidepup' },
      artifactReferences: result?.artifactReferences || [],
      seededFailure: Boolean(result?.seededFailure),
      environment: result?.environment || {},
      runRoot,
    });
    if (outcome?.journey?.status === 'unavailable' || outcome?.journey?.status === 'stopped') {
      continue;
    }
  }

  const aggregate = buildAggregate({ harness, visualPreflightFailure, missingRequiredEvidence });
  persistCalibrationSession(checkpointPath, harness, checkpoints);
  return { harness, checkpoints, aggregate, state: harness.buildResumeState() };
}

export function createCalibrationFixture(pattern) {
  const fixtures = {
    '14399': {
      pattern: '14399',
      bugId: '14399',
      expected: {
        speech: 'search results',
        browserState: 'search',
        accessibilityTree: 'search',
      },
    },
    '14410': {
      pattern: '14410',
      bugId: '14410',
      expected: {
        speech: 'search updated',
        browserState: 'status',
        accessibilityTree: 'status',
      },
    },
    checkbox: {
      pattern: 'checkbox',
      bugId: 'checkbox',
      expected: {
        speech: 'checkbox checked',
        browserState: 'checked',
        accessibilityTree: 'checkbox',
      },
    },
    tabs: {
      pattern: 'tabs',
      bugId: 'tabs',
      expected: {
        speech: 'tab selected',
        browserState: 'selected',
        accessibilityTree: 'tab',
      },
    },
    modal: {
      pattern: 'modal',
      bugId: 'modal',
      expected: {
        speech: 'dialog opened',
        browserState: 'dialog',
        accessibilityTree: 'dialog',
      },
    },
    'menu-button': {
      pattern: 'menu-button',
      bugId: 'menu-button',
      expected: {
        speech: 'menu button expanded',
        browserState: 'expanded',
        accessibilityTree: 'menu button',
      },
    },
    combobox: {
      pattern: 'combobox',
      bugId: 'combobox',
      expected: {
        speech: 'combo box selected',
        browserState: 'selected',
        accessibilityTree: 'combobox',
      },
    },
  };
  if (!fixtures[pattern]) {
    throw new Error(`Unknown calibration pattern: ${pattern}`);
  }
  return fixtures[pattern];
}
