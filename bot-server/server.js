const express = require('express');
const https = require('https');
const AgarBot = require('./bot');
const proto = require('./protocol');

const app = express();
app.use(express.json());

const sessions = new Map();
let sessionCounter = 0;

const WEB_BOUNCER = 'webbouncer-live-v8-0.agario.miniclippt.com';
const CLIENT_VERSION_INT = '31129';
const PROTO_VERSION = '15.0.3';
const BROWSER_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

function findServer(region, gameMode) {
  return new Promise((resolve, reject) => {
    const body = proto.encodeBouncerRequest(region, gameMode);
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
  const { count = 5, names, mode = 'feed', region = 'EU-London', gameMode = ':ffa', targetX = 0, targetY = 0, serverURL, serverIP, proxy, proxies } = req.body;

  const botCount = Math.min(count, 50);
  const botNames = names || Array.from({ length: botCount }, (_, i) => `XRD${i + 1}`);

  let serverInfo;

  if (serverURL) {
    const stripped = serverURL.replace(/^wss?:\/\//, '').replace(/:443$/, '');
    const hasPath = stripped.includes('/');

    if (hasPath) {
      const hostname = stripped.split('/')[0];
      serverInfo = { url: `wss://${stripped}`, hostname, token: '', fullPath: stripped };
      console.log(`[start] full path from client: ${serverInfo.fullPath}`);
    } else {
      console.log(`[start] URL has no path (${stripped}), using bouncer directly`);
      try {
        serverInfo = await findServer(region, gameMode);
        console.log(`[start] bouncer server: ${serverInfo.fullPath}`);
      } catch (e) {
        console.log(`[start] bouncer failed: ${e.message}`);
        return res.status(500).json({ error: `findServer failed: ${e.message}` });
      }
    }
  } else {
    try {
      serverInfo = await findServer(region, gameMode);
      console.log(`[start] no URL provided, bouncer server: ${serverInfo.fullPath}`);
    } catch (e) {
      console.log(`[start] findServer failed: ${e.message}`);
      return res.status(500).json({ error: `findServer failed: ${e.message}` });
    }
  }

  console.log(`[start] server=${serverInfo.url} host=${serverInfo.hostname}`);

  sessionCounter++;
  const sessionId = `s${sessionCounter}_${Date.now().toString(36)}`;
  const bots = [];

  const proxyList = proxies || (proxy ? [proxy] : []);

  for (let i = 0; i < botCount; i++) {
    const botProxy = proxyList.length > 0 ? proxyList[i % proxyList.length] : null;
    const bot = new AgarBot(
      botNames[i % botNames.length],
      serverInfo.url,
      serverInfo.hostname,
      serverInfo.token,
      mode,
      serverInfo.fullPath,
      botProxy
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

  res.json({
    sessionId,
    serverURL: serverInfo.url,
    hostname: serverInfo.hostname,
    botCount
  });
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
