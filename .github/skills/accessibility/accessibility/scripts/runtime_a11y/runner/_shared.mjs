import { chromium } from 'playwright';
import { execFile } from 'node:child_process';
import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';

import { evaluateAssertion } from './assertions.mjs';
import {
  buildProbeResults,
  emitProbeResult,
  findNamelessControls,
  loadProbeCriteriaMap,
  redactUrl,
} from './_core.mjs';
import { createScreenReaderDriver } from './drivers/driver-contract.mjs';

const DEFAULT_VIEWPORT = { width: 1440, height: 900 };

const CHROME_HARDENING_ARGS = Object.freeze([
  '--disable-session-crashed-bubble',
  '--hide-crash-restore-bubble',
  '--no-default-browser-check',
  '--no-first-run',
  // Chrome builds its native accessibility tree lazily. A CDP client reading
  // the accessibility tree does not by itself make Chrome emit the platform
  // (IAccessible2/UIA) events a screen reader listens to, so live-region
  // mutations can go unannounced while static content still reads correctly.
  // Forcing renderer accessibility keeps the native event path active.
  '--force-renderer-accessibility',
]);

const execFileAsync = promisify(execFile);

// Reads the title of the window the operating system currently has in the
// foreground. This is the window a screen reader actually reads, which is not
// necessarily the window the automation drives over the DevTools protocol.
const FOREGROUND_WINDOW_TITLE_SCRIPT = [
  'Add-Type -Namespace RuntimeA11y -Name Win -MemberDefinition \'',
  '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();',
  '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);',
  '\';',
  '$h = [RuntimeA11y.Win]::GetForegroundWindow();',
  '$b = New-Object System.Text.StringBuilder 1024;',
  '[void][RuntimeA11y.Win]::GetWindowTextW($h, $b, $b.Capacity);',
  '[Console]::Out.Write($b.ToString())',
].join(' ');

const ACTIVATE_WINDOW_BY_TITLE_SCRIPT = [
  'Add-Type -Namespace RuntimeA11y -Name Win -MemberDefinition \'',
  '[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);',
  '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr hWnd, System.Text.StringBuilder s, int n);',
  '[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);',
  '[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);',
  '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);',
  'public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);',
  '\';',
  '$expected = [Environment]::GetEnvironmentVariable("RUNTIME_A11Y_EXPECTED_WINDOW_TITLE");',
  'if ([string]::IsNullOrWhiteSpace($expected)) { return; }',
  '$expected = $expected.Trim();',
  '$match = [IntPtr]::Zero;',
  '$callback = [RuntimeA11y.Win+EnumWindowsProc]{',
  '  param([IntPtr]$hWnd, [IntPtr]$lParam)',
  '  if (-not [RuntimeA11y.Win]::IsWindowVisible($hWnd)) { return $true; }',
  '  $buffer = New-Object System.Text.StringBuilder 1024;',
  '  [void][RuntimeA11y.Win]::GetWindowTextW($hWnd, $buffer, $buffer.Capacity);',
  '  $title = $buffer.ToString();',
  '  if ([string]::IsNullOrWhiteSpace($title)) { return $true; }',
  '  if ($title.IndexOf($expected, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {',
  '    $script:match = $hWnd;',
  '    return $false;',
  '  }',
  '  return $true;',
  '};',
  '[void][RuntimeA11y.Win]::EnumWindows($callback, [IntPtr]::Zero);',
  'if ($match -ne [IntPtr]::Zero) {',
  '  [void][RuntimeA11y.Win]::ShowWindowAsync($match, 9);',
  '  [void][RuntimeA11y.Win]::SetForegroundWindow($match);',
  '}',
].join(' ');

export async function readForegroundWindowTitle() {
  if (process.platform !== 'win32') {
    return null;
  }
  try {
    // Fixed script text with no interpolated input.
    const { stdout } = await execFileAsync(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', FOREGROUND_WINDOW_TITLE_SCRIPT],
      { timeout: 5000, windowsHide: true },
    );
    return String(stdout || '').trim();
  } catch {
    return null;
  }
}

export async function activateWindowByTitle(expectedTitle) {
  if (process.platform !== 'win32') {
    return false;
  }
  const title = typeof expectedTitle === 'string' ? expectedTitle.trim() : '';
  if (!title) {
    return false;
  }
  try {
    await execFileAsync(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', ACTIVATE_WINDOW_BY_TITLE_SCRIPT],
      {
        timeout: 5000,
        windowsHide: true,
        env: {
          ...process.env,
          RUNTIME_A11Y_EXPECTED_WINDOW_TITLE: title,
        },
      },
    );
    return true;
  } catch {
    return false;
  }
}

export async function activatePageTarget({ page, context, browser, targetId } = {}) {
  const resolvedTargetId = typeof targetId === 'string' ? targetId.trim() : '';
  if (!resolvedTargetId) {
    return false;
  }

  const targetContext = context || page?.context?.();
  const cdpSessionFactory = targetContext?.newCDPSession?.bind(targetContext);
  const browserCdpFactory = browser?.newBrowserCDPSession?.bind(browser);
  if (!cdpSessionFactory && !browserCdpFactory) {
    return false;
  }

  try {
    const cdpSession = cdpSessionFactory
      ? await cdpSessionFactory(page)
      : await browserCdpFactory();
    await cdpSession.send('Target.activateTarget', { targetId: resolvedTargetId });
    await page?.bringToFront?.().catch(() => undefined);
    return true;
  } catch {
    return false;
  }
}

async function collectControlledWindowIdentity({ page, browser, context } = {}) {
  const pageTitle = await page?.title?.().catch(() => null);
  let pageUrl = null;
  try {
    if (typeof page?.url === 'function') {
      pageUrl = page.url() || null;
    }
  } catch {
    pageUrl = null;
  }
  const targetContext = context || page?.context?.();
  const cdpSessionFactory = targetContext?.newCDPSession?.bind(targetContext);
  const browserCdpFactory = browser?.newBrowserCDPSession?.bind(browser);

  let windowId = null;
  let targetInfo = null;
  if (cdpSessionFactory || browserCdpFactory) {
    try {
      const cdpSession = cdpSessionFactory ? await cdpSessionFactory(page) : await browserCdpFactory();
      const windowForTarget = await cdpSession.send('Browser.getWindowForTarget').catch(() => null);
      if (Number.isFinite(Number(windowForTarget?.windowId))) {
        windowId = Number(windowForTarget.windowId);
      }
      targetInfo = await cdpSession.send('Target.getTargetInfo').catch(() => null);
    } catch {
      // Fall back to the lightweight title/url identity captured from Playwright.
    }
  }

  return {
    windowId,
    pageTitle,
    pageUrl,
    pageTargetId: targetInfo?.targetInfo?.targetId || targetInfo?.targetId || null,
    targetTitle: targetInfo?.targetInfo?.title || targetInfo?.title || pageTitle || null,
    targetUrl: targetInfo?.targetInfo?.url || targetInfo?.url || pageUrl || null,
  };
}

// Binds the screen reader's reading context to the window under test.
//
// Playwright controls a specific window over CDP, but a screen reader narrates
// whichever window the OS has focused. Without this check the harness can
// synthesize keystrokes into an unrelated window and capture that window's
// speech, which silently produces evidence about the wrong surface.
export async function ensureAutomationWindowFocused({
  page,
  browser,
  context,
  timeoutMs = 5000,
  pollIntervalMs = 250,
  platform = process.platform,
  readForegroundTitle = readForegroundWindowTitle,
  activateWindow = activateWindowByTitle,
  activateTarget = activatePageTarget,
} = {}) {
  if (String(platform).toLowerCase() !== 'win32' && String(platform).toLowerCase() !== 'windows') {
    return { status: 'unsupported', reason: 'foreground-check-requires-windows' };
  }
  if (!page || typeof page.title !== 'function') {
    return { status: 'unbound', reason: 'page-unavailable', attempts: 0 };
  }

  const documentTitle = await page.title().catch(() => null);
  if (!documentTitle) {
    return { status: 'unbound', reason: 'document-title-unavailable', attempts: 0 };
  }

  const expectedIdentity = await collectControlledWindowIdentity({ page, browser, context });
  const deadline = Date.now() + timeoutMs;
  let attempts = 0;
  let remediationAttempted = false;
  let foregroundTitle = null;
  let foregroundIdentity = null;

  while (Date.now() < deadline && attempts < 2) {
    attempts += 1;
    await maximizeBrowserWindow({ browser, context, page });
    await page.bringToFront?.().catch(() => undefined);
    if (typeof page.focus === 'function') {
      await page.focus().catch(() => undefined);
    }
    foregroundTitle = await readForegroundTitle();
    foregroundIdentity = { windowTitle: foregroundTitle || null };

    // Chrome titles its window "<document title> - Google Chrome", so matching
    // on the document title confirms the focused window is the page under test.
    if (foregroundTitle && foregroundTitle.includes(documentTitle)) {
      return {
        status: 'bound',
        expectedIdentity,
        foregroundIdentity,
        expectedTitle: documentTitle,
        foregroundTitle,
        attempts,
        remediationAttempted,
        reason: null,
      };
    }

    if (attempts === 1 && timeoutMs > 0) {
      remediationAttempted = true;
      await activateTarget({
        page,
        context,
        browser,
        targetId: expectedIdentity?.pageTargetId,
      }).catch(() => undefined);
      await activateWindow(documentTitle).catch(() => undefined);
      await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
      continue;
    }
  }

  return {
    status: 'unbound',
    expectedIdentity,
    foregroundIdentity,
    expectedTitle: documentTitle,
    foregroundTitle,
    attempts,
    remediationAttempted,
    reason: 'foreground-window-does-not-match-page-under-test',
  };
}

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

export function resolveTargetUrl(baseUrl, surface) {
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

export function resolveLocator(page, target) {
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

async function runTriggerAction(action, strict) {
  if (strict) {
    await action();
    return;
  }
  await action().catch(() => undefined);
}

export async function applyTrigger(page, trigger, { strict = false } = {}) {
  if (!trigger) {
    return;
  }

  const action = trigger.action || 'visit';
  const target = trigger.target;
  const locator = resolveLocator(page, target);

  switch (action) {
    case 'click':
      await runTriggerAction(() => locator.click({ timeout: 1000 }), strict);
      break;
    case 'focus':
      await runTriggerAction(() => locator.focus({ timeout: 1000 }), strict);
      break;
    case 'hover':
      await runTriggerAction(() => locator.hover({ timeout: 1000 }), strict);
      break;
    case 'type':
      await runTriggerAction(
        () => locator.fill(trigger.value || '', { timeout: 1000 }),
        strict,
      );
      break;
    case 'press':
      await runTriggerAction(
        () => page.keyboard.press(trigger.value || 'Enter'),
        strict,
      );
      break;
    case 'navigate':
      await runTriggerAction(
        () => page.goto(trigger.value || '/', { waitUntil: 'domcontentloaded' }),
        strict,
      );
      break;
    case 'visit':
      if (typeof target === 'string' || target?.value) {
        await runTriggerAction(
          () => page.goto(target.value || target || '/', { waitUntil: 'domcontentloaded' }),
          strict,
        );
      }
      break;
    default:
      if (strict) {
        throw new Error(`Unsupported trigger action: ${action}`);
      }
      break;
  }

  if (trigger.waitFor) {
    const waitFor = resolveLocator(page, trigger.waitFor);
    await runTriggerAction(
      () => waitFor.waitFor({ state: 'visible', timeout: 1000 }),
      strict,
    );
  }
}

export async function applyStateEmulation(page, state) {
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

export async function maximizeBrowserWindow({ browser, context, page } = {}) {
  const targetContext = context || page?.context?.();
  const targetPage = page || null;
  const cdpSessionFactory = targetContext?.newCDPSession?.bind(targetContext);
  const browserCdpFactory = browser?.newBrowserCDPSession?.bind(browser);

  if (!cdpSessionFactory && !browserCdpFactory) {
    return { status: 'unavailable', reason: 'browser-cdp-unavailable' };
  }

  try {
    const cdpSession = cdpSessionFactory
      ? await cdpSessionFactory(targetPage)
      : await browserCdpFactory();
    const windowForTarget = await cdpSession.send('Browser.getWindowForTarget');
    if (!windowForTarget?.windowId) {
      return { status: 'unavailable', reason: 'browser-window-id-unavailable' };
    }

    await cdpSession.send('Browser.setWindowBounds', {
      windowId: windowForTarget.windowId,
      bounds: { windowState: 'maximized' },
    });

    if (targetPage && typeof targetPage.bringToFront === 'function') {
      await targetPage.bringToFront().catch(() => undefined);
    }

    return {
      status: 'maximized',
      reason: null,
      windowId: windowForTarget.windowId,
      browserContext: context ? 'context-provided' : 'context-absent',
      pageTarget: page ? 'page-provided' : 'page-absent',
    };
  } catch (error) {
    return {
      status: 'unavailable',
      reason: error instanceof Error ? error.message : String(error),
      browserContext: context ? 'context-provided' : 'context-absent',
      pageTarget: page ? 'page-provided' : 'page-absent',
    };
  }
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
  if (!page) {
    return null;
  }

  try {
    const context = typeof page.context === 'function' ? page.context() : null;
    const cdpSessionFactory = context?.newCDPSession?.bind(context);
    if (cdpSessionFactory) {
      const cdpSession = await cdpSessionFactory(page);
      await cdpSession.send('Accessibility.enable');
      const axTree = await cdpSession.send('Accessibility.getFullAXTree');
      return {
        source: 'cdp',
        nodes: Array.isArray(axTree?.nodes) ? axTree.nodes : [],
      };
    }
  } catch {
    // Fall back to the legacy snapshot API when the browser does not expose a
    // target-bound CDP session for accessibility capture.
  }

  try {
    return await page.accessibility.snapshot();
  } catch {
    return null;
  }
}

// Launch headless system Chrome by default. Real AT execution explicitly opts
// into a headed browser via the options passed from the executor path.
//
// Playwright gives each launched browser its own ephemeral profile directory and
// removes it on close, so automation never reads or writes a real browsing
// profile. Do not pass an explicit --user-data-dir; Playwright rejects it.
export function buildChromeLaunchOptions(options = {}) {
  const args = [...CHROME_HARDENING_ARGS];
  if (Array.isArray(options.args)) {
    for (const arg of options.args) {
      if (typeof arg === 'string' && arg && !args.includes(arg)) {
        args.push(arg);
      }
    }
  }

  return {
    channel: 'chrome',
    headless: options.headless ?? true,
    args,
  };
}

export async function launchChrome(options = {}) {
  return chromium.launch(buildChromeLaunchOptions(options));
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
  const browser = await chromium.launch(buildChromeLaunchOptions({ headless: true }));
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
    const expectedAnnouncements = Array.isArray(probeConfig.expectedAnnouncements)
      ? probeConfig.expectedAnnouncements
      : [];
    const assertions = (Array.isArray(snapshot?.assertions) ? snapshot.assertions : []).map((assertion) => ({
      ...assertion,
      ...evaluateAssertion(assertion, phrases),
    }));

    if (expectedAnnouncements.length > 0) {
      for (const assertion of expectedAnnouncements) {
        const evaluation = evaluateAssertion(assertion, phrases);
        assertions.push({
          id: assertion.id || 'announcement',
          type: assertion.type,
          value: assertion.value,
          ...evaluation,
        });
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
