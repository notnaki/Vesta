# Task A Report — Workspace project/session model, remove top tabs

## Files Changed

### `Sources/Halo/Tabs.swift` — full rewrite

- Deleted `TabBar`, `ChipView`, and all their wiring.
- Deleted `tabsSelfCheck()`.
- Added top-level structs `SidebarSession` and `SidebarProject` (consumed by Task B).
- Added `Proj` struct: `{ name, path, sessions, expanded }`.
- Rewrote `Workspace`:
  - Properties: `projs: [Proj]`, `activeP: Int`, `activeS: Int`, `activeTree: PaneTree`, `container: NSView`, `body: NSView`, `theme: Theme`.
  - Five callbacks: `onSelectSession`, `onCloseSession`, `onNewSession`, `onToggleExpand`, `onNewProject` (all optional closures), plus existing `onChange`.
  - Operations: `toggleExpand(_:)`, `newSession(_:)`, `newProject()`, `selectSession(_:_:)`, `closeSession(_:_:)`, `snapshot() -> [SidebarProject]`.
  - Session cycling: `nextSession()`, `prevSession()`, `selectSessionInActiveProject(_:)`.
  - Project appending: `appendProject(name:path:)`.
  - Backward-compat shims for `Control.swift`: `active: Int`, `tabs: [PaneTree]`, `newTab(cwd:)`, `closeTab()`, `closeTab(at:)`, `selectTab(_:)`, `nextTab()`, `prevTab()`.
  - `container` hosts `body` only (full-size, no tab strip). `showActive()` swaps the active session's `rootView` into `body`.
  - Launch: home project `Proj(name:"~", path:NSHomeDirectory(), sessions:[session@~], expanded:true)` created in `init`. Config projects appended via `appendProject` (collapsed + empty, lazy).
- Added `workspaceSelfCheck()`: pure data-model check (no ghostty/NSApp needed), testable from `swift run halo selfcheck`.

### `Sources/Halo/main.swift` — targeted edits

- Updated selfcheck branch: added `workspaceSelfCheck()` call before `print("all self-checks ok")`.
- `applicationDidFinishLaunching`: `workspace = Workspace(theme:)` (no `cwd:` arg); `loadProjects(_:into:)` appends config projects. Chrome `HaloWindowController` init still receives `projects:` and `onSelectProject:` (compat, unchanged Chrome.swift).
- Wired five callbacks (`onSelectSession`, `onCloseSession`, `onNewSession`, `onToggleExpand`, `onNewProject`) to Workspace ops + `refresh()`.
- Rewired keybinds:
  - `⌘T` → `newSession(activeP)` (cwd = ~)
  - `⌘W` (no shift) → `activeTree.closeFocused()` (pane within session)
  - `⌘⇧W` → `closeSession(activeP, activeS)` (close whole session)
  - `⌘}` / `⌘{` → `nextSession()` / `prevSession()` (cycle sessions in active project)
  - `⌘1–9` → `selectSessionInActiveProject(n)` (select by 1-based index)
  - `⌘D/⌘⇧D/⌘B/⌘]` unchanged.
- Added `loadProjects(_:into:)` (`@MainActor`) appending config projects to workspace. Kept legacy `loadProjects(_:) -> [Project]` (used nowhere after this change, but harmless).
- `abbreviateHome` unchanged.

## Final `Workspace` Public API Surface

```swift
// Top-level structs
struct SidebarSession { let label: String; let active: Bool }
struct SidebarProject { let name: String; var branch: String?; let expanded: Bool; let active: Bool; let sessions: [SidebarSession] }
struct Proj { var name: String; var path: String; var sessions: [PaneTree]; var expanded: Bool }

// Workspace (class, @MainActor)
final class Workspace {
    // State
    private(set) var projs: [Proj]
    private(set) var activeP: Int
    private(set) var activeS: Int
    var activeTree: PaneTree { get }
    let container: NSView

    // Callbacks
    var onSelectSession:  ((Int, Int) -> Void)?
    var onCloseSession:   ((Int, Int) -> Void)?
    var onNewSession:     ((Int) -> Void)?
    var onToggleExpand:   ((Int) -> Void)?
    var onNewProject:     (() -> Void)?
    var onChange:         (() -> Void)?

    // Init
    init(theme: Theme, cwd: String? = nil)

    // Core ops
    func toggleExpand(_ p: Int)
    func newSession(_ p: Int)
    func newProject()
    func selectSession(_ p: Int, _ s: Int)
    func closeSession(_ p: Int, _ s: Int)
    func snapshot() -> [SidebarProject]
    func appendProject(name: String, path: String)

    // Session cycling (keybind targets)
    func nextSession()
    func prevSession()
    func selectSessionInActiveProject(_ i: Int)   // 1-based

    // Control.swift compat shims (do not remove until Control.swift updated)
    var active: Int { get }
    var tabs: [PaneTree] { get }
    func newTab(cwd: String?)
    func closeTab()
    func closeTab(at i: Int)
    func selectTab(_ i: Int)
    func nextTab()
    func prevTab()
}
```

## Build Result

```
Build complete! (3.29s)
```

(Two linker warnings about missing ImGui symbols in libghostty-internal.a — pre-existing, not introduced by this task.)

## Selfcheck Output

```
controlSelfCheck ok
gitSelfCheck OK
workspaceSelfCheck OK
all self-checks ok
```

## Concerns

1. **`Control.swift` uses old API** (`workspace.tabs`, `workspace.active`, `workspace.newTab()`, `workspace.nextTab()`, `workspace.prevTab()`, `workspace.closeTab()`). Backward-compat shims keep it compiling without touching that file. These shims should be removed when Control.swift is updated (Task B or later).

2. **`workspaceSelfCheck` is data-model only** — it cannot create a real `Workspace` in selfcheck mode because `Workspace.init` creates `PaneTree` → `TerminalPane` → `GhosttyApp.shared` (needs a running NSApp). The selfcheck tests `Proj`, `SidebarSession`, `SidebarProject` struct logic and invariants at the data level. The full integration (sessions actually spawning, `closeSession` replace path, `toggleExpand` creating PaneTrees) is exercised at real app launch.

3. **Chrome.swift sidebar is not yet updated** — it still renders from the static `projects: [Project]` passed at init. Task B will wire `setProjects([SidebarProject])`. The five callbacks are wired in AppDelegate to drive Workspace + refresh(), per spec.

---

## Task A Fix Pass (review findings applied)

### FIX 1 — Launch crash (Critical)

`Workspace.init` was calling `showActive()` → `activeTree` → `projs[0].sessions[0]` on an empty sessions array — out-of-bounds trap at launch.

Fix: in `init`, build the home project as `var homeProj`, append a real session via `homeProj.sessions.append(makeTree(cwd: home))` before calling `projs.append(homeProj)` and `showActive()`. The home project now has exactly one session at `~` before `showActive()` runs.

### FIX 2 — CLI ignores cwd (Critical)

`newSession(_:)` hardcoded `makeTree(cwd: NSHomeDirectory())` and `newTab(cwd:)` routed through it, so `halo open /tmp` silently opened at `~`.

Fix: extracted private `addSession(_ p: Int, cwd: String?)` that appends a session at the given cwd, expands the project, and activates it. `newSession(_:)` now calls `addSession(p, cwd: NSHomeDirectory())` (unchanged default). `newTab(cwd:)` calls `addSession(targetP, cwd: cwd)` so the real cwd is honored.

### FIX 3 — Meaningless self-checks (Important)

The `closeSession`-never-zero check simulated a local counter variable and asserted on a dead decrement branch. The `toggleExpand` block created a `SidebarSession` stub and asserted `.active` on it (always true).

Fix: extracted `nonisolated static func replaceOnClose(totalSessions: Int) -> Bool` from `closeSession`'s decision branch; used it in `closeSession` (`if Workspace.replaceOnClose(totalSessions: total)`). Self-check now asserts the real function: `Workspace.replaceOnClose(totalSessions: 1) == true` and `Workspace.replaceOnClose(totalSessions: 2) == false`. The `toggleExpand` stub replaced with an honest `projs[emptyIdx].sessions.isEmpty == true` predicate check. No `Workspace`/`PaneTree` instantiation needed.

### FIX 4 — Minor cleanup

**(a)** Removed `cwd: String? = nil` parameter from `Workspace.init` (was already unused — call site in main.swift already used `Workspace(theme: theme)`).

**(b)** Added `projs.indices.contains(activeP)` bounds guard to `nextSession()`, `prevSession()`, and `selectSessionInActiveProject(_:)`.

**(c)** Removed the dead `loadProjects(_ settings: [String: String]) -> [Project]` overload from `main.swift`. It was never called after Task A (confirmed with grep).

### Build Result

```
Build complete! (3.07s)
```

(Two pre-existing linker warnings about missing ImGui symbols in libghostty-internal.a — not introduced by this task.)

### Selfcheck Output

```
controlSelfCheck ok
gitSelfCheck OK
workspaceSelfCheck OK
all self-checks ok
```
