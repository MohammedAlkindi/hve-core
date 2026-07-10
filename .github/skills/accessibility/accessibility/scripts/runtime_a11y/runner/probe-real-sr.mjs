import { realScreenReaderStatus } from './_core.mjs';
import { buildProbeResults, emitProbeResult, runProbeWithPage, runRealScreenReaderProbe } from './_shared.mjs';

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
    };
  });

  emitProbeResult(payload);
}
