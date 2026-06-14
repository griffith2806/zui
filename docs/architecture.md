# zui Architecture

## Layered Design

```
┌──────────────────────────────────────────┐
│              Application Code            │
├──────────────────────────────────────────┤
│    Widgets  │  Layout  │  Style          │
├─────────────┴──────────┴─────────────────┤
│         Events  │  Signals               │
├─────────────────┴────────────────────────┤
│   Core (event loop, allocator, timers)   │
├──────────────────────────────────────────┤
│  Platform backend  │  Graphics backend   │
└──────────────────────────────────────────┘
```

Lower layers must not import upper layers. Dependency direction is strictly downward.

## Key Invariants

### No hidden allocations
Every public function that allocates accepts `std.mem.Allocator` as its first argument. The framework never calls any global allocator. This lets embedders control memory strategy completely.

### Comptime backends
The graphics renderer and platform backend are comptime parameters, not runtime vtables. This means:
- Dead code for unused backends is eliminated.
- No function pointer overhead on the hot rendering path.
- Type errors in backend usage are caught at compile time.

Example:
```zig
const App = zui.Application(.{
    .platform = zui.platform.Win32,
    .renderer = zui.graphics.OpenGL,
});
```

### Signal/slot type safety
Signals carry a comptime payload type. Connecting a slot with the wrong signature is a compile error, not a runtime panic.

```zig
var btn = Button.init(alloc);
btn.clicked.connect(&my_handler); // clicked: Signal(void)
```

### Widget ownership
Widgets are owned by their parent container. The root widget is owned by the `Application`. Destroying a container destroys all children. No shared ownership.

## Subsystem Boundaries

| Subsystem  | May import              | Must not import         |
|------------|-------------------------|-------------------------|
| core       | std only                | everything else         |
| events     | core                    | widgets, layout, style  |
| signals    | core                    | events, widgets         |
| style      | core                    | events, signals, widgets|
| layout     | core, style             | events, signals, widgets|
| graphics   | core, style, layout     | events, signals, widgets|
| platform   | core, events            | widgets, layout, style  |
| widgets    | all of the above        | —                       |
