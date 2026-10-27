# Sabak Admin (mobile app)

A separate Godot 4.3 project for managing your games from your phone. Portrait, Arabic.
Talks to `../backend` (see backend/README.md).

## Pages
- Home: real revenue, orders, players, active players, codes, events, errors (test payments are counted apart and never added to revenue)
- Codes: create one custom or up to 200 generated codes (coins, gems, uses, expiry, game), copy, disable, delete, see usage
- Events: announcements with an optional one-time reward every player can claim; pause or delete
- Payments: every order with player, pack, amount, status; top spenders
- Errors: most frequent problems first, latest reports with platform and version; clear old
- A game filter at the top (all games or one game). Every game you build sends its own `game` name to the backend.

## Build
Push to GitHub: `.github/workflows/admin-android.yml` makes an APK, `admin-ios.yml` an unsigned IPA (same method as the game).
First launch: enter the server address (https://...) and the admin key printed by the backend.
The key stays on the phone only. Use HTTPS. Anyone with the key has full control, keep it private.

## Using it in your other games
Copy `scripts/backend.gd` and `scripts/backend_ui.gd` from the game, set `GAME` to your game's name and the server address.
Each game then appears in the filter automatically after its first player opens it.
