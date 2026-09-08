const express = require('express');
const https = require('https');
const AgarBot = require('./bot');
const proto = require('./protocol');

const app = express();
app.use(express.json());

const sessions = new Map();
const botKeys = new Map();
const proxyPool = [];
let proxyIndex = 0;
let sessionCounter = 0;

// Rotating proxy gateway: one URL, each connection = different IP
// Set via Railway env var: PROXY_GATEWAY=socks5://user:pass@gateway:port
// Set USE_PROXY=true to enable (disabled by default to avoid breaking WS)
const PROXY_GATEWAY = process.env.PROXY_GATEWAY || '';
const USE_PROXY = process.env.USE_PROXY === 'true';

function getNextProxy() {
  if (!USE_PROXY) return null;
  if (PROXY_GATEWAY) return PROXY_GATEWAY;
  if (proxyPool.length === 0) return null;
  const proxy = proxyPool[proxyIndex % proxyPool.length];
  proxyIndex++;
  return proxy;
}

const WEB_BOUNCER = 'webbouncer-live-v8-0.agario.miniclippt.com';
const CLIENT_VERSION_INT = '31129';
const PROTO_VERSION = '15.0.3';
const BROWSER_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

function findServer(region, gameMode, partyToken) {
  return new Promise((resolve, reject) => {
    const body = proto.encodeBouncerRequest(region, gameMode, partyToken);
    const options = {
      hostname: WEB_BOUNCER,
      port: 443,
      path: '/v4/findServer',
      method: 'POST',
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Length': body.length,
        'Accept': 'q=0.01',
        'x-support-proto-version': PROTO_VERSION,
        'x-client-version': CLIENT_VERSION_INT,
        'Origin': 'https://agar.io',
        'Referer': 'https://agar.io/',
        'User-Agent': BROWSER_UA
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        console.log(`[findServer] HTTP ${res.statusCode}: ${data.substring(0, 200)}`);
        try {
          const json = JSON.parse(data);
          const serverPath = json.endpoints?.https || json.endpoints?.http;
          if (!serverPath) return reject(new Error('no endpoints'));
          const wsURL = `wss://${serverPath}`;
          const hostname = serverPath.split('/')[0];
          const token = json.token || '';
          resolve({ url: wsURL, hostname, token, fullPath: serverPath });
        } catch (e) {
          reject(new Error(`parse error: ${e.message}`));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

app.get('/health', (req, res) => {
  res.json({ status: 'ok', sessions: sessions.size });
});

app.get('/api/test', async (req, res) => {
  const region = req.query.region || 'EU-London';
  const gameMode = req.query.gameMode || ':ffa';
  const proxy = req.query.proxy || null;
  const steps = [];

  steps.push({ step: 'bouncer', status: 'starting', time: Date.now() });
  let serverInfo;
  try {
    serverInfo = await findServer(region, gameMode);
    steps.push({ step: 'bouncer', status: 'ok', fullPath: serverInfo.fullPath, url: serverInfo.url });
  } catch (e) {
    steps.push({ step: 'bouncer', status: 'failed', error: e.message });
    return res.json({ success: false, steps });
  }

  steps.push({ step: 'bot_connect', status: 'starting', serverURL: serverInfo.url });
  const bot = new AgarBot('TEST', serverInfo.url, serverInfo.hostname, serverInfo.token, 'feed', serverInfo.fullPath, proxy);

  await new Promise(resolve => {
    bot.connect();
    let checks = 0;
    const interval = setInterval(() => {
      checks++;
      if (bot.state === 'alive' || bot.state === 'disconnected' || checks >= 30) {
        clearInterval(interval);
        resolve();
      }
    }, 500);
  });

  steps.push({
    step: 'result',
    state: bot.state,
    handshakeComplete: bot.handshakeComplete,
    gotWorldBorder: bot.gotWorldBorder,
    spawnAttempts: bot.spawnAttempts,
    packetCount: bot.packetCount,
    sendCount: bot.sendCount,
    lastError: bot.lastError,
    ownIDs: bot.ownIDs,
    cellCount: bot.cells.size
  });

  bot.disconnect();
  res.json({
    success: bot.state === 'alive' || bot.handshakeComplete,
    spawned: bot.ownIDs.length > 0,
    steps,
    logs: bot.log
  });
});

app.post('/api/start', async (req, res) => {
  const { count = 5, names, mode = 'follow', region = 'EU-London', gameMode = ':ffa', targetX = 0, targetY = 0, proxy, proxies, partyCode, botKey, tripleMass = false, boosterMode = false, feedtrackMode = false, targetUID = '', botSkin = '' } = req.body;

  let maxAllowed = 50;
  if (botKey) {
    const hashed = hashKey(botKey);
    const entry = botKeys.get(hashed);
    if (!entry) return res.status(403).json({ error: 'invalid bot key' });
    if (Date.now() > entry.expiresAt) return res.status(403).json({ error: 'bot key expired' });
    maxAllowed = entry.maxBots || 50;
    entry.uses++;
  }

  const botCount = Math.min(count, maxAllowed);
  const botNames = names || Array.from({ length: botCount }, (_, i) => `XRD${i + 1}`);

  let serverInfo;
  let generatedPartyCode = null;

  if (partyCode) {
    try {
      serverInfo = await findServer(region, ':party', partyCode);
      console.log(`[start] party join: ${serverInfo.fullPath} code=${partyCode}`);
    } catch (e) {
      console.log(`[start] party join failed: ${e.message}`);
      return res.status(500).json({ error: `party join failed: ${e.message}` });
    }
  } else {
    try {
      serverInfo = await findServer(region, ':party');
      generatedPartyCode = serverInfo.token || null;
      console.log(`[start] auto-party: ${serverInfo.fullPath} token=${generatedPartyCode}`);
    } catch (e) {
      console.log(`[start] auto-party failed, trying FFA: ${e.message}`);
      try {
        serverInfo = await findServer(region, gameMode);
        console.log(`[start] FFA fallback: ${serverInfo.fullPath}`);
      } catch (e2) {
        return res.status(500).json({ error: `findServer failed: ${e2.message}` });
      }
    }
  }

  console.log(`[start] server=${serverInfo.url} host=${serverInfo.hostname} mode=${mode} triple=${tripleMass} booster=${boosterMode} feedtrack=${feedtrackMode}`);

  sessionCounter++;
  const sessionId = `s${sessionCounter}_${Date.now().toString(36)}`;
  const bots = [];

  const userProxies = proxies || (proxy ? [proxy] : []);
  const botOptions = { tripleMass, boosterMode, feedtrackMode };

  for (let i = 0; i < botCount; i++) {
    let botProxy = null;
    if (userProxies.length > 0) {
      botProxy = userProxies[i % userProxies.length];
    } else if (proxyPool.length > 0) {
      botProxy = getNextProxy();
    }
    const bot = new AgarBot(
      botNames[i % botNames.length],
      serverInfo.url,
      serverInfo.hostname,
      serverInfo.token,
      mode,
      serverInfo.fullPath,
      botProxy,
      botOptions
    );
    bot.setTarget(targetX, targetY);
    bots.push(bot);
  }

  sessions.set(sessionId, {
    bots,
    serverInfo,
    mode,
    region,
    paused: false,
    createdAt: Date.now()
  });

  for (let i = 0; i < bots.length; i++) {
    setTimeout(() => bots[i].connect(), i * 1500);
  }

  const response = {
    sessionId,
    serverURL: serverInfo.url,
    hostname: serverInfo.hostname,
    botCount
  };
  if (generatedPartyCode) {
    response.partyCode = generatedPartyCode;
  }
  res.json(response);
});

app.post('/api/create-party', async (req, res) => {
  const { region = 'EU-London' } = req.body;
  try {
    const serverInfo = await findServer(region, ':party');
    res.json({
      partyCode: serverInfo.token,
      serverURL: serverInfo.url,
      fullPath: serverInfo.fullPath
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/stop', (req, res) => {
  const { sessionId } = req.body;
  const session = sessions.get(sessionId);
  if (!session) return res.status(404).json({ error: 'session not found' });

  for (const bot of session.bots) bot.disconnect();
  sessions.delete(sessionId);
  res.json({ status: 'stopped' });
});

app.get('/api/status/:sessionId', (req, res) => {
  const session = sessions.get(req.params.sessionId);
  if (!session) return res.status(404).json({ error: 'session not found' });

  const botStatuses = session.bots.map(b => b.getStatus());
  const alive = botStatuses.filter(b => b.state === 'alive').length;
  const connected = botStatuses.filter(b => b.state === 'connected' || b.state === 'spawning' || b.state === 'alive').length;

  res.json({
    sessionId: req.params.sessionId,
    alive,
    connected,
    total: session.bots.length,
    mode: session.mode,
    server: session.serverInfo.url,
    bots: botStatuses,
    logs: session.bots.flatMap(b => b.log).slice(-50)
  });
});

app.get('/api/logs/:sessionId', (req, res) => {
  const session = sessions.get(req.params.sessionId);
  if (!session) return res.status(404).json({ error: 'session not found' });
  const allLogs = session.bots.flatMap(b => b.log);
  const botDetails = session.bots.map(b => ({
    name: b.name,
    state: b.state,
    lastError: b.lastError,
    handshake: b.handshakeComplete,
    packets: b.packetCount,
    sent: b.sendCount,
    spawns: b.spawnAttempts,
    worldBorder: b.gotWorldBorder,
    cells: b.cells.size,
    ownIDs: b.ownIDs,
    proxy: b.proxy ? 'yes' : 'no',
    log: b.log
  }));
  res.json({ bots: botDetails, logs: allLogs });
});

app.post('/api/target', (req, res) => {
  const { sessionId, x, y } = req.body;
  const session = sessions.get(sessionId);
  if (!session) return res.status(404).json({ error: 'session not found' });

  for (const bot of session.bots) bot.setTarget(x, y);
  res.json({ status: 'ok' });
});

app.post('/api/pause', (req, res) => {
  const { sessionId } = req.body;
  const session = sessions.get(sessionId);
  if (!session) return res.status(404).json({ error: 'session not found' });

  session.paused = true;
  for (const bot of session.bots) bot.setPaused(true);
  res.json({ status: 'paused' });
});

app.post('/api/resume', (req, res) => {
  const { sessionId } = req.body;
  const session = sessions.get(sessionId);
  if (!session) return res.status(404).json({ error: 'session not found' });

  session.paused = false;
  for (const bot of session.bots) bot.setPaused(false);
  res.json({ status: 'resumed' });
});

app.post('/api/mode', (req, res) => {
  const { sessionId, mode } = req.body;
  const session = sessions.get(sessionId);
  if (!session) return res.status(404).json({ error: 'session not found' });

  session.mode = mode;
  for (const bot of session.bots) bot.setMode(mode);
  res.json({ status: 'ok', mode });
});

app.get('/api/sessions', (req, res) => {
  const list = [];
  for (const [id, session] of sessions) {
    const alive = session.bots.filter(b => b.state === 'alive').length;
    list.push({ sessionId: id, alive, total: session.bots.length, mode: session.mode, server: session.serverInfo.url });
  }
  res.json({ sessions: list });
});

// Bot key system
const crypto = require('crypto');
const ADMIN_SECRET = process.env.ADMIN_SECRET || 'xrd-admin-2024';

function generateBotKey() {
  return 'XRD-' + crypto.randomBytes(12).toString('hex').toUpperCase();
}

function hashKey(key) {
  return crypto.createHmac('sha256', ADMIN_SECRET).update(key).digest('hex');
}

app.post('/api/keys/create', (req, res) => {
  const { adminKey, maxBots = 50, duration = 30, label = '' } = req.body;
  if (adminKey !== ADMIN_SECRET) return res.status(403).json({ error: 'unauthorized' });

  const key = generateBotKey();
  const expiresAt = Date.now() + duration * 24 * 60 * 60 * 1000;
  botKeys.set(hashKey(key), { maxBots, expiresAt, label, createdAt: Date.now(), uses: 0 });
  res.json({ key, maxBots, expiresAt, label });
});

app.post('/api/keys/validate', (req, res) => {
  const { botKey } = req.body;
  if (!botKey) return res.status(400).json({ error: 'missing botKey' });

  const hashed = hashKey(botKey);
  const entry = botKeys.get(hashed);
  if (!entry) return res.json({ valid: false, error: 'invalid key' });
  if (Date.now() > entry.expiresAt) return res.json({ valid: false, error: 'expired' });

  entry.uses++;
  res.json({ valid: true, maxBots: entry.maxBots, expiresAt: entry.expiresAt, label: entry.label });
});

app.post('/api/keys/revoke', (req, res) => {
  const { adminKey, botKey } = req.body;
  if (adminKey !== ADMIN_SECRET) return res.status(403).json({ error: 'unauthorized' });

  const hashed = hashKey(botKey);
  if (botKeys.delete(hashed)) {
    res.json({ status: 'revoked' });
  } else {
    res.status(404).json({ error: 'key not found' });
  }
});

app.get('/api/keys/list', (req, res) => {
  const { adminKey } = req.query;
  if (adminKey !== ADMIN_SECRET) return res.status(403).json({ error: 'unauthorized' });

  const list = [];
  for (const [hash, entry] of botKeys) {
    list.push({ hash: hash.substring(0, 8) + '...', ...entry, expired: Date.now() > entry.expiresAt });
  }
  res.json({ keys: list });
});

// Proxy management
app.post('/api/proxies/add', (req, res) => {
  const { adminKey, proxies: newProxies } = req.body;
  if (adminKey !== ADMIN_SECRET) return res.status(403).json({ error: 'unauthorized' });
  if (!Array.isArray(newProxies)) return res.status(400).json({ error: 'proxies must be array' });

  let added = 0;
  for (const p of newProxies) {
    const trimmed = p.trim();
    if (trimmed && !proxyPool.includes(trimmed)) {
      proxyPool.push(trimmed);
      added++;
    }
  }
  console.log(`[proxies] added ${added}, total: ${proxyPool.length}`);
  res.json({ added, total: proxyPool.length });
});

app.post('/api/proxies/remove', (req, res) => {
  const { adminKey, proxy: toRemove } = req.body;
  if (adminKey !== ADMIN_SECRET) return res.status(403).json({ error: 'unauthorized' });

  const idx = proxyPool.indexOf(toRemove);
  if (idx !== -1) {
    proxyPool.splice(idx, 1);
    res.json({ removed: true, total: proxyPool.length });
  } else {
    res.status(404).json({ error: 'proxy not found' });
  }
});

app.post('/api/proxies/clear', (req, res) => {
  const { adminKey } = req.body;
  if (adminKey !== ADMIN_SECRET) return res.status(403).json({ error: 'unauthorized' });
  proxyPool.length = 0;
  proxyIndex = 0;
  res.json({ status: 'cleared' });
});

app.get('/api/proxies/list', (req, res) => {
  const { adminKey } = req.query;
  if (adminKey !== ADMIN_SECRET) return res.status(403).json({ error: 'unauthorized' });
  res.json({ gateway: PROXY_GATEWAY || null, proxies: proxyPool, total: proxyPool.length, currentIndex: proxyIndex });
});

app.post('/api/proxies/set-gateway', (req, res) => {
  const { adminKey, gateway } = req.body;
  if (adminKey !== ADMIN_SECRET) return res.status(403).json({ error: 'unauthorized' });
  // Can't change env var at runtime, but we can override via pool
  // If gateway is set, all bots use it. Clear pool to use gateway only.
  if (gateway) {
    proxyPool.length = 0;
    proxyPool.push(gateway);
    console.log(`[proxies] gateway set: ${gateway}`);
  }
  res.json({ status: 'ok', gateway, total: proxyPool.length });
});

app.post('/api/proxies/test', async (req, res) => {
  const { adminKey, proxy: testProxy } = req.body;
  if (adminKey !== ADMIN_SECRET) return res.status(403).json({ error: 'unauthorized' });

  let SocksProxyAgent;
  try { SocksProxyAgent = require('socks-proxy-agent').SocksProxyAgent; } catch(e) {
    return res.status(500).json({ error: 'socks-proxy-agent not installed' });
  }

  try {
    const agent = new SocksProxyAgent(testProxy);
    const start = Date.now();
    const result = await new Promise((resolve, reject) => {
      const req = https.request({ hostname: 'agar.io', port: 443, path: '/', method: 'HEAD', agent, timeout: 10000 }, (r) => {
        resolve({ status: r.statusCode, latency: Date.now() - start });
      });
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
      req.end();
    });
    res.json({ working: true, ...result, proxy: testProxy });
  } catch (e) {
    res.json({ working: false, error: e.message, proxy: testProxy });
  }
});

setInterval(() => {
  for (const [id, session] of sessions) {
    const allDead = session.bots.every(b => b.state === 'disconnected');
    const tooOld = Date.now() - session.createdAt > 30 * 60 * 1000;
    if (allDead || tooOld) {
      console.log(`[cleanup] removing session ${id} (allDead=${allDead} tooOld=${tooOld})`);
      for (const bot of session.bots) bot.disconnect();
      sessions.delete(id);
    }
  }
}, 30000);

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`XRD Bot Server running on port ${PORT}`);
});
