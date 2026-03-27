import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import { URL } from 'node:url';

function parseArgs(argv) {
  const options = {
    root: path.resolve('web/dist'),
    host: '0.0.0.0',
    port: 8080,
    apiTarget: '',
    wsTarget: '',
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];

    if (arg === '--root' && next) {
      options.root = path.resolve(next);
      i += 1;
    } else if (arg === '--host' && next) {
      options.host = next;
      i += 1;
    } else if (arg === '--port' && next) {
      options.port = Number(next);
      i += 1;
    } else if (arg === '--api-target' && next) {
      options.apiTarget = next;
      i += 1;
    } else if (arg === '--ws-target' && next) {
      options.wsTarget = next;
      i += 1;
    } else if (arg === '-h' || arg === '--help') {
      printUsage();
      process.exit(0);
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }

  return options;
}

function printUsage() {
  console.log(`Usage: node tools/web_preview_server.mjs [options]

Options:
  --root <dir>         Static build directory to serve. Default: web/dist
  --host <host>        Bind host. Default: 0.0.0.0
  --port <port>        Bind port. Default: 8080
  --api-target <url>   Proxy /api/* to this origin, e.g. http://game.local
  --ws-target <url>    Proxy /ws to this websocket target, e.g. ws://game.local:81
`);
}

function contentTypeFor(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
      return 'application/javascript; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.svg':
      return 'image/svg+xml';
    case '.map':
      return 'application/json; charset=utf-8';
    default:
      return 'application/octet-stream';
  }
}

function readStaticFile(rootDir, requestPath) {
  const cleanPath = requestPath === '/' ? '/index.html' : requestPath;
  const resolved = path.resolve(rootDir, `.${cleanPath}`);
  if (!resolved.startsWith(rootDir)) {
    return null;
  }

  if (!fs.existsSync(resolved) || fs.statSync(resolved).isDirectory()) {
    return null;
  }

  return resolved;
}

function proxyHttp(req, res, target) {
  const upstreamUrl = new URL(req.url, target);
  const client = upstreamUrl.protocol === 'https:' ? https : http;
  const proxyReq = client.request(
    upstreamUrl,
    {
      method: req.method,
      headers: {
        ...req.headers,
        host: upstreamUrl.host,
      },
    },
    (proxyRes) => {
      res.writeHead(proxyRes.statusCode ?? 502, proxyRes.headers);
      proxyRes.pipe(res);
    },
  );

  proxyReq.on('error', (err) => {
    res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(`HTTP proxy error: ${err.message}\n`);
  });

  req.pipe(proxyReq);
}

function createWsHandshakeHeaders(request, upstream) {
  const lines = [`GET ${upstream.pathname}${upstream.search} HTTP/1.1`];
  const headerEntries = Object.entries(request.headers);

  for (const [name, value] of headerEntries) {
    if (value === undefined) {
      continue;
    }

    if (name.toLowerCase() === 'host') {
      lines.push(`Host: ${upstream.host}`);
      continue;
    }

    if (Array.isArray(value)) {
      for (const item of value) {
        lines.push(`${name}: ${item}`);
      }
      continue;
    }

    lines.push(`${name}: ${value}`);
  }

  lines.push('\r\n');
  return lines.join('\r\n');
}

function proxyWebSocket(request, socket, head, wsTarget) {
  const upstreamUrl = new URL(wsTarget);
  const port = Number(upstreamUrl.port || (upstreamUrl.protocol === 'wss:' ? 443 : 80));
  const connect = upstreamUrl.protocol === 'wss:' ? tlsConnect : net.connect;

  const upstreamSocket = connect({
    host: upstreamUrl.hostname,
    port,
    servername: upstreamUrl.hostname,
  });

  upstreamSocket.on('connect', () => {
    const handshake = createWsHandshakeHeaders(request, upstreamUrl);
    upstreamSocket.write(handshake);
    if (head && head.length > 0) {
      upstreamSocket.write(head);
    }
    socket.pipe(upstreamSocket);
    upstreamSocket.pipe(socket);
  });

  upstreamSocket.on('error', () => {
    socket.destroy();
  });

  socket.on('error', () => {
    upstreamSocket.destroy();
  });
}

function tlsConnect(options) {
  return https.globalAgent.createConnection(options);
}

function injectRuntimeConfig(html, wsTarget) {
  const runtimeConfig = {
    wsUrl: wsTarget ? '/ws' : '',
  };

  const script = `<script>window.__CONTROLLER_CONFIG=${JSON.stringify(runtimeConfig)};</script>`;
  return html.replace('</head>', `${script}</head>`);
}

function createServer(options) {
  const rootDir = path.resolve(options.root);
  const apiTarget = options.apiTarget ? new URL(options.apiTarget) : null;
  const wsTarget = options.wsTarget || '';

  return http.createServer((req, res) => {
    if (!req.url) {
      res.writeHead(400);
      res.end();
      return;
    }

    if (apiTarget && req.url.startsWith('/api/')) {
      proxyHttp(req, res, apiTarget);
      return;
    }

    const filePath = readStaticFile(rootDir, new URL(req.url, 'http://localhost').pathname);
    if (!filePath) {
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('not found\n');
      return;
    }

    if (filePath.endsWith('index.html')) {
      const html = fs.readFileSync(filePath, 'utf8');
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(injectRuntimeConfig(html, wsTarget));
      return;
    }

    res.writeHead(200, { 'content-type': contentTypeFor(filePath) });
    fs.createReadStream(filePath).pipe(res);
  }).on('upgrade', (request, socket, head) => {
    if (!wsTarget || request.url !== '/ws') {
      socket.destroy();
      return;
    }

    proxyWebSocket(request, socket, head, wsTarget);
  });
}

const options = parseArgs(process.argv.slice(2));
const server = createServer(options);

server.listen(options.port, options.host, () => {
  console.log(`Preview server listening on http://${options.host}:${options.port}`);
  if (options.apiTarget) {
    console.log(`Proxying /api/* to ${options.apiTarget}`);
  }
  if (options.wsTarget) {
    console.log(`Proxying /ws to ${options.wsTarget}`);
  }
});
