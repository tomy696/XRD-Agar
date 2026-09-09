const WebSocket = require('ws');
const proto = require('./protocol');
let SocksProxyAgent, HttpsProxyAgent;
try { SocksProxyAgent = require('socks-proxy-agent').SocksProxyAgent; } catch(e) {}
try { HttpsProxyAgent = require('https-proxy-agent').HttpsProxyAgent; } catch(e) {}

const CLIENT_VERSION = '3.11.29';
const PROTOCOL_VERSION = 23;
const VERSION_INT = proto.versionToInt(CLIENT_VERSION);

class AgarBot {
  constructor(name, serverURL, hostname, token, mode, fullPath, proxy, options = {}) {
    this.name = name;
    this.serverURL = serverURL;
    this.hostname = hostname;
    this.fullPath = fullPath || hostname;
    this.token = token || '';
    this.mode = mode || 'follow';
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

    this.tripleMass = options.tripleMass || false;
    this.boosterMode = options.boosterMode || false;
    this.feedtrackMode = options.feedtrackMode || false;

    this.feedTickCount = 0;
    this.virusTargetX = 0;
    this.virusTargetY = 0;
    this.captchaCount = 0;
    this.reconnectCount = 0;
    this.maxReconnects = 5;
    this.onReconnect = null;
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
        try {
          const isSocks = this.proxy.startsWith('socks');
          if (isSocks && SocksProxyAgent) {
            wsOpts.agent = new SocksProxyAgent(this.proxy);
            this.addLog(`using SOCKS proxy: ${this.proxy.replace(/:[^:@]+@/, ':***@')}`);
          } else if (!isSocks && HttpsProxyAgent) {
            const m = this.proxy.match(/^https?:\/\/([^:]+):([^@]+)@([^:]+):(\d+)/);
            if (m) {
              wsOpts.agent = new HttpsProxyAgent({
                host: m[3],
                port: parseInt(m[4]),
                auth: `${m[1]}:${m[2]}`,
                protocol: 'http:'
              });
            } else {
              wsOpts.agent = new HttpsProxyAgent(this.proxy);
            }
            this.addLog(`using HTTP proxy: ${this.proxy.replace(/:[^:@]+@/, ':***@')}`);
          }
        } catch (e) {
          this.addLog(`proxy agent error: ${e.message}`);
        }
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
      this.reconnectWithNewIP();
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
      this.sendPong(decoded);
      return;
    }

    if (op === 0xF2) {
      this.captchaCount++;
      this.addLog(`CAPTCHA (0xF2) #${this.captchaCount}`);
      if (this.captchaCount >= 3) {
        this.addLog('too many captchas, reconnecting with new IP...');
        this.reconnectWithNewIP();
      }
      return;
    }

    const pkt = proto.parsePacket(decoded);
    if (!pkt) {
      if (this.packetCount <= 10) {
        this.addLog(`UNKNOWN op=0x${op.toString(16)} len=${decoded.length}`);
      }
      return;
    }

    switch (pkt.type) {
      case 'version':
        this.f1Raw = data;
        this.movementKey = pkt.movementKey;
        this.decryptionKey = (pkt.movementKey ^ VERSION_INT) >>> 0;
        this.encryptionKey = proto.murmur2(this.fullPath + pkt.ver, 255);
        this.handshakeComplete = true;
        this.addLog(`F1 mk=${pkt.movementKey} dk=${this.decryptionKey} ek=${this.encryptionKey} ver="${pkt.ver}"`);
        this.trySpawn();
        break;

      case 'outdated':
        this.addLog('OUTDATED version');
        this.lastError = 'version outdated';
        this.disconnect();
        break;

      case 'protoError':
        this.addLog('PROTO_ERROR');
        this.lastError = 'protocol rejected';
        this.disconnect();
        break;

      case 'captcha':
        this.captchaCount++;
        this.addLog(`CAPTCHA (0x55) #${this.captchaCount}`);
        if (this.captchaCount >= 3) {
          this.addLog('too many captchas, reconnecting with new IP...');
          this.reconnectWithNewIP();
        }
        break;

      case 'ack':
        break;

      case 'worldUpdate':
        for (const u of pkt.updates) this.cells.set(u.id, u);
        for (const r of pkt.removals) this.cells.delete(r);
        for (const e of pkt.eats) {
          this.cells.delete(e.eaten);
          this.ownIDs = this.ownIDs.filter(id => id !== e.eaten);
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
        break;

      case 'leaderboard':
        break;

      case 'unknown':
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
    } else {
      this.gameSend(Buffer.from([0xE3]));
    }
  }

  trySpawn() {
    if (this.state === 'alive' || this.state === 'disconnected') return;
    this.spawnAttempts++;
    this.state = 'spawning';
    const pkt = proto.spawnPacket(this.name);
    this.addLog(`SPAWN #${this.spawnAttempts} name="${this.name}"`);
    this.gameSend(pkt);

    if (this.spawnAttempts < 15) {
      const delay = this.spawnAttempts < 3 ? 2000 : 3000 + Math.random() * 2000;
      setTimeout(() => {
        if (this.state === 'spawning') this.trySpawn();
      }, delay);
    }
  }

  startMoveLoop() {
    if (this.moveInterval) clearInterval(this.moveInterval);
    this.moveInterval = setInterval(() => this.performAction(), 50);
  }

  getOwnPosition() {
    let totalX = 0, totalY = 0, count = 0;
    for (const id of this.ownIDs) {
      const cell = this.cells.get(id);
      if (cell) {
        totalX += cell.x;
        totalY += cell.y;
        count++;
      }
    }
    if (count === 0) return null;
    return { x: totalX / count, y: totalY / count };
  }

  findNearestVirus() {
    const myPos = this.getOwnPosition();
    if (!myPos) return null;
    let nearest = null;
    let minDist = Infinity;
    for (const [id, cell] of this.cells) {
      if (this.ownIDs.includes(id)) continue;
      if (cell.flags & 1) {
        const dx = cell.x - myPos.x;
        const dy = cell.y - myPos.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < minDist) {
          minDist = dist;
          nearest = cell;
        }
      }
    }
    return nearest;
  }

  findNearestEnemy() {
    const myPos = this.getOwnPosition();
    if (!myPos) return null;
    let nearest = null;
    let minDist = Infinity;
    for (const [id, cell] of this.cells) {
      if (this.ownIDs.includes(id)) continue;
      if (cell.flags & 1) continue;
      if (cell.size < 20) continue;
      const dx = cell.x - myPos.x;
      const dy = cell.y - myPos.y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < minDist) {
        minDist = dist;
        nearest = cell;
      }
    }
    return nearest;
  }

  performAction() {
    if (this.state !== 'alive' || this.paused) return;
    const wb = this.worldBorder;
    this.feedTickCount++;

    switch (this.mode) {
      case 'move':
        this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
        break;

      case 'feed':
        this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
        this.gameSend(proto.ejectPacket());
        if (this.tripleMass) {
          this.gameSend(proto.ejectPacket());
          this.gameSend(proto.ejectPacket());
        }
        break;

      case 'farm':
        this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
        if (this.boosterMode || this.feedTickCount % 2 === 0) {
          this.gameSend(proto.ejectPacket());
        }
        break;

      case 'makevirus': {
        const virus = this.findNearestVirus();
        if (virus) {
          this.gameSend(proto.movePacket(virus.x, virus.y, this.movementKey));
          this.gameSend(proto.ejectPacket());
        } else {
          this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
          this.gameSend(proto.ejectPacket());
        }
        break;
      }

      case 'breakvirus': {
        const virus = this.findNearestVirus();
        if (virus) {
          this.gameSend(proto.movePacket(virus.x, virus.y, this.movementKey));
          if (this.feedTickCount % 10 === 0) {
            this.gameSend(proto.splitPacket());
          }
        } else {
          this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
        }
        break;
      }

      case 'teamer': {
        const enemy = this.findNearestEnemy();
        if (enemy) {
          const myPos = this.getOwnPosition();
          if (myPos) {
            const dx = myPos.x - enemy.x;
            const dy = myPos.y - enemy.y;
            const dist = Math.sqrt(dx * dx + dy * dy);
            if (dist < 500) {
              const fleeX = myPos.x + dx;
              const fleeY = myPos.y + dy;
              this.gameSend(proto.movePacket(fleeX, fleeY, this.movementKey));
            } else {
              this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
              this.gameSend(proto.ejectPacket());
            }
          }
        } else {
          this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
          this.gameSend(proto.ejectPacket());
        }
        break;
      }

      default:
        this.gameSend(proto.movePacket(this.targetX, this.targetY, this.movementKey));
        this.gameSend(proto.ejectPacket());
    }

    if (this.feedtrackMode && this.feedTickCount % 3 === 0) {
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

  reconnectWithNewIP() {
    this.reconnectCount++;
    if (this.reconnectCount > this.maxReconnects) {
      this.addLog(`max reconnects (${this.maxReconnects}) reached`);
      this.lastError = 'max reconnects';
      this.disconnect();
      return;
    }
    if (this.moveInterval) { clearInterval(this.moveInterval); this.moveInterval = null; }
    if (this.ws) { try { this.ws.close(); } catch(e){} this.ws = null; }
    this.state = 'idle';
    this.ownIDs = [];
    this.cells.clear();
    this.handshakeComplete = false;
    this.captchaCount = 0;
    this.spawnAttempts = 0;

    if (this.onReconnect) {
      this.proxy = this.onReconnect();
      this.addLog(`reconnect #${this.reconnectCount} new proxy`);
    }

    const delay = 1000 + Math.random() * 2000;
    setTimeout(() => {
      if (this.state === 'idle') this.connect();
    }, delay);
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
      this.addLog(`disconnected: ${this.lastError}`);
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
