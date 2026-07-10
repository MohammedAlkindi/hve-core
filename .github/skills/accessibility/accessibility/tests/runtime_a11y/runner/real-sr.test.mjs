// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { realScreenReaderStatus } from '../../../scripts/runtime_a11y/runner/_core.mjs';
import { createScreenReaderDriver, validateScreenReaderConfig } from '../../../scripts/runtime_a11y/runner/drivers/driver-contract.mjs';

test('validateScreenReaderConfig accepts generic commands and functional assertions', () => {
  const result = validateScreenReaderConfig({
    commands: [{ kind: 'command', value: 'next' }, { kind: 'pause', durationMs: 200 }],
    expectedAnnouncements: [
      { id: 'role-name', type: 'contains', value: 'button' },
      { id: 'name', type: 'orderedContains', value: 'Clear search' },
    ],
  });

  assert.equal(result.ok, true);
  assert.deepEqual(result.errors, []);
});

test('createScreenReaderDriver reports unsupported platforms without starting a real screen reader', async () => {
  const driver = await createScreenReaderDriver({ platform: 'linux', driverName: 'guidepup' });

  assert.equal(driver.supported, false);
  assert.equal(driver.status, 'unsupported-platform');
});

test('realScreenReaderStatus returns candidate for unsupported, missing, or adapter-error snapshots', () => {
  assert.equal(realScreenReaderStatus({ ran: false, error: 'unsupported platform' }), 'candidate');
  assert.equal(realScreenReaderStatus({ ran: true, phrases: [], assertions: [] }), 'candidate');
  assert.equal(realScreenReaderStatus({ ran: true, phrases: ['button, Clear search'], assertions: [{ status: 'fail' }] }), 'fail');
});

test('realScreenReaderStatus passes only when every configured assertion matches', () => {
  const passing = realScreenReaderStatus({
    ran: true,
    phrases: ['button, Clear search', 'button, Close dialog'],
    assertions: [
      { status: 'pass', type: 'contains', value: 'button' },
      { status: 'pass', type: 'orderedContains', value: 'Clear search' },
    ],
  });

  const failing = realScreenReaderStatus({
    ran: true,
    phrases: ['button, Clear search'],
    assertions: [
      { status: 'pass', type: 'contains', value: 'button' },
      { status: 'fail', type: 'orderedContains', value: 'Close dialog' },
    ],
  });

  assert.equal(passing, 'pass');
  assert.equal(failing, 'fail');
});
