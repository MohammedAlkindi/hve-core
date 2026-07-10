// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT

import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DRIVER_DIR = path.dirname(fileURLToPath(import.meta.url));
const GUIDEPUP_MODULE = path.resolve(DRIVER_DIR, '../../node_modules/@guidepup/guidepup');

function normalizePlatform(platform) {
  return String(platform || '').toLowerCase();
}

function selectDriver(platform) {
  const normalized = normalizePlatform(platform);
  if (normalized === 'win32' || normalized === 'windows') {
    return 'nvda';
  }
  if (normalized === 'darwin' || normalized === 'macos' || normalized === 'macosx') {
    return 'voiceover';
  }
  return null;
}

export async function createGuidepupDriverAdapter({ platform = process.platform, config = {} } = {}) {
  const driver = selectDriver(platform);
  if (!driver) {
    return {
      supported: false,
      status: 'unsupported-platform',
      reason: `Guidepup real screen-reader support is only available on Windows and macOS. Received platform ${platform}.`,
    };
  }

  if (!existsSync(GUIDEPUP_MODULE)) {
    return {
      supported: false,
      status: 'unavailable-driver',
      reason: 'Guidepup dependency is not installed in the skill-local runtime_a11y package.',
    };
  }

  try {
    const mod = await import('@guidepup/guidepup');
    const target = driver === 'nvda' ? mod.nvda : mod.voiceOver;
    if (!target || typeof target.start !== 'function' || typeof target.stop !== 'function') {
      throw new Error(`Guidepup driver ${driver} is unavailable.`);
    }

    const commands = Array.isArray(config?.commands) ? config.commands : [];
    const expectedAnnouncements = Array.isArray(config?.expectedAnnouncements)
      ? config.expectedAnnouncements
      : [];

    return {
      supported: true,
      status: 'ready',
      driver,
      platform,
      async start() {
        await target.start();
        return { driver, platform };
      },
      async stop() {
        await target.stop();
      },
      async executeCommand(command) {
        if (!command || typeof command !== 'object') {
          return { kind: 'noop' };
        }
        if (command.kind === 'pause') {
          const durationMs = Number(command.durationMs || 0);
          await new Promise((resolve) => setTimeout(resolve, durationMs));
          return { kind: 'pause', durationMs };
        }
        if (command.kind === 'command') {
          const value = String(command.value || '');
          if (value === 'next') {
            await target.next();
          } else if (value === 'previous') {
            await target.previous();
          } else if (value === 'perform') {
            await target.perform();
          } else {
            await target.perform(target.keyboardCommands?.[value] ?? value);
          }
          return { kind: 'command', value };
        }
        return { kind: 'noop' };
      },
      async captureLog() {
        const phrases = Array.isArray(await target.spokenPhraseLog()) ? await target.spokenPhraseLog() : [];
        const assertions = expectedAnnouncements.map((assertion) => ({
          id: assertion.id || 'announcement',
          type: assertion.type,
          value: assertion.value,
          status: 'pending',
        }));
        return { driver, platform, phrases, assertions, commands };
      },
    };
  } catch (error) {
    return {
      supported: false,
      status: 'adapter-error',
      reason: error instanceof Error ? error.message : String(error),
    };
  }
}
