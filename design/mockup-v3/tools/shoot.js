// Screenshot every render/<slug>.html frame at 2x into png/<slug>/.
// usage: node tools/shoot.js [slug...]
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const ROOT = path.dirname(__dirname);
(async () => {
  const only = process.argv.slice(2);
  const files = fs.readdirSync(path.join(ROOT, 'render')).filter(f => f.endsWith('.html')).filter(f => !only.length || only.includes(f.slice(0, -5)));
  const b = await chromium.launch();
  const page = await b.newPage({ viewport: { width: 1900, height: 1200 }, deviceScaleFactor: 2 });
  for (const f of files) {
    const slug = f.slice(0, -5);
    await page.goto('file://' + path.join(ROOT, 'render', f));
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(300);
    const title = await page.title();
    const dir = path.join(ROOT, 'png', slug);
    fs.mkdirSync(dir, { recursive: true });
    await page.locator('#webFrame').screenshot({ path: path.join(dir, `Web - ${title}@2x.png`) });
    await page.locator('#droidFrame').screenshot({ path: path.join(dir, `Android - ${title}@2x.png`), omitBackground: true });
    console.log('shot', slug);
  }
  await b.close();
})();
