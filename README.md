# Desktop Controls

An [Omarchy](https://omarchy.org/) shell plugin: a bar button that opens a panel
for tuning Hyprland window appearance **live** — window opacity, corner
rounding, gaps, border width, blur, shadows and animations — without touching a
config file.

![Desktop Controls panel](preview.png)

## Controls

| Section | Control | Hyprland option |
|---|---|---|
| Window opacity | Focused windows (%) | `decoration:active_opacity` |
| Window opacity | Unfocused windows (%) | `decoration:inactive_opacity` |
| Shape & spacing | Corner rounding (px) | `decoration:rounding` |
| Shape & spacing | Inner gaps (px) | `general:gaps_in` |
| Shape & spacing | Outer gaps (px) | `general:gaps_out` |
| Shape & spacing | Border width (px) | `general:border_size` |
| Effects | Background blur | `decoration:blur:enabled` |
| Effects | Window shadows | `decoration:shadow:enabled` |
| Effects | Animations | `animations:enabled` |

Plus **Reset to default**, which restores the values captured the first time the
plugin ran.

## Install

```bash
omarchy plugin add https://github.com/paulsamoluk/Desktop_Controls.git
omarchy plugin enable psamoluk.desktop-controls
omarchy bar move psamoluk.desktop-controls --section right
```

Or by hand: clone into `~/.config/omarchy/plugins/psamoluk.desktop-controls`,
then `omarchy-shell shell rescanPlugins` and `omarchy plugin enable
psamoluk.desktop-controls`.

The plugin lands disabled so you can read the code before enabling it — it runs
unsandboxed inside `omarchy-shell`, as every shell plugin does.

## How it works

**Reads** use `hyprctl -j getoption <key>` (JSON), so the sliders always show
what the compositor is actually doing rather than what the plugin last sent.

**Writes** use `hyprctl eval 'hl.config({ ... })'`. They cannot use
`hyprctl keyword`: on a Lua-configured Hyprland it is refused outright —

```
$ hyprctl keyword decoration:rounding 12
keyword can't work with non-legacy parsers. Use eval.
```

Only the option being changed is included in each `hl.config()` call, so one
slider never disturbs the rest of the desktop.

**Persistence.** Values are written into this widget's own entry in
`~/.config/omarchy/shell.json` (the documented place for per-instance plugin
settings), alongside a `base*` snapshot of the desktop as it was before the
plugin first changed anything — that snapshot is what *Reset to default* restores.

**Drift.** Hyprland forgets runtime `hl.config()` changes whenever it reloads its
config (theme switch, editing a `.lua` file, `omarchy restart hyprctl`). The bar
widget re-states the saved values when the shell starts and checks the
compositor every few seconds, so tuning sticks instead of silently reverting.

## Requirements

Omarchy 4 (the Lua-config Hyprland, where `hyprctl eval` is the runtime config
path) on x86_64 or aarch64. Nothing else — the plugin calls `hyprctl` and `sh`
from the shell, no external packages.

## Remove

```bash
omarchy plugin remove psamoluk.desktop-controls
```

Removing the bar entry removes the saved values with it, since they live inline
on that entry.

## License

MIT — see [LICENSE](LICENSE).
