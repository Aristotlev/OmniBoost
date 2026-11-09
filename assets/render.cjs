const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  const svg = require('fs').readFileSync(process.argv[2], 'utf8');
  await p.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
  await p.screenshot({ path: process.argv[3], omitBackground: true, clip: { x: 0, y: 0, width: 1024, height: 1024 } });
  await b.close();
})();
