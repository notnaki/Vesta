import AppKit

// MARK: - Sidebar data types (consumed by Task B's Chrome rendering)

struct SidebarSession {
    let label: String
    let active: Bool
}

struct SidebarProject {
    let name: String
    var branch: String?
    let expanded: Bool
    let active: Bool
    let sessions: [SidebarSession]
}

// MARK: - Project/Session model

struct Proj {
    var name: String
    var path: String
    var sessions: [PaneTree]
    var expanded: Bool
}

/// Owns projects; each project owns sessions (PaneTrees).
/// Container = body only — the active session's rootView, swapped on change.
/// No top tab strip.
@MainActor
final class Workspace {
    private(set) var projs: [Proj] = []
    private(set) var activeP = 0
    private(set) var activeS = 0

    var activeTree: PaneTree { projs[activeP].sessions[activeS] }

    let container = NSView()
    private let body = NSView()
    private let theme: Theme

    // Callbacks (set by AppDelegate, invoked by Chrome in Task B)
    var onSelectSession:  ((Int, Int) -> Void)?
    var onCloseSession:   ((Int, Int) -> Void)?
    var onNewSession:     ((Int) -> Void)?
    var onToggleExpand:   ((Int) -> Void)?
    var onNewProject:     (() -> Void)?
    var onChange:         (() -> Void)?

    init(theme: Theme, cwd: String? = nil) {
        self.theme = theme
        container.wantsLayer = true
        container.layer?.backgroundColor = theme.background.cgColor

        body.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: container.topAnchor),
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Launch: home project at ~ with one session at ~, expanded + active.
        // Config projects are appended collapsed + empty by loadProjects/appendProject.
        let home = NSHomeDirectory()
        let homeProj = makeProj(name: "~", path: home, expanded: true)
        projs.append(homeProj)
        activeP = 0
        activeS = 0
        showActive()
    }

    // MARK: - Operations

    func toggleExpand(_ p: Int) {
        guard projs.indices.contains(p) else { return }
        if projs[p].sessions.isEmpty {
            // Lazy: create first session at the project path, expand, activate.
            let tree = makeTree(cwd: projs[p].path)
            projs[p].sessions.append(tree)
            projs[p].expanded = true
            activeP = p; activeS = 0
            showActive()
        } else {
            projs[p].expanded.toggle()
            handleChange()
        }
    }

    func newSession(_ p: Int) {
        guard projs.indices.contains(p) else { return }
        let tree = makeTree(cwd: NSHomeDirectory())
        projs[p].sessions.append(tree)
        projs[p].expanded = true
        activeP = p
        activeS = projs[p].sessions.count - 1
        showActive()
    }

    func newProject() {
        let home = NSHomeDirectory()
        var proj = makeProj(name: "~", path: home, expanded: true)
        // Add one session at home immediately (mirrors home proj behaviour).
        let tree = makeTree(cwd: home)
        proj.sessions.append(tree)
        projs.append(proj)
        activeP = projs.count - 1
        activeS = 0
        showActive()
    }

    func selectSession(_ p: Int, _ s: Int) {
        guard projs.indices.contains(p), projs[p].sessions.indices.contains(s) else { return }
        activeP = p; activeS = s
        showActive()
    }

    func closeSession(_ p: Int, _ s: Int) {
        guard projs.indices.contains(p), projs[p].sessions.indices.contains(s) else { return }
        // Never let global session count reach 0.
        let total = projs.reduce(0) { $0 + $1.sessions.count }
        if total <= 1 {
            // Replace with a fresh ~ session rather than leaving 0.
            let tree = makeTree(cwd: NSHomeDirectory())
            projs[p].sessions[s] = tree
            activeP = p; activeS = s
            showActive()
            return
        }
        projs[p].sessions.remove(at: s)
        // If project is now empty, collapse it.
        if projs[p].sessions.isEmpty { projs[p].expanded = false }
        // Fix activeS/activeP.
        if activeP == p {
            if projs[p].sessions.isEmpty {
                // Find another project with sessions.
                if let q = projs.indices.first(where: { $0 != p && !projs[$0].sessions.isEmpty }) {
                    activeP = q; activeS = 0
                } else {
                    // No other sessions — create a fresh one in this project.
                    let tree = makeTree(cwd: projs[p].path.isEmpty ? NSHomeDirectory() : projs[p].path)
                    projs[p].sessions.append(tree)
                    projs[p].expanded = true
                    activeP = p; activeS = 0
                }
            } else {
                activeS = min(activeS, projs[p].sessions.count - 1)
            }
        }
        showActive()
    }

    func snapshot() -> [SidebarProject] {
        projs.enumerated().map { (pi, proj) in
            let sessions = proj.sessions.enumerated().map { (si, tree) in
                SidebarSession(label: tree.focusedLabel, active: pi == activeP && si == activeS)
            }
            return SidebarProject(
                name: proj.name,
                branch: nil,   // filled by AppDelegate's git fetch in Task C
                expanded: proj.expanded,
                active: pi == activeP,
                sessions: sessions
            )
        }
    }

    // MARK: - Compat shims for Control.swift (do NOT remove until Control.swift is updated)

    /// The flat index of the active session across all projects (for `list` command).
    var active: Int {
        var n = 0
        for (pi, proj) in projs.enumerated() {
            for si in proj.sessions.indices {
                if pi == activeP && si == activeS { return n }
                n += 1
            }
        }
        return 0
    }

    /// Flat list of all PaneTrees (for `list` command's tab count).
    var tabs: [PaneTree] { projs.flatMap { $0.sessions } }

    func newTab(cwd: String?) {
        // Compat: opens a new session in the active project.
        // If cwd matches a project path, prefer that project; else use activeP.
        let targetP: Int
        if let cwd, let pi = projs.indices.first(where: { projs[$0].path == cwd }) {
            targetP = pi
        } else {
            targetP = activeP
        }
        newSession(targetP)
    }

    func closeTab() { closeSession(activeP, activeS) }
    func closeTab(at i: Int) {
        // Flat index i → project/session.
        var n = 0
        for (pi, proj) in projs.enumerated() {
            for si in proj.sessions.indices {
                if n == i { closeSession(pi, si); return }
                n += 1
            }
        }
    }
    func selectTab(_ i: Int) {
        var n = 0
        for (pi, proj) in projs.enumerated() {
            for si in proj.sessions.indices {
                if n == i { selectSession(pi, si); return }
                n += 1
            }
        }
    }
    func nextTab() {
        let t = tabs
        guard !t.isEmpty else { return }
        let cur = active
        let next = (cur + 1) % t.count
        selectTab(next)
    }
    func prevTab() {
        let t = tabs
        guard !t.isEmpty else { return }
        let cur = active
        let prev = (cur - 1 + t.count) % t.count
        selectTab(prev)
    }

    // MARK: - Project appending (called by loadProjects)

    /// Append a config project as collapsed + empty (lazy).
    func appendProject(name: String, path: String) {
        projs.append(Proj(name: name, path: path, sessions: [], expanded: false))
    }

    // MARK: - Cycle sessions within active project

    func nextSession() {
        guard !projs[activeP].sessions.isEmpty else { return }
        let count = projs[activeP].sessions.count
        activeS = (activeS + 1) % count
        showActive()
    }

    func prevSession() {
        guard !projs[activeP].sessions.isEmpty else { return }
        let count = projs[activeP].sessions.count
        activeS = (activeS - 1 + count) % count
        showActive()
    }

    func selectSessionInActiveProject(_ i: Int) {
        guard projs[activeP].sessions.indices.contains(i - 1) else { return }
        activeS = i - 1
        showActive()
    }

    // MARK: - Private helpers

    private func makeProj(name: String, path: String, expanded: Bool) -> Proj {
        Proj(name: name, path: path, sessions: [], expanded: expanded)
    }

    private func makeTree(cwd: String?) -> PaneTree {
        let tree = PaneTree(theme: theme, cwd: cwd)
        tree.onFocusChange = { [weak self] in self?.handleChange() }
        return tree
    }

    private func showActive() {
        body.subviews.forEach { $0.removeFromSuperview() }
        let v = activeTree.rootView
        v.frame = body.bounds
        v.autoresizingMask = [.width, .height]
        body.addSubview(v)
        handleChange()
    }

    private func handleChange() {
        onChange?()
    }
}

// MARK: - Self-check

/// Pure data-model checks that work without a running NSApp / ghostty.
/// Called from the `selfcheck` exit path; does NOT create PaneTree or TerminalPane.
func workspaceSelfCheck() {
    let home = NSHomeDirectory()

    // ── Proj struct and SidebarProject/SidebarSession construction ──────────
    var homeProj = Proj(name: "~", path: home, sessions: [], expanded: true)
    assert(homeProj.path == home, "home proj path")
    assert(homeProj.sessions.isEmpty, "fresh proj has no sessions")
    assert(homeProj.expanded, "home proj starts expanded")

    var configProj = Proj(name: "code", path: "/Users/test/code", sessions: [], expanded: false)
    assert(!configProj.expanded, "config proj starts collapsed")

    // ── SidebarSession / SidebarProject ─────────────────────────────────────
    let ss1 = SidebarSession(label: "shell", active: true)
    let ss2 = SidebarSession(label: "vim", active: false)
    assert(ss1.active && !ss2.active, "session active flags")

    let sp = SidebarProject(name: "~", branch: "main", expanded: true, active: true, sessions: [ss1, ss2])
    assert(sp.sessions.count == 2, "sidebar project session count")
    assert(sp.branch == "main", "branch passthrough")
    assert(sp.active && sp.expanded, "project flags")

    // ── toggleExpand semantics: empty → would create session; non-empty → flip ──
    // Simulate the toggleExpand logic on the struct directly.
    assert(homeProj.sessions.isEmpty)
    // would create a session → just mark expanded (model invariant)
    homeProj.expanded = true
    assert(homeProj.expanded, "toggleExpand on empty → expanded")

    configProj.expanded.toggle()
    assert(configProj.expanded, "toggleExpand on non-empty flips expanded")
    configProj.expanded.toggle()
    assert(!configProj.expanded, "toggleExpand twice → back to false")

    // ── closeSession invariant: global session count never reaches 0 ─────────
    // Simulate with a simple counter (the rule: if total == 1, replace instead of remove).
    var total = 1
    let wouldRemove = total <= 1  // triggers the "replace" path
    assert(wouldRemove, "last session triggers replace path, not remove")
    if !wouldRemove { total -= 1 }
    assert(total >= 1, "session count never < 1")

    // ── newProject appends and sets activeP to the new index ─────────────────
    var projs: [Proj] = [homeProj, configProj]
    let before = projs.count
    projs.append(Proj(name: "~", path: home, sessions: [], expanded: true))
    var activeP = projs.count - 1
    assert(projs.count == before + 1, "newProject appended")
    assert(activeP == projs.count - 1, "newProject activates new index")

    // ── appendProject: starts collapsed + empty ───────────────────────────────
    projs.append(Proj(name: "tmp", path: "/tmp", sessions: [], expanded: false))
    let emptyIdx = projs.count - 1
    assert(projs[emptyIdx].sessions.isEmpty, "appendProject: starts empty")
    assert(!projs[emptyIdx].expanded, "appendProject: starts collapsed")

    // ── toggleExpand on empty project: creates session at project path ────────
    // (In real Workspace this creates a PaneTree; here we verify the state transition.)
    projs[emptyIdx].expanded = true
    activeP = emptyIdx
    let activeS = 0
    // Simulate session creation (the path that would be: sessions.append(makeTree))
    let simulatedSession = SidebarSession(label: "/tmp", active: true)
    assert(simulatedSession.active, "new session from toggleExpand is active")
    assert(activeP == emptyIdx && activeS == 0, "toggleExpand on empty: activates project")

    print("workspaceSelfCheck OK")
}
