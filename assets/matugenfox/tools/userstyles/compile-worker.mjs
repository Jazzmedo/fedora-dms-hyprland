// Compiles one userstyle per message, so the build can use several cores.

import { parentPort } from 'node:worker_threads';
import less from 'less';

parentPort.on('message', async ({ id, source, filename }) => {
  const started = performance.now();
  try {
    const { css } = await less.render(source, { filename, javascriptEnabled: false });
    parentPort.postMessage({ id, css, ms: performance.now() - started });
  } catch (err) {
    const where = err.line ? ` (line ${err.line})` : '';
    parentPort.postMessage({ id, error: `${err.message}${where}`, ms: performance.now() - started });
  }
});
