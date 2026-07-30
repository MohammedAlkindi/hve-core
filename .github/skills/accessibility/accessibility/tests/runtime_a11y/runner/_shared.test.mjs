// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildChromeLaunchOptions, ensureAutomationWindowFocused } from '../../../scripts/runtime_a11y/runner/_shared.mjs';

test('buildChromeLaunchOptions hardens system Chrome against restore and first-run prompts', () => {
  const options = buildChromeLaunchOptions({ headless: false, args: ['--window-size=1440,900'] });

  assert.equal(options.channel, 'chrome');
  assert.equal(options.headless, false);
  assert.deepEqual(options.args, [
    '--disable-session-crashed-bubble',
    '--hide-crash-restore-bubble',
    '--no-default-browser-check',
    '--no-first-run',
    '--force-renderer-accessibility',
    '--window-size=1440,900',
  ]);
});

test('ensureAutomationWindowFocused binds when the foreground title matches the automation marker', async () => {
  const events = [];
  const page = {
    async title() {
      return 'runtime-a11y-marker';
    },
    async evaluate(callback, value) {
      if (typeof callback === 'function') {
        if (value === undefined) {
          return 'runtime-a11y-marker';
        }
        return value;
      }
      return value;
    },
    async bringToFront() {
      events.push('bring-to-front');
    },
  };
  const context = {
    async newCDPSession() {
      return {
        async send(method) {
          events.push(method);
          if (method === 'Browser.getWindowForTarget') {
            return { windowId: 3 };
          }
          if (method === 'Browser.setWindowBounds') {
            return {};
          }
          throw new Error(`unexpected method: ${method}`);
        },
      };
    },
  };

  const result = await ensureAutomationWindowFocused({
    page,
    browser: null,
    context,
    platform: 'win32',
    timeoutMs: 20,
    pollIntervalMs: 5,
    readForegroundTitle: async () => 'runtime-a11y-marker - Google Chrome',
    activateWindow: async () => false,
    activateTarget: async () => false,
  });

  assert.equal(result.status, 'bound');
  assert.equal(result.foregroundTitle, 'runtime-a11y-marker - Google Chrome');
  assert.equal(events.includes('bring-to-front'), true);
});

test('ensureAutomationWindowFocused reports an unbound result when the foreground title does not match', async () => {
  const page = {
    async title() {
      return 'runtime-a11y-marker';
    },
    async evaluate(callback, value) {
      if (typeof callback === 'function') {
        return 'runtime-a11y-marker';
      }
      return value;
    },
    async bringToFront() {},
  };
  const context = {
    async newCDPSession() {
      return {
        async send(method) {
          if (method === 'Browser.getWindowForTarget') {
            return { windowId: 4 };
          }
          if (method === 'Browser.setWindowBounds') {
            return {};
          }
          throw new Error(`unexpected method: ${method}`);
        },
      };
    },
  };

  const result = await ensureAutomationWindowFocused({
    page,
    browser: null,
    context,
    platform: 'win32',
    timeoutMs: 20,
    pollIntervalMs: 5,
    readForegroundTitle: async () => 'Other window - Google Chrome',
    activateWindow: async () => false,
    activateTarget: async () => false,
  });

  assert.equal(result.status, 'unbound');
  assert.equal(result.foregroundTitle, 'Other window - Google Chrome');
  assert.equal(result.reason.includes('foreground-window-does-not-match-page-under-test'), true);
});

test('ensureAutomationWindowFocused returns unsupported on non-Windows platforms', async () => {
  const result = await ensureAutomationWindowFocused({
    page: null,
    browser: null,
    context: null,
    platform: 'linux',
    timeoutMs: 20,
    pollIntervalMs: 5,
  });

  assert.equal(result.status, 'unsupported');
});

test('ensureAutomationWindowFocused uses activation remediation before second probe', async () => {
  const events = [];
  const page = {
    async title() {
      return 'runtime-a11y-marker';
    },
    async bringToFront() {
      events.push('bring-to-front');
    },
  };
  const context = {
    async newCDPSession() {
      return {
        async send(method) {
          if (method === 'Browser.getWindowForTarget') {
            return { windowId: 7 };
          }
          if (method === 'Target.getTargetInfo') {
            return { targetInfo: { targetId: 'target-7' } };
          }
          if (method === 'Browser.setWindowBounds') {
            return {};
          }
          throw new Error(`unexpected method: ${method}`);
        },
      };
    },
  };
  let readCount = 0;
  const result = await ensureAutomationWindowFocused({
    page,
    browser: null,
    context,
    platform: 'win32',
    timeoutMs: 30,
    pollIntervalMs: 1,
    readForegroundTitle: async () => {
      readCount += 1;
      if (readCount === 1) {
        return 'New Tab - Google Chrome';
      }
      return 'runtime-a11y-marker - Google Chrome';
    },
    activateWindow: async (title) => {
      events.push(`activate:${title}`);
      return true;
    },
    activateTarget: async ({ targetId }) => {
      events.push(`activate-target:${targetId}`);
      return true;
    },
  });

  assert.equal(result.status, 'bound');
  assert.equal(result.remediationAttempted, true);
  assert.equal(events.includes('activate-target:target-7'), true);
  assert.equal(events.includes('activate:runtime-a11y-marker'), true);
});
