#!/bin/bash
set -e

# Arguments passed from the main script
VERSION="$1"
ARCHITECTURE="$2"
WORK_DIR="$3" # The top-level build directory (e.g., ./build)
APP_STAGING_DIR="$4" # Directory containing the prepared app files (e.g., ./build/electron-app)
PACKAGE_NAME="$5"
MAINTAINER="$6"
DESCRIPTION="$7"

echo "--- Starting Debian Package Build with Multi-Environment Support ---"
echo "Version: $VERSION"
echo "Architecture: $ARCHITECTURE"
echo "Work Directory: $WORK_DIR"
echo "App Staging Directory: $APP_STAGING_DIR"
echo "Package Name: $PACKAGE_NAME"

PACKAGE_ROOT="$WORK_DIR/package"
INSTALL_DIR="$PACKAGE_ROOT/usr"

# Clean previous package structure if it exists
rm -rf "$PACKAGE_ROOT"

# Create Debian package structure
echo "Creating package structure in $PACKAGE_ROOT..."
mkdir -p "$PACKAGE_ROOT/DEBIAN"
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME"
mkdir -p "$INSTALL_DIR/share/applications"
mkdir -p "$INSTALL_DIR/share/icons"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/local/bin"

# --- Icon Installation ---
echo "🎨 Installing icons..."
# Map icon sizes to their corresponding extracted files (relative to WORK_DIR)
declare -A icon_files=(
    ["16"]="claude_13_16x16x32.png"
    ["24"]="claude_11_24x24x32.png"
    ["32"]="claude_10_32x32x32.png"
    ["48"]="claude_8_48x48x32.png"
    ["64"]="claude_7_64x64x32.png"
    ["256"]="claude_6_256x256x32.png"
)

for size in 16 24 32 48 64 256; do
    icon_dir="$INSTALL_DIR/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    icon_source_path="$WORK_DIR/${icon_files[$size]}"
    if [ -f "$icon_source_path" ]; then
        echo "Installing ${size}x${size} icon from $icon_source_path..."
        install -Dm 644 "$icon_source_path" "$icon_dir/claude-desktop.png"
    else
        echo "Warning: Missing ${size}x${size} icon at $icon_source_path"
    fi
done
echo "✓ Icons installed"

# --- Copy Application Files ---
echo "📦 Copying application files from $APP_STAGING_DIR..."
cp "$APP_STAGING_DIR/app.asar" "$INSTALL_DIR/lib/$PACKAGE_NAME/"
cp -r "$APP_STAGING_DIR/app.asar.unpacked" "$INSTALL_DIR/lib/$PACKAGE_NAME/"

# Copy local electron if it was packaged (check if node_modules exists in staging)
if [ -d "$APP_STAGING_DIR/node_modules" ]; then
    echo "Copying packaged electron..."
    cp -r "$APP_STAGING_DIR/node_modules" "$INSTALL_DIR/lib/$PACKAGE_NAME/"
fi
echo "✓ Application files copied"

# --- Create Desktop Entry ---
echo "📝 Creating desktop entry..."
cat > "$INSTALL_DIR/share/applications/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=/usr/bin/claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
EOF
echo "✓ Desktop entry created"

# --- Create Enhanced Launcher Script with Multi-Environment Support ---
echo "🚀 Creating enhanced launcher script with multi-environment support..."
cat > "$INSTALL_DIR/bin/claude-desktop" << EOF
#!/bin/bash
LOG_FILE="\$HOME/claude-desktop-launcher.log"

# Utility functions
verify_claude_window() {
    local window_id="\$1"
    xprop -id "\$window_id" WM_CLASS 2>/dev/null | grep -qi "claude"
}

get_desktop_flags() {
    local flags=()
    case "\$DESKTOP_ENV" in
        "Unity"|"ubuntu:Unity")
            flags=("--class=claude-desktop" "--name=Claude Desktop" "--force-desktop-shell" 
                   "--disable-features=VaapiVideoDecoder,UseOzonePlatform" "--use-gl=desktop" 
                   "--gtk-version=3" "--no-sandbox" "--disable-dev-shm-usage")
            export UBUNTU_MENUPROXY=1
            unset WAYLAND_DISPLAY
            ;;
        "GNOME"|"ubuntu:GNOME")
            if [ "\$SESSION_TYPE" = "wayland" ] && [ -n "\$WAYLAND_DISPLAY" ]; then
                flags=("--enable-features=UseOzonePlatform,WaylandWindowDecorations" 
                       "--ozone-platform=wayland" "--enable-wayland-ime" "--gtk-version=3" "--class=claude-desktop")
            else
                flags=("--class=claude-desktop" "--force-desktop-shell" "--disable-features=VaapiVideoDecoder" 
                       "--use-gl=desktop" "--gtk-version=3" "--no-sandbox")
            fi
            ;;
        "KDE")
            flags=("--class=claude-desktop" "--gtk-version=3" "--no-sandbox")
            ;;
        *)
            flags=("--class=claude-desktop" "--gtk-version=3" "--no-sandbox" "--disable-dev-shm-usage")
            ;;
    esac
    printf '%s\n' "\${flags[@]}"
}

apply_window_decorations() {
    local window_id="\$1"
    local desktop_env="\$2"
    
    if ! verify_claude_window "\$window_id"; then
        return 1
    fi
    
    # Common properties
    xprop -id "\$window_id" -f _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS "0x2, 0x0, 0x1, 0x0, 0x0" 2>/dev/null || true
    xprop -id "\$window_id" -set WM_CLASS "claude-desktop,Claude Desktop" 2>/dev/null || true
    xprop -id "\$window_id" -set _NET_WM_WINDOW_TYPE "_NET_WM_WINDOW_TYPE_NORMAL" 2>/dev/null || true
    
    # Desktop-specific properties
    case "\$desktop_env" in
        "Unity"|"ubuntu:Unity")
            xprop -id "\$window_id" -set _UNITY_OBJECT_PATH "/com/canonical/menu/\$(echo \$window_id | sed 's/0x//')" 2>/dev/null || true
            ;;
        "GNOME"|"ubuntu:GNOME")
            xprop -id "\$window_id" -set _GTK_MENUBAR_OBJECT_PATH "/org/gtk/Application/menu" 2>/dev/null || true
            xprop -id "\$window_id" -set _GTK_APPLICATION_OBJECT_PATH "/org/gtk/Application" 2>/dev/null || true
            wmctrl -i -r "\$window_id" -b add,demands_attention 2>/dev/null || true
            sleep 0.2
            wmctrl -i -r "\$window_id" -b remove,demands_attention 2>/dev/null || true
            ;;
    esac
}

# Detect desktop environment
DESKTOP_ENV="\${XDG_CURRENT_DESKTOP:-Unknown}"
SESSION_TYPE="\${XDG_SESSION_TYPE:-x11}"
echo "\$(date): Starting Claude Desktop (\$DESKTOP_ENV/\$SESSION_TYPE)" >> "\$LOG_FILE"

# Determine Electron executable
LOCAL_ELECTRON_PATH="/usr/lib/$PACKAGE_NAME/node_modules/electron/dist/electron"
if [ -f "\$LOCAL_ELECTRON_PATH" ]; then
    ELECTRON_EXEC="\$LOCAL_ELECTRON_PATH"
elif command -v electron &> /dev/null; then
    ELECTRON_EXEC="electron"
else
    echo "Error: Electron not found" >> "\$LOG_FILE"
    command -v zenity &> /dev/null && zenity --error --text="Electron framework missing. Install Electron or reinstall Claude Desktop."
    command -v kdialog &> /dev/null && kdialog --error "Electron framework missing. Install Electron or reinstall Claude Desktop."
    exit 1
fi

# Build command arguments
APP_PATH="/usr/lib/$PACKAGE_NAME/app.asar"
mapfile -t DESKTOP_FLAGS < <(get_desktop_flags)
ELECTRON_ARGS=("\$APP_PATH" "\${DESKTOP_FLAGS[@]}")

# Change to application directory and launch
cd "/usr/lib/$PACKAGE_NAME" || { echo "Failed to cd" >> "\$LOG_FILE"; exit 1; }

# Launch Claude Desktop
"\$ELECTRON_EXEC" "\${ELECTRON_ARGS[@]}" "\$@" &
CLAUDE_PID=\$!

# Apply window decorations after startup delay
(
    sleep 3
    CLAUDE_WINDOWS=\$(wmctrl -l 2>/dev/null | grep -E "(Claude|claude-desktop)" | awk '{print \$1}')
    
    for window_id in \$CLAUDE_WINDOWS; do
        if apply_window_decorations "\$window_id" "\$DESKTOP_ENV"; then
            echo "\$(date): Applied decorations to \$window_id" >> "\$LOG_FILE"
        fi
    done
    
    # Run additional fix script if available
    command -v claude-gnome-menubar-fix &> /dev/null && claude-gnome-menubar-fix >> "\$LOG_FILE" 2>&1 || true
) &

# Wait for application exit
wait \$CLAUDE_PID
echo "\$(date): Claude Desktop exited (code: \$?)" >> "\$LOG_FILE"
exit \$?
EOF
chmod +x "$INSTALL_DIR/bin/claude-desktop"
echo "✓ Enhanced launcher script created with multi-environment support"

# --- Create GNOME Menu Bar Fix Script ---
echo "🔧 Creating GNOME menu bar fix script..."
cat > "$INSTALL_DIR/local/bin/claude-gnome-menubar-fix" << 'EOF'
#!/bin/bash

verify_claude_window() {
    xprop -id "$1" WM_CLASS 2>/dev/null | grep -qi "claude"
}

apply_gnome_decorations() {
    local window_id="$1"
    
    # Core GNOME properties
    xprop -id "$window_id" -f _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS "0x2, 0x0, 0x1, 0x0, 0x0" 2>/dev/null || true
    xprop -id "$window_id" -set WM_CLASS "claude-desktop,Claude Desktop" 2>/dev/null || true
    xprop -id "$window_id" -set _NET_WM_WINDOW_TYPE "_NET_WM_WINDOW_TYPE_NORMAL" 2>/dev/null || true
    
    # GNOME menu bar integration
    xprop -id "$window_id" -set _GTK_MENUBAR_OBJECT_PATH "/org/gtk/Application/menu" 2>/dev/null || true
    xprop -id "$window_id" -set _GTK_APPLICATION_OBJECT_PATH "/org/gtk/Application" 2>/dev/null || true
    xprop -id "$window_id" -set _GTK_APP_MENU_OBJECT_PATH "/org/gtk/Application/appmenu" 2>/dev/null || true
    xprop -id "$window_id" -set _GTK_CSD "1" 2>/dev/null || true
    
    # Refresh decorations
    wmctrl -i -r "$window_id" -b add,demands_attention 2>/dev/null || true
    sleep 0.2
    wmctrl -i -r "$window_id" -b remove,demands_attention 2>/dev/null || true
    wmctrl -i -r "$window_id" -b remove,fullscreen,above,below 2>/dev/null || true
}

# Check if Claude Desktop is running
pgrep -f "claude-desktop" > /dev/null || { echo "Claude Desktop not running"; exit 1; }

sleep 2
CLAUDE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -E "(Claude|claude-desktop)" | awk '{print $1}')

[ -z "$CLAUDE_WINDOWS" ] && { echo "No Claude Desktop windows found"; exit 1; }

echo "Applying GNOME menu bar fixes..."
for window_id in $CLAUDE_WINDOWS; do
    if verify_claude_window "$window_id"; then
        apply_gnome_decorations "$window_id"
        echo "Applied fixes to window: $window_id"
    fi
done

echo "Menu bar fix complete. Try Alt+F10 if menu doesn't appear."
EOF
chmod +x "$INSTALL_DIR/local/bin/claude-gnome-menubar-fix"
echo "✓ GNOME menu bar fix script created"

# --- Create Universal Diagnostic Script ---
echo "🔍 Creating universal desktop diagnostic script..."
cat > "$INSTALL_DIR/local/bin/claude-desktop-diagnostic" << 'EOF'
#!/bin/bash
echo "🔍 Claude Desktop Environment Diagnostic"
echo

# Check if Claude Desktop is running
if ! pgrep -f "claude-desktop" > /dev/null; then
    echo "❌ Claude Desktop is not running"
    echo "   Start Claude Desktop first: claude-desktop"
    exit 1
fi

echo "✓ Claude Desktop is running"

# Check desktop environment
echo
echo "🖥️  Desktop Environment Check:"
echo "   XDG_CURRENT_DESKTOP: ${XDG_CURRENT_DESKTOP:-Not set}"
echo "   XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-Not set}"
echo "   DESKTOP_SESSION: ${DESKTOP_SESSION:-Not set}"

# Determine desktop environment type
DESKTOP_TYPE="Unknown"
case "${XDG_CURRENT_DESKTOP}" in
    "Unity"|"ubuntu:Unity")
        DESKTOP_TYPE="Unity"
        ;;
    "GNOME"|"ubuntu:GNOME")
        DESKTOP_TYPE="GNOME"
        ;;
    "KDE")
        DESKTOP_TYPE="KDE"
        ;;
    *)
        DESKTOP_TYPE="Other/Generic"
        ;;
esac

echo "   Detected Type: $DESKTOP_TYPE"

# Check window manager
echo
echo "🔧 Window Manager Check:"
if [ "$DESKTOP_TYPE" = "Unity" ]; then
    if pgrep -f "compiz" > /dev/null; then
        echo "✓ Compiz is running (required for Unity)"
    else
        echo "❌ Compiz is not running (required for Unity decorations)"
    fi
elif [ "$DESKTOP_TYPE" = "GNOME" ]; then
    if pgrep -f "gnome-shell" > /dev/null; then
        echo "✓ GNOME Shell is running"
    else
        echo "❌ GNOME Shell is not running"
    fi
    
    if pgrep -f "mutter" > /dev/null; then
        echo "✓ Mutter window manager is running"
    else
        echo "❌ Mutter window manager is not running"
    fi
fi

# Check window management tools
echo
echo "🛠️  Tools Check:"
for tool in wmctrl xprop xwininfo; do
    if command -v "$tool" &> /dev/null; then
        echo "✓ $tool is available"
    else
        echo "❌ $tool is missing (install with: sudo apt install x11-utils wmctrl)"
    fi
done

# Find Claude Desktop windows
echo
echo "🪟 Claude Desktop Windows:"
CLAUDE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -E "(Claude|claude-desktop)")

if [ -z "$CLAUDE_WINDOWS" ]; then
    echo "❌ No Claude Desktop windows found with wmctrl"
else
    echo "$CLAUDE_WINDOWS"
fi

# Get detailed window information
echo
echo "📊 Window Details:"
wmctrl -l | grep -E "(Claude|claude-desktop)" | while read line; do
    window_id=$(echo "$line" | awk '{print $1}')
    echo "Window ID: $window_id"
    
    # Check window properties
    echo "  Class: $(xprop -id "$window_id" WM_CLASS 2>/dev/null | cut -d'"' -f2,4 2>/dev/null || echo "Not set")"
    echo "  Name: $(xprop -id "$window_id" WM_NAME 2>/dev/null | cut -d'"' -f2 2>/dev/null || echo "Not set")"
    echo "  Type: $(xprop -id "$window_id" _NET_WM_WINDOW_TYPE 2>/dev/null | cut -d'=' -f2 2>/dev/null || echo "Not set")"
    
    # Check decoration hints
    MOTIF_HINTS=$(xprop -id "$window_id" _MOTIF_WM_HINTS 2>/dev/null | cut -d'=' -f2 2>/dev/null || echo "Not set")
    echo "  MOTIF Hints: $MOTIF_HINTS"
    
    echo
done

echo "🔧 Recommendations for $DESKTOP_TYPE:"

case "$DESKTOP_TYPE" in
    "Unity")
        echo "  🔧 Try Unity menu bar fix: claude-unity-menubar-fix"
        if ! pgrep -f "compiz" > /dev/null; then
            echo "  🔄 Restart Compiz: compiz --replace &"
        fi
        ;;
    "GNOME")
        echo "  🔧 Try GNOME menu bar fix: claude-gnome-menubar-fix"
        echo "  ⚙️  Check GNOME settings: Settings → Appearance → Window title bars"
        echo "  🔧 Try: gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'"
        ;;
    "KDE")
        echo "  🔧 KDE usually handles Electron apps well"
        echo "  ⚙️  Check System Settings → Appearance → Window Decorations"
        ;;
    *)
        echo "  🔧 Try generic fix: claude-gnome-menubar-fix"
        echo "  ⚙️  Check your desktop environment's window decoration settings"
        ;;
esac

echo "  ⌨️  Try keyboard shortcut: Alt+F10"
echo "  🖱️  Right-click in title bar area for menu options"

echo
echo "✅ Diagnostic complete!"
EOF
chmod +x "$INSTALL_DIR/local/bin/claude-desktop-diagnostic"
echo "✓ Universal diagnostic script created"

# --- Create Control File ---
echo "📄 Creating control file..."
# Determine dependencies based on whether electron was packaged
DEPENDS="nodejs, npm, p7zip-full, wmctrl, x11-utils" # Added wmctrl and x11-utils for window management
echo "Electron is packaged locally; not adding to external Depends list."

cat > "$PACKAGE_ROOT/DEBIAN/control" << EOF
Package: $PACKAGE_NAME
Version: $VERSION
Architecture: $ARCHITECTURE
Maintainer: $MAINTAINER
Depends: $DEPENDS
Description: $DESCRIPTION
 Claude is an AI assistant from Anthropic.
 This package provides the desktop interface for Claude with enhanced
 window decoration support for various Linux desktop environments.
 .
 Includes comprehensive support for Unity, GNOME, KDE and other desktop
 environments with automatic menu bar detection and fixing capabilities.
 .
 Features environment-specific optimizations and troubleshooting tools.
 .
 Supported on Debian-based Linux distributions (Debian, Ubuntu, Linux Mint, MX Linux, etc.)
 Requires: nodejs (>= 12.0.0), npm
EOF
echo "✓ Control file created"

# --- Create Postinst Script ---
echo "⚙️ Creating postinst script..."
cat > "$PACKAGE_ROOT/DEBIAN/postinst" << EOF
#!/bin/sh
set -e

# Update desktop database for MIME types
echo "Updating desktop database..."
update-desktop-database /usr/share/applications &> /dev/null || true

# Set correct permissions for chrome-sandbox
echo "Setting chrome-sandbox permissions..."
LOCAL_SANDBOX_PATH="/usr/lib/$PACKAGE_NAME/node_modules/electron/dist/chrome-sandbox"
if [ -f "\$LOCAL_SANDBOX_PATH" ]; then
    echo "Found chrome-sandbox at: \$LOCAL_SANDBOX_PATH"
    chown root:root "\$LOCAL_SANDBOX_PATH" || echo "Warning: Failed to chown chrome-sandbox"
    chmod 4755 "\$LOCAL_SANDBOX_PATH" || echo "Warning: Failed to chmod chrome-sandbox"
    echo "Permissions set for \$LOCAL_SANDBOX_PATH"
else
    echo "Warning: chrome-sandbox binary not found at \$LOCAL_SANDBOX_PATH. Sandbox may not function correctly."
fi

# Create symlinks for desktop environment scripts
echo "Creating desktop environment script symlinks..."
if [ -f "/usr/local/bin/claude-gnome-menubar-fix" ]; then
    ln -sf "/usr/local/bin/claude-gnome-menubar-fix" "/usr/bin/claude-gnome-menubar-fix" 2>/dev/null || true
fi

if [ -f "/usr/local/bin/claude-desktop-diagnostic" ]; then
    ln -sf "/usr/local/bin/claude-desktop-diagnostic" "/usr/bin/claude-desktop-diagnostic" 2>/dev/null || true
fi

# Maintain backward compatibility
if [ -f "/usr/local/bin/claude-unity-menubar-fix" ]; then
    ln -sf "/usr/local/bin/claude-gnome-menubar-fix" "/usr/bin/claude-unity-menubar-fix" 2>/dev/null || true
fi

echo "Claude Desktop installation completed successfully!"
echo ""
echo "📋 Desktop Environment Support:"
echo "  • Automatic window decoration fixing on startup"
echo "  • GNOME/Ubuntu: claude-gnome-menubar-fix"
echo "  • Unity: claude-unity-menubar-fix"
echo "  • Universal diagnostic: claude-desktop-diagnostic"
echo "  • Keyboard shortcut: Alt+F10 to toggle menu bar"
echo ""
echo "🚀 Launch Claude Desktop: claude-desktop"

exit 0
EOF
chmod +x "$PACKAGE_ROOT/DEBIAN/postinst"
echo "✓ Postinst script created"

# --- Build .deb Package ---
echo "📦 Building .deb package..."
DEB_FILE="$WORK_DIR/${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"

if ! dpkg-deb --build "$PACKAGE_ROOT" "$DEB_FILE"; then
    echo "❌ Failed to build .deb package"
    exit 1
fi

echo "✓ .deb package built successfully: $DEB_FILE"
echo "--- Debian Package Build with Multi-Environment Support Finished ---"
echo
echo "📋 Package includes:"
echo "  • Enhanced launcher with automatic environment detection"
echo "  • GNOME-specific menu bar fix: claude-gnome-menubar-fix"
echo "  • Unity compatibility: claude-unity-menubar-fix"
echo "  • Universal diagnostic tool: claude-desktop-diagnostic"
echo "  • Automatic window decoration fixing integrated into launcher"
echo "  • Support for Unity, GNOME, KDE and other desktop environments"
echo

exit 0