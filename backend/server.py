#!/usr/bin/env python3
# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
"""Sabak Studios backend: redeem codes, events, card payments, error reports, admin API.

Pure standard library (no pip packages): python3 server.py
Data lives in one SQLite file. Put it behind HTTPS (reverse proxy) before real use.
"""
import csv
import hashlib
import io
import hmac
import json
import os
import secrets
import sqlite3
import string
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
CFG_PATH = os.environ.get("SABAK_CONFIG", os.path.join(HERE, "config.json"))

DEFAULT_PACKS = [
    {"id": "c10k", "kind": "coins", "amount": 10000, "price_usd": 1.00},
    {"id": "c22k", "kind": "coins", "amount": 22000, "price_usd": 2.00},
    {"id": "c60k", "kind": "coins", "amount": 60000, "price_usd": 5.00},
    {"id": "c130k", "kind": "coins", "amount": 130000, "price_usd": 10.00},
    {"id": "c280k", "kind": "coins", "amount": 280000, "price_usd": 20.00},
    {"id": "g80", "kind": "gems", "amount": 80, "price_usd": 0.99},
    {"id": "g170", "kind": "gems", "amount": 170, "price_usd": 1.99},
    {"id": "g450", "kind": "gems", "amount": 450, "price_usd": 4.99},
    {"id": "g950", "kind": "gems", "amount": 950, "price_usd": 9.99},
    {"id": "g2000", "kind": "gems", "amount": 2000, "price_usd": 19.99},
]


def load_config():
    cfg = {
        "port": 8080,
        "db": os.path.join(HERE, "sabak.db"),
        "admin_key": "",
        "public_url": "http://localhost:8080",
        "provider": "test",  # "test" (no money) | "stripe"
        "stripe_secret": "",
        "stripe_webhook_secret": "",
        "packs": DEFAULT_PACKS,
    }
    if os.path.exists(CFG_PATH):
        with open(CFG_PATH, encoding="utf-8") as f:
            cfg.update(json.load(f))
    for k, env in [("port", "PORT"), ("admin_key", "ADMIN_KEY"), ("public_url", "PUBLIC_URL"), ("provider", "PAY_PROVIDER"),
                   ("stripe_secret", "STRIPE_SECRET"), ("stripe_webhook_secret", "STRIPE_WEBHOOK_SECRET"), ("db", "DB_PATH")]:
        if os.environ.get(env):
            cfg[k] = type(cfg[k])(os.environ[env])
    if not cfg["admin_key"]:
        cfg["admin_key"] = secrets.token_urlsafe(18)
        try:
            with open(CFG_PATH, "w", encoding="utf-8") as f:
                json.dump({"admin_key": cfg["admin_key"]}, f, indent=2)
            print("Created %s with a new admin key" % CFG_PATH)
        except OSError:
            pass
    return cfg


CFG = load_config()
DB_LOCK = threading.Lock()


def db():
    con = sqlite3.connect(CFG["db"], timeout=20)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    return con


def init_db():
    with DB_LOCK, db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS players(id TEXT PRIMARY KEY, name TEXT, game TEXT, platform TEXT, version TEXT, first_seen INTEGER, last_seen INTEGER);
        CREATE TABLE IF NOT EXISTS codes(code TEXT PRIMARY KEY, game TEXT, coins INTEGER, gems INTEGER, max_uses INTEGER, expires_at INTEGER, note TEXT, active INTEGER, created_at INTEGER);
        CREATE TABLE IF NOT EXISTS redemptions(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT, player_id TEXT, ts INTEGER, UNIQUE(code, player_id));
        CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY AUTOINCREMENT, game TEXT, title TEXT, title_ar TEXT, body TEXT, body_ar TEXT, starts_at INTEGER, ends_at INTEGER, reward_coins INTEGER, reward_gems INTEGER, active INTEGER, created_at INTEGER);
        CREATE TABLE IF NOT EXISTS event_claims(event_id INTEGER, player_id TEXT, ts INTEGER, PRIMARY KEY(event_id, player_id));
        CREATE TABLE IF NOT EXISTS orders(id TEXT PRIMARY KEY, player_id TEXT, game TEXT, pack_id TEXT, kind TEXT, amount INTEGER, price_usd REAL, provider TEXT, provider_ref TEXT, status TEXT, created_at INTEGER, paid_at INTEGER, granted_at INTEGER);
        CREATE TABLE IF NOT EXISTS reports(id INTEGER PRIMARY KEY AUTOINCREMENT, game TEXT, version TEXT, player_id TEXT, kind TEXT, message TEXT, stack TEXT, platform TEXT, ts INTEGER);
        CREATE TABLE IF NOT EXISTS grants(id INTEGER PRIMARY KEY AUTOINCREMENT, player_id TEXT, coins INTEGER, gems INTEGER, note TEXT, created_at INTEGER, claimed_at INTEGER);
        CREATE TABLE IF NOT EXISTS announcements(id INTEGER PRIMARY KEY AUTOINCREMENT, game TEXT, text TEXT, text_ar TEXT, ends_at INTEGER, active INTEGER, created_at INTEGER);
        CREATE TABLE IF NOT EXISTS gamecfg(game TEXT PRIMARY KEY, json TEXT);
        CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY AUTOINCREMENT, player_id TEXT, game TEXT, from_admin INTEGER, text TEXT, ts INTEGER, delivered_at INTEGER, read_at INTEGER);
        CREATE TABLE IF NOT EXISTS scores(game TEXT, board TEXT, player_id TEXT, name TEXT, score INTEGER, ts INTEGER, hidden INTEGER DEFAULT 0, PRIMARY KEY(game, board, player_id));
        CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, who TEXT, action TEXT, detail TEXT);
        CREATE TABLE IF NOT EXISTS admin_keys(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, role TEXT, key_hash TEXT UNIQUE, created_at INTEGER);
        CREATE INDEX IF NOT EXISTS ix_messages_player ON messages(player_id);
        CREATE INDEX IF NOT EXISTS ix_reports_ts ON reports(ts);
        CREATE INDEX IF NOT EXISTS ix_grants_player ON grants(player_id);
        CREATE INDEX IF NOT EXISTS ix_orders_player ON orders(player_id);
        """)
        migrate(c)


def now():
    return int(time.time())


def migrate(c):
    cols = [r["name"] for r in c.execute("PRAGMA table_info(players)")]
    if "banned" not in cols:
        c.execute("ALTER TABLE players ADD COLUMN banned INTEGER DEFAULT 0")
    if "ban_reason" not in cols:
        c.execute("ALTER TABLE players ADD COLUMN ban_reason TEXT DEFAULT ''")


def get_cfg(c, game=""):
    """remote settings: global ('') overlaid by the game's own, one top-level key at a time"""
    out = {}
    for g in ("", game):
        if g == "" and out:
            continue
        r = c.execute("SELECT json FROM gamecfg WHERE game=?", (g,)).fetchone()
        if r:
            try:
                out.update(json.loads(r["json"]))
            except ValueError:
                pass
        if game == "":
            break
    return out


def hash_key(k):
    return hashlib.sha256(k.encode()).hexdigest()


OWNER_ONLY = {"player/ban", "gamecfg", "keys", "key/create", "key/delete", "reports/clear", "code/delete", "event/delete",
              "announce/delete", "score/hide", "audit"}
GET_OWNER_ONLY = {"keys", "audit", "gamecfg"}


def is_banned(c, pid):
    r = c.execute("SELECT banned FROM players WHERE id=?", (pid,)).fetchone()
    return bool(r and r["banned"])


# ----------------------------------------------------------------------------- rate limiting
_hits = {}
_hits_lock = threading.Lock()


def rate_ok(key, limit, per=60):
    t = time.time()
    with _hits_lock:
        arr = [x for x in _hits.get(key, []) if t - x < per]
        if len(arr) >= limit:
            _hits[key] = arr
            return False
        arr.append(t)
        _hits[key] = arr
    return True


def new_code():
    alpha = string.ascii_uppercase.replace("O", "").replace("I", "") + "23456789"
    raw = "".join(secrets.choice(alpha) for _ in range(12))
    return "-".join(raw[i:i + 4] for i in range(0, 12, 4))


def norm_code(s):
    return "".join(ch for ch in str(s).upper() if ch.isalnum())


def pack_of(pack_id, game=""):
    with DB_LOCK, db() as c:
        over = get_cfg(c, game).get("packs")
    for p in (over if isinstance(over, list) and over else CFG["packs"]):
        if p["id"] == pack_id:
            return p
    return None


def touch_player(c, pid, name="", game="", platform="", version=""):
    if not pid:
        return
    row = c.execute("SELECT id FROM players WHERE id=?", (pid,)).fetchone()
    if row:
        c.execute("UPDATE players SET last_seen=?, name=COALESCE(NULLIF(?,''),name), game=COALESCE(NULLIF(?,''),game), platform=COALESCE(NULLIF(?,''),platform), version=COALESCE(NULLIF(?,''),version) WHERE id=?",
                  (now(), name, game, platform, version, pid))
    else:
        c.execute("INSERT INTO players(id,name,game,platform,version,first_seen,last_seen) VALUES(?,?,?,?,?,?,?)", (pid, name, game, platform, version, now(), now()))


# ----------------------------------------------------------------------------- payments
def stripe_create_checkout(order, pack):
    cents = int(round(float(pack["price_usd"]) * 100))
    form = {
        "mode": "payment",
        "success_url": CFG["public_url"].rstrip("/") + "/pay/done?order=" + order["id"],
        "cancel_url": CFG["public_url"].rstrip("/") + "/pay/cancel?order=" + order["id"],
        "client_reference_id": order["id"],
        "metadata[order_id]": order["id"],
        "line_items[0][quantity]": "1",
        "line_items[0][price_data][currency]": "usd",
        "line_items[0][price_data][unit_amount]": str(cents),
        "line_items[0][price_data][product_data][name]": "%d %s" % (pack["amount"], pack["kind"]),
    }
    req = urllib.request.Request("https://api.stripe.com/v1/checkout/sessions", data=urllib.parse.urlencode(form).encode(),
                                 headers={"Authorization": "Bearer " + CFG["stripe_secret"]})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.loads(r.read().decode())
    return data["id"], data["url"]


def verify_stripe_signature(payload, header, secret, tolerance=300):
    try:
        parts = dict(p.split("=", 1) for p in header.split(","))
        t = parts["t"]
        sig = parts["v1"]
    except Exception:
        return False
    if abs(time.time() - int(t)) > tolerance:
        return False
    expect = hmac.new(secret.encode(), (t + ".").encode() + payload, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expect, sig)


def mark_paid(order_id, ref=""):
    with DB_LOCK, db() as c:
        row = c.execute("SELECT status FROM orders WHERE id=?", (order_id,)).fetchone()
        if not row or row["status"] != "created":
            return False
        c.execute("UPDATE orders SET status='paid', paid_at=?, provider_ref=COALESCE(NULLIF(?,''),provider_ref) WHERE id=?", (now(), ref, order_id))
        return True


# ----------------------------------------------------------------------------- HTTP
class H(BaseHTTPRequestHandler):
    server_version = "Sabak/1.0"

    def log_message(self, fmt, *args):
        if os.environ.get("SABAK_QUIET"):
            return
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    # ---- helpers
    def ip(self):
        return self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()

    def send_json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, html, code=200):
        body = html.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def raw_body(self):
        if getattr(self, "_raw", None) is not None:
            return self._raw
        n = int(self.headers.get("Content-Length") or 0)
        if n > 200_000:
            raise ValueError("body too large")
        self._raw = self.rfile.read(n) if n else b""
        return self._raw

    def json_body(self):
        b = self.raw_body()
        return json.loads(b.decode() or "{}") if b else {}

    def admin_role(self):
        """('owner'|'editor'|'viewer', name) or None"""
        key = self.headers.get("X-Admin-Key", "")
        if not key:
            return None
        if hmac.compare_digest(key.encode(), CFG["admin_key"].encode()):
            return ("owner", "owner")
        with DB_LOCK, db() as c:
            r = c.execute("SELECT name, role FROM admin_keys WHERE key_hash=?", (hash_key(key),)).fetchone()
        return (r["role"], r["name"]) if r else None

    # ---- routing
    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")

    def do_DELETE(self):
        self.route("DELETE")

    def route(self, method):
        try:
            u = urllib.parse.urlparse(self.path)
            q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
            path = u.path.rstrip("/") or "/"
            if path == "/":
                return self.send_json({"service": "sabak-backend", "ok": True})
            if path.startswith("/admin/api/"):
                who = self.admin_role()
                if not who:
                    if not rate_ok("badadmin:" + self.ip(), 10):
                        return self.send_json({"error": "rate"}, 429)
                    return self.send_json({"error": "unauthorized"}, 401)
                self.role, self.who = who
                ap = path[len("/admin/api/"):]
                if self.role == "viewer" and (method != "GET" or ap in GET_OWNER_ONLY):
                    return self.send_json({"error": "forbidden"}, 403)
                if self.role == "editor" and (ap in OWNER_ONLY and (method != "GET" or ap in GET_OWNER_ONLY)):
                    return self.send_json({"error": "forbidden"}, 403)
                if method == "POST":
                    try:
                        det = self.raw_body().decode()[:200]
                    except Exception:
                        det = ""
                    with DB_LOCK, db() as c:
                        c.execute("INSERT INTO audit(ts,who,action,detail) VALUES(?,?,?,?)", (now(), self.who, ap, det))
                return self.admin(method, ap, q)
            return self.public(method, path, q)
        except Exception as e:  # never crash the server on a bad request
            sys.stderr.write("ERROR %r\n" % (e,))
            try:
                self.send_json({"error": "server", "detail": str(e)[:200]}, 500)
            except Exception:
                pass

    # ---- public API (game clients)
    def public(self, method, path, q):
        if path == "/api/config" and method == "GET":
            with DB_LOCK, db() as c:
                evs = [dict(r) for r in c.execute("SELECT id,title,title_ar,body,body_ar,ends_at,reward_coins,reward_gems FROM events WHERE active=1 AND starts_at<=? AND ends_at>=? AND (game=? OR game='')", (now(), now(), q.get("game", "")))]
            with DB_LOCK, db() as c:
                ann = [dict(r) for r in c.execute("SELECT id,text,text_ar FROM announcements WHERE active=1 AND (ends_at=0 OR ends_at>=?) AND (game=? OR game='') ORDER BY id DESC LIMIT 3", (now(), q.get("game", "")))]
            with DB_LOCK, db() as c:
                gcfg = get_cfg(c, q.get("game", ""))
            packs = gcfg.pop("packs", None)
            return self.send_json({"ok": True, "announcements": ann, "time": now(), "payments": CFG["provider"] in ("stripe", "test"), "provider": CFG["provider"],
                                   "packs": packs if isinstance(packs, list) and packs else CFG["packs"], "events": evs, "cfg": gcfg})
        if path == "/api/player/hello" and method == "POST":
            b = self.json_body()
            with DB_LOCK, db() as c:
                pid = str(b.get("player_id", ""))[:64]
                touch_player(c, pid, str(b.get("name", ""))[:40], str(b.get("game", ""))[:40], str(b.get("platform", ""))[:30], str(b.get("version", ""))[:20])
                banned = is_banned(c, pid)
                grants = [] if banned else [dict(r) for r in c.execute("SELECT id,coins,gems,note FROM grants WHERE player_id=? AND claimed_at IS NULL ORDER BY id LIMIT 20", (pid,))]
                msgs = [dict(r) for r in c.execute("SELECT id,text FROM messages WHERE player_id=? AND from_admin=1 AND delivered_at IS NULL ORDER BY id LIMIT 5", (pid,))]
            return self.send_json({"ok": True, "banned": banned, "grants": grants, "messages": msgs})
        if path == "/api/msg/ack" and method == "POST":
            b = self.json_body()
            with DB_LOCK, db() as c:
                c.execute("UPDATE messages SET delivered_at=? WHERE id=? AND player_id=? AND from_admin=1", (now(), int(b.get("id", 0)), str(b.get("player_id", ""))[:64]))
            return self.send_json({"ok": True})
        if path == "/api/support/send" and method == "POST":
            b = self.json_body()
            pid = str(b.get("player_id", ""))[:64]
            text = str(b.get("text", "")).strip()[:500]
            if not pid or not text:
                return self.send_json({"ok": False, "error": "invalid"})
            if not rate_ok("support:" + pid, 5, 600):
                return self.send_json({"ok": False, "error": "rate"}, 429)
            with DB_LOCK, db() as c:
                touch_player(c, pid, str(b.get("name", ""))[:40], str(b.get("game", ""))[:40])
                if is_banned(c, pid):
                    return self.send_json({"ok": False, "error": "banned"}, 403)
                c.execute("INSERT INTO messages(player_id,game,from_admin,text,ts) VALUES(?,?,0,?,?)", (pid, str(b.get("game", ""))[:40], text, now()))
            return self.send_json({"ok": True})
        if path == "/api/score" and method == "POST":
            b = self.json_body()
            pid = str(b.get("player_id", ""))[:64]
            try:
                sc = int(b.get("score", 0))
            except (TypeError, ValueError):
                sc = -1
            if not pid or sc < 0 or sc > 2_000_000_000:
                return self.send_json({"ok": False, "error": "invalid"})
            if not rate_ok("score:" + pid, 30):
                return self.send_json({"ok": False, "error": "rate"}, 429)
            game = str(b.get("game", ""))[:40]
            board = str(b.get("board", "xp"))[:30]
            with DB_LOCK, db() as c:
                touch_player(c, pid, str(b.get("name", ""))[:40], game)
                if is_banned(c, pid):
                    return self.send_json({"ok": False, "error": "banned"}, 403)
                c.execute("INSERT INTO scores(game,board,player_id,name,score,ts) VALUES(?,?,?,?,?,?) ON CONFLICT(game,board,player_id) DO UPDATE SET score=MAX(score,excluded.score), name=excluded.name, ts=excluded.ts",
                          (game, board, pid, str(b.get("name", ""))[:40], sc, now()))
            return self.send_json({"ok": True})
        if path == "/api/leaderboard" and method == "GET":
            game = q.get("game", "")
            board = q.get("board", "xp")
            lim = max(1, min(int(q.get("limit", 20)), 50))
            with DB_LOCK, db() as c:
                base = "FROM scores s LEFT JOIN players p ON p.id=s.player_id WHERE s.game=? AND s.board=? AND s.hidden=0 AND COALESCE(p.banned,0)=0"
                rows = [dict(r) for r in c.execute("SELECT s.name, s.score, s.player_id " + base + " ORDER BY s.score DESC LIMIT ?", (game, board, lim))]
                me = None
                pid = q.get("player_id", "")
                if pid:
                    r = c.execute("SELECT s.score " + base + " AND s.player_id=?", (game, board, pid)).fetchone()
                    if r:
                        rank = c.execute("SELECT COUNT(*) n " + base + " AND s.score>?", (game, board, r["score"])).fetchone()["n"] + 1
                        me = {"score": r["score"], "rank": rank}
            for r in rows:
                r["mine"] = r.pop("player_id") == pid and pid != ""
            return self.send_json({"ok": True, "rows": rows, "me": me})
        if path == "/api/grant/ack" and method == "POST":
            b = self.json_body()
            with DB_LOCK, db() as c:
                c.execute("UPDATE grants SET claimed_at=? WHERE id=? AND player_id=? AND claimed_at IS NULL", (now(), int(b.get("id", 0)), str(b.get("player_id", ""))[:64]))
            return self.send_json({"ok": True})
        if path == "/api/redeem" and method == "POST":
            return self.redeem(self.json_body())
        if path == "/api/events" and method == "GET":
            return self.events_for(q)
        if path == "/api/event/claim" and method == "POST":
            return self.event_claim(self.json_body())
        if path == "/api/pay/create" and method == "POST":
            return self.pay_create(self.json_body())
        if path == "/api/pay/claim" and method == "POST":
            return self.pay_claim(self.json_body())
        if path == "/api/pay/status" and method == "GET":
            with DB_LOCK, db() as c:
                r = c.execute("SELECT status FROM orders WHERE id=? AND player_id=?", (q.get("order_id", ""), q.get("player_id", ""))).fetchone()
            return self.send_json({"ok": bool(r), "status": r["status"] if r else "unknown"})
        if path == "/api/pay/webhook/stripe" and method == "POST":
            return self.stripe_webhook()
        if path.startswith("/pay/test/") and method == "GET":
            return self.test_pay_page(path.rsplit("/", 1)[-1])
        if path.startswith("/pay/test/") and method == "POST":
            return self.test_pay_confirm(path.rsplit("/", 1)[-1])
        if path in ("/pay/done", "/pay/cancel"):
            msg = "Payment received. Go back to the game." if path == "/pay/done" else "Payment cancelled."
            return self.send_html("<meta name=viewport content='width=device-width'><body style='font-family:sans-serif;background:#10131a;color:#fff;text-align:center;padding:60px'><h2>%s</h2><p>%s</p>" % ("Sabak Studios", msg))
        if path == "/api/report" and method == "POST":
            return self.report(self.json_body())
        return self.send_json({"error": "not_found"}, 404)

    def redeem(self, b):
        pid = str(b.get("player_id", ""))[:64]
        code = norm_code(b.get("code", ""))
        if not pid or len(code) < 6:
            return self.send_json({"ok": False, "error": "invalid"})
        if not rate_ok("redeem:" + self.ip(), 12) or not rate_ok("redeemp:" + pid, 8):
            return self.send_json({"ok": False, "error": "rate"}, 429)
        game = str(b.get("game", ""))
        with DB_LOCK, db() as c:
            touch_player(c, pid, game=game)
            if is_banned(c, pid):
                return self.send_json({"ok": False, "error": "banned"}, 403)
            row = None
            for r in c.execute("SELECT * FROM codes WHERE active=1"):
                if norm_code(r["code"]) == code:
                    row = r
                    break
            if not row or (row["game"] and game and row["game"] != game):
                return self.send_json({"ok": False, "error": "invalid"})
            if row["expires_at"] and row["expires_at"] < now():
                return self.send_json({"ok": False, "error": "expired"})
            if c.execute("SELECT 1 FROM redemptions WHERE code=? AND player_id=?", (row["code"], pid)).fetchone():
                return self.send_json({"ok": False, "error": "used"})
            used = c.execute("SELECT COUNT(*) n FROM redemptions WHERE code=?", (row["code"],)).fetchone()["n"]
            if row["max_uses"] and used >= row["max_uses"]:
                return self.send_json({"ok": False, "error": "limit"})
            c.execute("INSERT INTO redemptions(code,player_id,ts) VALUES(?,?,?)", (row["code"], pid, now()))
            return self.send_json({"ok": True, "coins": row["coins"], "gems": row["gems"]})

    def events_for(self, q):
        pid = q.get("player_id", "")
        with DB_LOCK, db() as c:
            out = []
            for r in c.execute("SELECT * FROM events WHERE active=1 AND starts_at<=? AND ends_at>=? AND (game=? OR game='') ORDER BY ends_at", (now(), now(), q.get("game", ""))):
                d = dict(r)
                d["claimed"] = bool(c.execute("SELECT 1 FROM event_claims WHERE event_id=? AND player_id=?", (r["id"], pid)).fetchone())
                out.append(d)
        return self.send_json({"ok": True, "events": out, "time": now()})

    def event_claim(self, b):
        pid = str(b.get("player_id", ""))[:64]
        eid = int(b.get("event_id", 0))
        with DB_LOCK, db() as c:
            if is_banned(c, pid):
                return self.send_json({"ok": False, "error": "banned"}, 403)
            r = c.execute("SELECT * FROM events WHERE id=? AND active=1 AND starts_at<=? AND ends_at>=?", (eid, now(), now())).fetchone()
            if not r:
                return self.send_json({"ok": False, "error": "closed"})
            if c.execute("SELECT 1 FROM event_claims WHERE event_id=? AND player_id=?", (eid, pid)).fetchone():
                return self.send_json({"ok": False, "error": "used"})
            c.execute("INSERT INTO event_claims VALUES(?,?,?)", (eid, pid, now()))
            touch_player(c, pid)
            return self.send_json({"ok": True, "coins": r["reward_coins"], "gems": r["reward_gems"]})

    def pay_create(self, b):
        pid = str(b.get("player_id", ""))[:64]
        pack = pack_of(str(b.get("pack_id", "")), str(b.get("game", ""))[:40])
        if not pid or not pack:
            return self.send_json({"ok": False, "error": "invalid"})
        if CFG["provider"] not in ("stripe", "test"):
            return self.send_json({"ok": False, "error": "payments_off"})
        if not rate_ok("pay:" + pid, 10):
            return self.send_json({"ok": False, "error": "rate"}, 429)
        order = {"id": "ord_" + secrets.token_urlsafe(10), "player_id": pid, "game": str(b.get("game", ""))[:40], "pack_id": pack["id"]}
        try:
            if CFG["provider"] == "stripe":
                ref, url = stripe_create_checkout(order, pack)
            else:
                ref, url = "test", CFG["public_url"].rstrip("/") + "/pay/test/" + order["id"]
        except (urllib.error.URLError, KeyError, ValueError) as e:
            return self.send_json({"ok": False, "error": "gateway", "detail": str(e)[:120]}, 502)
        with DB_LOCK, db() as c:
            touch_player(c, pid, game=order["game"])
            c.execute("INSERT INTO orders VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)", (order["id"], pid, order["game"], pack["id"], pack["kind"], pack["amount"], pack["price_usd"], CFG["provider"], ref, "created", now(), None, None))
        return self.send_json({"ok": True, "order_id": order["id"], "checkout_url": url, "provider": CFG["provider"]})

    def pay_claim(self, b):
        pid = str(b.get("player_id", ""))[:64]
        oid = str(b.get("order_id", ""))
        with DB_LOCK, db() as c:
            r = c.execute("SELECT * FROM orders WHERE id=? AND player_id=?", (oid, pid)).fetchone()
            if not r:
                return self.send_json({"ok": False, "error": "unknown"})
            if r["status"] == "created":
                return self.send_json({"ok": False, "error": "pending"})
            if r["status"] != "paid":
                return self.send_json({"ok": False, "error": r["status"]})
            c.execute("UPDATE orders SET status='granted', granted_at=? WHERE id=?", (now(), oid))
            return self.send_json({"ok": True, "kind": r["kind"], "amount": r["amount"], "pack_id": r["pack_id"]})

    def stripe_webhook(self):
        payload = self.raw_body()
        if not CFG["stripe_webhook_secret"] or not verify_stripe_signature(payload, self.headers.get("Stripe-Signature", ""), CFG["stripe_webhook_secret"]):
            return self.send_json({"error": "bad_signature"}, 400)
        ev = json.loads(payload.decode())
        if ev.get("type") in ("checkout.session.completed", "checkout.session.async_payment_succeeded"):
            obj = ev["data"]["object"]
            if obj.get("payment_status") == "paid":
                mark_paid(obj.get("client_reference_id") or obj.get("metadata", {}).get("order_id", ""), obj.get("payment_intent") or "")
        return self.send_json({"ok": True})

    def test_pay_page(self, oid):
        if CFG["provider"] != "test":
            return self.send_json({"error": "not_found"}, 404)
        return self.send_html("<meta name=viewport content='width=device-width'><body style='font-family:sans-serif;background:#10131a;color:#fff;text-align:center;padding:50px'><h2>TEST PAYMENT</h2><p>No real money is charged.</p><form method=post><button style='font-size:22px;padding:14px 30px;background:#ff7a1a;border:0;border-radius:10px'>Pay (test)</button></form>")

    def test_pay_confirm(self, oid):
        if CFG["provider"] != "test":
            return self.send_json({"error": "not_found"}, 404)
        self.raw_body()
        mark_paid(oid, "test")
        return self.send_html("<meta name=viewport content='width=device-width'><body style='font-family:sans-serif;background:#10131a;color:#fff;text-align:center;padding:60px'><h2>Paid (test)</h2><p>Go back to the game.</p>")

    def report(self, b):
        if not rate_ok("report:" + self.ip(), 60):
            return self.send_json({"ok": False, "error": "rate"}, 429)
        with DB_LOCK, db() as c:
            c.execute("INSERT INTO reports(game,version,player_id,kind,message,stack,platform,ts) VALUES(?,?,?,?,?,?,?,?)",
                      (str(b.get("game", ""))[:40], str(b.get("version", ""))[:20], str(b.get("player_id", ""))[:64], str(b.get("kind", "error"))[:20],
                       str(b.get("message", ""))[:600], str(b.get("stack", ""))[:4000], str(b.get("platform", ""))[:40], now()))
        return self.send_json({"ok": True})

    # ---- admin API
    def admin(self, method, path, q):
        game = q.get("game", "")
        gw = " AND game=?" if game else ""
        ga = (game,) if game else ()
        with DB_LOCK, db() as c:
            if path == "ping":
                return self.send_json({"ok": True, "role": self.role})
            if path == "summary":
                day = now() - 86400
                rev = c.execute("SELECT COALESCE(SUM(price_usd),0) s, COUNT(*) n FROM orders WHERE status IN ('paid','granted') AND provider!='test'" + gw, ga).fetchone()
                rev_t = c.execute("SELECT COALESCE(SUM(price_usd),0) s, COUNT(*) n FROM orders WHERE status IN ('paid','granted') AND provider='test'" + gw, ga).fetchone()
                rev_d = c.execute("SELECT COALESCE(SUM(price_usd),0) s FROM orders WHERE status IN ('paid','granted') AND provider!='test' AND paid_at>?" + gw, (day,) + ga).fetchone()
                out = {
                    "revenue_usd": rev["s"], "paid_orders": rev["n"], "revenue_24h_usd": rev_d["s"], "test_revenue_usd": rev_t["s"], "test_orders": rev_t["n"],
                    "pending_orders": c.execute("SELECT COUNT(*) n FROM orders WHERE status='created'" + gw, ga).fetchone()["n"],
                    "players": c.execute("SELECT COUNT(*) n FROM players WHERE 1=1" + gw, ga).fetchone()["n"],
                    "active_24h": c.execute("SELECT COUNT(*) n FROM players WHERE last_seen>?" + gw, (day,) + ga).fetchone()["n"],
                    "codes_active": c.execute("SELECT COUNT(*) n FROM codes WHERE active=1" + gw, ga).fetchone()["n"],
                    "redemptions": c.execute("SELECT COUNT(*) n FROM redemptions").fetchone()["n"],
                    "events_active": c.execute("SELECT COUNT(*) n FROM events WHERE active=1 AND ends_at>=?" + gw, (now(),) + ga).fetchone()["n"],
                    "errors_24h": c.execute("SELECT COUNT(*) n FROM reports WHERE ts>? AND kind!='info'" + gw, (day,) + ga).fetchone()["n"],
                    "games": [r["game"] for r in c.execute("SELECT DISTINCT game FROM players WHERE game!=''")],
                    "provider": CFG["provider"],
                }
                series = []
                t0 = now() - (now() % 86400)   # UTC midnight today
                for i in range(6, -1, -1):
                    a, z = t0 - i * 86400, t0 - i * 86400 + 86400
                    series.append({
                        "day": time.strftime("%m-%d", time.gmtime(a)),
                        "new_players": c.execute("SELECT COUNT(*) n FROM players WHERE first_seen>=? AND first_seen<?" + gw, (a, z) + ga).fetchone()["n"],
                        "active": c.execute("SELECT COUNT(*) n FROM players WHERE last_seen>=? AND last_seen<?" + gw, (a, z) + ga).fetchone()["n"],
                        "redemptions": c.execute("SELECT COUNT(*) n FROM redemptions WHERE ts>=? AND ts<?", (a, z)).fetchone()["n"],
                        "revenue": c.execute("SELECT COALESCE(SUM(price_usd),0) s FROM orders WHERE status IN ('paid','granted') AND provider!='test' AND paid_at>=? AND paid_at<?" + gw, (a, z) + ga).fetchone()["s"],
                    })
                out["series"] = series
                out["errors_1h"] = c.execute("SELECT COUNT(*) n FROM reports WHERE ts>? AND kind!='info'" + gw, (now() - 3600,) + ga).fetchone()["n"]
                out["support_unread"] = c.execute("SELECT COUNT(*) n FROM messages WHERE from_admin=0 AND read_at IS NULL").fetchone()["n"]
                out["banned"] = c.execute("SELECT COUNT(*) n FROM players WHERE banned=1" + gw, ga).fetchone()["n"]
                return self.send_json(out)
            if path == "payments":
                rows = c.execute("SELECT o.*, COALESCE(p.name,'') name FROM orders o LEFT JOIN players p ON p.id=o.player_id WHERE 1=1" + gw.replace("game", "o.game") + " ORDER BY o.created_at DESC LIMIT ?", ga + (int(q.get("limit", 100)),))
                return self.send_json({"payments": [dict(r) for r in rows]})
            if path == "spenders":
                rows = c.execute("SELECT o.player_id, COALESCE(p.name,'') name, SUM(o.price_usd) total, COUNT(*) n, MAX(o.paid_at) last FROM orders o LEFT JOIN players p ON p.id=o.player_id WHERE o.status IN ('paid','granted') AND o.provider!='test'" + gw.replace("game", "o.game") + " GROUP BY o.player_id ORDER BY total DESC LIMIT 100", ga)
                return self.send_json({"spenders": [dict(r) for r in rows]})
            if path == "players":
                term = str(q.get("q", "")).strip()
                tw = " AND (name LIKE ? OR id LIKE ?)" if term else ""
                ta = ("%" + term + "%", "%" + term + "%") if term else ()
                rows = c.execute("SELECT * FROM players WHERE 1=1" + gw + tw + " ORDER BY last_seen DESC LIMIT 200", ga + ta)
                return self.send_json({"players": [dict(r) for r in rows]})
            if path == "gamecfg":
                g = q.get("game", "")
                if method == "GET":
                    r = c.execute("SELECT json FROM gamecfg WHERE game=?", (g,)).fetchone()
                    own = json.loads(r["json"]) if r else {}
                    return self.send_json({"ok": True, "cfg": own, "effective": get_cfg(c, g), "game": g, "packs_default": CFG["packs"]})
                b = self.json_body()
                g = str(b.get("game", ""))[:40]
                key = str(b.get("key", ""))[:40]
                if not key:
                    return self.send_json({"ok": False, "error": "invalid"})
                r = c.execute("SELECT json FROM gamecfg WHERE game=?", (g,)).fetchone()
                cur = json.loads(r["json"]) if r else {}
                if b.get("value", None) is None:
                    cur.pop(key, None)
                else:
                    cur[key] = b["value"]
                c.execute("INSERT INTO gamecfg(game,json) VALUES(?,?) ON CONFLICT(game) DO UPDATE SET json=excluded.json", (g, json.dumps(cur, ensure_ascii=False)))
                return self.send_json({"ok": True, "cfg": cur})
            if path == "support":
                rows = c.execute("SELECT m.player_id, COALESCE(p.name,'') name, COALESCE(p.game,'') game, MAX(m.id) last_id, SUM(CASE WHEN m.from_admin=0 AND m.read_at IS NULL THEN 1 ELSE 0 END) unread FROM messages m LEFT JOIN players p ON p.id=m.player_id WHERE 1=1" + gw.replace("game", "m.game") + " GROUP BY m.player_id ORDER BY last_id DESC LIMIT 100", ga)
                out = []
                for r in rows:
                    d = dict(r)
                    last = c.execute("SELECT text, from_admin, ts FROM messages WHERE id=?", (d["last_id"],)).fetchone()
                    d.update({"text": last["text"], "from_admin": last["from_admin"], "ts": last["ts"]})
                    out.append(d)
                return self.send_json({"threads": out})
            if path == "support/thread":
                pid = q.get("player_id", "")
                c.execute("UPDATE messages SET read_at=? WHERE player_id=? AND from_admin=0 AND read_at IS NULL", (now(), pid))
                rows = c.execute("SELECT id,from_admin,text,ts,delivered_at FROM messages WHERE player_id=? ORDER BY id DESC LIMIT 60", (pid,))
                return self.send_json({"messages": [dict(r) for r in rows][::-1]})
            if path == "support/send" and method == "POST":
                b = self.json_body()
                pid = str(b.get("player_id", ""))
                text = str(b.get("text", "")).strip()[:500]
                r = c.execute("SELECT game FROM players WHERE id=?", (pid,)).fetchone()
                if not r or not text:
                    return self.send_json({"ok": False, "error": "invalid"})
                c.execute("INSERT INTO messages(player_id,game,from_admin,text,ts) VALUES(?,?,1,?,?)", (pid, r["game"], text, now()))
                return self.send_json({"ok": True})
            if path == "scores":
                board = q.get("board", "xp")
                rows = c.execute("SELECT s.game, s.board, s.player_id, s.name, s.score, s.hidden, COALESCE(p.banned,0) banned FROM scores s LEFT JOIN players p ON p.id=s.player_id WHERE s.board=?" + gw.replace("game", "s.game") + " ORDER BY s.score DESC LIMIT 100", (board,) + ga)
                return self.send_json({"scores": [dict(r) for r in rows]})
            if path == "score/hide" and method == "POST":
                b = self.json_body()
                c.execute("UPDATE scores SET hidden=? WHERE game=? AND board=? AND player_id=?", (1 if b.get("hidden") else 0, str(b.get("game", "")), str(b.get("board", "xp")), str(b.get("player_id", ""))))
                return self.send_json({"ok": True})
            if path == "audit":
                rows = c.execute("SELECT * FROM audit ORDER BY id DESC LIMIT 150")
                return self.send_json({"audit": [dict(r) for r in rows]})
            if path == "keys":
                return self.send_json({"keys": [dict(r) for r in c.execute("SELECT id,name,role,created_at FROM admin_keys ORDER BY id")]})
            if path == "key/create" and method == "POST":
                b = self.json_body()
                role = str(b.get("role", "viewer"))
                if role not in ("editor", "viewer"):
                    role = "viewer"
                k = secrets.token_urlsafe(18)
                c.execute("INSERT INTO admin_keys(name,role,key_hash,created_at) VALUES(?,?,?,?)", (str(b.get("name", "مساعد"))[:30], role, hash_key(k), now()))
                return self.send_json({"ok": True, "key": k, "role": role})
            if path == "key/delete" and method == "POST":
                c.execute("DELETE FROM admin_keys WHERE id=?", (int(self.json_body().get("id", 0)),))
                return self.send_json({"ok": True})
            if path == "export":
                what = q.get("what", "players")
                buf = io.StringIO()
                w = csv.writer(buf)
                if what == "payments":
                    cols = ["id", "player_id", "game", "pack_id", "kind", "amount", "price_usd", "provider", "status", "created_at", "paid_at"]
                    rows = c.execute("SELECT " + ",".join(cols) + " FROM orders WHERE 1=1" + gw + " ORDER BY created_at DESC LIMIT 5000", ga)
                elif what == "codes":
                    cols = ["code", "game", "coins", "gems", "max_uses", "expires_at", "note", "active", "created_at"]
                    rows = c.execute("SELECT " + ",".join(cols) + " FROM codes WHERE 1=1" + gw + " ORDER BY created_at DESC LIMIT 5000", ga)
                else:
                    cols = ["id", "name", "game", "platform", "version", "first_seen", "last_seen", "banned"]
                    rows = c.execute("SELECT " + ",".join(cols) + " FROM players WHERE 1=1" + gw + " ORDER BY last_seen DESC LIMIT 20000", ga)
                w.writerow(cols)
                for r in rows:
                    w.writerow([r[k] for k in cols])
                return self.send_json({"ok": True, "csv": buf.getvalue(), "what": what})
            if path == "player/ban" and method == "POST":
                b = self.json_body()
                c.execute("UPDATE players SET banned=?, ban_reason=? WHERE id=?", (1 if b.get("banned") else 0, str(b.get("reason", ""))[:80], str(b.get("player_id", ""))))
                return self.send_json({"ok": True})
            if path == "player/grant" and method == "POST":
                b = self.json_body()
                coins = max(0, min(int(b.get("coins", 0) or 0), 100000000))
                gems = max(0, min(int(b.get("gems", 0) or 0), 1000000))
                pid = str(b.get("player_id", ""))
                if not pid or (coins == 0 and gems == 0) or not c.execute("SELECT 1 FROM players WHERE id=?", (pid,)).fetchone():
                    return self.send_json({"ok": False, "error": "invalid"})
                c.execute("INSERT INTO grants(player_id,coins,gems,note,created_at) VALUES(?,?,?,?,?)", (pid, coins, gems, str(b.get("note", ""))[:80], now()))
                return self.send_json({"ok": True})
            if path == "grants":
                rows = c.execute("SELECT g.*, COALESCE(p.name,'') name FROM grants g LEFT JOIN players p ON p.id=g.player_id ORDER BY g.id DESC LIMIT 50")
                return self.send_json({"grants": [dict(r) for r in rows]})
            if path == "announcements":
                if method == "GET":
                    return self.send_json({"announcements": [dict(r) for r in c.execute("SELECT * FROM announcements WHERE 1=1" + gw + " ORDER BY id DESC LIMIT 50", ga)]})
                b = self.json_body()
                days = float(b.get("days", 0) or 0)
                c.execute("INSERT INTO announcements(game,text,text_ar,ends_at,active,created_at) VALUES(?,?,?,?,1,?)",
                          (str(b.get("game", ""))[:40], str(b.get("text", ""))[:300], str(b.get("text_ar", ""))[:300], now() + int(days * 86400) if days > 0 else 0, now()))
                return self.send_json({"ok": True})
            if path == "announce/toggle" and method == "POST":
                b = self.json_body()
                c.execute("UPDATE announcements SET active=? WHERE id=?", (1 if b.get("active") else 0, int(b.get("id", 0))))
                return self.send_json({"ok": True})
            if path == "announce/delete" and method == "POST":
                c.execute("DELETE FROM announcements WHERE id=?", (int(self.json_body().get("id", 0)),))
                return self.send_json({"ok": True})
            if path == "codes":
                if method == "GET":
                    rows = []
                    for r in c.execute("SELECT * FROM codes WHERE 1=1" + gw + " ORDER BY created_at DESC LIMIT 300", ga):
                        d = dict(r)
                        d["used"] = c.execute("SELECT COUNT(*) n FROM redemptions WHERE code=?", (r["code"],)).fetchone()["n"]
                        rows.append(d)
                    return self.send_json({"codes": rows})
                b = self.json_body()
                count = max(1, min(int(b.get("count", 1)), 200))
                made = []
                for _ in range(count):
                    code = norm_code(b.get("code", "")) if (b.get("code") and count == 1) else new_code()
                    code = code if "-" in code or not (len(code) == 12) else "-".join(code[i:i + 4] for i in range(0, 12, 4))
                    exp = now() + int(float(b.get("expires_days", 0)) * 86400) if float(b.get("expires_days", 0) or 0) > 0 else 0
                    try:
                        c.execute("INSERT INTO codes VALUES(?,?,?,?,?,?,?,?,?)", (code, str(b.get("game", ""))[:40], int(b.get("coins", 0)), int(b.get("gems", 0)), int(b.get("max_uses", 1)), exp, str(b.get("note", ""))[:80], 1, now()))
                        made.append(code)
                    except sqlite3.IntegrityError:
                        return self.send_json({"ok": False, "error": "exists", "made": made})
                return self.send_json({"ok": True, "codes": made})
            if path == "code/toggle" and method == "POST":
                b = self.json_body()
                c.execute("UPDATE codes SET active=? WHERE code=?", (1 if b.get("active") else 0, str(b.get("code", ""))))
                return self.send_json({"ok": True})
            if path == "code/delete" and method == "POST":
                c.execute("DELETE FROM codes WHERE code=?", (str(self.json_body().get("code", "")),))
                return self.send_json({"ok": True})
            if path == "events":
                if method == "GET":
                    return self.send_json({"events": [dict(r) for r in c.execute("SELECT e.*, (SELECT COUNT(*) FROM event_claims k WHERE k.event_id=e.id) claims FROM events e WHERE 1=1" + gw.replace("game", "e.game") + " ORDER BY ends_at DESC LIMIT 100", ga)]})
                b = self.json_body()
                days = float(b.get("days", 7))
                c.execute("INSERT INTO events(game,title,title_ar,body,body_ar,starts_at,ends_at,reward_coins,reward_gems,active,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                          (str(b.get("game", ""))[:40], str(b.get("title", ""))[:80], str(b.get("title_ar", ""))[:80], str(b.get("body", ""))[:300], str(b.get("body_ar", ""))[:300],
                           now(), now() + int(days * 86400), int(b.get("reward_coins", 0)), int(b.get("reward_gems", 0)), 1, now()))
                return self.send_json({"ok": True})
            if path == "event/toggle" and method == "POST":
                b = self.json_body()
                c.execute("UPDATE events SET active=? WHERE id=?", (1 if b.get("active") else 0, int(b.get("id", 0))))
                return self.send_json({"ok": True})
            if path == "event/delete" and method == "POST":
                c.execute("DELETE FROM events WHERE id=?", (int(self.json_body().get("id", 0)),))
                return self.send_json({"ok": True})
            if path == "reports":
                kind = q.get("kind", "")
                extra = " AND kind=?" if kind else ""
                ea = (kind,) if kind else ()
                rows = c.execute("SELECT * FROM reports WHERE 1=1" + gw + extra + " ORDER BY ts DESC LIMIT ?", ga + ea + (int(q.get("limit", 100)),))
                groups = c.execute("SELECT message, COUNT(*) n, MAX(ts) last, COUNT(DISTINCT player_id) players, game FROM reports WHERE 1=1" + gw + " GROUP BY message, game ORDER BY n DESC LIMIT 30", ga)
                return self.send_json({"reports": [dict(r) for r in rows], "top": [dict(r) for r in groups]})
            if path == "reports/clear" and method == "POST":
                c.execute("DELETE FROM reports WHERE ts<?", (now() - 86400 * int(self.json_body().get("older_days", 0)),))
                return self.send_json({"ok": True})
        return self.send_json({"error": "not_found"}, 404)


def main():
    init_db()
    srv = ThreadingHTTPServer(("0.0.0.0", int(CFG["port"])), H)
    print("Sabak backend on port %s  provider=%s" % (CFG["port"], CFG["provider"]))
    print("Admin key: %s" % CFG["admin_key"])
    if CFG["provider"] == "stripe" and not (CFG["stripe_secret"] and CFG["stripe_webhook_secret"]):
        print("WARNING: provider=stripe but stripe_secret / stripe_webhook_secret are not set")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
