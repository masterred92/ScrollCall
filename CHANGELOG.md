# Changelog

## 1.0.0 (Nov 20, 2026)

First release, part of the Frost Suite.

- Unread untranslated scroll count; shown only while you carry some (or `/frost scroll`), never in combat.
- Logs each Comprehension read from a bag check after the cast (or from bags alone when casts are hidden, marked "(from bags)"),
  priced from PriceLog "before AH cut", or "soulbound" / "no price scan".
- Mixed bag changes (other loot in the same window) are flagged "uncertain" and kept out of the gold total; the pre-read
  bags are kept when the bag update arrives before the cast event.
- Session total ("before AH cut"), last 50 reads (`/frost scroll log`), `reset`, `debug`, tooltip line on unread scrolls.
