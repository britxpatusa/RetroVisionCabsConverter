import Foundation

/// Manages embedded scripts securely
/// Scripts are stored in code and written to a protected temp location only when needed
final class SecureScriptManager {
    
    static let shared = SecureScriptManager()
    
    private var scriptsDirectory: URL?
    private let fileManager = FileManager.default
    
    private init() {}
    
    /// Get the secure scripts directory, creating scripts if needed
    func getScriptsDirectory() throws -> URL {
        if let existing = scriptsDirectory, fileManager.fileExists(atPath: existing.path) {
            return existing
        }
        
        // Create in app's container with restricted permissions
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("RetroVisionCabsConverter")
        let scriptsDir = appDir.appendingPathComponent(".scripts") // Hidden folder
        
        // Create directories
        try fileManager.createDirectory(at: scriptsDir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: scriptsDir.appendingPathComponent("python"), withIntermediateDirectories: true)
        
        // Write scripts
        try writeScript(Scripts.convertScript, to: scriptsDir.appendingPathComponent("bin/convert_aoj_cabinets.sh"))
        try writeScript(Scripts.convertSingleScript, to: scriptsDir.appendingPathComponent("bin/convert_single_cabinet.sh"))
        try writeScript(Scripts.setupVenvScript, to: scriptsDir.appendingPathComponent("bin/setup_venv.sh"))
        try writeScript(Scripts.checkToolsScript, to: scriptsDir.appendingPathComponent("bin/check_tools.sh"))
        try writeScript(Scripts.makeJobScript, to: scriptsDir.appendingPathComponent("python/aoj_make_job.py"))
        try writeScript(Scripts.blenderExportScript, to: scriptsDir.appendingPathComponent("python/blender_apply_job_and_export_usdz.py"))
        
        // Make shell scripts executable
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptsDir.appendingPathComponent("bin/convert_aoj_cabinets.sh").path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptsDir.appendingPathComponent("bin/convert_single_cabinet.sh").path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptsDir.appendingPathComponent("bin/setup_venv.sh").path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptsDir.appendingPathComponent("bin/check_tools.sh").path)
        
        // Restrict directory permissions
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptsDir.path)
        
        scriptsDirectory = scriptsDir
        return scriptsDir
    }
    
    private func writeScript(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        // Set restrictive permissions (owner read/write only for scripts, executable for shell)
        let isShellScript = url.pathExtension == "sh"
        let permissions: Int16 = isShellScript ? 0o700 : 0o600
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
    
    /// Clean up scripts (call on app termination if desired)
    func cleanup() {
        guard let dir = scriptsDirectory else { return }
        try? fileManager.removeItem(at: dir)
        scriptsDirectory = nil
    }
    
    // MARK: - Script Paths
    
    var converterScriptPath: String {
        (try? getScriptsDirectory().appendingPathComponent("bin/convert_aoj_cabinets.sh").path) ?? ""
    }
    
    var singleConverterScriptPath: String {
        (try? getScriptsDirectory().appendingPathComponent("bin/convert_single_cabinet.sh").path) ?? ""
    }
    
    var pythonScriptsPath: String {
        (try? getScriptsDirectory().appendingPathComponent("python").path) ?? ""
    }
    
    var shellScriptsPath: String {
        (try? getScriptsDirectory().appendingPathComponent("bin").path) ?? ""
    }
}

// MARK: - Embedded Script Content

private enum Scripts {
    
    static let convertScript = """
#!/usr/bin/env bash
set -euo pipefail

BASE="${RETROVISION_BASE:-}"
AGE_SRC="${RETROVISION_AGE_SRC:-}"
WORK="$BASE/_Work/AoJ"
OUT="$BASE/Output/USDZ"
MODEL_LIB="$BASE/ModelLibrary"
VENV="${RETROVISION_VENV:-}"
BLENDER="${RETROVISION_BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
SCRIPTS="${RETROVISION_SCRIPTS:-}"

PY="$VENV/bin/python"
MAKEJOB="$SCRIPTS/aoj_make_job.py"
BL_SCRIPT="$SCRIPTS/blender_apply_job_and_export_usdz.py"

mkdir -p "$WORK" "$OUT" "$MODEL_LIB"

if [[ ! -x "$PY" ]]; then
  echo "❌ Python environment not configured"
  echo "   Please run Setup to install dependencies"
  exit 2
fi

if [[ ! -x "$BLENDER" ]]; then
  echo "❌ Blender not installed"
  echo "   Please install Blender from blender.org"
  exit 2
fi

if [[ ! -f "$MAKEJOB" ]] || [[ ! -f "$BL_SCRIPT" ]]; then
  echo "❌ Internal scripts not found"
  echo "   Please restart the application"
  exit 2
fi

# Check if AGE_SRC is a single cabinet (has description.yaml) or a folder of cabinets
single_cabinet_mode=false
if [[ -f "$AGE_SRC/description.yaml" ]]; then
  single_cabinet_mode=true
  echo "Single cabinet mode: $(basename "$AGE_SRC")"
  items=("$AGE_SRC")
else
  echo "Scanning cabinets folder..."
  shopt -s nullglob
  items=("$AGE_SRC"/*)
  shopt -u nullglob
fi

if [[ ${#items[@]} -eq 0 ]]; then
  echo "No cabinet folders found"
  exit 0
fi

total=${#items[@]}
current=0

# Load template map if provided
template_map_file="${CABINET_TEMPLATE_MAP:-}"

for item in "${items[@]}"; do
  name="$(basename "$item")"
  base="${name%.*}"
  ((current++)) || true

  cabdir=""
  if [[ -d "$item" ]]; then
    cabdir="$item"
  elif [[ -f "$item" && "$item" == *.zip ]]; then
    cabdir="$WORK/$base"
    rm -rf "$cabdir"
    mkdir -p "$cabdir"
    echo "[$current/$total] Extracting: $name"
    if ! /usr/bin/unzip -q -o "$item" -d "$cabdir" 2>/dev/null; then
      echo "[$current/$total] ❌ Failed to extract: $name"
      continue
    fi
    # Check if files ended up in a subfolder (some ZIPs have nested folder)
    if [[ ! -f "$cabdir/description.yaml" ]]; then
      # Try to find it in a subfolder
      subfolder=$(find "$cabdir" -maxdepth 1 -type d ! -name ".*" ! -name "__MACOSX" ! -path "$cabdir" | head -1)
      if [[ -n "$subfolder" && -f "$subfolder/description.yaml" ]]; then
        cabdir="$subfolder"
      fi
    fi
  else
    continue
  fi

  if [[ ! -f "$cabdir/description.yaml" ]]; then
    echo "[$current/$total] Skipping: $name (no description.yaml found)"
    # Show what was found
    echo "         Contents: $(ls -1 "$cabdir" 2>/dev/null | head -5 | tr '\\n' ' ')"
    continue
  fi

  job="$WORK/$base.job.json"
  out_dir="$OUT/$base"
  out_usdz="$out_dir/$base.usdz"
  out_meta="$out_dir/$base.rkmeta.json"
  screen_data="$WORK/$base.screen.json"
  log_file="$out_dir/$base.blender.log.txt"

  # Create output folder for this cabinet
  mkdir -p "$out_dir"

  # Look up template for this cabinet from template map
  cabinet_template=""
  if [[ -n "$template_map_file" && -f "$template_map_file" ]]; then
    cabinet_template=$("$PY" -c "
import json
m = json.load(open('$template_map_file'))
print(m.get('$base', ''))
" 2>/dev/null)
  fi
  
  # Export template path for this cabinet
  export CABINET_TEMPLATE_PATH="$cabinet_template"

  echo "[$current/$total] Processing: $name"
  "$PY" "$MAKEJOB" "$cabdir" "$job" > /dev/null 2>&1

  template_info=""
  if [[ -n "$cabinet_template" ]]; then
    template_info=" ($(basename "${cabinet_template%.*}"))"
  fi
  echo "[$current/$total] Converting to USDZ...$template_info"
  # Use configured temp directory (passed via environment) to avoid cross-filesystem issues
  BLENDER_TEMP="${RETROVISION_BLENDER_TEMP:-$BASE/.temp/blender}"
  mkdir -p "$BLENDER_TEMP"
  TMPDIR="$BLENDER_TEMP" TMP="$BLENDER_TEMP" TEMP="$BLENDER_TEMP" \\
  "$BLENDER" -b --factory-startup \\
    --python "$BL_SCRIPT" -- \\
    --job "$job" --srcdir "$cabdir" --model_library "$MODEL_LIB" --out "$out_usdz" --screen_data "$screen_data" \\
    > "$log_file" 2>&1 || {
      echo "[$current/$total] ❌ Failed: $name"
      continue
    }

  "$PY" - <<PY > /dev/null 2>&1
import json
from pathlib import Path

job = json.loads(Path("$job").read_text(encoding="utf-8"))

# Load screen geometry if available
screen = None
screen_file = Path("$screen_data")
if screen_file.exists():
    try:
        screen = json.loads(screen_file.read_text(encoding="utf-8"))
    except:
        pass

meta = {
  "name": job.get("cabinet_name"),
  "rom": job.get("rom"),
  "year": job.get("year"),
  "video": job.get("video"),
  "crt": job.get("crt"),
  "screen": screen,
  "coinslot": job.get("coinslot"),
  "coinslotgeometry": job.get("coinslotgeometry"),
  "rk_contract": job.get("rk_contract")
}
Path("$out_meta").write_text(json.dumps(meta, indent=2), encoding="utf-8")
PY

  echo "[$current/$total] ✓ Completed: $name"
done

echo ""
echo "Conversion complete! Processed $current cabinets."
"""
    
    /// Single cabinet conversion script - takes cabinet path as first argument
    static let convertSingleScript = """
#!/usr/bin/env bash
set -euo pipefail

# Single cabinet conversion script
# Usage: convert_single_cabinet.sh <cabinet_folder_path>

CABINET_PATH="${1:-}"
if [[ -z "$CABINET_PATH" || ! -d "$CABINET_PATH" ]]; then
  echo "❌ Invalid cabinet path: $CABINET_PATH"
  exit 1
fi

BASE="${RETROVISION_BASE:-}"
WORK="$BASE/_Work/AoJ"
OUT="$BASE/Output/USDZ"
MODEL_LIB="$BASE/ModelLibrary"
VENV="${RETROVISION_VENV:-}"
BLENDER="${RETROVISION_BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
SCRIPTS="${RETROVISION_SCRIPTS:-}"

PY="$VENV/bin/python"
MAKEJOB="$SCRIPTS/aoj_make_job.py"
BL_SCRIPT="$SCRIPTS/blender_apply_job_and_export_usdz.py"

mkdir -p "$WORK" "$OUT" "$MODEL_LIB"

if [[ ! -x "$PY" ]]; then
  echo "❌ Python environment not configured"
  echo "   Please run Setup to install dependencies"
  exit 2
fi

if [[ ! -x "$BLENDER" ]]; then
  echo "❌ Blender not installed"
  echo "   Please install Blender from blender.org"
  exit 2
fi

if [[ ! -f "$MAKEJOB" ]] || [[ ! -f "$BL_SCRIPT" ]]; then
  echo "❌ Internal scripts not found"
  echo "   Please restart the application"
  exit 2
fi

name="$(basename "$CABINET_PATH")"
base="${name%.*}"

if [[ ! -f "$CABINET_PATH/description.yaml" ]]; then
  echo "❌ No cabinet definition found"
  echo "   Missing description.yaml in cabinet folder"
  exit 3
fi

job="$WORK/$base.job.json"
out_dir="$OUT/$base"
out_usdz="$out_dir/$base.usdz"
out_meta="$out_dir/$base.rkmeta.json"
screen_data="$WORK/$base.screen.json"
log_file="$out_dir/$base.blender.log.txt"

# Create output folder for this cabinet
mkdir -p "$out_dir"

echo "🔧 Creating conversion job..."
"$PY" "$MAKEJOB" "$CABINET_PATH" "$job"

echo "🎨 Applying textures and materials..."
# Use configured temp directory (passed via environment) to avoid cross-filesystem issues
BLENDER_TEMP="${RETROVISION_BLENDER_TEMP:-$BASE/.temp/blender}"
mkdir -p "$BLENDER_TEMP"
TMPDIR="$BLENDER_TEMP" TMP="$BLENDER_TEMP" TEMP="$BLENDER_TEMP" \\
"$BLENDER" -b --factory-startup \\
  --python "$BL_SCRIPT" -- \\
  --job "$job" --srcdir "$CABINET_PATH" --model_library "$MODEL_LIB" --out "$out_usdz" --screen_data "$screen_data" \\
  > "$log_file" 2>&1 || {
    echo "❌ Blender conversion failed"
    echo "   Check log: $log_file"
    exit 4
  }

echo "📝 Generating metadata with screen geometry..."
"$PY" - <<PY
import json
from pathlib import Path

job = json.loads(Path("$job").read_text(encoding="utf-8"))

# Load screen geometry if available
screen = None
screen_file = Path("$screen_data")
if screen_file.exists():
    try:
        screen = json.loads(screen_file.read_text(encoding="utf-8"))
        print("  ✓ Screen geometry included")
    except:
        pass

meta = {
  "name": job.get("cabinet_name"),
  "rom": job.get("rom"),
  "year": job.get("year"),
  "video": job.get("video"),
  "crt": job.get("crt"),
  "screen": screen,
  "coinslot": job.get("coinslot"),
  "coinslotgeometry": job.get("coinslotgeometry"),
  "rk_contract": job.get("rk_contract")
}
Path("$out_meta").write_text(json.dumps(meta, indent=2), encoding="utf-8")
PY

echo ""
echo "✅ Conversion complete!"
echo "   Output folder: $out_dir"
echo "   USDZ: $base.usdz"
echo "   Meta: $base.rkmeta.json"
"""
    
    static let setupVenvScript = """
#!/usr/bin/env bash
set -euo pipefail

VENV_PATH="${1:-}"
if [[ -z "$VENV_PATH" ]]; then
  echo "Configuration error"
  exit 1
fi

echo "Creating Python environment..."
mkdir -p "$(dirname "$VENV_PATH")"
python3 -m venv "$VENV_PATH"
source "$VENV_PATH/bin/activate"

echo "Updating package manager..."
python -m pip install --upgrade pip setuptools wheel > /dev/null 2>&1

echo "Installing USD support (this may take a few minutes)..."
pip install usd-core > /dev/null 2>&1

echo "Installing image processing..."
pip install pillow > /dev/null 2>&1

echo "Installing utilities..."
pip install numpy pyyaml > /dev/null 2>&1

echo "Verifying installation..."
python -c "from pxr import Usd; print('  ✓ USD support ready')"
python -c "import PIL; print('  ✓ Image processing ready')"
python -c "import numpy; print('  ✓ Numerical support ready')"
python -c "import yaml; print('  ✓ YAML support ready')"

deactivate
echo ""
echo "✅ Python environment configured successfully"
"""
    
    static let checkToolsScript = """
#!/usr/bin/env bash
set -euo pipefail

VENV_PATH="${RETROVISION_VENV:-}"
BLENDER_PATH="${RETROVISION_BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"

echo "Checking installed tools..."
echo ""

echo "Python:"
if command -v python3 >/dev/null 2>&1; then
  VER=$(python3 --version 2>&1 | cut -d' ' -f2)
  echo "  ✓ Installed (version $VER)"
else
  echo "  ✗ Not found"
fi

echo ""
echo "Blender:"
if [[ -x "$BLENDER_PATH" ]]; then
  VER=$("$BLENDER_PATH" --version 2>&1 | head -n 1 | cut -d' ' -f2)
  echo "  ✓ Installed (version $VER)"
else
  echo "  ✗ Not found"
fi

echo ""
echo "Python Packages:"
if [[ -n "$VENV_PATH" && -f "$VENV_PATH/bin/activate" ]]; then
  source "$VENV_PATH/bin/activate"
  python -c "from pxr import Usd; print('  ✓ USD support')" 2>/dev/null || echo "  ✗ USD support missing"
  python -c "import PIL; print('  ✓ Image processing')" 2>/dev/null || echo "  ✗ Image processing missing"
  python -c "import numpy; print('  ✓ Numerical support')" 2>/dev/null || echo "  ✗ Numerical support missing"
  python -c "import yaml; print('  ✓ YAML support')" 2>/dev/null || echo "  ✗ YAML support missing"
  deactivate
else
  echo "  ✗ Python environment not configured"
fi

echo ""
echo "Tool check complete."
"""
    
    static let makeJobScript = """
#!/usr/bin/env python3
import json, sys
from pathlib import Path
import yaml

def main():
    if len(sys.argv) < 3:
        print("Usage: aoj_make_job.py <cabinet_folder> <out_job_json>", file=sys.stderr)
        return 2

    cab_dir = Path(sys.argv[1]).resolve()
    out_json = Path(sys.argv[2]).resolve()

    desc = cab_dir / "description.yaml"
    if not desc.exists():
        print(f"ERROR: description.yaml not found in: {cab_dir}", file=sys.stderr)
        return 3

    data = yaml.safe_load(desc.read_text(encoding="utf-8", errors="ignore")) or {}

    style = data.get("style")
    model_doc = data.get("model") or None
    model_file = None
    model_style_ref = None

    if isinstance(model_doc, dict):
        model_file = model_doc.get("file")
        model_style_ref = model_doc.get("style")

    if not model_file:
        glbs = sorted(cab_dir.glob("*.glb"))
        if glbs:
            model_file = glbs[0].name

    # Parse video/attraction settings
    video_doc = data.get("video") or None
    video = None
    if isinstance(video_doc, dict):
        video = {
            "file": video_doc.get("file"),
            "invertx": bool(video_doc.get("invertx", False)),
            "inverty": bool(video_doc.get("inverty", False)),
            "distance": video_doc.get("distance"),  # Attraction video play distance
        }
    
    # Parse attraction audio
    attraction_audio = data.get("attraction-sound") or data.get("attractionsound") or None
    if isinstance(attraction_audio, dict):
        if not video:
            video = {}
        video["attraction_audio"] = {
            "file": attraction_audio.get("file"),
            "volume": attraction_audio.get("volume", 1.0),
        }

    # Parse CRT/screen configuration fully
    crt_doc = data.get("crt") or {}
    crt = {
        "type": crt_doc.get("type", "19i"),
        "orientation": crt_doc.get("orientation", "vertical"),
    }
    
    # Parse screen sub-document for shader/damage settings
    screen_doc = crt_doc.get("screen") or {}
    if screen_doc:
        crt["screen"] = {
            "shader": screen_doc.get("shader", "crt"),
            "damage": screen_doc.get("damage", "low"),
            "invertx": bool(screen_doc.get("invertx", False)),
            "inverty": bool(screen_doc.get("inverty", False)),
            "properties": screen_doc.get("properties"),  # Custom shader properties
        }
    
    # Parse CRT geometry adjustments
    geometry_doc = crt_doc.get("geometry") or {}
    if geometry_doc:
        crt["geometry"] = {
            "scale": geometry_doc.get("scale", 100),
            "rotation": geometry_doc.get("rotation") or {},
        }
    
    coinslot = data.get("coinslot")
    coinslotgeometry = data.get("coinslotgeometry") or {}
    insertcoin = data.get("insertcoin", True)  # Whether to auto-insert coin
    
    # Parse T-Molding configuration
    tmolding_doc = data.get("t-molding") or None
    tmolding = None
    if isinstance(tmolding_doc, dict) and tmolding_doc.get("enabled", False):
        tmolding = {
            "enabled": True,
            "color": tmolding_doc.get("color") or {"r": 26, "g": 26, "b": 26, "name": "Black"},
        }
        led_doc = tmolding_doc.get("led") or None
        if isinstance(led_doc, dict) and led_doc.get("enabled", False):
            tmolding["led"] = {
                "enabled": True,
                "animation": led_doc.get("animation", "pulse"),
                "speed": float(led_doc.get("speed", 1.0)),
            }
    
    # Parse controllers configuration
    controllers_doc = data.get("controllers") or {}
    controllers = None
    if controllers_doc:
        controllers = {
            "control_scheme": controllers_doc.get("control-scheme"),
            "device": controllers_doc.get("device"),
            "player1": controllers_doc.get("player1") or {},
            "player2": controllers_doc.get("player2") or {},
        }
    
    # Parse light gun configuration
    lightgun_doc = data.get("lightgun") or {}
    lightgun = None
    if lightgun_doc:
        lightgun = {
            "model_file": lightgun_doc.get("model"),
            "sight": lightgun_doc.get("sight") or {},
            "screen_adjust": lightgun_doc.get("screen") or {},
        }

    # Parse parts with full Age of Joy CDL support
    parts_out = []
    interactive_elements = []  # Track interactive elements for VisionOS
    
    for p in data.get("parts") or []:
        if not isinstance(p, dict):
            continue
        name = (p.get("name") or "").strip()
        if not name:
            continue

        part_type = (p.get("type") or "default").strip().lower()
        art = p.get("art") or None
        color = p.get("color") or None
        material = p.get("material") or None
        visibility = p.get("visibility", True)
        physical = p.get("physical", False)
        
        # Parse emission settings
        emission_doc = p.get("emission") or None
        emission = None
        if isinstance(emission_doc, dict):
            emission = {
                "enabled": True,
                "color": emission_doc.get("color"),
                "strength": emission_doc.get("strength", 1.0),
                "mask_file": emission_doc.get("mask"),  # Emission mask texture
            }
        
        # Parse audio configuration for speaker parts
        audio_doc = p.get("audio") or None
        audio = None
        if isinstance(audio_doc, dict):
            audio = {
                "file": audio_doc.get("file"),
                "volume": float(audio_doc.get("volume", 1.0)),
                "loop": bool(audio_doc.get("loop", False)),
                "min_distance": float(audio_doc.get("min-distance", 1.0)),
                "max_distance": float(audio_doc.get("max-distance", 5.0)),
            }

        art_out = None
        if isinstance(art, dict):
            art_out = {
                "file": art.get("file"),
                "invertx": bool(art.get("invertx", False)),
                "inverty": bool(art.get("inverty", False)),
                "rotate": art.get("rotate", 0),
            }

        # Parse marquee illumination settings
        marquee_out = None
        illumination_type = p.get("illumination-type")
        if part_type == "marquee" or illumination_type:
            marquee_out = {
                "illumination_type": illumination_type or "two-tubes",
                "color": color,  # Light color for marquee
            }

        part_entry = {
            "name": name,
            "type": part_type,
            "art": art_out,
            "color": color,
            "material": material,
            "marquee": marquee_out,
            "visibility": visibility,
            "physical": physical,
            "emission": emission,
            "audio": audio,
        }
        parts_out.append(part_entry)
        
        # Track interactive elements for VisionOS
        name_lower = name.lower()
        if any(x in name_lower for x in ["joystick", "button", "stick", "trigger", "pedal", "wheel", "shifter"]):
            interactive_elements.append({
                "name": name,
                "type": "control",
                "interaction": "tap" if "button" in name_lower else "drag",
                "physical": physical,
            })
        elif "coin" in name_lower:
            interactive_elements.append({
                "name": name,
                "type": "coinslot",
                "interaction": "tap",
            })
        elif name_lower == "screen" or part_type == "screen":
            interactive_elements.append({
                "name": name,
                "type": "screen",
                "interaction": "gaze",
                "touch_enabled": True,
            })

    # Build RealityKit contract with enhanced interaction data
    rk_contract = {
        "version": "1.2",
        "screen_node_name": "screen",
        "marquee_node_name": "marquee",
        "coinslot_node_name": "coinslot",
        "tmolding_node_name": "t-molding" if tmolding else None,
        "screen_capabilities": {
            "video_playback": True,
            "render_target": True,
            "touch_input": True,
            "gaze_input": True,
            "spatial_input": True,
            "orientation": crt.get("orientation", "vertical"),
            "shader_type": crt.get("screen", {}).get("shader", "crt"),
        },
        "interactive_elements": interactive_elements,
        "led_effects": tmolding.get("led") if tmolding else None,
        "interaction_modes": ["video", "emulator", "web"],
        "controllers": controllers,
        "lightgun": lightgun,
    }

    job = {
        "cabinet_name": data.get("name") or cab_dir.name,
        "game": data.get("game"),
        "year": data.get("year"),
        "rom": data.get("rom"),
        "md5sum": data.get("md5sum"),
        "timetoload": data.get("timetoload"),
        "cabinet_author": data.get("cabinet author"),
        "material_root": data.get("material"),
        "style": style,
        "model": {"file": model_file, "style_ref": model_style_ref} if model_file else None,
        "video": video,
        "crt": crt,
        "coinslot": coinslot,
        "coinslotgeometry": coinslotgeometry,
        "insertcoin": insertcoin,
        "parts": parts_out,
        "t-molding": tmolding,
        "controllers": controllers,
        "lightgun": lightgun,
        "rk_contract": rk_contract,
    }

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(job, indent=2), encoding="utf-8")
    print(f"OK: wrote {out_json}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
"""
    
    static let blenderExportScript = """
import bpy
import json
import os
import sys
from pathlib import Path

def log(msg): print(msg, flush=True)

def argv_after_double_dash():
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1:]
    return []

def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def get_obj(name):
    return bpy.data.objects.get(name)

def find_first_contains(substr):
    s = substr.lower()
    for obj in bpy.data.objects:
        if obj.type == "MESH" and s in obj.name.lower():
            return obj
    return None

def safe_rename(obj, new_name):
    if not obj or obj.name == new_name:
        return
    base = new_name
    i = 1
    while bpy.data.objects.get(new_name) is not None:
        new_name = f"{base}.{i:03d}"
        i += 1
    obj.name = new_name

def ensure_root_parent():
    # Look for existing root parent (cabinet-root or cabinet_root)
    root = bpy.data.objects.get("cabinet-root") or bpy.data.objects.get("cabinet_root")
    
    if root is None:
        # No root exists - create one and parent orphan meshes to it
        root = bpy.data.objects.new("cabinet_root", None)
        bpy.context.scene.collection.objects.link(root)
        
        # Only parent objects that don't already have a parent
        for obj in bpy.context.scene.objects:
            if obj.type == "MESH" and obj.parent is None:
                # Use matrix_parent_inverse to preserve world transform
                obj.parent = root
                obj.matrix_parent_inverse = root.matrix_world.inverted()
    else:
        # Root exists - rename to standard name if needed
        if root.name == "cabinet-root":
            root.name = "cabinet_root"
    
    return root

def normalize_names_for_realitykit(job):
    m = get_obj("marquee") or find_first_contains("marquee")
    if m: safe_rename(m, "marquee")

    b = get_obj("bezel") or find_first_contains("bezel")
    if b: safe_rename(b, "bezel")

    j = get_obj("joystick") or find_first_contains("joystick")
    if j: safe_rename(j, "joystick")

    cs = get_obj("coin-slot") or find_first_contains("coin-slot") or find_first_contains("coinslot")
    if cs: safe_rename(cs, "coinslot")

    crt = job.get("crt") or {}
    orientation = (crt.get("orientation") or "").lower()

    screen = None
    if orientation.startswith("vert"):
        screen = get_obj("screen-mock-vertical") or find_first_contains("screen-mock-vertical")
    elif orientation.startswith("horiz"):
        screen = get_obj("screen-mock-horizontal") or find_first_contains("screen-mock-horizontal")

    if screen is None:
        screen = get_obj("screen-base") or find_first_contains("screen-base")
    if screen is None:
        screen = get_obj("screen") or find_first_contains("screen")
    if screen:
        safe_rename(screen, "screen")

    ensure_root_parent()

# Part name aliases for flexible matching
# Each key is the template part name, values are possible mesh names in GLB models
# IMPORTANT: Use exact names where possible; substring matching can cause false positives
PART_ALIASES = {
    # Side panels
    "left": ["left", "side-left", "sideleft", "left-side", "leftside", "side_left", "left_side", "l-side", "lside", "sidepanel-left", "panel-left", "sideart"],
    "right": ["right", "side-right", "sideright", "right-side", "rightside", "side_right", "right_side", "r-side", "rside", "sidepanel-right", "panel-right"],
    "left-inside": ["left-inside", "leftinside", "left_inside", "inside-left", "insideleft", "inner-left", "innerleft"],
    "right-inside": ["right-inside", "rightinside", "right_inside", "inside-right", "insideright", "inner-right", "innerright"],
    # Front panels
    "front": ["front", "front-panel", "frontpanel", "front_panel", "artfront"],
    "front-kick": ["front-kick", "frontkick", "kick", "kickplate", "kick-plate", "front_kick", "kick_panel", "lower-front"],
    "front-lower": ["front-lower", "frontlower", "front_lower", "lower-panel", "lowerpanel", "holster-panel"],
    "front-upper": ["front-upper", "frontupper", "front_upper", "upper-panel", "upperpanel"],
    # Back/Top/Bottom panels
    "back": ["back", "rear", "back-panel", "backpanel", "rear-panel", "rearpanel", "back_panel", "rear_panel", "back-door", "backdoor", "cabinet-frame", "cabinet-body"],
    "top": ["top", "top-panel", "toppanel", "cap", "top_panel", "ceiling", "roof", "topcap", "top-cap", "cabinet-top"],
    "bottom": ["bottom", "bottom-panel", "bottompanel", "bottom_panel", "floor", "underside", "cabinet-base", "cabinet-bottom", "base"],
    # Marquee
    "marquee": ["marquee", "marq", "header", "topper", "sign", "marquee-panel", "marqueepanel", "marquee-art", "marquee_art"],
    "marquee-box": ["marquee-box", "marqueebox", "marquee_box", "header-box", "headerbox", "marquee-housing", "marqueehousing", "marquee-frame", "marqueeframe"],
    # Screen/Bezel
    "bezel": ["bezel", "monitor-bezel", "monitorbezel", "screen-bezel", "screenbezel", "monitor_bezel", "screen_bezel", "monitor-frame", "inner-bezel", "innerbezel", "glass", "top-glass"],
    "bezel-back": ["bezel-back", "bezelback", "bezel_back", "bezel-backing", "bezel-rear", "screen-backing", "bezel-back-transp"],
    "bezel-back-back": ["bezel-back-back", "bezelbackback", "bezel_back_back", "bezel-backing-back"],
    "bezel-upper": ["bezel-upper", "bezelupper", "bezel_upper", "upper-bezel", "upperbezel", "bezel-top"],
    "bezel-left": ["bezel-left", "bezelleft", "bezel_left", "bezel-inside-left", "bezel-side-left"],
    "bezel-right": ["bezel-right", "bezelright", "bezel_right", "bezel-inside-right", "bezel-side-right"],
    "bezel-front-left": ["bezel-front-left", "bezelfrontleft", "bezel_front_left"],
    "bezel-front-right": ["bezel-front-right", "bezelfrontright", "bezel_front_right"],
    "bezel-inside": ["bezel-inside", "bezelinside", "bezel_inside"],
    "screen": ["screen", "monitor", "display", "crt", "screen-base", "screenbase", "screen_base"],
    # Control panels
    "cp-shell": ["cp-shell", "cpshell", "control-panel-shell", "controlpanelshell", "cp_shell", "cp-housing", "cphousing", "control_shell", "control-housing"],
    "joystick": ["joystick", "control-panel", "controlpanel", "controls", "cp-overlay", "cpoverlay", "control_panel", "cp_overlay", "deck", "control-deck", "controldeck", "joystick1"],
    "joystick-down": ["joystick-down", "joystickdown", "joystick_down", "cp-underside", "control-underside", "deck-bottom", "cp-bottom", "control-panel-underside", "joystick-below"],
    "joystick-down-1": ["joystick-down-1", "joystickdown1", "joystick_down_1", "cp-underside-1", "joystick-down1"],
    "joystick-down-2": ["joystick-down-2", "joystickdown2", "joystick_down_2", "cp-underside-2", "joystick-down2"],
    "joystick-up": ["joystick-up", "joystickup", "joystick_up", "cp-top", "control-top", "deck-top"],
    "joystick-upper": ["joystick-upper", "joystickupper", "joystick_upper", "cp-upper", "control-upper"],
    "joystick-2": ["joystick-2", "joystick2", "joystick_2", "control-panel-2", "player2-control", "p2-control"],
    # Coin/Speaker
    "coin-door": ["coin-door", "coindoor", "coinslot", "coin-slot", "coin_door", "coin_slot", "coin-panel", "coinpanel", "coinmech"],
    "speaker": ["speaker", "speaker-panel", "speakerpanel", "speaker_panel", "speaker-grill", "speakergrill", "audio-panel", "audio"],
    # T-Molding
    "t-molding": ["t-molding", "tmolding", "t_molding", "molding", "trim", "edge-trim", "edgetrim", "t-mold", "tmold", "edge-strip"],
    # Light gun specific
    "gun": ["gun", "gun-left", "gun-1", "gun1", "pistol", "pistol-left", "lightgun"],
    "gun2": ["gun2", "gun-right", "gun-2", "pistol-right", "lightgun2"],
    "pedal": ["pedal", "foot-pedal", "footpedal", "reload-pedal"],
    "gun-shelf": ["gun-shelf", "gunshelf", "gun_shelf", "holster-shelf"],
    # Driving cabinet specific
    "dashboard": ["dashboard", "dash", "instruments", "gauges", "instrument-panel", "speedometer"],
    "steering-wheel": ["steering-wheel", "steeringwheel", "steering_wheel", "wheel"],
    "steering-column": ["steering-column", "steeringcolumn", "steering_column", "column"],
    "gear-shifter": ["gear-shifter", "gearshifter", "gear_shifter", "shifter", "transmission"],
    "seat": ["seat", "bucket-seat", "bucketseat", "chair", "racing-seat"],
    "gas-pedal": ["gas-pedal", "gaspedal", "gas_pedal", "accelerator", "gas"],
    "brake-pedal": ["brake-pedal", "brakepedal", "brake_pedal", "brake"],
}

# Mesh names to exclude from generic matching (these are special purpose meshes)
MESH_EXCLUSIONS = {
    "screen-base", "screenbase", "screen_base", "screen-mock-vertical", "screen-mock-horizontal",
    "screen.001", "buttons", "sticks", "cabinet-root", "leg-1", "leg-2", "leg-3", "leg-4"
}

# Parts that should only match exactly (no substring matching)
EXACT_MATCH_PARTS = {"marquee", "bezel", "screen", "gun", "gun2", "front", "seat", "dashboard"}

def find_objects_for_part(part_name):
    pn = part_name.lower()
    hits = []
    
    # Get all possible aliases for this part
    aliases = PART_ALIASES.get(pn, [pn])
    # Also add the original name if not already included
    if pn not in aliases:
        aliases = [pn] + list(aliases)
    
    # Check if this part requires exact matching only
    exact_only = pn in EXACT_MATCH_PARTS
    
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        n = obj.name.lower()
        
        # Skip excluded meshes
        if n in MESH_EXCLUSIONS:
            continue
        
        # Check against all aliases
        matched = False
        for alias in aliases:
            # Exact match - always check
            if n == alias:
                matched = True
                break
            
            # For non-exact-match parts, also check substrings
            if not exact_only:
                # Alias contained in mesh name (e.g., "front" in "front-kick")
                # But avoid matching "marquee" in "marquee-box"
                if alias in n and not any(n.startswith(alias + "-") or n.startswith(alias + "_") for _ in [1]):
                    # Additional check: don't match if mesh name is a more specific version
                    if not (n.replace(alias, "").strip("-_") and n.startswith(alias)):
                        matched = True
                        break
                # Mesh name exactly equals an alias
                elif n == alias:
                    matched = True
                    break
        
        if matched and obj not in hits:
            hits.append(obj)
    
    return hits

def ensure_material(obj, mat_name, preserve_existing=False):
    # If preserve_existing is True and object has materials with textures, keep them
    if preserve_existing and obj.data.materials:
        # Check if any existing material has an image texture
        for mat in obj.data.materials:
            if mat and mat.use_nodes:
                for node in mat.node_tree.nodes:
                    if node.type == 'TEX_IMAGE' and node.image:
                        log(f"  Preserving existing material with embedded texture: {mat.name}")
                        return None  # Signal to skip material assignment
    
    # Clear any existing materials
    obj.data.materials.clear()
    
    # Create a new material with a unique name
    mat = bpy.data.materials.new(name=mat_name)
    obj.data.materials.append(mat)
    return mat

def set_blend_for_bezel(mat):
    try:
        mat.use_nodes = True
    except: pass
    try:
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
    except: pass
    try:
        if hasattr(mat, "shadow_method"):
            mat.shadow_method = "HASHED"
    except: pass

def material_preset(name):
    n = (name or "").lower()
    if n == "black": return (0.05, 0.05, 0.05), 0.7
    if n == "plastic": return (0.12, 0.12, 0.12), 0.35
    if n == "lightwood": return (0.65, 0.55, 0.40), 0.65
    if n == "darkwood": return (0.22, 0.16, 0.10), 0.7
    return (0.3, 0.3, 0.3), 0.7

def rgb_from_color_doc(cdoc):
    if not isinstance(cdoc, dict):
        return (1, 1, 1), 1.0
    r = float(cdoc.get("r", 255)) / 255.0
    g = float(cdoc.get("g", 255)) / 255.0
    b = float(cdoc.get("b", 255)) / 255.0
    intensity = float(cdoc.get("intensity", 1.0))
    return (r, g, b), intensity

def extract_interactive_elements(job):
    # Extract geometry data for all interactive elements
    from mathutils import Vector
    
    interactive = []
    
    # Define interactive part patterns
    interactive_patterns = {
        "joystick": {"type": "control", "interaction": "drag", "axis": "xy"},
        "joystick-2": {"type": "control", "interaction": "drag", "axis": "xy"},
        "button": {"type": "control", "interaction": "tap"},
        "coin": {"type": "coinslot", "interaction": "tap"},
        "steering": {"type": "control", "interaction": "rotate", "axis": "z"},
        "pedal": {"type": "control", "interaction": "press", "axis": "x"},
        "shifter": {"type": "control", "interaction": "drag", "axis": "y"},
        "trigger": {"type": "control", "interaction": "tap"},
        "trackball": {"type": "control", "interaction": "drag", "axis": "xy"},
        "spinner": {"type": "control", "interaction": "rotate", "axis": "y"},
    }
    
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        
        name_lower = obj.name.lower()
        
        for pattern, config in interactive_patterns.items():
            if pattern in name_lower:
                # Get bounding box center
                bbox_corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
                center = Vector((
                    sum(c.x for c in bbox_corners) / 8,
                    sum(c.y for c in bbox_corners) / 8,
                    sum(c.z for c in bbox_corners) / 8
                ))
                
                interactive.append({
                    "name": obj.name,
                    "type": config["type"],
                    "interaction": config["interaction"],
                    "axis": config.get("axis"),
                    "center": [round(center.x, 6), round(center.y, 6), round(center.z, 6)],
                })
                break
    
    return interactive if interactive else None

def extract_screen_geometry(job):
    # Extract geometry data from screen mesh for VisionOS interaction
    from mathutils import Vector
    
    screen_obj = bpy.data.objects.get("screen")
    if not screen_obj or screen_obj.type != "MESH":
        log("WARN: No screen mesh found for geometry extraction")
        return None
    
    # Ensure mesh data is up to date
    screen_obj.data.update()
    
    # Get world-space bounding box corners
    bbox_corners = [screen_obj.matrix_world @ Vector(corner) for corner in screen_obj.bound_box]
    
    # Calculate min/max bounds
    min_corner = Vector((
        min(c.x for c in bbox_corners),
        min(c.y for c in bbox_corners),
        min(c.z for c in bbox_corners)
    ))
    max_corner = Vector((
        max(c.x for c in bbox_corners),
        max(c.y for c in bbox_corners),
        max(c.z for c in bbox_corners)
    ))
    
    # Calculate center point
    center = (min_corner + max_corner) / 2
    
    # Calculate dimensions
    dimensions = max_corner - min_corner
    
    # Calculate average face normal in world space
    mesh = screen_obj.data
    normal = Vector((0, 0, 0))
    if mesh.polygons:
        for poly in mesh.polygons:
            normal += poly.normal
        normal.normalize()
        # Transform normal to world space
        normal = (screen_obj.matrix_world.to_3x3() @ normal).normalized()
    else:
        normal = Vector((0, 0, 1))  # Default forward
    
    # Get world transform matrix as list of lists
    transform = [[screen_obj.matrix_world[i][j] for j in range(4)] for i in range(4)]
    
    # Determine width and height based on orientation
    # Typically screen faces Z axis, so width is X, height is Y
    width = abs(dimensions.x)
    height = abs(dimensions.y)
    depth = abs(dimensions.z)
    
    # If the screen is rotated, we may need to swap
    if depth > width:
        width, depth = depth, width
    if depth > height:
        height, depth = depth, height
    
    # Calculate aspect ratio
    aspect_ratio = width / height if height > 0.001 else 1.0
    
    # Get CRT orientation from job
    crt = job.get("crt") or {}
    orientation = (crt.get("orientation") or "vertical").lower()
    if orientation.startswith("horiz"):
        orientation = "horizontal"
    else:
        orientation = "vertical"
    
    # Get CRT configuration from job
    crt_config = job.get("crt") or {}
    screen_config = crt_config.get("screen") or {}
    
    screen_data = {
        "bounds": {
            "min": [round(min_corner.x, 6), round(min_corner.y, 6), round(min_corner.z, 6)],
            "max": [round(max_corner.x, 6), round(max_corner.y, 6), round(max_corner.z, 6)]
        },
        "center": [round(center.x, 6), round(center.y, 6), round(center.z, 6)],
        "dimensions": {
            "width": round(width, 6),
            "height": round(height, 6),
            "depth": round(depth, 6)
        },
        "normal": [round(normal.x, 6), round(normal.y, 6), round(normal.z, 6)],
        "transform": [[round(v, 6) for v in row] for row in transform],
        "aspect_ratio": round(aspect_ratio, 4),
        "orientation": orientation,
        "interactive": True,
        "node_name": "screen",
        # CRT configuration from YAML
        "crt": {
            "type": crt_config.get("type", "19i"),
            "shader": screen_config.get("shader", "crt"),
            "damage": screen_config.get("damage", "low"),
            "invertx": screen_config.get("invertx", False),
            "inverty": screen_config.get("inverty", False),
        },
        # VisionOS interaction capabilities
        "capabilities": {
            "video_playback": True,
            "touch_input": True,
            "gaze_input": True,
            "spatial_input": True,
        }
    }
    
    log(f"Screen geometry extracted: center={screen_data['center']}, dimensions={screen_data['dimensions']}")
    log(f"CRT config: type={screen_data['crt']['type']}, orientation={orientation}")
    return screen_data

def usd_export_safe(filepath):
    op = bpy.ops.wm.usd_export
    props = {"filepath": filepath}
    try:
        rna = op.get_rna_type()
        prop_names = set(rna.properties.keys())
    except:
        prop_names = set()

    candidates = {
        "selected_objects_only": False,
        "visible_objects_only": False,
        "relative_paths": True,
        "export_materials": True,
        "export_textures": True,
        "overwrite_textures": True,
        "export_uvmaps": True,
        "export_normals": True,
        "export_meshes": True,
        "export_lights": True,
        "export_cameras": True,
        "export_animation": False,
        # Axis conversion for iOS/VisionOS (Y-up, -Z forward)
        "convert_orientation": True,
        "export_global_forward_selection": "NEGATIVE_Z",
        "export_global_up_selection": "Y",
    }
    for k, v in candidates.items():
        if k in prop_names:
            props[k] = v

    return op(**props)

def usd_export_with_animation(filepath):
    # Export USDZ with animation support for LED effects
    op = bpy.ops.wm.usd_export
    props = {"filepath": filepath}
    try:
        rna = op.get_rna_type()
        prop_names = set(rna.properties.keys())
    except:
        prop_names = set()

    candidates = {
        "selected_objects_only": False,
        "visible_objects_only": False,
        "relative_paths": True,
        "export_materials": True,
        "export_textures": True,
        "overwrite_textures": True,
        "export_uvmaps": True,
        "export_normals": True,
        "export_meshes": True,
        "export_lights": True,
        # Axis conversion for iOS/VisionOS (Y-up, -Z forward)
        "convert_orientation": True,
        "export_global_forward_selection": "NEGATIVE_Z",
        "export_global_up_selection": "Y",
        "export_cameras": True,
        "export_animation": True,  # Enable animation export for LED effects
    }
    for k, v in candidates.items():
        if k in prop_names:
            props[k] = v

    return op(**props)

def build_material(mat, *, image_path=None, invertx=False, inverty=False, rotate_deg=0,
                   base_rgb=(1,1,1), make_emissive=False, emissive_rgb=(1,1,1),
                   emissive_strength=2.0, use_alpha=False, roughness=0.7):
    # Note: GLB UV origin is at bottom-left, but textures are authored with top-left origin
    # So we need to flip Y by default to display correctly
    # The inverty parameter becomes "don't invert" when True
    inverty = not inverty  # Flip the default behavior
    
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    bsdf.inputs["Base Color"].default_value = (base_rgb[0], base_rgb[1], base_rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = float(roughness)

    tex = None
    if image_path and os.path.exists(image_path):
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(image_path, check_existing=True)

        uv = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")

        sx = -1.0 if invertx else 1.0
        sy = -1.0 if inverty else 1.0
        mapping.inputs["Scale"].default_value = (sx, sy, 1.0)
        mapping.inputs["Location"].default_value = (1.0 if invertx else 0.0, 1.0 if inverty else 0.0, 0.0)
        mapping.inputs["Rotation"].default_value = (0.0, 0.0, rotate_deg * 3.14159265 / 180.0)

        links.new(uv.outputs["UV"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if use_alpha:
            links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])

    if make_emissive:
        bsdf.inputs["Emission Color"].default_value = (emissive_rgb[0], emissive_rgb[1], emissive_rgb[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = float(emissive_strength)
        if tex:
            links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])

def create_tmolding_geometry():
    '''Create T-molding geometry by tracing the front edges of side panels'''
    import bmesh
    from mathutils import Vector
    import math
    
    log("Creating T-molding geometry from side panel profiles...")
    
    # Find all meshes (exclude t-molding itself)
    all_meshes = [obj for obj in bpy.data.objects if obj.type == 'MESH' 
                  and 'mock' not in obj.name.lower() 
                  and 't-mold' not in obj.name.lower()
                  and 'tmold' not in obj.name.lower()]
    if not all_meshes:
        log("WARN: No meshes found to derive T-molding path")
        return None
    
    # Collect all vertices from side panel meshes (or all meshes if no "side" found)
    side_meshes = [obj for obj in all_meshes if 'side' in obj.name.lower()]
    if not side_meshes:
        side_meshes = all_meshes  # Use all meshes if no explicit side panels
    
    all_verts = []
    for obj in side_meshes:
        for v in obj.data.vertices:
            all_verts.append(obj.matrix_world @ v.co)
    
    if not all_verts:
        log("WARN: No vertices found in side meshes")
        return None
    
    # Calculate bounds
    min_x = min(v.x for v in all_verts)
    max_x = max(v.x for v in all_verts)
    min_y = min(v.y for v in all_verts)
    max_y = max(v.y for v in all_verts)
    min_z = min(v.z for v in all_verts)
    max_z = max(v.z for v in all_verts)
    
    log(f"Cabinet bounds: X[{min_x:.2f},{max_x:.2f}] Y[{min_y:.2f},{max_y:.2f}] Z[{min_z:.2f},{max_z:.2f}]")
    
    # T-molding parameters
    radius = 0.008   # 8mm radius tube
    offset = 0.003   # Small offset from surface
    
    # Extract front edge profiles for LEFT and RIGHT sides
    # Front = minimum X, Left = minimum Y, Right = maximum Y
    x_tolerance = 0.05   # Vertices within 5cm of front edge
    y_tolerance = 0.05   # Vertices within 5cm of side edge
    
    def extract_front_profile_by_z(verts, target_y, is_left, z_step=0.05):
        '''Extract front edge profile by sampling at regular Z intervals'''
        # Filter vertices at the target Y edge
        y_tol = y_tolerance
        edge_verts = []
        for v in verts:
            if is_left and v.y < target_y + y_tol:
                edge_verts.append((v.x, v.z))
            elif not is_left and v.y > target_y - y_tol:
                edge_verts.append((v.x, v.z))
        
        if not edge_verts:
            return []
        
        # For each Z height, find the minimum X (front edge)
        profile = []
        z = min_z + 0.01
        while z <= max_z - 0.01:
            # Find all verts near this Z
            nearby = [(x, zv) for x, zv in edge_verts if abs(zv - z) < z_step]
            if nearby:
                # Get minimum X (front edge) at this height
                front_x = min(x for x, zv in nearby)
                profile.append((front_x, z))
            z += z_step
        
        return profile
    
    # Get profiles - sample every 5cm in Z
    left_profile = extract_front_profile_by_z(all_verts, min_y, is_left=True, z_step=0.05)
    right_profile = extract_front_profile_by_z(all_verts, max_y, is_left=False, z_step=0.05)
    
    log(f"Left profile: {len(left_profile)} points, Right profile: {len(right_profile)} points")
    
    # If left profile is incomplete (less than 50% of height covered), mirror the right profile
    if left_profile:
        left_z_range = max(z for x, z in left_profile) - min(z for x, z in left_profile)
    else:
        left_z_range = 0
    
    cabinet_height = max_z - min_z
    if left_z_range < cabinet_height * 0.5 and right_profile:
        log(f"Left profile incomplete (covers {left_z_range:.2f}m), using right profile as reference")
        left_profile = right_profile  # Use same X-Z profile, Y will be different
    
    # If profiles are still empty, create a simple vertical profile
    if not left_profile:
        left_profile = [(min_x, min_z + 0.02), (min_x, max_z - 0.02)]
    if not right_profile:
        right_profile = [(min_x, min_z + 0.02), (min_x, max_z - 0.02)]
    
    # Ensure profiles extend from bottom to near-top of cabinet
    # Add start/end points if needed to cover full height
    def extend_profile(profile, target_min_z, target_max_z):
        if not profile:
            return profile
        
        # Check if profile covers enough of the cabinet height
        profile_min_z = min(z for x, z in profile)
        profile_max_z = max(z for x, z in profile)
        
        extended = list(profile)
        
        # Add bottom point if profile doesn't start low enough
        if profile_min_z > target_min_z + 0.1:
            # Use the X from the lowest existing point
            bottom_x = profile[0][0]
            extended.insert(0, (bottom_x, target_min_z + 0.02))
        
        # Add top point if profile doesn't reach high enough
        if profile_max_z < target_max_z - 0.2:
            # Use the X from the highest existing point
            top_x = profile[-1][0]
            extended.append((top_x, target_max_z - 0.05))
        
        return extended
    
    left_profile = extend_profile(left_profile, min_z, max_z)
    right_profile = extend_profile(right_profile, min_z, max_z)
    
    log(f"Extended profiles: left={len(left_profile)} pts, right={len(right_profile)} pts")
    
    # Build path points for T-molding strips
    # LEFT SIDE: runs along the front-left edge from bottom to top
    left_y = min_y + offset
    left_path = [(x - offset, left_y, z) for x, z in left_profile]
    
    # RIGHT SIDE: runs along the front-right edge from bottom to top
    right_y = max_y - offset
    right_path = [(x - offset, right_y, z) for x, z in right_profile]
    
    log(f"T-molding paths: left={len(left_path)} pts at Y={left_y:.3f}, right={len(right_path)} pts at Y={right_y:.3f}")
    
    # Create mesh
    mesh = bpy.data.meshes.new("t-molding")
    bm = bmesh.new()
    
    def create_tube_segment(p1, p2, r, bm_target):
        '''Create a tube segment between two points'''
        direction = Vector(p2) - Vector(p1)
        length = direction.length
        if length < 0.005:
            return
        
        direction.normalize()
        
        # Create circle profile
        segments = 8
        perp1 = direction.orthogonal().normalized()
        perp2 = direction.cross(perp1).normalized()
        
        start_verts = []
        end_verts = []
        
        for i in range(segments):
            angle = 2.0 * math.pi * i / segments
            off = perp1 * (r * math.cos(angle)) + perp2 * (r * math.sin(angle))
            
            start_pos = Vector(p1) + off
            end_pos = Vector(p2) + off
            
            start_verts.append(bm_target.verts.new(start_pos))
            end_verts.append(bm_target.verts.new(end_pos))
        
        bm_target.verts.ensure_lookup_table()
        
        # Create faces around the tube
        for i in range(segments):
            j = (i + 1) % segments
            try:
                bm_target.faces.new([start_verts[i], start_verts[j], end_verts[j], end_verts[i]])
            except:
                pass  # Face might already exist
    
    # Create tube segments for LEFT side T-molding
    for i in range(len(left_path) - 1):
        create_tube_segment(left_path[i], left_path[i + 1], radius, bm)
    
    # Create tube segments for RIGHT side T-molding
    for i in range(len(right_path) - 1):
        create_tube_segment(right_path[i], right_path[i + 1], radius, bm)
    
    bm.to_mesh(mesh)
    bm.free()
    
    # Create object
    obj = bpy.data.objects.new("t-molding", mesh)
    bpy.context.collection.objects.link(obj)
    
    total_points = len(left_path) + len(right_path)
    log(f"T-molding geometry created: {len(left_path)} left pts + {len(right_path)} right pts")
    return obj

def apply_tmolding(job):
    # Apply T-molding color and LED effects
    tmolding_config = job.get("t-molding")
    if not tmolding_config:
        return
    
    if not tmolding_config.get("enabled", False):
        return
    
    log("Applying T-Molding configuration...")
    
    # Find T-molding mesh(es)
    tmolding_objs = find_objects_for_part("t-molding") or find_objects_for_part("tmolding") or find_objects_for_part("trim")
    
    # If no T-molding mesh exists, create one
    if not tmolding_objs:
        log("No T-molding mesh found in model, generating geometry...")
        created_obj = create_tmolding_geometry()
        if created_obj:
            tmolding_objs = [created_obj]
        else:
            log("WARN: Could not create T-molding geometry, skipping")
            return
    
    # Get color (handle None values)
    color_doc = tmolding_config.get("color") or {}
    r = float(color_doc.get("r", 26)) / 255.0
    g = float(color_doc.get("g", 26)) / 255.0
    b = float(color_doc.get("b", 26)) / 255.0
    base_rgb = (r, g, b)
    
    # Check for LED settings (handle None values)
    led_config = tmolding_config.get("led") or {}
    led_enabled = led_config.get("enabled", False)
    led_animation = led_config.get("animation", "pulse")
    led_speed = float(led_config.get("speed", 1.0))
    
    for obj in tmolding_objs:
        mat = ensure_material(obj, "mat_tmolding")
        mat.use_nodes = True
        nt = mat.node_tree
        nodes = nt.nodes
        links = nt.links
        nodes.clear()
        
        out = nodes.new("ShaderNodeOutputMaterial")
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        
        # Set base color
        bsdf.inputs["Base Color"].default_value = (base_rgb[0], base_rgb[1], base_rgb[2], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.3  # Slightly shiny plastic
        bsdf.inputs["Metallic"].default_value = 0.1
        
        if led_enabled:
            # Make it emissive for LED effect
            bsdf.inputs["Emission Color"].default_value = (base_rgb[0], base_rgb[1], base_rgb[2], 1.0)
            
            # Set up animation for LED effect
            log(f"Creating LED animation: {led_animation} at {led_speed}x speed")
            
            # Configure scene for animation
            scene = bpy.context.scene
            scene.frame_start = 1
            fps = 24
            duration_frames = int(fps * 2.0 / led_speed)  # 2 second base animation
            scene.frame_end = duration_frames
            
            # Animate emission strength based on animation type
            emission_input = bsdf.inputs["Emission Strength"]
            
            if led_animation == "pulse":
                # Breathing/pulse effect - sine wave
                keyframes = [
                    (1, 0.5),
                    (duration_frames // 4, 3.0),
                    (duration_frames // 2, 0.5),
                    (duration_frames * 3 // 4, 3.0),
                    (duration_frames, 0.5),
                ]
            elif led_animation == "flash":
                # Strobe effect - rapid on/off
                keyframes = []
                flash_interval = max(2, duration_frames // 8)
                for i in range(0, duration_frames + 1, flash_interval):
                    on = (i // flash_interval) % 2 == 0
                    keyframes.append((i + 1, 4.0 if on else 0.2))
            elif led_animation == "chase":
                # Chase effect - gradual intensity changes
                keyframes = [
                    (1, 0.2),
                    (duration_frames // 6, 2.0),
                    (duration_frames // 3, 4.0),
                    (duration_frames // 2, 2.0),
                    (duration_frames * 2 // 3, 4.0),
                    (duration_frames * 5 // 6, 2.0),
                    (duration_frames, 0.2),
                ]
            elif led_animation == "rainbow":
                # Rainbow - also animate the emission color hue
                keyframes = [(1, 2.5), (duration_frames, 2.5)]  # Constant strength
                # Animate color through hue
                emission_color = bsdf.inputs["Emission Color"]
                import colorsys
                num_colors = 6
                for i in range(num_colors + 1):
                    frame = 1 + (duration_frames - 1) * i // num_colors
                    hue = i / num_colors
                    r, g, b = colorsys.hsv_to_rgb(hue, 1.0, 1.0)
                    emission_color.default_value = (r, g, b, 1.0)
                    emission_color.keyframe_insert(data_path="default_value", frame=frame)
            else:
                # Default pulse
                keyframes = [
                    (1, 0.5),
                    (duration_frames // 2, 3.0),
                    (duration_frames, 0.5),
                ]
            
            # Apply keyframes
            for frame, value in keyframes:
                emission_input.default_value = value
                emission_input.keyframe_insert(data_path="default_value", frame=frame)
            
            # Make animation loop by setting interpolation
            try:
                if mat.node_tree.animation_data and mat.node_tree.animation_data.action:
                    action = mat.node_tree.animation_data.action
                    # Access fcurves - handle different Blender versions
                    fcurves = getattr(action, 'fcurves', None)
                    if fcurves is None:
                        # Blender 5.x might use different API
                        fcurves = []
                        for fc in bpy.data.actions[action.name].fcurves if hasattr(bpy.data.actions.get(action.name, None), 'fcurves') else []:
                            fcurves.append(fc)
                    
                    for fcurve in fcurves:
                        for kp in fcurve.keyframe_points:
                            kp.interpolation = 'BEZIER'
                        try:
                            fcurve.modifiers.new(type='CYCLES')
                        except:
                            pass  # CYCLES modifier might not be available
            except Exception as e:
                log(f"Note: Could not set animation loop: {e}")
            
            log(f"T-Molding LED animation created with {len(keyframes)} keyframes over {duration_frames} frames")
        else:
            # Static color, slight glow
            bsdf.inputs["Emission Color"].default_value = (base_rgb[0], base_rgb[1], base_rgb[2], 1.0)
            bsdf.inputs["Emission Strength"].default_value = 0.3
        
        log(f"T-Molding applied to {obj.name}: color=({r:.2f}, {g:.2f}, {b:.2f}), LED={led_enabled}")

def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", required=True)
    ap.add_argument("--srcdir", required=True)
    ap.add_argument("--model_library", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--screen_data", required=False, default=None, help="Output path for screen geometry JSON")
    args = ap.parse_args(argv_after_double_dash())

    job_path = Path(args.job).resolve()
    srcdir = Path(args.srcdir).resolve()
    model_lib = Path(args.model_library).resolve()
    out_usdz = Path(args.out).resolve()
    screen_data_path = Path(args.screen_data).resolve() if args.screen_data else None

    job = json.loads(job_path.read_text(encoding="utf-8"))

    clean_scene()

    model_doc = job.get("model") or {}
    style = job.get("style")
    model_path = None

    # Age of Joy recommends using a single base cabinet model and re-skinning it
    # We follow the same approach: use bundled GLB if provided, otherwise use our
    # selected cabinet template
    
    # 0. Check if user selected a specific template via environment variable
    user_template = os.environ.get("CABINET_TEMPLATE_PATH")
    template_dir = None  # Will store the template directory for fallback textures
    
    if user_template:
        template_file = Path(user_template)
        if template_file.exists() and template_file.suffix.lower() == ".glb":
            model_path = template_file.resolve()
            template_dir = template_file.parent  # Store template directory
            log(f"Using user-selected template: {model_path.name}")
            log(f"Template directory for fallbacks: {template_dir}")
    
    # 1. Check if cabinet has a bundled GLB model file (overrides template)
    if not model_path and isinstance(model_doc, dict) and model_doc.get("file"):
        candidate = (srcdir / model_doc["file"]).resolve()
        if candidate.exists():
            model_path = candidate
            log(f"Using cabinet's bundled model: {model_doc['file']}")
    
    # 2. Fall back to Upright template if no template selected and no bundled model
    if not model_path or not model_path.exists():
        log(f"No bundled model, using default Upright cabinet template (style was: {style})")
        
        # Find the Upright template GLB
        # Note: Template paths are now passed via environment or found dynamically
        template_dirs = [
            model_lib.parent / "Resources" / "Templates" / "Upright",
            model_lib.parent.parent / "Resources" / "Templates" / "Upright",
            Path(__file__).parent / "Resources" / "Templates" / "Upright",
            # Check RETROVISION_BASE environment variable for configured workspace
            Path(os.environ.get("RETROVISION_BASE", "")) / "Resources" / "Templates" / "Upright" if os.environ.get("RETROVISION_BASE") else None,
        ]
        template_dirs = [d for d in template_dirs if d is not None]
        
        for tdir in template_dirs:
            if tdir.exists() and tdir.is_dir():
                glb_files = list(tdir.glob("*.glb"))
                if glb_files:
                    model_path = glb_files[0].resolve()
                    template_dir = tdir  # Store for fallback textures
                    log(f"Using default Upright template: {model_path}")
                    log(f"Template directory for fallbacks: {template_dir}")
                    break
    
    if not model_path or not model_path.exists():
        raise RuntimeError(f"Model not found. No GLB in cabinet folder and no template found.")

    log(f"Importing GLB: {model_path}")
    bpy.ops.import_scene.gltf(filepath=str(model_path))

    # Check if model has embedded textures - if so, we should preserve them
    model_has_embedded_textures = False
    for mat in bpy.data.materials:
        if mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == 'TEX_IMAGE' and node.image:
                    model_has_embedded_textures = True
                    break
        if model_has_embedded_textures:
            break
    
    if model_has_embedded_textures:
        # Count embedded textures for logging
        tex_count = sum(1 for img in bpy.data.images if img.packed_file or not img.filepath)
        log(f"Model has {tex_count} embedded textures - will preserve materials when external textures are missing")

    normalize_names_for_realitykit(job)
    
    # Extract screen geometry for VisionOS interaction
    screen_geometry = extract_screen_geometry(job)
    
    # Extract interactive elements (joysticks, buttons, etc.)
    interactive_elements = extract_interactive_elements(job)
    
    if screen_data_path:
        screen_data_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Combine all VisionOS metadata
        visionos_metadata = {
            "screen": screen_geometry,
            "interactive_elements": interactive_elements,
            "rk_contract": job.get("rk_contract"),
            "cabinet_info": {
                "name": job.get("cabinet_name"),
                "game": job.get("game"),
                "year": job.get("year"),
                "rom": job.get("rom"),
            },
            "controllers": job.get("controllers"),
            "lightgun": job.get("lightgun"),
        }
        
        screen_data_path.write_text(json.dumps(visionos_metadata, indent=2), encoding="utf-8")
        log(f"VisionOS metadata saved to: {screen_data_path}")
        if interactive_elements:
            log(f"Found {len(interactive_elements)} interactive elements")

    root_rgb, root_rough = material_preset(job.get("material_root"))

    # Log available mesh names for debugging
    available_meshes = [obj.name for obj in bpy.data.objects if obj.type == "MESH"]
    log(f"Available meshes in model: {available_meshes}")

    parts_list = job.get("parts") or []
    log(f"Processing {len(parts_list)} parts from job...")
    
    for p in parts_list:
        pname = p.get("name")
        if not pname:
            log("WARN: Part has no name, skipping")
            continue
        ptype = (p.get("type") or "default").lower()
        
        log(f"Processing part: '{pname}' (type={ptype})")

        objs = find_objects_for_part(pname)
        if not objs:
            aliases = PART_ALIASES.get(pname.lower(), [pname])
            log(f"WARN: no mesh matched part '{pname}' (tried aliases: {aliases})")
            continue
        
        log(f"  Found {len(objs)} mesh(es) for '{pname}'")

        base_rgb, rough = root_rgb, root_rough
        if p.get("material"):
            base_rgb, rough = material_preset(p["material"])

        if p.get("color"):
            c_rgb, intensity = rgb_from_color_doc(p["color"])
            mul = max(0.0, 1.0 + (float(intensity) * 0.15))
            base_rgb = (c_rgb[0] * mul, c_rgb[1] * mul, c_rgb[2] * mul)

        art = p.get("art") or {}
        img_file = art.get("file") if isinstance(art, dict) else None
        img_path = str((srcdir / img_file).resolve()) if img_file else None
        
        # Try fallback textures from template's DefaultArt folder or shared assets
        def find_fallback_texture(part_name):
            # Look for fallback texture in template's DefaultArt folder or shared assets
            search_dirs = []
            
            # 1. Template's DefaultArt folder (highest priority)
            if template_dir:
                default_art_dir = template_dir / "DefaultArt"
                if default_art_dir.exists():
                    search_dirs.append(default_art_dir)
            
            # 2. Shared assets folder (for generic parts like coin door)
            shared_dirs = [
                Path(os.environ.get("RETROVISION_BASE", "")) / "Resources" / "SharedAssets" / "CoinDoor" if os.environ.get("RETROVISION_BASE") else None,
                model_lib.parent / "Resources" / "SharedAssets" / "CoinDoor" if model_lib else None,
            ]
            shared_dirs = [d for d in shared_dirs if d is not None]
            for sd in shared_dirs:
                if sd and sd.exists():
                    search_dirs.append(sd)
                    break
            
            for search_dir in search_dirs:
                # Try exact match first (e.g., "left.png", "CD-25c.png")
                for ext in [".png", ".jpg", ".jpeg"]:
                    candidate = search_dir / f"{part_name}{ext}"
                    if candidate.exists():
                        return str(candidate)
                
                # Try lowercase
                part_lower = part_name.lower()
                for ext in [".png", ".jpg", ".jpeg"]:
                    candidate = search_dir / f"{part_lower}{ext}"
                    if candidate.exists():
                        return str(candidate)
            
            return None
        
        # Track whether to preserve existing embedded textures
        preserve_existing = False
        
        if img_path:
            if os.path.exists(img_path):
                log(f"  Applying texture: {img_file}")
            else:
                log(f"  WARN: Texture file not found: {img_path}")
                # Try fallback texture
                fallback = find_fallback_texture(pname)
                if fallback:
                    img_path = fallback
                    log(f"  Using fallback texture: {fallback}")
                else:
                    # No fallback - if model has embedded textures, skip this part
                    img_path = None
                    if model_has_embedded_textures:
                        log(f"  Skipping - model has embedded textures")
                        continue  # Skip to next part
                    else:
                        log(f"  Using base color (no texture)")
        else:
            # No texture specified - try fallback
            fallback = find_fallback_texture(pname)
            if fallback:
                img_path = fallback
                log(f"  Using fallback texture: {fallback}")
            else:
                # If model has embedded textures, skip material modification
                if model_has_embedded_textures:
                    log(f"  Skipping - model has embedded textures")
                    continue  # Skip to next part
                else:
                    log(f"  Using base color (no texture)")

        invertx = bool(art.get("invertx", False)) if isinstance(art, dict) else False
        inverty = bool(art.get("inverty", False)) if isinstance(art, dict) else False
        rotate = float(art.get("rotate", 0) or 0) if isinstance(art, dict) else 0

        # Handle marquee illumination based on CDL specification
        make_emissive = (ptype == "marquee") or (pname.lower() == "marquee")
        emissive_rgb = base_rgb
        emissive_strength = 2.5
        
        # Parse marquee illumination type from YAML
        marquee_config = p.get("marquee") or {}
        illumination_type = marquee_config.get("illumination_type", "two-tubes")
        
        if make_emissive:
            # Adjust emissive strength based on illumination type
            # Reference: Age of Joy CDL - illumination-type options
            if illumination_type == "none":
                make_emissive = False
                emissive_strength = 0
            elif illumination_type == "lamp":
                # Single incandescent lamp - warm, dimmer
                emissive_strength = 1.5
                emissive_rgb = (1.0, 0.9, 0.7)  # Warm yellow
            elif illumination_type == "two-lamps":
                # Two incandescent lamps - warmer, brighter
                emissive_strength = 2.0
                emissive_rgb = (1.0, 0.92, 0.75)  # Warm yellow
            elif illumination_type == "tube":
                # Single fluorescent tube - cooler, white
                emissive_strength = 2.5
                emissive_rgb = (0.95, 0.98, 1.0)  # Cool white
            else:  # "two-tubes" default
                # Two fluorescent tubes - brightest, cool white
                emissive_strength = 3.0
                emissive_rgb = (0.97, 0.99, 1.0)  # Bright cool white
            
            # Override with custom color if specified in YAML
            if p.get("color"):
                c_rgb, intensity = rgb_from_color_doc(p["color"])
                emissive_rgb = c_rgb
                # Intensity can be negative to darken
                emissive_strength = max(0.5, emissive_strength + float(intensity) * 0.5)
            
            log(f"  Marquee illumination: {illumination_type}, strength={emissive_strength:.1f}")

        use_alpha = ptype == "bezel"

        for obj in objs:
            # If no texture and preserve_existing, check for embedded textures
            mat = ensure_material(obj, f"mat_{pname}", preserve_existing=preserve_existing and not img_path)
            
            if mat is None:
                # Material was preserved (has embedded texture)
                log(f"  Kept existing material for {obj.name}")
                continue
            
            if use_alpha:
                set_blend_for_bezel(mat)

            build_material(
                mat,
                image_path=img_path,
                invertx=invertx,
                inverty=inverty,
                rotate_deg=rotate,
                base_rgb=base_rgb,
                make_emissive=make_emissive,
                emissive_rgb=emissive_rgb,
                emissive_strength=emissive_strength,
                use_alpha=use_alpha,
                roughness=rough
            )
            log(f"  Applied material to {obj.name}")
    
    log(f"Finished processing {len(parts_list)} parts")
    
    # Apply black material to any unmapped meshes (but preserve embedded textures)
    processed_meshes = set()
    for p in parts_list:
        pname = p.get("name")
        if pname:
            for obj in find_objects_for_part(pname):
                processed_meshes.add(obj.name)
    
    black_mat = None
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name not in processed_meshes:
            # Skip screen mocks
            if "mock" in obj.name.lower() or "screen" in obj.name.lower():
                continue
            
            # Skip meshes that have embedded textures
            has_embedded_tex = False
            for mat in obj.data.materials:
                if mat and mat.use_nodes:
                    for node in mat.node_tree.nodes:
                        if node.type == 'TEX_IMAGE' and node.image:
                            has_embedded_tex = True
                            break
                if has_embedded_tex:
                    break
            
            if has_embedded_tex:
                log(f"  Preserving embedded textures for: {obj.name}")
                continue
            
            if not black_mat:
                black_mat = bpy.data.materials.new("black_default")
                black_mat.use_nodes = True
                bsdf = black_mat.node_tree.nodes["Principled BSDF"]
                bsdf.inputs["Base Color"].default_value = (0.02, 0.02, 0.02, 1.0)
                bsdf.inputs["Roughness"].default_value = 0.8
            obj.data.materials.clear()
            obj.data.materials.append(black_mat)
            log(f"  Applied black to unmapped mesh: {obj.name}")

    # Apply T-Molding configuration (color and LED effects)
    apply_tmolding(job)
    
    # Check if we need animation export (for LED effects)
    tmolding_config = job.get("t-molding") or {}
    led_config = tmolding_config.get("led") or {}
    has_animation = tmolding_config.get("enabled", False) and led_config.get("enabled", False)

    out_usdz.parent.mkdir(parents=True, exist_ok=True)
    log(f"Exporting USDZ: {out_usdz}")
    
    if has_animation:
        log("Exporting with LED animation...")
        usd_export_with_animation(str(out_usdz))
    else:
        usd_export_safe(str(out_usdz))
    
    log("DONE")

if __name__ == "__main__":
    main()
"""
}
