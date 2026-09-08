const WebSocket = require('ws');
const proto = require('./protocol');
let SocksProxyAgent, HttpsProxyAgent;
try { SocksProxyAgent = require('socks-proxy-agent').SocksProxyAgent; } catch(e) {}
try { HttpsProxyAgent = require('https-proxy-agent').HttpsProxyAgent; } catch(e) {}

const CLIENT_VERSION = '3.11.29';
const PROTOCOL_VERSION = 23;
const VERSION_INT = proto.versionToInt(CLIENT_VERSION);

class AgarBot {
  constructor(name, serverURL, hostname, token, mode, fullPath, proxy) {
    this.name = name;
    this.serverURL = serverURL;
    this.hostname = hostname;
    this.fullPath = fullPath || hostname;
    this.token = token || '';
    this.mode = mode || 'feed';
    this.state = 'idle';
    this.ws = null;
    this.ownIDs = [];
    this.cells = new Map();
    this.worldBorder = { minX: -7071, minY: -7071, maxX: 7071, maxY: 7071 };
    this.targetX = 0;
    this.targetY = 0;
    this.movementKey = 0;
    this.encryptionKey = 0;
    this.decryptionKey = 0;
    this.handshakeComplete = false;
    this.packetCount = 0;
    this.sendCount = 0;
    this.moveInterval = null;
    this.pingInterval = null;
    this.respawnCount = 0;
    this.spawnAttempts = 0;
    this.lastError = '';
    this.log = [];
    this.gotWorldBorder = false;
    this.f1Raw = null;
    this.paused = false;
    this.proxy = proxy || null;
  }

  addLog(msg) {
    const line = `[${this.name}] ${msg}`;
    this.log.push(line);
    if (this.log.length > 50) this.log.shift();
    console.log(line);
  }

  connect() {
    this.state = 'connecting';
    this.lastError = '';
    this.handshakeComplete = false;
    this.encryptionKey = 0;
    this.decryptionKey = 0;
    this.packetCount = 0;
    this.sendCount = 0;
    this.spawnAttempts = 0;
    this.gotWorldBorder = false;

    this.addLog(`connecting to ${this.serverURL}`);

    try {
      const wsOpts = {
        origin: 'https://agar.io',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
          'Origin': 'https://agar.io',
        },
        rejectUnauthorized: false,
        handshakeTimeout: 10000
      };
      if (this.proxy) {
        const isSocks = this.proxy.startsWith('socks');
        if (isSocks && SocksProxyAgent) {
          wsOpts.agent = new SocksProxyAgent(this.proxy);
        } else if (!isSocks && HttpsProxyAgent) {
          wsOpts.agent = new HttpsProxyAgent(this.proxy);
        }
        this.addLog(`using proxy (${isSocks ? 'socks' : 'http'}): ${this.proxy.replace(/:[^:@]+@/, ':***@')}`);
      }
      this.ws = new WebSocket(this.serverURL, wsOpts);
    } catch (e) {
      this.addLog(`WS create error: ${e.message}`);
      this.lastError = e.message;
      this.state = 'disconnected';
      return;
    }

    this.ws.binaryType = 'nodebuffer';

    this.ws.on('open', () => {
      this.addLog('WS OPEN');
      this.state = 'connected';
      this.sendHandshake();
    });

    this.ws.on('message', (data) => {
      this.handlePacket(Buffer.from(data));
    });

    this.ws.on('close', (code, reason) => {
      this.addLog(`WS closed code=${code} reason=${reason || ''}`);
      this.lastError = `closed code=${code}`;
      this.disconnect();
    });

    this.ws.on('error', (err) => {
      this.addLog(`WS error: ${err.message}`);
      this.lastError = err.message;
      this.disconnect();
    });

    this.ws.on('ping', () => {
      this.addLog('WS-level PING received (auto-pong by ws lib)');
    });

    setTimeout(() => {
      if (this.state === 'connecting') {
        this.addLog('connection timeout');
        this.lastError = 'timeout';
        this.disconnect();
      }
    }, 12000);
  }

  sendHandshake() {
    this.rawSend(proto.handshakePacket(PROTOCOL_VERSION));
    this.rawSend(proto.versionIntPacket(VERSION_INT));
    if (this.token) {
      this.rawSend(proto.tokenPacket(this.token));
    }
    this.addLog(`handshake sent proto=${PROTOCOL_VERSION} versionInt=${VERSION_INT}`);
  }

  rawSend(buf) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return false;
    this.ws.send(buf);
    this.sendCount++;
    return true;
  }

  gameSend(buf) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return false;
    if (this.handshakeComplete) {
      const encrypted = proto.xorWithKey(buf, this.encryptionKey);
      this.encryptionKey = proto.rotateKey(this.encryptionKey);
      this.ws.send(encrypted);
      this.sendCount++;
      return true;
    } else {
      this.ws.send(buf);
      this.sendCount++;
      return true;
    }
  }

  handlePacket(data) {
    this.packetCount++;

    if (this.packetCount <= 5) {
      this.addLog(`pkt#${this.packetCount} raw len=${data.length} first20=[${data.slice(0, 20).toString('hex')}]`);
    }

    let decoded = data;
    if (this.handshakeComplete) {
      decoded = proto.xorWithKey(data, this.decryptionKey);
    }

    const op = decoded[0];

    if (op === 0xE2) {
      this.addLog(`PING received (0xE2) len=${decoded.length}`);
      this.sendPong(decoded);
      return;
    }

    if (op === 0xF2) {
      this.addLog(`CAPTCHA_REQUEST (0xF2) len=${decoded.length} — ignoring, will retry spawn`);
      return;
    }

    const pkt = proto.parsePacket(decoded);
    if (!pkt) {
      this.addLog(`UNKNOWN pkt#${this.packetCount} op=0x${op.toString(16)} (${op}) len=${decoded.length} hex=[${decoded.slice(0, 30).toString('hex')}]`);
      return;
    }

    switch (pkt.type) {
      case 'version':
        this.f1Raw = data;
        this.movementKey = pkt.movementKey;
        this.decryptionKey = (pkt.movementKey ^ VERSION_INT) >>> 0;
        this.encryptionKey = proto.murmur2(this.fullPath + pkt.ver, 255);
        this.handshakeComplete = true;
        this.addLog(`F1 mk=${pkt.movementKey} dk=${this.decryptionKey} ek=${this.encryptionKey} ver="${pkt.ver}" path="${this.fullPath}"`);
        this.trySpawn();
        break;

      case 'outdated':
        this.addLog('OUTDATED client version rejected');
        this.lastError = 'version outdated';
        this.disconnect();
        break;

      case 'protoError':
        this.addLog('PROTO_ERROR protocol rejected');
        this.lastError = 'protocol rejected';
        this.disconnect();
        break;

      case 'captcha':
        this.addLog('CAPTCHA requested (0x55) — not disconnecting, will keep trying');
        break;

      case 'ack':
        this.addLog('ACK received');
        break;

      case 'worldUpdate':
        for (const u of pkt.updates) this.cells.set(u.id, u);
        for (const r of pkt.removals) this.cells.delete(r);
        for (const e of pkt.eats) {
          this.cells.delete(e.eaten);
          this.ownIDs = this.ownIDs.filter(id => id !== e.eaten);
        }

        if (this.packetCount <= 8 || this.packetCount % 100 === 0) {
          this.addLog(`worldUpdate: ${pkt.updates.length} updates, ${pkt.removals.length} removals, ${pkt.eats.length} eats, cells=${this.cells.size}`);
        }

        if (this.state === 'alive' && this.ownIDs.length === 0) {
          this.state = 'dead';
          this.handleDeath();
        }
        if (this.state === 'alive') this.performAction();
        break;

      case 'ownIDs':
        for (const id of pkt.ids) {
          if (!this.ownIDs.includes(id)) this.ownIDs.push(id);
        }
        if (this.ownIDs.length > 0 && this.state !== 'alive') {
          this.state = 'alive';
          this.addLog(`ALIVE! ids=${this.ownIDs}`);
          this.startMoveLoop();
        }
        break;

      case 'worldBorder':
        this.gotWorldBorder = true;
        this.worldBorder = pkt;
        this.addLog(`worldBorder: ${pkt.minX.toFixed(0)},${pkt.minY.toFixed(0)} to ${pkt.maxX.toFixed(0)},${pkt.maxY.toFixed(0)}`);
        if (this.state !== 'alive') {
          setTimeout(() => this.trySpawn(), 300);
        }
        break;

      case 'clearAll':
        this.cells.clear();
        this.addLog('clearAll');
        break;

      case 'leaderboard':
        break;

      case 'unknown':
        this.addLog(`unknown pkt op=0x${pkt.op.toString(16)} (${pkt.op}) len=${pkt.len} hex=[${decoded.slice(0, 30).toString('hex')}]`);
        if (pkt.len === 33) {
          try {
            const buf = decoded;
            const minX = buf.readDoubleLE(1);
            const minY = buf.readDoubleLE(9);
            const maxX = buf.readDoubleLE(17);
            const maxY = buf.readDoubleLE(25);
            if (Math.abs(minX) < 50000 && maxX > minX && maxY > minY) {
              this.worldBorder = { minX, minY, maxX, maxY };
              this.gotWorldBorder = true;
              this.addLog(`heuristic worldBorder: ${minX.toFixed(0)},${minY.toFixed(0)} to ${maxX.toFixed(0)},${maxY.toFixed(0)}`);
              if (this.state !== 'alive') {
                setTimeout(() => this.trySpawn(), 300);
              }
            }
          } catch (e) {}
        }
        break;
    }
  }

  sendPong(pingData) {
    if (pingData.length >= 5) {
      const pong = Buffer.alloc(pingData.length);
      pingData.copy(pong);
      pong[0] = 0xE3;
      this.gameSend(pong);
      this.addLog(`PONG sent (0xE3) len=${pong.length}`);
    } else {
      const pong = Buffer.from([0xE3]);
      this.gameSend(pong);
      this.addLog('PONG sent (0xE3) 1 byte');
    }
  }

  trySpawn() {
    if (this.state === 'alive' || this.state === 'disconnected') return;
    this.spawnAttempts++;
    this.state = 'spawning';
    const pkt = proto.spawnPacket(this.name);
    this.addLog(`SPAWN attempt #${this.spawnAttempts} name="${this.name}" pktLen=${pkt.length} pktHex=[${pkt.toString('hex')}]`);
    this.gameSend(pkt);

    if (this.spawnAttempts < 5) {
      setTimeout(() => {
        if (this.state === 'spawning') {
          this.addLog(`spawn retry (still spawning after attempt #${this.spawnAttempts})`);
          this.trySpawn();
        }
      }, 2000);
    }
  }

  startMoveLoop() {
    if (this.moveInterval) clearInterval(this.moveInterval);
    this.moveInterval = setInterval(() => this.performAction(), 50);
  }

  performAction() {
    if (this.state !== 'alive' || this.paused) return;
    const wb = this.worldBorder;

    switch (this.mode) {
      case 'feed':
        this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
        this.gameSend(proto.ejectPacket());
        break;
      case 'split':
        this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
        this.gameSend(proto.splitPacket());
        break;
      case 'random_feed': {
        const rx = wb.minX + Math.random() * (wb.maxX - wb.minX);
        const ry = wb.minY + Math.random() * (wb.maxY - wb.minY);
        this.gameSend(proto.movePacket(rx, ry, this.movementKey));
        this.gameSend(proto.ejectPacket());
        break;
      }
      default:
        this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
        this.gameSend(proto.ejectPacket());
    }
  }

  handleDeath() {
    if (this.moveInterval) { clearInterval(this.moveInterval); this.moveInterval = null; }
    this.respawnCount++;
    if (this.respawnCount > 20) {
      this.addLog('max respawns');
      this.lastError = 'max respawns';
      this.disconnect();
      return;
    }
    setTimeout(() => {
      if (this.state === 'dead') this.trySpawn();
    }, this.respawnCount > 10 ? 3000 : 1000);
  }

  setTarget(x, y) {
    this.targetX = x;
    this.targetY = y;
  }

  setMode(mode) {
    this.mode = mode;
  }

  setPaused(paused) {
    this.paused = paused;
    this.addLog(paused ? 'PAUSED' : 'RESUMED');
  }

  disconnect() {
    if (this.moveInterval) { clearInterval(this.moveInterval); this.moveInterval = null; }
    if (this.pingInterval) { clearInterval(this.pingInterval); this.pingInterval = null; }
    if (this.ws) {
      try { this.ws.close(); } catch (e) {}
      this.ws = null;
    }
    if (this.state !== 'disconnected') {
      this.state = 'disconnected';
      this.addLog(`disconnected: ${this.lastError} (pkts=${this.packetCount} sent=${this.sendCount} spawns=${this.spawnAttempts})`);
    }
  }

  getStatus() {
    return {
      name: this.name,
      state: this.state,
      packetCount: this.packetCount,
      sendCount: this.sendCount,
      ownIDs: this.ownIDs,
      lastError: this.lastError,
      respawnCount: this.respawnCount,
      spawnAttempts: this.spawnAttempts,
      gotWorldBorder: this.gotWorldBorder,
      handshakeComplete: this.handshakeComplete,
      cellCount: this.cells.size,
      paused: this.paused
    };
  }
}

module.exports = AgarBot;
