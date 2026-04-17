[Back to Guide Contents](README.md)

# Settings And Controls

The mod keeps its control surface intentionally small. Most interaction happens through the main market window and contextual side panels.

## Main Entry Points

You can open the main market window through:

- The `Trade Market` shortcut in the shortcut bar.
- The `Toggle Trade Market` control, which can be bound as a hotkey in Factorio controls.

## Contextual Panels

Some UI appears only when it is relevant:

- Opening a `Trade Box` shows the `Trade order` side panel.
- Selecting an inserter shows the `Trade stats` side panel.

This keeps most of the mod's UI close to the entity you are working with.

## Runtime Setting

The mod currently exposes one gameplay-facing setting:

- `Show Trade Box Chart Tags`

What it does:

- When enabled, active trade boxes appear on the map as chart tags.
- When disabled, those tags are removed.

## Important Setting Scope

`Show Trade Box Chart Tags` is a `runtime-global` setting.

That means:

- It affects the whole force.
- It is not a personal preference per player.
- Admin docs call this out explicitly because it matches how Factorio chart tags work.

## UI Behavior Worth Knowing

- The main market window remembers the selected main tab per player.
- The market filter updates the listing live as you type.
- Contract drafting fields persist while the window stays open.
- Trade-box and contract feedback is shown inline in the relevant panel.

[Back to Guide Contents](README.md)
