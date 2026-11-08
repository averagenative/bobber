# Bobber

Bobber is a fishing helper for World of Warcraft: Forever. Double right-click the water to cast, right-click anywhere to hook and loot, and hear every splash. Swap between your pole and weapons in one click, and see what you've caught in a window that moves where you want it.

## Features

- **Double right-click to cast.** This works only while a fishing pole is equipped, so double right-clicks do nothing unusual when you aren't fishing. The window shows whether it's ready.
- **Right-click anywhere to loot.** While the line is out, a right-click anywhere hooks the bobber, and the catch goes straight into your bags. You can switch to a double right-click, or turn it off and click the bobber yourself.
- **Lures on cast.** When your pole has no lure, your next cast press puts on the best lure you have instead, and the press after that casts. If you have no lure you can use, Bobber just casts.
- **Enhanced fishing sounds.** While a pole is equipped, sound effects play at full volume, and music and ambient sound are off. Your own settings come back when the pole comes off, and also after a reload, a disconnect, or a logout.
- **Sound in the background.** Game sound keeps playing when WoW isn't the active window, so you hear the splash from another app.
- **Pole and weapon swapping.** The window has slots for your pole, main hand, and off hand. Click the pole to fish and click a weapon to fight. Bobber remembers what you use, or you can drag items onto the slots. The weapon slots work in combat, and your weapons go back on as soon as combat starts.
- **A catch window.** Session, zone, and all-time tabs list each fish with its count and share. The window also shows casts, catches, fish that got away, hooks that came too early, catches per hour, fishing time, your fishing skill with its bonus, and the time left on your lure.
- **A window you control.** Drag it from anywhere, lock it, collapse it, scale it with Ctrl and the mouse wheel, or fade its background with Shift and the mouse wheel. The gear button in its header opens the options. It opens when you equip a pole and closes when you take it off. Pick one of four themes: Harbor, Midnight, Ember, or Parchment (light).

## Use Bobber

1. Equip your fishing pole. Click the pole slot in the Bobber window, or use the **Equip fishing pole** key binding.
2. Double right-click the water to cast. If your pole has no lure and you have one in your bags, this first press puts the lure on (it takes 5 seconds), and the next double right-click casts.
3. When the bobber splashes, right-click anywhere. Bobber loots the catch for you.
4. To fight, click a weapon slot. If combat starts while you're fishing, Bobber puts your weapons back on.

While the line is out, holding the right mouse button to turn the camera also hooks the bobber, because the press itself is the hook. Turn the camera with the left mouse button while you fish, or switch **Right-click to loot** to a double right-click.

### Lures

Bobber knows every lure in WoW: Forever's game data. It puts on the one with the biggest bonus that your fishing skill can use. At an equal bonus, the Wide-Brimmed Fishing Hat goes first because it isn't used up, then the easier-to-get lure.

| Lure | Bonus | Lasts | Needs Fishing |
|---|---|---|---|
| Aquadynamic Fish Attractor | +100 | 5 min | 100 |
| Bright Baubles | +75 | 10 min | 100 |
| Flesh Eating Worm | +75 | 10 min | 100 |
| Nightcrawlers | +50 | 10 min | 50 |
| Aquadynamic Fish Lens | +50 | 10 min | 50 |
| Wide-Brimmed Fishing Hat (worn, 10-minute cooldown) | +25 | 10 min | 1 |
| Shiny Bauble | +25 | 10 min | none |
| "Secret" Bait | +25 | 10 min | none |

### Gear slots

The three slots are, in order: fishing pole, main hand, and off hand.

- Click the pole slot to equip your pole.
- Click either weapon slot to put both weapons back.
- Drag an item onto a slot to choose it. You can also pick an item up and click the slot.
- Right-click a slot to forget your choice and go back to the item Bobber remembered.

If you haven't chosen items, Bobber remembers the last pole you equipped (or finds one in your bags) and the weapons you held before you switched to the pole. A dimmed slot means the item isn't in your bags or equipped.

## Options

Open the options with the gear button in the Bobber window's header, from **Options > AddOns > Bobber**, with `/bobber options`, or by right-clicking Bobber in the addons button by the minimap.

| Option | Default | What it does |
|---|---|---|
| Double right-click to cast | On | Double right-click the water to cast, while a pole is equipped. |
| Double-click speed | 0.40 s | The longest time between the two clicks. |
| Right-click to loot | Single right-click anywhere | How right-click hooks the bobber: single, double, or off. |
| Cast key also hooks | On | The Cast Fishing key hooks while the line is out. |
| Cast key equips your pole | On | The Cast Fishing key equips your pole when it's off. |
| Put on a lure when you cast | On | With no lure on the pole, a cast press puts on the best lure in your bags. No lure in your bags: it just casts. |
| Always reach the bobber | On | Widens soft targeting while the line is out. |
| Show an icon over the bobber | Off | Shows the game's interact icon over the bobber. |
| Auto-loot fish | On | Takes everything from fishing loot windows only. |
| Enhance fishing sounds | On | Louder splash while a pole is equipped. |
| Sound in the background | On | Game sound keeps playing when WoW isn't the active window. |
| Weapons back when combat starts | On | Puts your weapons on when combat starts. |
| Open the window when you equip a pole | On | |
| Close the window when you take the pole off | On | |
| Lock the window | Off | A locked window can't be dragged. |
| Theme | Harbor | The window colors. |
| Window opacity | 90% | How solid the window's background is. Text and icons stay fully visible. Shift and the mouse wheel over the window change it too. |

## Key bindings

Set these in **Options > Keybindings > AddOns > Bobber**:

- **Cast Fishing (hooks while the line is out)**: one key that casts, hooks, and equips your pole if it's off.
- **Equip fishing pole**
- **Equip weapons**: works in combat.
- **Show or hide the Bobber window**

## Slash commands

| Command | What it does |
|---|---|
| `/bobber` | Show or hide the window. |
| `/bobber options` | Open the options. |
| `/bobber lock`, `/bobber unlock` | Lock or unlock the window. |
| `/bobber reset` | Move the window back to the middle of the screen. |
| `/bobber newsession` | Start a new fishing session. |
| `/bobber debug` | Toggle debug messages. |

## What Bobber doesn't do

The game lets addons cast spells, use items, and interact with objects only in direct response to your own click or key press. Blizzard's rules forbid automating play. Bobber follows both:

- Every cast and every hook is your own click or key press. Bobber changes what one click does, and never clicks for you.
- Bobber doesn't detect bites, cast by itself, or hook by itself.
- During combat, the game locks key bindings and secure buttons. Bobber puts your mouse buttons and keys back to normal before combat starts, and restores its hooks when combat ends.

## Install

Install Bobber from CurseForge, or copy the `Bobber` folder into `World of Warcraft/_forever_/Interface/AddOns/`. A new install needs a full game restart; updates need only `/reload`.

## Develop

Bobber is plain Lua with no libraries. Each file starts with a comment that explains what it does:

| File | What it holds |
|---|---|
| `Core.lua` | The shared addon table, the event bus, saved variables and defaults, helpers, and the slash command. |
| `CVarLease.lua` | Temporary game setting changes that are always undone. |
| `Themes.lua` | The window color themes. |
| `Casting.lua` | Double-click casting, right-click hooking, and the cast key. |
| `Sounds.lua` | Enhanced fishing sounds. |
| `Gear.lua` | The pole and weapon slots and the combat weapon swap. |
| `Lures.lua` | Choosing a lure and putting it on with a cast press. |
| `Catches.lua` | Catch counting, fishing auto-loot, and fishing skill. |
| `Window.lua` | The Bobber window. |
| `Options.lua` | The options panel. |

The checks run under Neovim's built-in LuaJIT (`nvim -l`), which speaks Lua 5.1 like the game:

```
make check
make install
make package
make hooks
```

- `make check` runs the static checks (`tools/check.lua`) and a smoke test (`tools/smoke.lua`). The smoke test loads Bobber in a fake game environment, plays a fishing session, and checks the results.
- `make install` copies the addon into the Forever `AddOns` folder. Set `WOW_ADDONS` to install somewhere else.
- `make package` builds `dist/Bobber-<version>.zip` for CurseForge.
- `make hooks` runs `make check` before every `git push`.

To release a version, update `## Version:` in `Bobber.toc`, add a matching `## <version>` entry to `CHANGELOG.md`, run `make package`, and upload the zip.

## Credits

Bobber's feature set is inspired by Fishing Buddy by Sutorix. The OneCast and EzFishing addons (both MIT-licensed) documented how casting and soft-target hooking behave on WoW: Forever, and OneCast first documented the classic lures for Forever. The full lure list in `Lures.lua` is read from Forever's game data through wago.tools. Bobber's code is its own.

## License

MIT. See [LICENSE](LICENSE).
