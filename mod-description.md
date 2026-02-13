Agricultural Roboport
======================

Automate farming with construction robots. Your bots plant seeds and harvest crops — just like they build factories, but for agriculture. No more idling construction bots!

What does it do?
----------------
- **Auto-farming**: Roboports automatically seed and harvest plants in their coverage area
- **Vegetation Planner** (ALT+V): Manual tool for precise planting and clearing
- **Quality mutations**: Research "Controlled Mutations" to breed higher-quality plants through environmental exposure
- **Universal compatibility**: Works with any mod that adds plantable items
- **Performance-optimized**: Handles huge farms without lag

Quick Start
-----------
1. Build an Agricultural Roboport
2. Open its GUI and pick a mode (Harvest only / Harvest & Seed)
3. Set up filters to choose what to plant (optional)
4. Your bots handle the rest!

Quality Mutations
-----------------
Harvest plants in polluted or high-solar areas to trigger random quality upgrades. Research "Controlled Mutations" (8 levels) to improve your chances and control upgrade direction.

- Base mutation chance: **0.5% - 20%** (scales with pollution)
- **Pollution scaling**: Higher pollution = more mutations (1x at clean air, 40x at 500+ pollution)
- **Research matters**: Each tech level gives +20% improvement chance, fighting against pollution penalties
- **Per-player visualization**: Enable flying text in settings to see mutation details

Vegetation Planner
------------------
Got bots but no roboports? Use the Vegetation Planner tool:
- Access via shortcut (ALT+V) after researching "Soil Analysis"
- Draw areas to seed or clear (Alt-select)
- Independent filters for precise control

Settings
--------
**Startup** (requires restart):
- **Enable quality plants** — Track and display plant quality
- **Dense seeding** — Plant every tile instead of every 3rd tile (performance impact!)

**Runtime** (adjustable anytime):
- **Performance tuning**: Adjust harvest/seed checks per tick to balance speed vs CPU
- **Ignore cliffs** — Preserve natural terrain
- **Mutation visualization** — Show/hide mutation flying text (per-player)
- **Debug logging** — Enable for troubleshooting if you dare, but better contact me.

Performance Tips
----------------
- Large farms running slow? Lower "harvest checks per call" and "max seeds per tick"
- Use whitelist filters to plant only what you need

Filtering Tips
--------------
- **Whitelist**: Pick specific items and qualities (e.g., only uncommon jellynut seeds)
- **Blacklist**: Block entire item types across all qualities
- **Circuit network mode**: Control operation mode and filters from circuit signals
- **Vegetation Planner**: Has its own independent filters for manual work

Compatibility
-------------
- Factorio 2.0+
- Requires Space Age + Quality DLCs
- Works with any mod adding plantable items (no config needed!)
- Supports 7 languages: English, German, Spanish, French, Russian, Chinese, Japanese
