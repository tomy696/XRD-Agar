// XRD Agar.io Injection Script
(function() {
    'use strict';

    var XRD = {
        zoomLevel: 1.0,
        autoFeed: false,
        feedTimer: null,
        activeWS: null,
        players: {},
        ownIDs: [],

        init: function() {
            this.hookCanvas();
            this.hookWebSocket();
            this.startPlayerScan();
            this.notifyNative('ready', 'ok');
        },

        hookCanvas: function() {
            var self = this;

            // Hook setTransform — catches camera set via ctx.setTransform(zoom,0,0,zoom,cx,cy)
            var origSetTransform = CanvasRenderingContext2D.prototype.setTransform;
            CanvasRenderingContext2D.prototype.setTransform = function(a, b, c, d, e, f) {
                if (typeof a === 'number' && self.zoomLevel !== 1.0
                    && this.canvas && this.canvas.width > 100
                    && a === d && b === 0 && c === 0 && Math.abs(a) !== 1) {
                    return origSetTransform.call(this,
                        a * self.zoomLevel, b, c, d * self.zoomLevel, e, f);
                }
                return origSetTransform.call(this, a, b, c, d, e, f);
            };

            // Hook scale — catches camera set via ctx.scale(zoom, zoom)
            var origScale = CanvasRenderingContext2D.prototype.scale;
            CanvasRenderingContext2D.prototype.scale = function(x, y) {
                if (self.zoomLevel !== 1.0 && this.canvas && this.canvas.width > 100) {
                    return origScale.call(this, x * self.zoomLevel, y * self.zoomLevel);
                }
                return origScale.call(this, x, y);
            };

            // Hook WebGL viewport (if game uses WebGL)
            try {
                var WGL = WebGLRenderingContext.prototype;
                var origViewport = WGL.viewport;
                WGL.viewport = function(x, y, w, h) {
                    if (self.zoomLevel !== 1.0) {
                        var inv = 1.0 / self.zoomLevel;
                        var nw = Math.round(w * inv);
                        var nh = Math.round(h * inv);
                        return origViewport.call(this,
                            Math.round(x - (nw - w) / 2),
                            Math.round(y - (nh - h) / 2), nw, nh);
                    }
                    return origViewport.call(this, x, y, w, h);
                };
            } catch (e) {}

            try {
                var WGL2 = WebGL2RenderingContext.prototype;
                var origViewport2 = WGL2.viewport;
                WGL2.viewport = function(x, y, w, h) {
                    if (self.zoomLevel !== 1.0) {
                        var inv = 1.0 / self.zoomLevel;
                        var nw = Math.round(w * inv);
                        var nh = Math.round(h * inv);
                        return origViewport2.call(this,
                            Math.round(x - (nw - w) / 2),
                            Math.round(y - (nh - h) / 2), nw, nh);
                    }
                    return origViewport2.call(this, x, y, w, h);
                };
            } catch (e) {}

            self.notifyNative('hooks', 'installed');
        },

        hookWebSocket: function() {
            var OrigWebSocket = window.WebSocket;
            var self = this;

            window.WebSocket = function(url, protocols) {
                self.notifyNative('serverURL', url);

                var ws = protocols
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

        parseServerMessage: function(view) {
            if (view.byteLength < 1) return;
            var opcode = view.getUint8(0);

            if (opcode === 16) {
                this.parseWorldUpdate(view);
            } else if (opcode === 50) {
                this.parseOwnIDs(view);
            }
        },

        parseWorldUpdate: function(view) {
            var offset = 1;
            if (offset + 2 > view.byteLength) return;
            var eatCount = view.getUint16(offset, true);
            offset += 2;
            offset += eatCount * 8;

            while (offset + 4 <= view.byteLength) {
                var id = view.getUint32(offset, true);
                offset += 4;
                if (id === 0) break;
                if (offset + 6 > view.byteLength) break;

                var x = view.getInt16(offset, true); offset += 2;
                var y = view.getInt16(offset, true); offset += 2;
                var size = view.getInt16(offset, true); offset += 2;
                if (offset >= view.byteLength) break;
                var flags = view.getUint8(offset); offset += 1;

                var isVirus = (flags & 0x01) !== 0;
                var hasColor = (flags & 0x02) !== 0;
                var hasSkin = (flags & 0x04) !== 0;
                var hasName = (flags & 0x08) !== 0;
                var hasExtFlags = (flags & 0x80) !== 0;

                if (hasExtFlags && offset < view.byteLength) offset += 1;
                if (hasColor && offset + 3 <= view.byteLength) offset += 3;

                var skin = '';
                if (hasSkin) {
                    while (offset < view.byteLength && view.getUint8(offset) !== 0) {
                        skin += String.fromCharCode(view.getUint8(offset));
                        offset++;
                    }
                    if (offset < view.byteLength) offset++;
                }

                var name = '';
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
                        x: x, y: y,
                        mass: Math.floor(size * size / 100),
                        size: size,
                        uid: id.toString(16).toUpperCase().padStart(8, '0')
                    };
                }
            }
        },

        parseOwnIDs: function(view) {
            this.ownIDs = [];
            for (var i = 1; i + 3 < view.byteLength; i += 4) {
                this.ownIDs.push(view.getUint32(i, true));
            }
            this.notifyNative('ownIDs', JSON.stringify(this.ownIDs));
        },

        startPlayerScan: function() {
            setInterval(function() {
                var list = Object.values(XRD.players)
                    .filter(function(p) { return XRD.ownIDs.indexOf(p.id) === -1; })
                    .sort(function(a, b) { return b.mass - a.mass; })
                    .slice(0, 50);
                XRD.notifyNative('players', JSON.stringify(list));
            }, 500);
        },

        setZoom: function(level) {
            this.zoomLevel = level;
        },

        setFeedInterval: function(ms) {
            if (this.feedTimer) { clearInterval(this.feedTimer); this.feedTimer = null; }
            if (ms > 0) {
                this.autoFeed = true;
                var self = this;
                this.feedTimer = setInterval(function() {
                    if (self.activeWS && self.activeWS.readyState === 1) {
                        var p = new ArrayBuffer(1);
                        new DataView(p).setUint8(0, 21);
                        self.activeWS.send(p);
                    }
                }, ms);
            } else {
                this.autoFeed = false;
            }
        },

        sendFeed: function() {
            if (this.activeWS && this.activeWS.readyState === 1) {
                var p = new ArrayBuffer(1);
                new DataView(p).setUint8(0, 21);
                this.activeWS.send(p);
            }
        },

        notifyNative: function(type, data) {
            try {
                window.webkit.messageHandlers.xrdBridge.postMessage({
                    type: type, data: data
                });
            } catch (e) {}
        }
    };

    if (document.readyState === 'complete' || document.readyState === 'interactive') {
        XRD.init();
    } else {
        window.addEventListener('DOMContentLoaded', function() { XRD.init(); });
    }

    window.XRD = XRD;
})();
