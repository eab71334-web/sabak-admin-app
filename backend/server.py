#!/usr/bin/env python3
# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
"""Sabak Studios backend: redeem codes, events, card payments, error reports, admin API.

Pure standard library (no pip packages): python3 server.py
Data lives in one SQLite file. Put it behind HTTPS (reverse proxy) before real use.
"""
import hashlib
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
        CREATE INDEX IF NOT EXISTS ix_reports_ts ON reports(ts);
        CREATE INDEX IF NOT EXISTS ix_orders_player ON orders(player_id);
        """)


def now():
    return int(time.time())


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


def pack_of(pack_id):
    for p in CFG["packs"]:
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
        c.execute("INSERT INTO players VALUES(?,?,?,?,?,?,?)", (pid, name, game, platform, version, now(), now()))


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
        n = int(self.headers.get("Content-Length") or 0)
        if n > 200_000:
            raise ValueError("body too large")
        return self.rfile.read(n) if n else b""

    def json_body(self):
        b = self.raw_body()
        return json.loads(b.decode() or "{}") if b else {}

    def is_admin(self):
        key = self.headers.get("X-Admin-Key", "")
        return hmac.compare_digest(key.encode(), CFG["admin_key"].encode())

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
                if not self.is_admin():
                    if not rate_ok("badadmin:" + self.ip(), 10):
                        return self.send_json({"error": "rate"}, 429)
                    return self.send_json({"error": "unauthorized"}, 401)
                return self.admin(method, path[len("/admin/api/"):], q)
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
            return self.send_json({"ok": True, "time": now(), "payments": CFG["provider"] in ("stripe", "test"), "provider": CFG["provider"], "packs": CFG["packs"], "events": evs})
        if path == "/api/player/hello" and method == "POST":
            b = self.json_body()
            with DB_LOCK, db() as c:
                touch_player(c, str(b.get("player_id", ""))[:64], str(b.get("name", ""))[:40], str(b.get("game", ""))[:40], str(b.get("platform", ""))[:30], str(b.get("version", ""))[:20])
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
        pack = pack_of(str(b.get("pack_id", "")))
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
                return self.send_json({"ok": True})
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
                return self.send_json(out)
            if path == "payments":
                rows = c.execute("SELECT o.*, COALESCE(p.name,'') name FROM orders o LEFT JOIN players p ON p.id=o.player_id WHERE 1=1" + gw.replace("game", "o.game") + " ORDER BY o.created_at DESC LIMIT ?", ga + (int(q.get("limit", 100)),))
                return self.send_json({"payments": [dict(r) for r in rows]})
            if path == "spenders":
                rows = c.execute("SELECT o.player_id, COALESCE(p.name,'') name, SUM(o.price_usd) total, COUNT(*) n, MAX(o.paid_at) last FROM orders o LEFT JOIN players p ON p.id=o.player_id WHERE o.status IN ('paid','granted') AND o.provider!='test'" + gw.replace("game", "o.game") + " GROUP BY o.player_id ORDER BY total DESC LIMIT 100", ga)
                return self.send_json({"spenders": [dict(r) for r in rows]})
            if path == "players":
                rows = c.execute("SELECT * FROM players WHERE 1=1" + gw + " ORDER BY last_seen DESC LIMIT 200", ga)
                return self.send_json({"players": [dict(r) for r in rows]})
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
