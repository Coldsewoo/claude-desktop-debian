# Claude Desktop for Debian/Ubuntu

This repository provides tools to build and install Claude Desktop on Debian-based Linux distributions with enhanced window decoration support.

## Features

- **Native Package Installation**: Creates proper .deb packages for Debian/Ubuntu
- **Window Decoration Support**: Automatic detection and configuration for various desktop environments
- **Unity Optimization**: Special support for Unity desktop with menu bar fixes
- **GNOME/Wayland Compatibility**: Enhanced support for modern GNOME environments
- **Desktop Integration**: Proper MIME type handling and application integration

## Quick Install

1. **Download the pre-built package:**
   ```bash
   wget https://github.com/your-repo/claude-desktop-debian/releases/latest/download/claude-desktop_0.10.38_amd64.deb
   sudo dpkg -i claude-desktop_0.10.38_amd64.deb
   sudo apt-get install -f  # Fix any dependency issues
   ```

2. **Launch Claude Desktop:**
   ```bash
   claude-desktop
   ```

## Building from Source

### Prerequisites

```bash
sudo apt update
sudo apt install nodejs npm p7zip-full wmctrl x11-utils build-essential
```

### Build Process

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-repo/claude-desktop-debian.git
   cd claude-desktop-debian
   ```

2. **Run the build script:**
   ```bash
   ./build.sh
   ```

3. **Install the generated package:**
   ```bash
   sudo dpkg -i claude-desktop_*.deb
   sudo apt-get install -f
   ```

## Window Decoration Support

The package includes automatic window decoration fixes for various desktop environments:

### Unity Desktop
- Automatic menu bar and window decoration application
- Manual fix available: `claude-unity-window-rules`
- Optimized launcher flags for Unity/Compiz compatibility

### GNOME
- Wayland and X11 support
- Client-side decoration handling
- Proper integration with GNOME window manager

### KDE Plasma
- Native window decoration support
- Qt integration for consistent appearance

### Other Desktop Environments
- Generic fallback with standard decoration flags
- Automatic detection and appropriate flag application

## Troubleshooting

### Window Decorations Missing
1. **For Unity users:**
   ```bash
   claude-unity-window-rules
   ```

2. **Check launcher logs:**
   ```bash
   tail -f ~/claude-desktop-launcher.log
   ```

3. **Manual window manager refresh:**
   - Try Alt+F10 to toggle menu bar
   - Right-click title bar to access window options

### Installation Issues
1. **Missing dependencies:**
   ```bash
   sudo apt-get install -f
   ```

2. **Permission issues:**
   ```bash
   sudo dpkg-reconfigure claude-desktop
   ```

## Technical Details

### Package Structure
- **Application**: Installed to `/usr/lib/claude-desktop/`
- **Launcher**: Enhanced script at `/usr/bin/claude-desktop`
- **Desktop Integration**: `.desktop` file with proper MIME types
- **Window Rules**: Unity-specific scripts in `/usr/local/bin/`

### Desktop Environment Detection
The launcher automatically detects:
- Desktop environment (`$XDG_CURRENT_DESKTOP`)
- Display server (X11/Wayland)
- Session type (`$XDG_SESSION_TYPE`)

And applies appropriate Electron flags for optimal window decoration support.

### Electron Flags by Environment

**Unity:**
- `--force-desktop-shell`
- `--enable-menu-bar-binding`
- `--show-menubar`
- Unity-specific window rules via xprop

**GNOME:**
- `--enable-features=UseOzonePlatform,WaylandWindowDecorations`
- `--ozone-platform=wayland` (on Wayland)
- `--gtk-version=3`

**KDE:**
- `--enable-features=UseOzonePlatform`
- `--ozone-platform=auto`

## Development

### Building Custom Versions
Modify the build script variables in `build.sh`:
- `CLAUDE_VERSION`: Application version
- `PACKAGE_VERSION`: Package version
- `MAINTAINER`: Package maintainer info

### Adding Desktop Environment Support
Edit `scripts/build-deb-package.sh` to add detection and flags for new desktop environments in the launcher script.

## License

This project is dual-licensed under:
- Apache License 2.0 (LICENSE-APACHE)
- MIT License (LICENSE-MIT)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test on multiple desktop environments
4. Submit a pull request

## Support

For issues specific to:
- **Window decorations**: Check the launcher logs and try manual window rules
- **Package installation**: Ensure all dependencies are installed
- **Unity desktop**: Use the included `claude-unity-window-rules` script
- **GNOME/Wayland**: Verify Wayland-specific flags are being applied

Report bugs and feature requests in the GitHub Issues section.
