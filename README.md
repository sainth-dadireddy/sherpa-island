# Sherpa Island

Hybrid macOS dynamic-island app for the MacBook notch. Claude-aware when Claude Code is active, general productivity otherwise.

**Forked from** [devmegablaster/Notch-Pilot](https://github.com/devmegablaster/Notch-Pilot) (Claude OAuth foundation).

## Widgets (11 Sherpa-specific + Notch-Pilot inherited)

### Claude mode
- 5h/7d usage % with pacing marker
- Permission interception popup
- Multi-session list (🟢🟡🟣 emoji tabs)
- Burn rate · ETA · pace delta
- 24h cost ledger
- MCP health badges
- Memory DB stats (rows + last save age)
- /memoryr quick search (⌥Space palette)

### General mode
- Now playing (Spotify/Apple Music via MediaRemote)
- Calendar next event + countdown (EventKit)
- Battery percentage
- CPU/GPU/SSD/battery temperature (IOKit AppleSMC)
- Fan RPM + Macs Fan Control bridge (read-only by default)

### Auto mode-switch
- pgrep claude detection
- 6 modes: claudeFocus · interrupt · general · meetingAlert · powerSaver · thermalAlert

## Build

```bash
swift build
.build/arm64-apple-macosx/debug/NotchPilot
```

Requires macOS 26 Tahoe (Swift 6.3+, Liquid Glass APIs).

## License

MIT. Credits to Notch-Pilot (devmegablaster), exelban/stats, ThermalForge, boring.notch for inspirational patterns.

Generated 2026-05-23 via parallel multi-agent build (Claude Opus + codex + agy + Sherpa Code Generator).
