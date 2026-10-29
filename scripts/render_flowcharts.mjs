// แปลงต้นฉบับ scripts/flowcharts/*.mmd → รูป docs/flowcharts/*.png (ความละเอียด 2 เท่า สำหรับใส่สไลด์)
// ใช้ Microsoft Edge ที่มีในเครื่องรัน Mermaid ไม่ต้องติดตั้งแพ็กเกจเพิ่ม (ต้องต่อเน็ต)
//   node scripts/render_flowcharts.mjs            (ทุกไฟล์)
//   node scripts/render_flowcharts.mjs 05-ai      (เฉพาะไฟล์ที่ชื่อขึ้นต้นด้วย 05-ai)
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const SRC = resolve(import.meta.dirname, 'flowcharts');
const OUT = resolve(import.meta.dirname, '../docs/flowcharts');
const EDGE = [
  process.env.EDGE_PATH,
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
].find((p) => p && existsSync(p));
if (!EDGE) throw new Error('ไม่พบ Microsoft Edge (กำหนด EDGE_PATH ได้)');

const MERMAID = 'https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.esm.min.mjs';
const SCALE = 2;
const PAD = 24;

// สีตามธีมแอป (ชมพู) + ฟอนต์ไทยที่มีใน Windows
const config = {
  startOnLoad: false,
  theme: 'base',
  themeVariables: {
    fontFamily: '"Leelawadee UI", Tahoma, sans-serif',
    fontSize: '16px',
    primaryColor: '#FDE1EA',
    primaryBorderColor: '#E5437F',
    primaryTextColor: '#2B2B2B',
    secondaryColor: '#FFF1F4',
    tertiaryColor: '#FDF7EC',
    lineColor: '#5D5D5D',
    clusterBkg: '#FFF8F0',
    clusterBorder: '#F7A1C0',
    actorBkg: '#FDE1EA',
    actorBorder: '#E5437F',
    noteBkgColor: '#FFF1D6',
  },
  // label เป็นข้อความ SVG ล้วน (ไม่ใช้ HTML) → ขนาดรูปคำนวณได้แม่น
  flowchart: { htmlLabels: false, curve: 'basis' },
  sequence: { useMaxWidth: false },
};

const tmp = mkdtempSync(join(tmpdir(), 'flowcharts-'));
const edge = (...args) =>
  execFileSync(EDGE, ['--headless=new', '--disable-gpu', '--hide-scrollbars', `--user-data-dir=${join(tmp, 'profile')}`, ...args], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'ignore'],
  });

const filter = process.argv[2] ?? '';
const files = readdirSync(SRC).filter((f) => f.endsWith('.mmd') && f.startsWith(filter)).sort();
mkdirSync(OUT, { recursive: true });

try {
  for (const file of files) {
    const name = file.replace(/\.mmd$/, '');
    const source = readFileSync(join(SRC, file), 'utf8');

    // 1) ให้ Mermaid วาดเป็น SVG ในเบราว์เซอร์ แล้วอ่าน DOM ออกมา
    const renderHtml = join(tmp, `${name}.render.html`);
    writeFileSync(renderHtml, `<!doctype html><meta charset="utf-8"><body>
<script type="module">
import mermaid from '${MERMAID}';
mermaid.initialize(${JSON.stringify(config)});
try {
  const { svg } = await mermaid.render('chart', ${JSON.stringify(source)});
  document.body.innerHTML = '<div id="out">' + svg + '</div>';
} catch (e) {
  document.body.innerHTML = '<div id="err">' + String(e.message || e).replace(/</g, '&lt;') + '</div>';
}
</script>`);
    const dom = edge('--dump-dom', '--virtual-time-budget=20000', pathToFileURL(renderHtml).href);
    const err = dom.match(/<div id="err">([\s\S]*?)<\/div>/);
    if (err) throw new Error(`${file}: ${err[1]}`);
    let svg = dom.match(/<svg[\s\S]*<\/svg>/)?.[0];
    if (!svg) throw new Error(`${file}: Mermaid ไม่ได้สร้าง SVG (ต่อเน็ตเพื่อโหลด Mermaid ได้ไหม?)`);

    // 2) ใส่ขนาดจริงให้ SVG (Mermaid ใส่ไว้แค่ viewBox + max-width) เพื่อถ่ายภาพได้พอดี
    const [, , w, h] = svg.match(/viewBox="([^"]+)"/)[1].split(/\s+/).map(Number);
    const width = Math.ceil(w);
    const height = Math.ceil(h);
    svg = svg
      .replace(/^<svg([^>]*?)\swidth="[^"]*"/, '<svg$1')
      .replace(/^<svg([^>]*?)\sstyle="[^"]*"/, '<svg$1')
      .replace(/^<svg/, `<svg width="${width}" height="${height}" style="background:#ffffff"`);

    // 3) ถ่ายภาพ SVG เป็น PNG พื้นขาว ขอบ ${PAD}px
    const shotHtml = join(tmp, `${name}.shot.html`);
    writeFileSync(shotHtml, `<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;background:#fff}body{padding:${PAD}px}svg{display:block}</style>${svg}`);
    const png = join(OUT, `${name}.png`);
    edge(`--force-device-scale-factor=${SCALE}`, `--window-size=${width + PAD * 2},${height + PAD * 2}`, `--screenshot=${png}`, pathToFileURL(shotHtml).href);
    if (!existsSync(png)) throw new Error(`${file}: สร้าง PNG ไม่สำเร็จ`);
    console.log(`✔ ${name}  (${width}×${height})`);
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
