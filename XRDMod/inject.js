// XRD Agar.io Injection Script
(function() {
    'use strict';

    const XRD = {
        zoomLevel: 1.0,
        autoFeed: false,
        feedInterval: null,
        players: {},
        ownIDs: [],
        serverURL: '',
        targetUID: '',

        init: function() {
            this.hookCanvas();
            this.hookWebSocket();
            this.startPlayerScan();
            this.setupFeedLoop();
        },

        // Hook into the game's canvas rendering for zoom
        hookCanvas: function() {
            const origGetContext = HTMLCanvasElement.prototype.getContext;
            const self = this;
            HTMLCanvasElement.prototype.getContext = function(type, attrs) {
                const ctx = origGetContext.call(this, type, attrs);
                if (type === '2d' && this.width > 100) {
                    const origScale = ctx.scale;
                    ctx.scale = function(x, y) {
                        return origScale.call(this, x * self.zoomLevel, y * self.zoomLevel);
                    };
                }
                return ctx;
            };
        },

        // Hook WebSocket to intercept server URL and game data
        hookWebSocket: function() {
            const OrigWebSocket = window.WebSocket;
            const self = this;

            window.WebSocket = function(url, protocols) {
                self.serverURL = url;
                self.notifyNative('serverURL', url);

                const ws = protocols
                    ? new OrigWebSocket(url, protocols)
                    : new OrigWebSocket(url);

                ws.addEventListener('message', function(e) {
                    if (e.data instanceof ArrayBuffer) {
                        self.parseServerMessage(new DataView(e.data));
                    }
                });

                self.activeWS = ws;
                return ws;
            };
            window.WebSocket.prototype = OrigWebSocket.prototype;
            window.WebSocket.CONNECTING = OrigWebSocket.CONNECTING;
            window.WebSocket.OPEN = OrigWebSocket.OPEN;
            window.WebSocket.CLOSING = OrigWebSocket.CLOSING;
            window.WebSocket.CLOSED = OrigWebSocket.CLOSED;
        },

        // Parse incoming server packets for player data
        parseServerMessage: function(view) {
            if (view.byteLength < 1) return;
            const opcode = view.getUint8(0);

            if (opcode === 16) {
                this.parseWorldUpdate(view);
            } else if (opcode === 50) {
                this.parseOwnIDs(view);
            }
        },

        parseWorldUpdate: function(view) {
            let offset = 1;
            if (offset + 2 > view.byteLength) return;
            const eatCount = view.getUint16(offset, true);
            offset += 2;
            offset += eatCount * 8;

            while (offset + 4 <= view.byteLength) {
                const id = view.getUint32(offset, true);
                offset += 4;
                if (id === 0) break;
                if (offset + 6 > view.byteLength) break;

                const x = view.getInt16(offset, true); offset += 2;
                const y = view.getInt16(offset, true); offset += 2;
                const size = view.getInt16(offset, true); offset += 2;
                if (offset >= view.byteLength) break;
                const flags = view.getUint8(offset); offset += 1;

                const isVirus = (flags & 0x01) !== 0;
                const hasColor = (flags & 0x02) !== 0;
                const hasSkin = (flags & 0x04) !== 0;
                const hasName = (flags & 0x08) !== 0;
                const hasExtFlags = (flags & 0x80) !== 0;

                if (hasExtFlags && offset < view.byteLength) offset += 1;
                if (hasColor && offset + 3 <= view.byteLength) offset += 3;

                let skin = '';
                if (hasSkin) {
                    while (offset < view.byteLength && view.getUint8(offset) !== 0) {
                        skin += String.fromCharCode(view.getUint8(offset));
                        offset++;
                    }
                    if (offset < view.byteLength) offset++;
                }

                let name = '';
                if (hasName) {
                    while (offset < view.byteLength && view.getUint8(offset) !== 0) {
                        name += String.fromCharCode(view.getUint8(offset));
                        offset++;
                    }
                    if (offset < view.byteLength) offset++;
                }

                if (!isVirus && size > 10) {
                    this.players[id] = {
                        id: id,
                        name: name || ('Cell_' + id),
                        x: x,
                        y: y,
                        mass: Math.floor(size * size / 100),
                        size: size,
                        uid: id.toString(16).toUpperCase().padStart(8, '0')
                    };
                }
            }
        },

        parseOwnIDs: function(view) {
            this.ownIDs = [];
            for (let i = 1; i + 3 < view.byteLength; i += 4) {
                this.ownIDs.push(view.getUint32(i, true));
            }
            this.notifyNative('ownIDs', JSON.stringify(this.ownIDs));
        },

        // Periodic player list sync to native
        startPlayerScan: function() {
            setInterval(() => {
                const playerList = Object.values(this.players)
                    .filter(p => !this.ownIDs.includes(p.id))
                    .sort((a, b) => b.mass - a.mass)
                    .slice(0, 50);
                this.notifyNative('players', JSON.stringify(playerList));
            }, 500);
        },

        // Auto-feed loop
        setupFeedLoop: function() {
            setInterval(() => {
                if (this.autoFeed && this.activeWS && this.activeWS.readyState === 1) {
                    const packet = new ArrayBuffer(1);
                    new DataView(packet).setUint8(0, 21);
                    this.activeWS.send(packet);
                }
            }, 80);
        },

        // Set zoom level from native
        setZoom: function(level) {
            this.zoomLevel = level;
        },

        // Toggle auto-feed from native
        setAutoFeed: function(enabled) {
            this.autoFeed = enabled;
        },

        // Get player position by UID
        getPlayerPosition: function(uid) {
            const player = Object.values(this.players).find(p => p.uid === uid);
            if (player) {
                return JSON.stringify({ x: player.x, y: player.y, mass: player.mass });
            }
            return null;
        },

        // Send data to native Swift
        notifyNative: function(type, data) {
            try {
                window.webkit.messageHandlers.xrdBridge.postMessage({
                    type: type,
                    data: data
                });
            } catch (e) {}
        }
    };

    if (document.readyState === 'complete') {
        XRD.init();
    } else {
        window.addEventListener('load', () => XRD.init());
    }

    window.XRD = XRD;
})();
