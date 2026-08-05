// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import { realScreenReaderStatus } from './_core.mjs';
import { buildProbeResults, emitProbeResult, isScreenReaderCleanupUnproven, runProbeWithPage, runRealScreenReaderProbe } from './_shared.mjs';

export async function runProbe() {
  const payload = await runProbeWithPage(async ({ page, surface, state, targetUrl }) => {
    const snapshot = await runRealScreenReaderProbe(page, { surface, state, targetUrl });

    const results = await buildProbeResults({
      probeId: 'probe-real-sr',
      surfaceId: surface?.id || 'unknown',
      state,
      evidence: `${targetUrl} ${JSON.stringify(snapshot)}`,
      decideStatus: realScreenReaderStatus(snapshot),
      informStatus: 'candidate',
    });

    return {
      probeId: 'probe-real-sr',
      runAt: new Date().toISOString(),
      baseUrl: targetUrl,
      results,
      cleanup: snapshot?.cleanup || null,
    };
  });

  // The accessibility result is emitted first: an unproven stop is an
  // operational failure, not a reason to discard a valid finding.
  emitProbeResult(payload);

  if (isScreenReaderCleanupUnproven(payload?.cleanup)) {
    const reason = payload.cleanup.reason || payload.cleanup.stopError || 'screen-reader-stop-unverified';
    process.stderr.write(`Screen reader cleanup could not be verified: ${reason}\n`);
    process.exitCode = 1;
  }
}
