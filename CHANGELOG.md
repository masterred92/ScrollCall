# Changelog

## 1.0.1 (Nov 20, 2026)

- Layout fixes (FrostSuite-1.0 r4, shared by the suite): a status too long to sit beside the title moves to its own line instead of running into it, and box heights fit their text.
- The session total moves to its own line below the title.
- Low-level Mages (FrostSuite-1.0 r6, shared by the suite): until you have Comprehension the box shows one calm line, e.g. `Learn Comprehension to read scrolls`, with a small **Hide until I learn** button (saved per character). It steps aside in combat and comes back by itself as soon as you learn it (checked when you learn a spell, level up, change talents or leave combat). The READ prompt on scroll tooltips waits until Comprehension is learned.

## 1.0.0 (Nov 20, 2026)

First release, part of the Frost Suite.

- Unread untranslated scroll count; shown only while you carry some (or `/frost scroll`), never in combat.
- Logs each Comprehension read from a bag check after the cast (or from bags alone when casts are hidden, marked "(from bags)"),
  priced from PriceLog "before AH cut", or "soulbound" / "no price scan".
- Mixed bag changes (other loot in the same window) are flagged "uncertain" and kept out of the gold total; the pre-read
  bags are kept when the bag update arrives before the cast event.
- Session total ("before AH cut"), last 50 reads (`/frost scroll log`), `reset`, `debug`, tooltip line on unread scrolls.
