# Agricultural Roboport Mod for Factorio 2.0+

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
- [ ] Invite community contributions for additional languages
---

This checklist will be updated as new features are completed or added.

## Options & Settings

Below are the main runtime settings exposed by the mod and their intended effect on gameplay and performance:

- `agricultural-roboport-max-seeds-per-tick`: Maximum number of seed ghosts a roboport will place per tick. Lower values reduce CPU spikes but slow down initial seeding.
- `agricultural-roboport-ignore-cliffs`: When true, the harvester will ignore cliffs when deciding what to deconstruct. Turning this off (default) will include cliffs which can cause more deconstruction work and cost cliff explosives.
- `agricultural-roboport-debug`: Enables file logging for debugging. Useful during testing but can produce large logs and should be off in normal play.
- `agricultural-roboport-tdm-period`: Time-division multiplexing (TDM) period in ticks. Larger values spread work over a longer window; smaller values make the system respond faster but concentrate work in fewer ticks.
- `agricultural-roboport-tdm-tick-interval`: How often (in ticks) the TDM handler runs. Lower values run more frequently and can reduce per-tick load but increase overall scheduling overhead.
- `agricultural-roboport-seed-checks-per-call`: How many precomputed seed positions the seed routine will check per invocation. Lower values reduce per-call CPU usage but increase time to cover the whole area.
- `agricultural-roboport-max-harvest-per-call`: Hard limit of successful deconstruction orders per harvest call. Keeps deconstruction throughput bounded to avoid huge spikes.
- `agricultural-roboport-harvest-checks-per-call`: How many harvest grid cells are scanned per harvest invocation. Increasing this speeds up area coverage at the cost of more CPU per call.

Tuning advice:
- For low-end machines or dense maps, reduce `*_checks-per-call` and `max-*` values to spread work across ticks.
- For faster cleanup and aggressive automation, increase `*_checks-per-call` and `max-*` but monitor CPU usage and set `agricultural-roboport-debug` to `false`.
