import { chromium } from 'playwright';
import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';

import {
  buildProbeResults,
  emitProbeResult,
  findNamelessControls,
  loadProbeCriteriaMap,
  redactUrl,
} from './_core.mjs';
import { createScreenReaderDriver } from './drivers/driver-contract.mjs';

const DEFAULT_VIEWPORT = { width: 1280, height: 900 };

// Installed as an init script before navigation so it observes the live DOM from
// first paint. Records post-load live-region announcements into a window global
// that probes (notably probe-live-region) read to decide whether a status
// message actually fired rather than merely existing. The shared runner clears
// the update log immediately before the state trigger so recorded updates are
// genuine trigger-driven announcements, not hydration noise.
export function liveRegionObserverScript() {
  const LIVE_SELECTOR =
    '[aria-live="polite"],[aria-live="assertive"],[role="status"],[role="alert"],[role="log"]';
  const state = { updates: [], loadCount: 0, emptyAtLoad: 0 };
  window.__runtimeA11yLiveRegion = state;

  const regionFor = (node) => {
    const element = node && node.nodeType === 1 ? node : node && node.parentElement;
    return element && element.closest ? element.closest(LIVE_SELECTOR) : null;
  };

  let started = false;
  const start = () => {
    if (started || !document.body) {
      return;
    }
    started = true;
    const regions = Array.from(document.querySelectorAll(LIVE_SELECTOR));
    state.loadCount = regions.length;
    state.emptyAtLoad = regions.filter((region) => (region.textContent || '').trim() === '').length;

    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        const region = regionFor(mutation.target);
        if (!region) {
          continue;
        }
        const text = (region.textContent || '').trim();
        state.updates.push({ text: text.slice(0, 120), at: Date.now() });
        if (state.updates.length > 20) {
          state.updates.shift();
        }
      }
    });
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      characterData: true,
      attributes: true,
      attributeFilter: ['aria-live'],
    });
  };

  if (document.body) {
    start();
  } else {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  }
}

function getRuntimeConfig() {
  const raw = process.env.RUNTIME_A11Y_CONFIG || '{}';
  return JSON.parse(raw);
}

function getRuntimeContext() {
  const config = getRuntimeConfig();
  return {
    config,
    probeId: process.env.RUNTIME_A11Y_PROBE_ID || 'probe-unknown',
    surfaceId: process.env.RUNTIME_A11Y_SURFACE_ID || '',
    state: process.env.RUNTIME_A11Y_STATE || 'default',
    baseUrl: process.env.RUNTIME_A11Y_BASE_URL || config.baseUrl || 'http://127.0.0.1:3000',
    trace: process.env.RUNTIME_A11Y_TRACE === '1',
  };
}

function resolveTargetUrl(baseUrl, surface) {
  const route = surface?.route || '';
  if (!route) {
    return baseUrl;
  }

  try {
    return new URL(route, baseUrl).toString();
  } catch {
    const normalized = route.startsWith('/') ? route : `/${route}`;
    return `${baseUrl.replace(/\/$/, '')}${normalized}`;
  }
}

function resolveLocator(page, target) {
  if (typeof target === 'string') {
    return page.locator(target);
  }

  if (target && typeof target === 'object') {
    if (target.kind === 'role') {
      return page.getByRole(target.role || 'button', { name: target.name || undefined });
    }
    if (target.value) {
      return page.locator(target.value);
    }
  }

  return page.locator('body');
}

async function applyTrigger(page, trigger) {
  if (!trigger) {
    return;
  }

  const action = trigger.action || 'visit';
  const target = trigger.target;
  const locator = resolveLocator(page, target);

  switch (action) {
    case 'click':
      await locator.click({ timeout: 1000 }).catch(() => undefined);
      break;
    case 'focus':
      await locator.focus({ timeout: 1000 }).catch(() => undefined);
      break;
    case 'hover':
      await locator.hover({ timeout: 1000 }).catch(() => undefined);
      break;
    case 'type':
      await locator.fill(trigger.value || '', { timeout: 1000 }).catch(() => undefined);
      break;
    case 'press':
      await page.keyboard.press(trigger.value || 'Enter').catch(() => undefined);
      break;
    case 'navigate':
      await page.goto(trigger.value || '/', { waitUntil: 'domcontentloaded' }).catch(() => undefined);
      break;
    case 'visit':
      if (typeof target === 'string' || target?.value) {
        await page.goto(target.value || target || '/', { waitUntil: 'domcontentloaded' }).catch(() => undefined);
      }
      break;
    default:
      break;
  }

  if (trigger.waitFor) {
    const waitFor = resolveLocator(page, trigger.waitFor);
    await waitFor.waitFor({ state: 'visible', timeout: 1000 }).catch(() => undefined);
  }
}

async function applyStateEmulation(page, state) {
  const viewport = state === 'mobile'
    ? { width: 390, height: 844 }
    : state === 'reflow-320'
      ? { width: 320, height: 900 }
      : state === 'zoom-400'
        ? { width: 1280, height: 900 }
        : DEFAULT_VIEWPORT;

  await page.setViewportSize(viewport);
  await page.emulateMedia({
    colorScheme: state.includes('dark') ? 'dark' : 'light',
    forcedColors: state.includes('forced-colors') ? 'active' : 'none',
    reducedMotion: state.includes('reduced-motion') ? 'reduce' : 'no-preference',
  });

  if (state.includes('zoom-400')) {
    await page.evaluate(() => {
      document.documentElement.style.fontSize = '200%';
    }).catch(() => undefined);
  }

  if (state.includes('reflow-320')) {
    await page.evaluate(() => {
      document.documentElement.style.fontSize = '16px';
    }).catch(() => undefined);
  }
}

async function gatherTracingAssets(page, context, tracePath) {
  if (!tracePath) {
    return null;
  }

  await page.screenshot({ path: tracePath.replace(/\.zip$/, '.png'), fullPage: true }).catch(() => undefined);
  await context.tracing.stop({ path: tracePath }).catch(() => undefined);
  return tracePath;
}

export async function injectAxe(page) {
  try {
    const mod = await import('@axe-core/playwright');
    const AxeBuilder = mod.default || mod.AxeBuilder;
    if (!AxeBuilder) {
      return null;
    }
    const builder = new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']);
    return await builder.analyze();
  } catch {
    return null;
  }
}

export async function snapshotAccessibilityTree(page) {
  try {
    return await page.accessibility.snapshot();
  } catch {
    return null;
  }
}

// Launch headless system Chrome. Exposed so smoke tests (which live outside the
// node_modules tree) can obtain a browser without importing the 'playwright'
// bare specifier from a location where it does not resolve.
export async function launchChrome() {
  return chromium.launch({ channel: 'chrome', headless: true });
}

// The virtual screen reader's browser build is a self-contained ESM bundle,
// resolved from the skill-local node_modules relative to this module.
const VSR_BROWSER_BUILD = new URL(
  '../node_modules/@guidepup/virtual-screen-reader/lib/esm/index.browser.js',
  import.meta.url,
);

// Inject the virtual screen reader into the live page, drive it end to end, and
// return a snapshot of the announced phrase log with the nameless interactive
// controls it exposes. Shared by probe-virtual-sr and its smoke tests so both
// exercise the identical capture path.
export async function captureVirtualSr(page) {
  try {
    const moduleSource = await readFile(VSR_BROWSER_BUILD, 'utf8');
    const traversal = await page.evaluate(async (source) => {
      const blob = new Blob([source], { type: 'text/javascript' });
      const url = URL.createObjectURL(blob);
      try {
        const { virtual } = await import(url);
        await virtual.start({ container: document.body });
        let guard = 0;
        let reachedEnd = false;
        while (guard < 2000) {
          guard += 1;
          await virtual.next();
          if ((await virtual.lastSpokenPhrase()) === 'end of document') {
            reachedEnd = true;
            break;
          }
        }
        const log = await virtual.spokenPhraseLog();
        await virtual.stop();
        return { log, reachedEnd };
      } finally {
        URL.revokeObjectURL(url);
      }
    }, moduleSource);

    const nameless = findNamelessControls(traversal.log);
    return {
      ran: true,
      phraseCount: traversal.log.length,
      reachedEnd: traversal.reachedEnd,
      namelessCount: nameless.length,
      nameless: nameless.slice(0, 5),
    };
  } catch (error) {
    return { ran: false, error: error instanceof Error ? error.message : String(error) };
  }
}

// Clear the live-region announcement log so only updates after this point count
// as a fired status message.
export async function clearLiveRegionLog(page) {
  await page
    .evaluate(() => {
      if (window.__runtimeA11yLiveRegion) {
        window.__runtimeA11yLiveRegion.updates = [];
      }
    })
    .catch(() => undefined);
}

// Read the live-region observation snapshot after allowing debounced announcers
// to settle. Shared by probe-live-region and its smoke tests.
export async function readLiveRegionSnapshot(page, { settleMs = 500 } = {}) {
  if (settleMs > 0) {
    await page.waitForTimeout(settleMs).catch(() => undefined);
  }
  return page.evaluate(() => {
    const LIVE_SELECTOR =
      '[aria-live="polite"],[aria-live="assertive"],[role="status"],[role="alert"],[role="log"]';
    const live = window.__runtimeA11yLiveRegion || { updates: [], loadCount: 0, emptyAtLoad: 0 };
    return {
      regionsAtLoad: live.loadCount,
      regionsNow: document.querySelectorAll(LIVE_SELECTOR).length,
      emptyAtLoad: live.emptyAtLoad,
      fired: live.updates.length > 0,
      firedTexts: live.updates.map((update) => update.text).slice(-3),
    };
  });
}

export async function runProbeWithPage(callback) {
  const contextData = getRuntimeContext();
  const { config, probeId, surfaceId, state, baseUrl, trace } = contextData;
  const surface = (config.surfaces || []).find((entry) => entry.id === surfaceId) || null;
  const targetUrl = resolveTargetUrl(baseUrl, surface);
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const context = await browser.newContext({
    viewport: DEFAULT_VIEWPORT,
    colorScheme: 'light',
    forcedColors: 'none',
    reducedMotion: 'no-preference',
  });
  const page = await context.newPage();
  // Observe live-region announcements from first paint so probes can decide
  // whether a status message fires, not merely whether a region exists.
  await page.addInitScript(liveRegionObserverScript);

  let tracePath = null;
  if (trace) {
    await context.tracing.start({ screenshots: true, snapshots: true, sources: true });
    const artifactsDir = path.join(process.cwd(), 'artifacts', `${probeId}-${surfaceId}-${state}`);
    await mkdir(artifactsDir, { recursive: true });
    tracePath = path.join(artifactsDir, 'trace.zip');
  }

  try {
    await applyStateEmulation(page, state);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });
    // Allow client frameworks to hydrate so probes observe the settled DOM
    // rather than transient pre-hydration markup. Capped so a page that never
    // reaches network idle does not stall the run.
    await page.waitForLoadState('networkidle', { timeout: 2500 }).catch(() => undefined);
    const trigger = surface?.states?.find((entry) => entry.state === state)?.trigger || null;
    // Discard any live-region updates from hydration so only trigger-driven
    // announcements are counted as a fired status message.
    await clearLiveRegionLog(page);
    await applyTrigger(page, trigger);
    return await callback({ browser, context, page, targetUrl, surface, state, tracePath, baseUrl, probeId, surfaceId });
  } finally {
    if (tracePath) {
      await gatherTracingAssets(page, context, tracePath).catch(() => undefined);
    }
    await context.close().catch(() => undefined);
    await browser.close().catch(() => undefined);
  }
}

export async function runRealScreenReaderProbe(page, { surface, state, targetUrl, config = {} } = {}) {
  const runtimeConfig = config || getRuntimeContext().config || {};
  const surfaceConfig = surface?.states?.find((entry) => entry.state === state) || {};
  const probeConfig = surfaceConfig?.realScreenReader || runtimeConfig?.realScreenReader || {};
  let driver = null;

  try {
    driver = await createScreenReaderDriver({ platform: process.platform, config: probeConfig });

    if (!driver?.supported) {
      return {
        ran: false,
        supported: false,
        reason: driver?.reason || driver?.status || 'unsupported',
        phrases: [],
        assertions: [],
        driver: driver?.driver || null,
        platform: process.platform,
      };
    }

    await driver.start();
    for (const command of probeConfig.commands || []) {
      await driver.executeCommand(command);
    }
    const snapshot = await driver.captureLog();
    const phrases = Array.isArray(snapshot?.phrases) ? snapshot.phrases : [];
    const assertions = Array.isArray(snapshot?.assertions) ? snapshot.assertions : [];

    if (Array.isArray(probeConfig.expectedAnnouncements) && probeConfig.expectedAnnouncements.length > 0) {
      const normalized = phrases.join(' || ');
      for (const assertion of assertions) {
        if (assertion.type === 'contains') {
          assertion.status = normalized.toLowerCase().includes(String(assertion.value || '').toLowerCase()) ? 'pass' : 'fail';
        } else if (assertion.type === 'matches') {
          const regex = new RegExp(assertion.value);
          assertion.status = regex.test(normalized) ? 'pass' : 'fail';
        } else if (assertion.type === 'orderedContains') {
          assertion.status = normalized.toLowerCase().includes(String(assertion.value || '').toLowerCase()) ? 'pass' : 'fail';
        } else {
          assertion.status = 'candidate';
        }
      }
    }

    return {
      ran: true,
      supported: true,
      phrases,
      assertions,
      driver: snapshot?.driver || driver?.driver || null,
      platform: process.platform,
      targetUrl,
      state,
      evidence: JSON.stringify({ phrases, assertions, driver: snapshot?.driver || driver?.driver || null }),
    };
  } catch (error) {
    return {
      ran: false,
      supported: false,
      reason: error instanceof Error ? error.message : String(error),
      phrases: [],
      assertions: [],
      driver: driver?.driver || null,
      platform: process.platform,
    };
  } finally {
    if (driver?.supported && typeof driver.stop === 'function') {
      await driver.stop().catch(() => undefined);
    }
  }
}

export { redactUrl, buildProbeResults, emitProbeResult, loadProbeCriteriaMap };
