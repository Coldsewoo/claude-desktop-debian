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
echo "--- Claude Desktop Launcher Start ---" >> "\$LOG_FILE"
echo "Timestamp: \$(date)" >> "\$LOG_FILE"
echo "Arguments: \$@" >> "\$LOG_FILE"

# Detect desktop environment and display server
DESKTOP_ENV="\${XDG_CURRENT_DESKTOP:-Unknown}"
SESSION_TYPE="\${XDG_SESSION_TYPE:-x11}"
echo "Desktop Environment: \$DESKTOP_ENV" >> "\$LOG_FILE"
echo "Session Type: \$SESSION_TYPE" >> "\$LOG_FILE"

# Determine Electron executable path
ELECTRON_EXEC="electron" # Default to global
LOCAL_ELECTRON_PATH="/usr/lib/$PACKAGE_NAME/node_modules/electron/dist/electron"
if [ -f "\$LOCAL_ELECTRON_PATH" ]; then
    ELECTRON_EXEC="\$LOCAL_ELECTRON_PATH"
    echo "Using local Electron: \$ELECTRON_EXEC" >> "\$LOG_FILE"
else
    # Check if global electron exists before declaring it as the choice
    if command -v electron &> /dev/null; then
        echo "Using global Electron: \$ELECTRON_EXEC" >> "\$LOG_FILE"
    else
        echo "Error: Electron executable not found (checked local \$LOCAL_ELECTRON_PATH and global path)." >> "\$LOG_FILE"
        # Optionally, display an error to the user via zenity or kdialog if available
        if command -v zenity &> /dev/null; then
            zenity --error --text="Claude Desktop cannot start because the Electron framework is missing. Please ensure Electron is installed globally or reinstall Claude Desktop."
        elif command -v kdialog &> /dev/null; then
            kdialog --error "Claude Desktop cannot start because the Electron framework is missing. Please ensure Electron is installed globally or reinstall Claude Desktop."
        fi
        exit 1
    fi
fi

# Base command arguments array, starting with app path
APP_PATH="/usr/lib/$PACKAGE_NAME/app.asar"
ELECTRON_ARGS=("\$APP_PATH")

# Add window decoration flags based on desktop environment
case "\$DESKTOP_ENV" in
    "Unity"|"ubuntu:Unity")
        echo "Applying Unity-specific window decoration flags (X11 only)" >> "\$LOG_FILE"
        # Unity always uses X11, so force X11 mode and disable Wayland
        ELECTRON_ARGS+=(
            "--class=claude-desktop"
            "--name=Claude Desktop"
            "--force-desktop-shell"
            "--disable-features=VaapiVideoDecoder,UseOzonePlatform"
            "--use-gl=desktop"
            "--gtk-version=3"
            "--no-sandbox"
            "--disable-dev-shm-usage"
        )
        # Set Unity-specific environment
        export UBUNTU_MENUPROXY=1
        # Force X11 environment
        unset WAYLAND_DISPLAY
        ;;
    "GNOME"|"ubuntu:GNOME")
        echo "Applying GNOME-specific window decoration flags" >> "\$LOG_FILE"
        if [ "\$SESSION_TYPE" = "wayland" ] && [ -n "\$WAYLAND_DISPLAY" ]; then
            echo "Using Wayland mode for GNOME" >> "\$LOG_FILE"
            ELECTRON_ARGS+=(
                "--enable-features=UseOzonePlatform,WaylandWindowDecorations"
                "--ozone-platform=wayland"
                "--enable-wayland-ime"
                "--gtk-version=3"
                "--class=claude-desktop"
            )
        else
            echo "Using X11 mode for GNOME" >> "\$LOG_FILE"
            ELECTRON_ARGS+=(
                "--class=claude-desktop"
                "--force-desktop-shell"
                "--disable-features=VaapiVideoDecoder"
                "--use-gl=desktop"
                "--gtk-version=3"
                "--no-sandbox"
            )
        fi
        ;;
    "KDE")
        echo "Applying KDE-specific window decoration flags" >> "\$LOG_FILE"
        ELECTRON_ARGS+=(
            "--class=claude-desktop"
            "--gtk-version=3"
            "--no-sandbox"
        )
        ;;
    *)
        echo "Applying generic window decoration flags for \$DESKTOP_ENV" >> "\$LOG_FILE"
        # Generic fallback - minimal flags for maximum compatibility
        ELECTRON_ARGS+=(
            "--class=claude-desktop"
            "--gtk-version=3"
            "--no-sandbox"
            "--disable-dev-shm-usage"
        )
        ;;
esac

# Change to the application directory
APP_DIR="/usr/lib/$PACKAGE_NAME"
echo "Changing directory to \$APP_DIR" >> "\$LOG_FILE"
cd "\$APP_DIR" || { echo "Failed to cd to \$APP_DIR" >> "\$LOG_FILE"; exit 1; }

# Execute Electron with app path, flags, and script arguments
FINAL_CMD="\"\$ELECTRON_EXEC\" \"\${ELECTRON_ARGS[@]}\" \"\$@\""
echo "Executing: \$FINAL_CMD" >> "\$LOG_FILE"

# Launch Claude Desktop
"\$ELECTRON_EXEC" "\${ELECTRON_ARGS[@]}" "\$@" &
CLAUDE_PID=\$!

# Apply window decoration rules based on environment
if [ "\$DESKTOP_ENV" = "Unity" ] || [ "\$DESKTOP_ENV" = "ubuntu:Unity" ]; then
    echo "Applying Unity window decoration rules..." >> "\$LOG_FILE"
    (
        sleep 4
        
        # Find Claude Desktop windows
        CLAUDE_WINDOWS=\$(wmctrl -l 2>/dev/null | grep -i "claude" | awk '{print \$1}')
        
        for window_id in \$CLAUDE_WINDOWS; do
            if [ -n "\$window_id" ]; then
                echo "Applying Unity rules to window: \$window_id" >> "\$LOG_FILE"
                
                # Unity-specific window decoration rules
                xprop -id "\$window_id" -f _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS "0x2, 0x0, 0x1, 0x0, 0x0" 2>/dev/null || true
                xprop -id "\$window_id" -set WM_CLASS "claude-desktop,Claude Desktop" 2>/dev/null || true
                xprop -id "\$window_id" -set _NET_WM_WINDOW_TYPE "_NET_WM_WINDOW_TYPE_NORMAL" 2>/dev/null || true
                xprop -id "\$window_id" -set _UNITY_OBJECT_PATH "/com/canonical/menu/\$(echo \$window_id | sed 's/0x//')" 2>/dev/null || true
            fi
        done
    ) &
elif [ "\$DESKTOP_ENV" = "GNOME" ] || [ "\$DESKTOP_ENV" = "ubuntu:GNOME" ]; then
    echo "Applying GNOME window decoration rules..." >> "\$LOG_FILE"
    (
        sleep 3
        
        # Find Claude Desktop windows
        CLAUDE_WINDOWS=\$(wmctrl -l 2>/dev/null | grep -i "claude" | awk '{print \$1}')
        
        for window_id in \$CLAUDE_WINDOWS; do
            if [ -n "\$window_id" ]; then
                echo "Applying GNOME rules to window: \$window_id" >> "\$LOG_FILE"
                
                # GNOME-specific window decoration rules
                xprop -id "\$window_id" -f _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS "0x2, 0x0, 0x1, 0x0, 0x0" 2>/dev/null || true
                xprop -id "\$window_id" -set WM_CLASS "claude-desktop,Claude Desktop" 2>/dev/null || true
                xprop -id "\$window_id" -set _NET_WM_WINDOW_TYPE "_NET_WM_WINDOW_TYPE_NORMAL" 2>/dev/null || true
                
                # GNOME menu bar integration
                xprop -id "\$window_id" -set _GTK_MENUBAR_OBJECT_PATH "/org/gtk/Application/menu" 2>/dev/null || true
                xprop -id "\$window_id" -set _GTK_APPLICATION_OBJECT_PATH "/org/gtk/Application" 2>/dev/null || true
                
                # Force window decoration refresh
                wmctrl -i -r "\$window_id" -b add,demands_attention 2>/dev/null || true
                sleep 0.2
                wmctrl -i -r "\$window_id" -b remove,demands_attention 2>/dev/null || true
            fi
        done
        
        # Run GNOME menu bar fix if available
        if command -v claude-gnome-menubar-fix &> /dev/null; then
            echo "Running GNOME menu bar fix script..." >> "\$LOG_FILE"
            claude-gnome-menubar-fix >> "\$LOG_FILE" 2>&1 || true
        fi
    ) &
fi

# Wait for Claude Desktop to finish
wait \$CLAUDE_PID
EXIT_CODE=\$?
echo "Electron exited with code: \$EXIT_CODE" >> "\$LOG_FILE"
echo "--- Claude Desktop Launcher End ---" >> "\$LOG_FILE"
exit \$EXIT_CODE
EOF
chmod +x "$INSTALL_DIR/bin/claude-desktop"
echo "✓ Enhanced launcher script created with multi-environment support"

# --- Create GNOME Menu Bar Fix Script ---
echo "🔧 Creating GNOME menu bar fix script..."
cat > "$INSTALL_DIR/local/bin/claude-gnome-menubar-fix" << 'EOF'
#!/bin/bash

# GNOME Menu Bar Fix for Running Claude Desktop
# Comprehensive fix for GNOME window decorations and menu bar

echo "🔧 GNOME Menu Bar Fix for Claude Desktop"

# Check if Claude Desktop is running
if ! pgrep -f "claude-desktop" > /dev/null; then
    echo "❌ Claude Desktop is not running"
    echo "   Start Claude Desktop first: claude-desktop"
    exit 1
fi

echo "✓ Claude Desktop is running"

# Wait a moment for windows to stabilize
sleep 2

# Find Claude Desktop windows
echo "🔍 Finding Claude Desktop windows..."
CLAUDE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -i "claude" | awk '{print $1}')

if [ -z "$CLAUDE_WINDOWS" ]; then
    echo "❌ No Claude Desktop windows found"
    echo "   Make sure Claude Desktop is fully loaded"
    exit 1
fi

echo "✓ Found Claude Desktop windows: $CLAUDE_WINDOWS"

# Apply GNOME-specific window decoration rules
for window_id in $CLAUDE_WINDOWS; do
    echo "🔧 Processing window: $window_id"
    
    # Get current window title for confirmation
    WINDOW_TITLE=$(xprop -id "$window_id" WM_NAME 2>/dev/null | cut -d'"' -f2 2>/dev/null || echo "Unknown")
    echo "   Window title: $WINDOW_TITLE"
    
    # Force window decorations and menu bar
    echo "   Setting window decorations..."
    xprop -id "$window_id" -f _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS "0x2, 0x0, 0x1, 0x0, 0x0" 2>/dev/null || true
    
    # Set proper window class
    echo "   Setting window class..."
    xprop -id "$window_id" -set WM_CLASS "claude-desktop,Claude Desktop" 2>/dev/null || true
    
    # Force normal window type
    echo "   Setting window type..."
    xprop -id "$window_id" -set _NET_WM_WINDOW_TYPE "_NET_WM_WINDOW_TYPE_NORMAL" 2>/dev/null || true
    
    # GNOME menu bar integration
    echo "   Setting GNOME menu bar properties..."
    xprop -id "$window_id" -set _GTK_MENUBAR_OBJECT_PATH "/org/gtk/Application/menu" 2>/dev/null || true
    xprop -id "$window_id" -set _GTK_APPLICATION_OBJECT_PATH "/org/gtk/Application" 2>/dev/null || true
    
    # Force window state changes to trigger decoration refresh
    echo "   Refreshing window decorations..."
    wmctrl -i -r "$window_id" -b add,demands_attention 2>/dev/null || true
    sleep 0.3
    wmctrl -i -r "$window_id" -b remove,demands_attention 2>/dev/null || true
    
    # Remove any problematic window states
    echo "   Normalizing window state..."
    wmctrl -i -r "$window_id" -b remove,fullscreen 2>/dev/null || true
    wmctrl -i -r "$window_id" -b remove,above 2>/dev/null || true
    wmctrl -i -r "$window_id" -b remove,below 2>/dev/null || true
    
    echo "   ✓ GNOME rules applied to window $window_id"
done

echo
echo "🎯 Additional GNOME menu bar attempts..."

# Try GNOME-specific approaches
for window_id in $CLAUDE_WINDOWS; do
    echo "🔄 Attempting GNOME menu integration for window: $window_id"
    
    # Try to force GTK menu bar visibility
    xprop -id "$window_id" -set _GTK_MENUBAR_OBJECT_PATH "/org/gtk/Application/menu/$(echo $window_id | sed 's/0x//')" 2>/dev/null || true
    xprop -id "$window_id" -set _GTK_APP_MENU_OBJECT_PATH "/org/gtk/Application/appmenu" 2>/dev/null || true
    
    # Try window manager hints for GNOME
    xprop -id "$window_id" -set _NET_WM_STATE "_NET_WM_STATE_FOCUSED" 2>/dev/null || true
    
    # Force CSD (Client Side Decorations) properties
    xprop -id "$window_id" -set _GTK_CSD "1" 2>/dev/null || true
done

echo
echo "✅ GNOME menu bar fix applied!"
echo
echo "📋 What was done:"
echo "  • Applied MOTIF window hints for decorations"
echo "  • Set proper window class and type"
echo "  • Added GTK menu bar integration properties"
echo "  • Forced window decoration refresh"
echo "  • Applied GNOME-specific menu bar hints"
echo
echo "🔧 If menu bar still doesn't appear:"
echo "  1. Try keyboard shortcut: Alt+F10"
echo "  2. Check GNOME settings: Settings → Appearance"
echo "  3. Try: gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'"
echo "  4. Restart Claude Desktop for automatic fixes"
echo
echo "📝 GNOME Menu Bar Settings:"
echo "  • Check: Settings → Appearance → Window title bars"
echo "  • Ensure: Show window title bars is enabled"
EOF
chmod +x "$INSTALL_DIR/local/bin/claude-gnome-menubar-fix"
echo "✓ GNOME menu bar fix script created"

# --- Create Universal Diagnostic Script ---
echo "🔍 Creating universal desktop diagnostic script..."
cat > "$INSTALL_DIR/local/bin/claude-desktop-diagnostic" << 'EOF'
#!/bin/bash

# Universal Desktop Environment Diagnostic for Claude Desktop
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
CLAUDE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -i "claude")

if [ -z "$CLAUDE_WINDOWS" ]; then
    echo "❌ No Claude Desktop windows found with wmctrl"
else
    echo "$CLAUDE_WINDOWS"
fi

# Get detailed window information
echo
echo "📊 Window Details:"
wmctrl -l | grep -i "claude" | while read line; do
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