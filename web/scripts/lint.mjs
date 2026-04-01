import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const WEB_DIR = process.cwd();
const SRC_DIR = path.join(WEB_DIR, 'src');
const REQUIRED_FILES = [
  path.join(WEB_DIR, 'index.html'),
  path.join(SRC_DIR, 'main.js'),
  path.join(SRC_DIR, 'styles.css'),
];

function fail(message) {
  console.error(`[web-lint] ${message}`);
  process.exit(1);
}

function walkJavaScriptFiles(dir) {
  const entries = readdirSync(dir, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkJavaScriptFiles(fullPath));
      continue;
    }

    if (entry.isFile() && fullPath.endsWith('.js')) {
      files.push(fullPath);
    }
  }

  return files.sort();
}

for (const filePath of REQUIRED_FILES) {
  if (!existsSync(filePath)) {
    fail(`missing required file: ${path.relative(WEB_DIR, filePath)}`);
  }
}

const html = readFileSync(path.join(WEB_DIR, 'index.html'), 'utf8');
if (!html.includes('<script type="module" src="/src/main.js"></script>')) {
  fail('index.html must load /src/main.js as the module entrypoint');
}

const jsFiles = walkJavaScriptFiles(SRC_DIR);
if (jsFiles.length === 0) {
  fail('no JavaScript source files found under web/src');
}

for (const filePath of jsFiles) {
  const result = spawnSync(process.execPath, ['--check', filePath], {
    cwd: WEB_DIR,
    encoding: 'utf8',
  });

  if (result.status !== 0) {
    process.stderr.write(result.stderr);
    fail(`syntax check failed for ${path.relative(WEB_DIR, filePath)}`);
  }
}

const cssPath = path.join(SRC_DIR, 'styles.css');
if (!statSync(cssPath).isFile()) {
  fail('web/src/styles.css must be a file');
}

const css = readFileSync(cssPath, 'utf8');
if (!css.includes('@import "../../third_party/virtual-gamepad-lib/gamepad_assets/base.css";')) {
  fail('web/src/styles.css must import the shared virtual-gamepad base stylesheet');
}

console.log(`[web-lint] checked ${jsFiles.length} JavaScript files, index.html, and styles.css`);
