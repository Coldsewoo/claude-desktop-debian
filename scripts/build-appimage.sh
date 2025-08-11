#!/bin/bash
set -e

# Arguments passed from the main script
VERSION="$1"
ARCHITECTURE="$2"
WORK_DIR="$3" # The top-level build directory (e.g., ./build)
APP_STAGING_DIR="$4" # Directory containing the prepared app files (e.g., ./build/electron-app)
PACKAGE_NAME="$5"
# MAINTAINER and DESCRIPTION might not be directly used by AppImage tools but passed for consistency

echo "--- Starting AppImage Build ---"
echo "Version: $VERSION"
echo "Architecture: $ARCHITECTURE"
echo "Work Directory: $WORK_DIR"
echo "App Staging Directory: $APP_STAGING_DIR"
echo "Package Name: $PACKAGE_NAME"

COMPONENT_ID="io.github.aaddrick.claude-desktop-debian"
# Define AppDir structure path
APPDIR_PATH="$WORK_DIR/${COMPONENT_ID}.AppDir"
rm -rf "$APPDIR_PATH"
mkdir -p "$APPDIR_PATH/usr/bin"
mkdir -p "$APPDIR_PATH/usr/lib"
mkdir -p "$APPDIR_PATH/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR_PATH/usr/share/applications"

echo "📦 Staging application files into AppDir..."
# Copy the core application files (asar, unpacked resources, node_modules if present)
# Explicitly copy required components to ensure hidden files/dirs like .bin are included
if [ -f "$APP_STAGING_DIR/app.asar" ]; then
    cp -a "$APP_STAGING_DIR/app.asar" "$APPDIR_PATH/usr/lib/"
fi
if [ -d "$APP_STAGING_DIR/app.asar.unpacked" ]; then
    cp -a "$APP_STAGING_DIR/app.asar.unpacked" "$APPDIR_PATH/usr/lib/"
fi
if [ -d "$APP_STAGING_DIR/node_modules" ]; then
    echo "Copying node_modules from staging to AppDir..."
    cp -a "$APP_STAGING_DIR/node_modules" "$APPDIR_PATH/usr/lib/"
fi

# Ensure Electron is bundled within the AppDir for portability
# Check if electron was copied into the staging dir's node_modules
# The actual executable is usually inside the 'dist' directory
BUNDLED_ELECTRON_PATH="$APPDIR_PATH/usr/lib/node_modules/electron/dist/electron"
echo "Checking for executable at: $BUNDLED_ELECTRON_PATH"
if [ ! -x "$BUNDLED_ELECTRON_PATH" ]; then # Check if it exists and is executable
    echo "❌ Electron executable not found or not executable in staging area ($BUNDLED_ELECTRON_PATH)."
    echo "   AppImage requires Electron to be bundled. Ensure the main script copies it correctly."
    exit 1
fi
# Ensure the bundled electron is executable (redundant check, but safe)
chmod +x "$BUNDLED_ELECTRON_PATH"

# --- Create AppRun Script ---
echo "🚀 Creating AppRun script..."
# Note: We use $VERSION and $PACKAGE_NAME from the build script environment here
# They will be embedded into the AppRun script.
cat > "$APPDIR_PATH/AppRun" << EOF
#!/bin/bash
set -e

# Find the location of the AppRun script and the AppImage file itself
APPDIR=\$(dirname "\$0")
# Try to get the absolute path of the AppImage file being run
# $APPIMAGE is often set by the AppImage runtime, otherwise try readlink
APPIMAGE_PATH="\${APPIMAGE:-}"
if [ -z "\$APPIMAGE_PATH" ]; then
    # Find the AppRun script itself, which should be $0
    # Use readlink -f to get the absolute path, handling symlinks
    # Go up one level from AppRun's dir to get the AppImage path (usually)
    # This might be fragile if AppRun is not at the root, but it's standard.
    APPIMAGE_PATH=\$(readlink -f "\$APPDIR/../$(basename "$APPDIR" .AppDir).AppImage" 2>/dev/null || readlink -f "\$0" 2>/dev/null)
    # As a final fallback, just use $0, hoping it's the AppImage path
    if [ -z "\$APPIMAGE_PATH" ] || [ ! -f "\$APPIMAGE_PATH" ]; then
        APPIMAGE_PATH="\$0"
    fi
fi

# --- Desktop Integration (Handled by AppImageLauncher) ---
# The bundled .desktop file (claude-desktop-appimage.desktop) inside the AppImage
# contains the necessary MimeType=x-scheme-handler/claude; entry.
# AppImageLauncher (or similar tools) will use this file to integrate
# the AppImage with the system, including setting up the URI scheme handler,
# if the user chooses to integrate. No manual registration is needed here.
# --- End Desktop Integration ---


# Set up environment variables if needed (e.g., LD_LIBRARY_PATH)
# export LD_LIBRARY_PATH="\$APPDIR/usr/lib:\$LD_LIBRARY_PATH"

# Utility function to get desktop-specific flags
get_desktop_flags() {
    local desktop_env="\${XDG_CURRENT_DESKTOP:-Unknown}"
    local session_type="\${XDG_SESSION_TYPE:-x11}"
    local is_wayland=false
    [ -n "\$WAYLAND_DISPLAY" ] && is_wayland=true
    
    case "\$desktop_env" in
        "Unity"|"ubuntu:Unity")
            export UBUNTU_MENUPROXY=1
            unset WAYLAND_DISPLAY
            echo "--class=claude-desktop --name=Claude Desktop --force-desktop-shell --disable-features=VaapiVideoDecoder,UseOzonePlatform --use-gl=desktop --gtk-version=3"
            ;;
        "GNOME"|"ubuntu:GNOME")
            if [ "\$is_wayland" = true ]; then
                echo "--enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3 --gtk-version=3 --class=claude-desktop"
            else
                echo "--class=claude-desktop --force-desktop-shell --disable-features=VaapiVideoDecoder --use-gl=desktop --gtk-version=3"
            fi
            ;;
        "KDE")
            echo "--class=claude-desktop --gtk-version=3"
            ;;
        *)
            if [ "\$is_wayland" = true ]; then
                echo "--enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3 --class=claude-desktop --gtk-version=3"
            else
                echo "--class=claude-desktop --gtk-version=3"
            fi
            ;;
    esac
}

# Set up execution environment
DESKTOP_ENV="\${XDG_CURRENT_DESKTOP:-Unknown}"
ELECTRON_EXEC="\$APPDIR/usr/lib/node_modules/electron/dist/electron"
APP_PATH="\$APPDIR/usr/lib/app.asar"

# Build command arguments
DESKTOP_FLAGS=\$(get_desktop_flags)
ELECTRON_ARGS=("--no-sandbox" "\$APP_PATH")
IFS=' ' read -r -a FLAGS <<< "\$DESKTOP_FLAGS"
ELECTRON_ARGS+=("\${FLAGS[@]}")

# Change to the application resources directory (where app.asar is)
cd "\$APPDIR/usr/lib" || exit 1

# Define log file path in user's home directory
LOG_FILE="\$HOME/claude-desktop-launcher.log"

# Change to HOME directory before exec'ing Electron to avoid CWD permission issues
cd "\$HOME" || exit 1

# Log startup and execute
echo "\$(date): Starting Claude Desktop AppImage (\$DESKTOP_ENV)" >> "\$LOG_FILE"
exec "\$ELECTRON_EXEC" "\${ELECTRON_ARGS[@]}" "\$@" >> "\$LOG_FILE" 2>&1
EOF
chmod +x "$APPDIR_PATH/AppRun"
echo "✓ AppRun script created (with logging to \$HOME/claude-desktop-launcher.log, --no-sandbox, and CWD set to \$HOME)"

# --- Create Desktop Entry (Bundled inside AppDir) ---
echo "📝 Creating bundled desktop entry..."
# This is the desktop file *inside* the AppImage, used by tools like appimaged
cat > "$APPDIR_PATH/$COMPONENT_ID.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=AppRun %u
Icon=$COMPONENT_ID
Type=Application
Terminal=false
Categories=Network;Utility;
Comment=Claude Desktop for Linux
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
X-AppImage-Version=$VERSION
X-AppImage-Name=Claude Desktop
EOF
# Also place it in the standard location for tools like appimaged and validation
mkdir -p "$APPDIR_PATH/usr/share/applications"
cp "$APPDIR_PATH/$COMPONENT_ID.desktop" "$APPDIR_PATH/usr/share/applications/"
echo "✓ Bundled desktop entry created and copied to usr/share/applications/"

# --- Copy Icons ---
echo "🎨 Copying icons..."
# Use the 256x256 icon as the main AppImage icon
ICON_SOURCE_PATH="$WORK_DIR/claude_6_256x256x32.png"
if [ -f "$ICON_SOURCE_PATH" ]; then
    # Standard location within AppDir
    cp "$ICON_SOURCE_PATH" "$APPDIR_PATH/usr/share/icons/hicolor/256x256/apps/${COMPONENT_ID}.png"
    # Top-level icon (used by appimagetool) - Should match the Icon field in the .desktop file
    cp "$ICON_SOURCE_PATH" "$APPDIR_PATH/${COMPONENT_ID}.png"
    # Top-level icon without extension (fallback for some tools)
    cp "$ICON_SOURCE_PATH" "$APPDIR_PATH/${COMPONENT_ID}"
    # Hidden .DirIcon (fallback for some systems/tools)
    cp "$ICON_SOURCE_PATH" "$APPDIR_PATH/.DirIcon"
    echo "✓ Icon copied to standard path, top-level (.png and no ext), and .DirIcon"
else
    echo "Warning: Missing 256x256 icon at $ICON_SOURCE_PATH. AppImage icon might be missing."
fi

# --- Create AppStream Metadata ---
echo "📄 Creating AppStream metadata..."
METADATA_DIR="$APPDIR_PATH/usr/share/metainfo"
mkdir -p "$METADATA_DIR"

# Use the package name for the appdata file name (seems required by appimagetool warning)
# Use reverse-DNS for component ID and filename, following common practice
APPDATA_FILE="$METADATA_DIR/${COMPONENT_ID}.appdata.xml" # Filename matches component ID

# Generate the AppStream XML file
# Use MIT license based on LICENSE-MIT file in repo
# ID follows reverse DNS convention
cat > "$APPDATA_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$COMPONENT_ID</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>MIT</project_license>
  <developer id="io.github.aaddrick">
    <name>aaddrick</name>
  </developer>

  <name>Claude Desktop</name>
  <summary>Unofficial desktop client for Claude AI</summary>

  <description>
    <p>
      Provides a desktop experience for interacting with Claude AI, wrapping the web interface.
    </p>
  </description>

  <launchable type="desktop-id">${COMPONENT_ID}.desktop</launchable> <!-- Reference the actual .desktop file -->

  <icon type="stock">${COMPONENT_ID}</icon> <!-- Use the icon name from .desktop -->
  <url type="homepage">https://github.com/aaddrick/claude-desktop-debian</url>
  <screenshots>
      <screenshot type="default">
          <image>https://github.com/user-attachments/assets/93080028-6f71-48bd-8e59-5149d148cd45</image>
      </screenshot>
  </screenshots>
  <provides>
    <binary>AppRun</binary> <!-- Provide the actual binary -->
  </provides>

  <categories>
    <category>Network</category>
    <category>Utility</category>
  </categories>

  <content_rating type="oars-1.1" />

  <releases>
    <release version="$VERSION" date="$(date +%Y-%m-%d)">
      <description>
        <p>Version $VERSION.</p>
      </description>
    </release>
  </releases>

</component>
EOF
echo "✓ AppStream metadata created at $APPDATA_FILE"


# --- Get appimagetool ---
APPIMAGETOOL_PATH=""
if command -v appimagetool &> /dev/null; then
    APPIMAGETOOL_PATH=$(command -v appimagetool)
    echo "✓ Found appimagetool in PATH: $APPIMAGETOOL_PATH"
elif [ -f "$WORK_DIR/appimagetool-x86_64.AppImage" ]; then # Check for specific arch first
    APPIMAGETOOL_PATH="$WORK_DIR/appimagetool-x86_64.AppImage"
    echo "✓ Found downloaded x86_64 appimagetool: $APPIMAGETOOL_PATH"
elif [ -f "$WORK_DIR/appimagetool-aarch64.AppImage" ]; then # Check for other arch
    APPIMAGETOOL_PATH="$WORK_DIR/appimagetool-aarch64.AppImage"
    echo "✓ Found downloaded aarch64 appimagetool: $APPIMAGETOOL_PATH"
else
    echo "🛠️ Downloading appimagetool..."
    # Determine architecture for download URL
    TOOL_ARCH=""
    case "$ARCHITECTURE" in # Use target ARCHITECTURE passed to script
        "amd64") TOOL_ARCH="x86_64" ;;
        "arm64") TOOL_ARCH="aarch64" ;;
        *) echo "❌ Unsupported architecture for appimagetool download: $ARCHITECTURE"; exit 1 ;;
    esac

    APPIMAGETOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${TOOL_ARCH}.AppImage"
    APPIMAGETOOL_PATH="$WORK_DIR/appimagetool-${TOOL_ARCH}.AppImage"

    if wget -q -O "$APPIMAGETOOL_PATH" "$APPIMAGETOOL_URL"; then
        chmod +x "$APPIMAGETOOL_PATH"
        echo "✓ Downloaded appimagetool to $APPIMAGETOOL_PATH"
    else
        echo "❌ Failed to download appimagetool from $APPIMAGETOOL_URL"
        rm -f "$APPIMAGETOOL_PATH" # Clean up partial download
        exit 1
    fi
fi

# --- Build AppImage ---
echo "📦 Building AppImage..."
OUTPUT_FILENAME="${PACKAGE_NAME}-${VERSION}-${ARCHITECTURE}.AppImage"
OUTPUT_PATH="$WORK_DIR/$OUTPUT_FILENAME"

# Execute appimagetool
# Export ARCH instead of using env
export ARCH="$ARCHITECTURE"
echo "Using ARCH=$ARCH" # Debug output
if "$APPIMAGETOOL_PATH" "$APPDIR_PATH" "$OUTPUT_PATH"; then
    echo "✓ AppImage built successfully: $OUTPUT_PATH"
else
    echo "❌ Failed to build AppImage using $APPIMAGETOOL_PATH"
    exit 1
fi

echo "--- AppImage Build Finished ---"

exit 0