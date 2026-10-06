#!/usr/bin/env bash
# Builds Velocity Heat for Linux and Windows in one go.
#
#   ./build.sh            build both (zips land in build/)
#   ./build.sh linux      only Linux
#   ./build.sh windows    only Windows
#
# Needs Godot 4.7. If it isn't installed (or GODOT doesn't point at it), the script
# downloads Godot and the export templates once into .godot-tools/ (about 1 GB).
set -euo pipefail
cd "$(dirname "$0")"

GODOT_VERSION="4.7"
RELEASE="${GODOT_VERSION}-stable"
URL="https://github.com/godotengine/godot/releases/download/${RELEASE}"
TOOLS="$PWD/.godot-tools"
TARGETS="${1:-all}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required (install it with your package manager)."; }

need unzip
case "$(uname -s)" in
	Linux) HOST=linux ;;
	Darwin) HOST=macos ;;
	*) die "Use build.bat on Windows." ;;
esac

# ---------------------------------------------------------------- Godot editor
is_right_godot() { "$1" --headless --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"; }

if [ -n "${GODOT:-}" ]; then
	is_right_godot "$GODOT" || die "GODOT=$GODOT is not Godot ${GODOT_VERSION}."
else
	for cand in godot godot4 "$TOOLS/Godot_v${RELEASE}_linux.x86_64" "$TOOLS/Godot.app/Contents/MacOS/Godot"; do
		if command -v "$cand" >/dev/null 2>&1 && is_right_godot "$cand"; then GODOT="$cand"; break; fi
	done
fi
if [ -z "${GODOT:-}" ]; then
	need curl
	mkdir -p "$TOOLS"
	if [ "$HOST" = linux ]; then
		say "Downloading Godot ${RELEASE} (Linux)..."
		curl -fL --progress-bar -o "$TOOLS/godot.zip" "$URL/Godot_v${RELEASE}_linux.x86_64.zip"
		unzip -oq "$TOOLS/godot.zip" -d "$TOOLS" && rm "$TOOLS/godot.zip"
		GODOT="$TOOLS/Godot_v${RELEASE}_linux.x86_64"
		chmod +x "$GODOT"
	else
		say "Downloading Godot ${RELEASE} (macOS)..."
		curl -fL --progress-bar -o "$TOOLS/godot.zip" "$URL/Godot_v${RELEASE}_macos.universal.zip"
		unzip -oq "$TOOLS/godot.zip" -d "$TOOLS" && rm "$TOOLS/godot.zip"
		GODOT="$TOOLS/Godot.app/Contents/MacOS/Godot"
	fi
fi
say "Using $("$GODOT" --headless --version 2>/dev/null | head -1)"

# ---------------------------------------------------------------- export templates
if [ "$HOST" = linux ]; then
	TPL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}.stable"
else
	TPL_DIR="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"
fi
if [ ! -f "$TPL_DIR/linux_release.x86_64" ] || [ ! -f "$TPL_DIR/windows_release_x86_64.exe" ]; then
	need curl
	mkdir -p "$TOOLS" "$TPL_DIR"
	if [ ! -f "$TOOLS/templates.tpz" ]; then
		say "Downloading export templates (one time, ~1 GB)..."
		curl -fL --progress-bar -o "$TOOLS/templates.tpz.part" "$URL/Godot_v${RELEASE}_export_templates.tpz"
		mv "$TOOLS/templates.tpz.part" "$TOOLS/templates.tpz"
	fi
	say "Installing the Linux and Windows templates..."
	unzip -ojq "$TOOLS/templates.tpz" templates/linux_release.x86_64 templates/windows_release_x86_64.exe templates/version.txt -d "$TPL_DIR"
	chmod +x "$TPL_DIR/linux_release.x86_64"
	rm -f "$TOOLS/templates.tpz" # the two templates we need are installed now
fi

# ---------------------------------------------------------------- build
# Stamp the build so the main menu shows which version you're running.
printf '%s  %s\n' "$(git rev-parse --short HEAD 2>/dev/null || echo local)" "$(date +%Y-%m-%d)" > version.txt
say "Importing assets..."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || "$GODOT" --headless --path . --editor --quit >/dev/null 2>&1 || true

radio_readme() {
	mkdir -p "$1/Radio"
	cat > "$1/Radio/README.txt" <<'EOF'
Put your own MP3 / OGG / WAV files in this folder.
In the game press Q (keyboard) or L3 (controller) while driving to turn the radio on or skip a song.
Hold the button to switch back to the game's soundtrack.
Name files "Artist - Title.mp3" (or tag them) so the game shows the right song name.
EOF
}

export_one() { # preset, folder, binary
	local preset="$1" dir="build/$2" bin="$3"
	say "Exporting $preset..."
	rm -rf "$dir" && mkdir -p "$dir"
	local log="build/export-$2.log"
	if ! "$GODOT" --headless --path . --export-release "$preset" "$dir/$bin" >"$log" 2>&1 || [ ! -s "$dir/$bin" ]; then
		tail -n 30 "$log"
		die "$preset export failed (full log: $log)."
	fi
	radio_readme "$dir"
	(cd build && rm -f "VelocityHeat-$2.zip" && zip -qr "VelocityHeat-$2.zip" "$2" 2>/dev/null) || true
	say "$preset build ready: $dir/$bin"
}

mkdir -p build
case "$TARGETS" in
	all) export_one "Linux" linux VelocityHeat.x86_64; export_one "Windows" windows VelocityHeat.exe ;;
	linux) export_one "Linux" linux VelocityHeat.x86_64 ;;
	windows) export_one "Windows" windows VelocityHeat.exe ;;
	*) die "Unknown target '$TARGETS' (use all, linux or windows)." ;;
esac
say "Done. Run ./build/linux/VelocityHeat.x86_64 (Linux) or build\\windows\\VelocityHeat.exe (Windows)."
