# Sabak backend

Redeem codes, events, card payments, error reports and the admin API for HAIRPIN RUSH and your other games.
Pure Python 3 (standard library only) + one SQLite file. Needs Python 3.8+.

## Run
    ./run.sh                      # first start creates config.json and prints the ADMIN KEY
    python3 test_backend.py       # 30 end-to-end checks (temp database)

Environment variables override config.json: PORT, ADMIN_KEY, PUBLIC_URL, PAY_PROVIDER, STRIPE_SECRET, STRIPE_WEBHOOK_SECRET, DB_PATH.

## Before real use
1. Put it behind HTTPS (Caddy / nginx / a host that gives you https). Passwords and admin key travel in headers.
2. Keep config.json private. Back up sabak.db.
3. Payments: `provider` is `test` by default (a fake pay page, no money). For real cards set `provider` to `stripe`,
   fill `stripe_secret` and `stripe_webhook_secret`, and add a Stripe webhook to `https://YOUR-DOMAIN/api/pay/webhook/stripe`
   for the events `checkout.session.completed`. IMPORTANT: check that your country is supported by the gateway you choose
   (Stripe does not onboard every country). Another gateway needs a small adapter in `server.py` (create checkout + webhook -> `mark_paid`).
4. App-store rules: Apple and Google require their own in-app purchase for digital goods inside store apps.
   A card page opened outside the app is fine for sideloaded / direct-download builds, not for store releases.

## How a purchase works (the server decides the price and the amount)
1. game -> `POST /api/pay/create {player_id, pack_id}` -> server makes an order and returns `checkout_url`
2. player pays on that page -> the gateway calls the webhook -> order becomes `paid`
3. game -> `POST /api/pay/claim` -> server marks it `granted` once and returns the amount -> game credits it

## Public API
GET /api/config, POST /api/player/hello, POST /api/redeem, GET /api/events, POST /api/event/claim,
POST /api/pay/create, GET /api/pay/status, POST /api/pay/claim, POST /api/report

## Admin API (header `X-Admin-Key`)
GET summary, payments, spenders, players, codes, events, reports; POST codes (create), code/toggle, code/delete,
events (create), event/toggle, event/delete, reports/clear. Add `?game=hairpin` to filter by game.

## Known limits
- Player progress lives on the phone. The server controls codes, events and purchases, but cannot stop someone editing their own save file.
- Rate limits are in memory (reset on restart). SQLite is fine for thousands of players, not millions.
