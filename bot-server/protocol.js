function murmur2(str, seed) {
  const bytes = Buffer.from(str, 'utf8');
  let l = bytes.length;
  let h = (seed ^ l) >>> 0;
  let i = 0;
  while (l >= 4) {
    let k = bytes[i] | (bytes[i + 1] << 8) | (bytes[i + 2] << 16) | (bytes[i + 3] << 24);
    k = Math.imul(k, 0x5bd1e995);
    k ^= k >>> 24;
    k = Math.imul(k, 0x5bd1e995);
    h = Math.imul(h, 0x5bd1e995) ^ k;
    l -= 4;
    i += 4;
  }
  switch (l) {
    case 3: h ^= bytes[i + 2] << 16;
    case 2: h ^= bytes[i + 1] << 8;
    case 1: h ^= bytes[i]; h = Math.imul(h, 0x5bd1e995);
  }
  h ^= h >>> 13;
  h = Math.imul(h, 0x5bd1e995);
  h ^= h >>> 15;
  return h >>> 0;
}

function rotateKey(key) {
  let k = Math.imul(key, 1540483477);
  k = Math.imul(((k >>> 24) ^ k), 1540483477) ^ 114296087;
  k = Math.imul(((k >>> 13) ^ k), 1540483477);
  k = ((k >>> 15) ^ k) >>> 0;
  return k;
}

function xorWithKey(buf, key) {
  if (key === 0) return buf;
  const out = Buffer.alloc(buf.length);
  const kb = [(key & 0xFF), (key >> 8 & 0xFF), (key >> 16 & 0xFF), (key >> 24 & 0xFF)];
  for (let i = 0; i < buf.length; i++) {
    out[i] = buf[i] ^ kb[i % 4];
  }
  return out;
}

function versionToInt(ver) {
  const p = ver.split('.').map(Number);
  return p[0] * 10000 + p[1] * 100 + p[2];
}

function handshakePacket(protoVersion) {
  const buf = Buffer.alloc(5);
  buf[0] = 0xFE;
  buf.writeUInt32LE(protoVersion, 1);
  return buf;
}

function versionIntPacket(versionInt) {
  const buf = Buffer.alloc(9);
  buf[0] = 0xFF;
  buf.writeUInt32LE(versionInt, 1);
  buf.writeUInt32LE(0, 5);
  return buf;
}

function spawnPacket(name) {
  const nameBytes = Buffer.from(name, 'utf8');
  const buf = Buffer.alloc(1 + nameBytes.length + 1);
  buf[0] = 0;
  nameBytes.copy(buf, 1);
  buf[buf.length - 1] = 0;
  return buf;
}

function movePacket(x, y, movementKey) {
  const buf = Buffer.alloc(13);
  buf[0] = 16;
  buf.writeInt32LE(Math.round(x), 1);
  buf.writeInt32LE(Math.round(y), 5);
  buf.writeUInt32LE(movementKey, 9);
  return buf;
}

function ejectPacket() {
  return Buffer.from([21]);
}

function splitPacket() {
  return Buffer.from([17]);
}

function pongPacket(pingData) {
  if (pingData && pingData.length > 1) {
    const pong = Buffer.alloc(pingData.length);
    pingData.copy(pong);
    pong[0] = 0xE3;
    return pong;
  }
  return Buffer.from([0xE3]);
}

function tokenPacket(token) {
  const tb = Buffer.from(token, 'utf8');
  const buf = Buffer.alloc(1 + tb.length + 1);
  buf[0] = 81;
  tb.copy(buf, 1);
  buf[buf.length - 1] = 0;
  return buf;
}

function lz4Decompress(input) {
  const output = [];
  let i = 0;
  const n = input.length;
  while (i < n) {
    const token = input[i++];
    let litLen = token >> 4;
    if (litLen > 0) {
      if (litLen === 15) {
        let ext;
        do {
          if (i >= n) return null;
          ext = input[i++];
          litLen += ext;
        } while (ext === 255);
      }
      if (i + litLen > n) return null;
      for (let j = 0; j < litLen; j++) output.push(input[i++]);
      if (i >= n) break;
    }
    if (i + 1 >= n) return null;
    const offset = input[i] | (input[i + 1] << 8);
    i += 2;
    if (offset === 0 || offset > output.length) return null;
    let matchLen = (token & 0x0F) + 4;
    if ((token & 0x0F) === 15) {
      let ext;
      do {
        if (i >= n) return null;
        ext = input[i++];
        matchLen += ext;
      } while (ext === 255);
    }
    let pos = output.length - offset;
    for (let j = 0; j < matchLen; j++) {
      output.push(output[pos++]);
    }
  }
  return output.length > 0 ? Buffer.from(output) : null;
}

function parsePacket(data) {
  if (data.length === 0) return null;
  const op = data[0];

  if (op === 0xF1) {
    if (data.length < 5) return { type: 'version', movementKey: 0, ver: '' };
    const mk = data.readUInt32LE(1);
    let ver = '';
    let i = 5;
    while (i < data.length && data[i] !== 0) { ver += String.fromCharCode(data[i++]); }
    return { type: 'version', movementKey: mk, ver };
  }
  if (op === 0x80) return { type: 'outdated' };
  if (op === 0x81) return { type: 'protoError' };
  if (op === 0x55) return { type: 'captcha' };
  if (op === 0xF2) return { type: 'captchaV3' };
  if (op === 0xE2) return { type: 'ping', data };
  if (op === 0x6B) return { type: 'ack' };

  if (op === 0xFF && data.length > 5) {
    const decompressed = lz4Decompress(data.slice(5));
    if (decompressed) return parsePacket(decompressed);
    return null;
  }

  if (op === 16 || op === 0x66) return parseWorldUpdate(data);
  if (op === 32 || op === 50) return parseOwnIDs(data);
  if (op === 64) return parseWorldBorder(data);
  if (op === 20) return { type: 'clearAll' };
  if (op === 17 || op === 0xDC) return { type: 'leaderboard' };

  return { type: 'unknown', op, len: data.length };
}

function parseWorldUpdate(data) {
  let off = 1;
  const r = (n) => { const v = data.readUInt16LE(off); off += 2; return v; };
  const r32 = () => { const v = data.readUInt32LE(off); off += 4; return v; };
  const ri32 = () => { const v = data.readInt32LE(off); off += 4; return v; };
  const r8 = () => data[off++];
  const rStr = () => { let s = ''; while (off < data.length && data[off] !== 0) s += String.fromCharCode(data[off++]); off++; return s; };

  const eats = [];
  try {
    const eatCount = r();
    for (let i = 0; i < eatCount; i++) {
      eats.push({ eater: r32(), eaten: r32() });
    }
    const updates = [];
    while (off + 4 <= data.length) {
      const id = r32();
      if (id === 0) break;
      if (off + 10 > data.length) break;
      const x = ri32();
      const y = ri32();
      const size = r();
      const flags = r8();
      const isVirus = !!(flags & 0x01);
      if (flags & 0x80) r8();
      if (flags & 0x02) { r8(); r8(); r8(); }
      let skin = '';
      if (flags & 0x04) skin = rStr();
      let name = '';
      if (flags & 0x08) name = rStr();
      updates.push({ id, x, y, size, name, isVirus, skin });
    }
    const removals = [];
    if (off + 2 <= data.length) {
      const rc = r();
      for (let i = 0; i < rc && off + 4 <= data.length; i++) removals.push(r32());
    }
    return { type: 'worldUpdate', eats, updates, removals };
  } catch (e) {
    return { type: 'worldUpdate', eats: [], updates: [], removals: [] };
  }
}

function parseOwnIDs(data) {
  const ids = [];
  let off = 1;
  while (off + 4 <= data.length) {
    ids.push(data.readUInt32LE(off));
    off += 4;
  }
  return { type: 'ownIDs', ids };
}

function parseWorldBorder(data) {
  if (data.length < 33) return { type: 'worldBorder', minX: -7071, minY: -7071, maxX: 7071, maxY: 7071 };
  return {
    type: 'worldBorder',
    minX: data.readDoubleLE(1),
    minY: data.readDoubleLE(9),
    maxX: data.readDoubleLE(17),
    maxY: data.readDoubleLE(25)
  };
}

function encodeBouncerRequest(region, gamemode) {
  const rb = Buffer.from(region, 'utf8');
  const mb = Buffer.from(gamemode, 'utf8');
  const inner = Buffer.alloc(2 + rb.length + 2 + mb.length);
  let off = 0;
  inner[off++] = 0x0A; inner[off++] = rb.length; rb.copy(inner, off); off += rb.length;
  inner[off++] = 0x12; inner[off++] = mb.length; mb.copy(inner, off);
  const outer = Buffer.alloc(2 + inner.length);
  outer[0] = 0x0A; outer[1] = inner.length; inner.copy(outer, 2);
  return outer;
}

module.exports = {
  murmur2, rotateKey, xorWithKey, versionToInt,
  handshakePacket, versionIntPacket, spawnPacket, movePacket,
  ejectPacket, splitPacket, pongPacket, tokenPacket, lz4Decompress,
  parsePacket, encodeBouncerRequest
};
