# Agricultural Roboport Mod for Factorio 2.0+

For a complete feature overview and newcomer guide, see [mod-description.md](mod-description.md).

## Mod Compatibility

This mod **automatically detects and supports all agricultural items** from any mod - no configuration needed!

The mod scans all game prototypes and creates virtual seed entities for any item with a `plant_result` property, regardless of:
- **Item naming** (works with "tree-seed", "boompuff-spore", "alien-plant", etc.)
- **Item category** (item, capsule, ammo, tool, or any custom category)
- **Mod origin** (base game, DLC, or any third-party mod)

### Supported Mods (Partial List)
- ✅ **Base game** - all vanilla seeds
- ✅ **Space Age DLC** - all planet-specific agriculture
- ✅ **Boompuff Agriculture** - boompuff-spore and variants
- ✅ **Any mod with plantable items** - automatic detection

### How It Works
1. At game startup, the mod scans every prototype category
2. Any item with `plant_result` is recognized as a seed
3. Virtual ghost entities are created automatically
4. Seeds appear in filter dropdowns
5. Quality tracking works (if enabled)
6. Tile restrictions and buildability rules apply

**No settings. No configuration. It just works.**

## Feature & Progress Checklist

- [x] Implemented ghost-able plants by creating virtual entities, generated automatically
- [x] Add Agricultural Roboport building
- [x] Add Agricultural Roboport automatic seeding and harvesting of plants
- [x] Add Agricultural Roboport UI, which features modes of operation, filtering of allowed seeds and construction zone
- [x] Add performance-related settings (max. allowed seeds to place at once)
- [x] Add options on either to remove cliffs automatically or not, default to false (cliffs are not ignored in deconstruction by default)

- [x] Add graphics for virtual seeds
- [x] Improve performance by time-division-multiplexing the seeding and harvesting tasks of multiple roboports
- [x] Fix water-based plants seeding issue
- [x] Add missing translation keys for new features and UI elements
- [x] Finalize and review all in-game translations
- [x] Provide support for essential languages:
	- [x] English (en)
	- [x] German (de)
	- [x] Spanish (es)
	- [x] French (fr)
	- [x] Russian (ru)
	- [x] Chinese (zh)
	- [x] Japanese (ja)
- [x] Add quality support for plants and seeds (Factorio 2.0 quality system)
- [x] Implement quality mutation system with configurable rates
- [x] Dynamic UI adaptation based on quality setting (item vs item-with-quality selectors)
- [x] Quality badge rendering with alt-mode integration
- [x] Fix manual planting quality preservation
- [x] Add support for custom seed items from other mods (non-standard naming)
- [x] Implement blacklist filtering at item level (quality-agnostic)
- [x] Add Vegetation Planner - manual selection tool for planning vegetation in specific areas
- [x] Vegetation planner with independent filter configuration and shortcut integration
- [ ] Invite community contributions for additional languages

---

This checklist will be updated as new features are completed or added.

## Options & Settings

Below are the main settings exposed by the mod and their intended effect on gameplay and performance:

### Startup Settings

- `agricultural-roboport-enable-quality`: Toggle quality tracking and display for plants. When enabled, plants retain quality from seeds and can mutate during harvest. When disabled, all quality logic is bypassed. **Requires game restart.**
- `agricultural-roboport-dense-seeding`: Attempt to seed on every tile (instead of every 3rd tile in standard mode). Enables much denser plant packing and requires more construction bots. **Requires game restart.**

### Runtime Settings

#### Performance & Behavior

- `agricultural-roboport-max-seeds-per-tick`: Maximum number of seed ghosts a roboport will place per tick. Lower values reduce CPU spikes but slow down initial seeding.
- `agricultural-roboport-ignore-cliffs`: When true, the harvester will ignore cliffs when deciding what to deconstruct. Turning this off (default) will include cliffs which can cause more deconstruction work and cost cliff explosives.
- `agricultural-roboport-tdm-period`: Time-division multiplexing (TDM) period in ticks. Larger values spread work over a longer window; smaller values make the system respond faster but concentrate work in fewer ticks.
- `agricultural-roboport-tdm-tick-interval`: How often (in ticks) the TDM handler runs. Lower values run more frequently and can reduce per-tick load but increase overall scheduling overhead.
- `agricultural-roboport-seed-checks-per-call`: How many precomputed seed positions the seed routine will check per invocation. Lower values reduce per-call CPU usage but increase time to cover the whole area.
- `agricultural-roboport-max-harvest-per-call`: Hard limit of successful deconstruction orders per harvest call. Keeps deconstruction throughput bounded to avoid huge spikes.
- `agricultural-roboport-harvest-checks-per-call`: How many harvest grid cells are scanned per harvest invocation. Increasing this speeds up area coverage at the cost of more CPU per call.

#### Quality System

- `agricultural-roboport-quality-proc-multiplier`: Multiplies the base 0.5% quality mutation chance when harvesting plants. Set to 0 to disable mutations, or up to 200 for increased mutation rates (e.g., 100 = 50% chance).
- `agricultural-roboport-quality-improvement-chance`: Probability (0-100%) that a quality mutation will upgrade to the next tier instead of downgrading. Default is 10%. Higher quality plants have slightly lower improvement chance due to level adjustment.

#### Debug

- `agricultural-roboport-debug`: Enables file logging for debugging. Useful during testing but can produce large logs and should be off in normal play.

### Tuning Advice

- **Dense seeding**: Seeding on every tile increases collision checks and ghost placements. For extremely large operations, you can use whitelist filters to limit which plants are seeded.
- For low-end machines or dense maps, reduce `*_checks-per-call` and `max-*` values to spread work across ticks.
- For faster cleanup and aggressive automation, increase `*_checks-per-call` and `max-*` but monitor CPU usage and set `agricultural-roboport-debug` to `false`.
- Use quality mutation settings to balance farming efficiency with desired quality progression rates.
- Disable quality support entirely (startup setting) if not using the quality system to skip all quality-related overhead.
