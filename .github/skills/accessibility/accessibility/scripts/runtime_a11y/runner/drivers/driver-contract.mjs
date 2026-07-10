// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT

import { createGuidepupDriverAdapter } from './guidepup-adapter.mjs';

export function validateScreenReaderConfig(config = {}) {
  const errors = [];
  const commands = Array.isArray(config?.commands) ? config.commands : [];
  const expectedAnnouncements = Array.isArray(config?.expectedAnnouncements)
    ? config.expectedAnnouncements
    : [];

  for (const command of commands) {
    if (!command || typeof command !== 'object') {
      errors.push('Each command must be an object.');
      continue;
    }
    if (command.kind === 'command' && typeof command.value !== 'string') {
      errors.push('Command entries require a string value.');
    }
    if (command.kind === 'pause' && (typeof command.durationMs !== 'number' || command.durationMs < 0)) {
      errors.push('Pause entries require a non-negative durationMs number.');
    }
  }

  for (const assertion of expectedAnnouncements) {
    if (!assertion || typeof assertion !== 'object') {
      errors.push('Each expected announcement must be an object.');
      continue;
    }
    if (!['contains', 'matches', 'orderedContains'].includes(assertion.type)) {
      errors.push('Expected announcements support contains, matches, or orderedContains.');
    }
    if (typeof assertion.value !== 'string' || assertion.value.trim() === '') {
      errors.push('Expected announcements require a non-empty string value.');
    }
  }

  return { ok: errors.length === 0, errors };
}

export async function createScreenReaderDriver({ platform = process.platform, driverName = 'guidepup', config = null } = {}) {
  const normalizedDriver = String(driverName || 'guidepup').toLowerCase();
  if (normalizedDriver !== 'guidepup') {
    return {
      supported: false,
      status: 'unsupported-driver',
      reason: `Unsupported screen-reader driver: ${driverName}`,
    };
  }

  const validation = validateScreenReaderConfig(config || {});
  if (!validation.ok) {
    return {
      supported: false,
      status: 'invalid-config',
      errors: validation.errors,
    };
  }

  const adapter = await createGuidepupDriverAdapter({ platform, config: config || {} });
  return adapter;
}
