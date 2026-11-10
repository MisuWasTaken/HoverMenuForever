# Development

This addon was developed with assistance from AI. Its functionality was tested in-game based on my own feedback based on my real game need.

# HoverMenu Forever

A lightweight mouseover addon made for **World of Warcraft Forever** (interface `16001`). It keeps your UI clean and reveals the elements you need when you move your mouse over them.

## Features

- **Game menu:** Hide the character, talents, quest log, map, and other menu buttons until mouseover.
- **Bag bar:** Show or hide the entire bag bar, including the main backpack, as one group.
- **Quest tracker:** Mouseover support for Questie and Blizzard's default objective tracker.
- **Minimap:** Mouseover support for the default minimap and **SexyMap**, including borders and decorations.
- **Separate timers:** Set a 0–15 second hide delay for each group.
- **Smooth fade:** Adjust fade duration between 0 and 1.5 seconds, or set it to 0 for instant transitions.

Each group can be enabled or disabled separately.

## Commands

- `/hmf` or `/hovermenu` — Open settings.
- `/hmf debug` — Display detected UI frames in the chat for troubleshooting.

## Compatibility

Designed and tested in-game with WoW Forever, **Questie**, and **SexyMap**. It also handles the corresponding default Blizzard UI elements. It does not modify your SexyMap theme, layout, size, or positioning.

This addon has **no required dependencies**; Questie and SexyMap support is optional.

## Version

**v0.5.2** — Reduced periodic frame checks and mouseover polling overhead while preserving the behavior of v0.5.1.

## Known limitations

Some UI addons may modify or replace Blizzard's default interface elements, which could cause compatibility issues with HoverMenu Forever.

If something isn't hiding correctly, use /hmf debug and include the chat output when reporting the issue.

## Support & Feedback

If you find a bug or have a suggestion, feel free to open a issue on Github.
You can also reach me on my discord: misuzu01