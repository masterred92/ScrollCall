# Scroll Call

A gold log for a Mage's **Comprehension** on **WoW: Forever** (Interface 16001). Version 1.0.0. Part of Kenny's Frost Suite,
and it works alone.

Untranslated scrolls ("A Mage can decipher this with their Comprehension skill.") pile up in your bags. Scroll Call:

- counts the **unread** ones (`3 unread scrolls`), and shows itself only while you carry some (or with `/frost scroll`), never in combat;
- logs what each read **turned into**, straight from your bags: `Spell Notes: ~2g 50s before AH cut`, `soulbound`, or
  `no price scan`. Prices are your own **PriceLog** scans through the shared Kenny hub; there's no guess;
- keeps a session total and the last 50 reads (`/frost scroll log`);
- adds `Scroll Call: unread: READ` to the tooltip of an untranslated scroll.

It never reads, casts, sells or moves anything for you.

## How a read is seen

| Mode | When | How |
| --- | --- | --- |
| `cast` | the game shows your own Comprehend Scroll casts to addons | your bags before the cast are compared with your bags after it. Whatever appeared, once a scroll has left, is the result. If a scroll left and nothing appeared within 5 seconds, it logs `nothing new in your bags`. |
| `bags` | cast events are hidden, or none seen yet | a read is logged when exactly one untranslated scroll leaves your bags and something new appears in the same bag update. These entries are marked `(from bags)`. |

`/frost scroll debug` shows the mode and the counts.

Item and spell IDs come from the game's tables for build 1.60.1.70862: 17 untranslated scrolls (ItemSparse) and the five
Comprehend Scroll spell IDs (SpellName).

## Commands

The Frost Suite has no per-addon slash commands, only `/frost <sub>`. That keeps the risk of clashing with other addons low.

- `/frost scroll`: show or hide the box (out of combat)
- `/frost scroll log`: the last 10 reads
- `/frost scroll reset`: clear the log and session
- `/frost scroll debug`: what the box can see
- `/frost lock | unlock | scale 0.8-1.4 | reset | debug`: the shared dock

## Checks

`tests/run.sh <wow-ui-source>`, `tools/verify_unit_events.py <wow-ui-source>`, `tools/check_suite_lib.sh`, `tools/verify_media.sh`.

MIT licence. Uses the game's own textures only.
