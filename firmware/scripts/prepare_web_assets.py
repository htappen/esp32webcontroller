Import("env")

from pathlib import Path
import subprocess
from SCons.Script import COMMAND_LINE_TARGETS


def prepare_web_assets():
    if "clean" in COMMAND_LINE_TARGETS:
        return

    project_dir = Path(env["PROJECT_DIR"]).resolve()
    root_dir = project_dir.parent
    script_path = root_dir / "tools" / "sync_web_assets.sh"

    print("[pio] preparing web assets")
    subprocess.run([str(script_path)], check=True, cwd=root_dir)

prepare_web_assets()
