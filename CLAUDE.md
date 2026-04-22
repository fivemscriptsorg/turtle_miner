# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Lua programs for **CC:Tweaked** mining turtles in Minecraft. There is no host-side build, test, or lint tooling — the code runs inside the game on a turtle's emulated Lua VM. Changes are validated by running the installer on a turtle and watching it mine.

- Target hardware: **non-advanced mining turtle** (`term.getSize()` = 39×13, no color). Rendering is ASCII only.
- Optional peripherals: Environment Detector and Geo Scanner from the **Advanced Peripherals** mod.

## Release / deploy flow

`main` branch is the release. The installer (`install.lua`) points to:
`https://raw.githubusercontent.com/fivemscriptsorg/turtle_miner/main`

On the turtle:
```
install                # downloads install.lua first; if changed, re-execs with --post-update
```
The self-update mechanism means a commit to `main` is effectively a deploy. If you add a new module, add its path to `FILES` in `install.lua` and commit — next `install` run on the turtle will pick it up without extra steps.

## Module loading (important)

Modules are loaded with the **deprecated** `os.loadAPI` in `startup.lua`. Semantics:
- `os.loadAPI("miner/config.lua")` runs the file with a custom environment and exposes every global it defines as a field on a table named `config` (basename of the file, no `.lua`).
- Inside a module, `function foo()` (no `local`) becomes `config.foo` to the caller.
- Cross-module calls look like globals: `ui.setStatus(...)`, `inventory.isOre(...)`, etc.
- Order in `startup.lua` matters: `ui` before `config` before `mining`, etc.

If you migrate to `require`, every module must `return M` and every reference must become `local ui = require("miner.ui")`. Do it as a single coordinated change — mixing the two styles breaks imports silently.

## Shared state

Everything hangs off `_G.state`, built in `startup.lua:defaultState()`. It mixes:
- **Persistent config**: `pattern`, `shaftLength`, `branchLength`, `branchSpacing`, `tunnelWidth`
- **Live position**: `x`, `y`, `z`, `facing`
- **Counters**: `blocksMined`, `oresFound`, `chestsPlaced`
- **Progress**: `currentStep` (for resume)
- **Runtime-only (NOT persisted)**: `envDetector`, `geoScanner`, `hasEnvDetector`, `hasGeoScanner` (userdata — can't be serialized)

`miner/persist.lua` has a whitelist (`PERSIST_FIELDS`) of what gets saved. Peripherals are always re-detected on boot.

## Facing convention

```
0 = +X (front / default starting direction)
1 = +Z (right)
2 = -X (back)
3 = -Z (left)
```
Turtle is placed at `(0,0,0)` facing `+X`. `movement.turnLeft/turnRight/turnAround/faceDirection` keep `state.facing` in sync — always use those, never call `turtle.turnLeft/turnRight` directly.

## Critical gotcha: dig/inspect vertical is facing-independent

`turtle.digUp`, `turtle.digDown`, `turtle.detectUp`, `turtle.inspectUp` (and Down variants) always operate on the block directly above/below the turtle, **regardless of which way the turtle is facing**. Turning left and then calling `digUp` does **not** dig the block above-and-to-the-left — it digs the same ceiling block.

This caused the original 3×3 carving bug: the author expected turning + `digUp` to hit the upper side corners. To carve any column other than the turtle's own, the turtle must physically move into that column. See `carveSideColumn` in `miner/mining.lua` for the pattern.

## Mining pipeline

`mining.run()` is the entry point called from `startup.lua`.

- `runBranchMining` / `runTunnelMining` drive a `for step = startStep, shaftLength` loop. `startStep` honors `state.currentStep` so resume can skip completed steps.
- Each iteration calls `carveFullSlice()` (see "Alternating lane pattern" below).
- After every shaft step: `persist.save()` writes `/miner/state.dat`. On clean return, `persist.clear()` removes it.
- `mineBranch(length)` tracks *actual* steps advanced (not the requested `length`) so a blocked branch doesn't overshoot the main shaft on the return trip. Before the backtrack it calls `returnToPassCenter()` so the straight-line return works.
- `returnToStart` uses `faceDirection(2)` + forward loop to get back to X=0, then corrects Z drift, then places a final chest.

## Alternating lane pattern (fuel optimization)

`carveFullSlice` does NOT return to the center column between slices. It alternates: a slice that starts in center ends in right, the next slice starts in right and ends in left, the next starts in left and ends in right, etc. This saves ~2 forwards per slice vs returning to center every time.

Two pieces of state drive it:
- `state.passFacing` — the "forward" direction of the current pass (shaft or branch). Set at the start of each pass.
- `state.sliceLane` — lateral offset from the pass centerline: `0` = center, `-1` = left (left of `passFacing`), `+1` = right.

Per slice:
1. `faceDirection(passFacing)`, then advance one block (dig f+u+d, forward, dig u+d).
2. If `tunnelWidth >= 3`, visit the two other lanes in an order that ends away from the starting lane (e.g. starting at `+1`: visit `0`, then `-1`, ending at `-1`).

At the end of a pass you MUST call `returnToPassCenter()` before any straight-line backtrack — otherwise the turtle is in a side lane and the backtrack drifts off-shaft. `mineBranch` and both `runXxxMining` loops already do this.

Around branches: `runBranchMining` calls `returnToPassCenter()` before turning to branch, then after both branches reassigns `state.passFacing = facingStart` and `state.sliceLane = 0` to restore the shaft's pass frame. `mineBranch` sets its own `passFacing` / `sliceLane` on entry — these are re-owned by the caller after it returns.

Both `sliceLane` and `passFacing` are in `PERSIST_FIELDS` so resume lands back in the right lane.

## Movement safety

`movement.safeForward/safeUp/safeDown` retry up to `MAX_TRIES = 8`: on failure they `dig` if a block is detected, else `attack` (mob), with a 0.2s sleep between retries. `safeBack` has no dig path — if `turtle.back()` fails it turns around, does a `safeForward`, turns around again. Position tracking (`state.x/y/z`) is updated **only on successful moves**, so a failed move never corrupts coordinates. Always route through `movement.*` rather than `turtle.forward/back/up/down` to keep position state consistent.

## Inventory

`miner/inventory.lua` classifies items via three sets:
- `JUNK_ITEMS` — dropped to make space
- `KEEP_ITEMS` — never dropped (coal, charcoal, coal_block, chest)
- `isOre(name)` — pattern-matches `_ore$` plus `ancient_debris` and raw_ variants

`handleFullInventory` escalates: `compact()` → `dropJunk()` → `placeChest()`. `placeChest` digs a hole in the right-hand wall and places the chest there so it doesn't block the tunnel. The turtle MUST be in the center column facing forward when it's called, so only call it between `carveFullSlice()` iterations.

## Remote control (rednet)

Protocol name: `turtle_miner`. Hostname: `miner-<computerID>`. If the turtle has a modem peripheral (side or upgrade), `remote.init()` opens it and calls `rednet.host`. The client (`client.lua`, run on a separate computer with a modem) discovers turtles via `rednet.lookup(PROTOCOL)`.

During mining, `startup.lua` runs two coroutines via `parallel.waitForAny`:
- `mining.run()` — the normal mining pipeline
- `remote.listener()` — infinite loop of `rednet.receive(PROTOCOL, 2)` with a status broadcast every `BROADCAST_INTERVAL` seconds

When `mining.run()` returns, `parallel.waitForAny` kills the listener. The listener is a pure consumer/producer — it never calls mining logic. It communicates by setting `state.remoteCmd`.

`mining.checkRemoteCmd()` is called at the top of every slice loop (`runBranchMining`, `runTunnelMining`, `mineBranch`). It:
- blocks on `pause` (polling with `sleep(0.3)`) until the cmd changes
- returns `true` for `home` or `stop` (caller breaks the loop)

`mining.run()` handles `stop` specially: it saves the checkpoint and skips `returnToStart` so the turtle freezes in place — resumable on next boot.

Messages are always plain Lua tables. Client → turtle: `{ action = "pause" | "resume" | "home" | "stop" | "status" | "ping" }`. Turtle → client: `{ kind = "status", data = <snapshot> }`, `{ kind = "ack", action = "..." }`, `{ kind = "event", type = "...", data = {...} }`. Snapshots never include userdata (peripherals) — see `remote.snapshot()` for the whitelist.

## Swarm (multi-turtle cooperation)

`miner/swarm.lua` adds a data layer for multiple turtles sharing a world. It does NOT add pathfinding or active job distribution — it's the primitives on which those would sit.

**GPS**: `swarm.initGPS()` calls `gps.locate()` after the modem is open. On success it stores `state.origin` = the ABS world coords of the turtle's local `(0,0,0)`. Then `swarm.toAbs(lx,ly,lz)` and `swarm.toLocal(ax,ay,az)` convert between frames. If GPS fails (no hosts / out of range), origin stays `nil` and cross-turtle coord sharing is disabled — each turtle still works fine in local-only mode.

Requires 3+ GPS host computers set up in the world (`gps host <x> <y> <z>` per host) and the turtle's modem in range of them.

**Ore map**: shared `state.oreMap`, keyed by `"x_y_z"` of absolute coords, each entry `{x, y, z, name, seenAt, by, claimedBy, claimUntil}`. Auto-prunes entries older than 5 min, caps at 500 entries. Populated by:
- `swarm.broadcastOreSpotted(localPos, name)` — converts to ABS, broadcasts `ore_spotted`, inserts locally.
- `swarm.broadcastOreGone(localPos)` — broadcasts `ore_gone`, removes locally.

Both are called from `mining.inspectAndLog` whenever an ore is found and dug.

**Message handling**: `swarm.handleSwarmMessage(sender, msg)` is called first inside `remote.handleMessage`. It handles `ore_spotted`, `ore_gone`, `ore_claim`, `sync_request`, `sync_dump`. Returns `true` if it handled the message so `remote` doesn't double-handle.

**Joining the network**: `startup.lua` calls `swarm.requestSync()` after init. Any other turtle on the net replies with `{kind="sync_dump", oreMap=...}`, which gets merged in.

**Not yet implemented** (hooks are there, logic isn't): claim-and-chase (idle turtle navigates to a known unclaimed ore), job queue, refuel base, dead-turtle detection. `nearestUnclaimed(fromAbs, maxDist)` and `claimOre(absPos, byId, ttl)` are ready for consumers to use.

## Fleet dashboard (client)

`client.lua` has two modes. `single` is the original: one turtle, detailed dashboard, pause/resume/home/stop. `fleet` shows all turtles in a tabular dashboard (world/local pos, fuel, status, progress, ores) plus a combined ore-map counter. A `launchFleet` skeleton sends `configure` messages with `zOffset` per turtle — the turtle side doesn't auto-apply configure yet (stays as roadmap).

The fleet listener merges `ore_spotted` from any sender into a local map so the operator sees a global view.

## Advanced Peripherals

All calls into `envDetector`/`geoScanner` are wrapped in `pcall`. They silently degrade to "no data" on cooldown, insufficient FE, disconnected peripheral, or API version skew. Don't remove the `pcall` wrapping even though it looks redundant — different AP versions have renamed methods.

## Resume semantics

On boot, `startup.lua` checks for `/miner/state.dat`. If found, shows a prompt with saved pattern / step / position and asks `[R] Reanudar [N] Nueva [D] Borrar`. Resume is **trust-based**: it assumes the turtle is physically at the saved position. If the user moved the turtle, the tracked coordinates will be wrong and the turtle will try to mine into the wrong blocks. Always advise "Nueva" if in doubt.

## Things that are NOT bugs

- `os.loadAPI` deprecation warning: intentional, not migrated to `require` (risk vs reward).
- `pcall` around every Advanced Peripherals call: defensive by design.
- `autoRefuel(100)` called on every `safeForward/Up/Down`: has an early return when fuel ≥ min, so the hot path is one `turtle.getFuelLevel()` call.
- Tunnel entrance (slice at `x=0`) is only 1 block wide regardless of `tunnelWidth`: the turtle's starting block is not carved sideways. By design.
