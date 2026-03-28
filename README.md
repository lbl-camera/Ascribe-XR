# Ascribe-XR

**Scientific data visualization in virtual reality using Godot 4.4 + OpenXR**

Ascribe-XR is a VR application for exploring and interacting with scientific datasets (meshes, volumes, point clouds) in immersive 3D environments. Developed at Lawrence Berkeley National Laboratory's Advanced Light Source.

## Features

- **Dynamic Specimens:** Parametric data generation with adjustable parameters via procedural UI
- **Volume Rendering:** 3D volumetric data visualization
- **Mesh Visualization:** Triangle mesh display with materials and lighting
- **Multiplayer:** WebRTC-based multiplayer with room support
- **Ascribe-Link Integration:** HTTP-based specimen server with caching
- **Story Mode:** Narrative-driven specimen exploration
- **VR Support:** OpenXR compatible (Quest, PCVR, etc.)

## Project Structure

```
Ascribe-XR/
├── scenes/          # Godot scene files (.tscn)
│   ├── Main/       # Main application scenes
│   ├── UI/         # User interface scenes
│   ├── Specimen/   # Specimen template scenes
│   ├── Player/     # VR player/avatar
│   ├── Rooms/      # Environment scenes
│   └── ...
├── scripts/         # GDScript source files (.gd)
│   ├── UI/         # UI controllers
│   ├── Specimen/   # Specimen logic
│   ├── DataSources/# Data loading backends
│   ├── DataClasses/# Data structures
│   ├── singletons/ # Autoload singletons
│   └── ...
├── specimens/       # Pre-configured specimen instances
├── specimen_data/   # Raw data files (meshes, volumes, etc.)
├── assets/          # Textures, models, icons
├── shaders/         # Custom GLSL shaders
├── addons/          # Third-party Godot plugins
└── testscenes/      # Development test scenes
```

## Getting Started

### Prerequisites

- Godot 4.4+ (OpenXR build)
- VR headset (optional for development)
- Python 3.10+ (for Ascribe-Link server)

### Running Locally

1. **Clone the repository:**
   ```bash
   git clone https://github.com/lbl-camera/Ascribe-XR.git
   cd Ascribe-XR
   ```

2. **Open in Godot:**
   - Launch Godot 4.4+
   - Import the project
   - Press F5 to run

3. **Start Ascribe-Link server (optional):**
   ```bash
   cd ../Ascribe-Link
   python -m ascribe_link
   ```
   Server runs at `http://localhost:8000`

### VR Setup

- **Quest:** Enable developer mode, connect via Link/Air Link
- **PCVR:** Ensure SteamVR or OpenXR runtime is active
- **Standalone:** Build APK and install via SideQuest

## Dynamic Specimens

Dynamic specimens generate data on-demand from parametric functions. Parameters are adjusted via an auto-generated UI in VR.

**Example:** Parametric Sphere
- Appears in menu with ⚙️ icon
- Select → Adjust radius/resolution sliders → Submit
- Server generates mesh, client displays result
- Multiple users in same room share cached results

See [Ascribe-Link](https://github.com/ronpandolfi/Ascribe-Link) for backend documentation.

## Configuration

### Config Singleton

Edit `scripts/singletons/config.gd`:

```gdscript
@export var ascribe_link_url = "http://localhost:8000"  # Server URL
@export var webrtcroomname = "ascribe"                   # Default multiplayer room
@export var webrtcbroker = "vision.lbl.gov"              # WebRTC signaling server
```

## Development

### Adding a New Specimen

1. Create scene in `specimens/` (or use template from `scenes/Specimen/`)
2. Set specimen properties:
   - `display_name`: Menu label
   - `thumbnail`: Preview image
   - `enabled`: Show in menu
3. Add data file to `specimen_data/`

### Creating a Dynamic Specimen

1. Add function to Ascribe-Link (see backend docs)
2. Create `specimen.json` with schema:
   ```json
   {
     "id": "my_specimen",
     "display_name": "My Specimen",
     "type": "mesh",
     "function_name": "generate_my_specimen",
     "schema": { ... }
   }
   ```
3. Specimen appears in menu with ⚙️ icon

## Multiplayer

WebRTC-based peer-to-peer multiplayer:
- Room-based sessions (default room: "ascribe")
- Synchronized specimen spawning
- Shared voice chat
- Pickable object interactions

Configure in `Config` singleton.

## Contributing

See `testscenes/` for development examples.

## License

Ascribe XR Copyright (c) 2025, The Regents of the University of California,
through Lawrence Berkeley National Laboratory (subject to receipt of
any required approvals from the U.S. Dept. of Energy). All rights reserved.

See `readme.md` for full license text.

## Related Projects

- [Ascribe-Link](https://github.com/ronpandolfi/Ascribe-Link) - Specimen server backend
- [Paper (ACM)](https://dl.acm.org/doi/10.1145/3731599.3767368) - VRST 2024 publication

## Contact

Advanced Light Source, Lawrence Berkeley National Laboratory
