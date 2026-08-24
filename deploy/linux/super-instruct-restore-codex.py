#!/usr/bin/env python3
import json
import os
import shutil
from pathlib import Path


def codex_home() -> Path:
    configured = os.environ.get("CODEX_HOME")
    if configured:
        return Path(configured)
    return Path(os.environ.get("HOME", "~")).expanduser() / ".codex"


def main() -> None:
    home = codex_home()
    config = home / "config.toml"
    backup = home / "config.toml.super-instruct-bak"
    bridge = home / "bridge.md"
    manifest = home / "super-instruct-skills-deployed.json"
    skills_dir = home / "skills"
    skills_backup = home / "super-instruct-skills-backup"

    if backup.is_file():
        shutil.copy2(backup, config)
        backup.unlink()
        print(f"restored {config}")

    bridge.unlink(missing_ok=True)

    deployed = []
    if manifest.is_file():
        try:
            value = json.loads(manifest.read_text())
            if isinstance(value, list):
                deployed = [item for item in value if isinstance(item, str)]
        except (OSError, json.JSONDecodeError):
            pass

    for skill_id in deployed:
        target = skills_dir / skill_id
        backup_skill = skills_backup / skill_id
        if target.is_dir():
            shutil.rmtree(target)
        if backup_skill.is_dir():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(backup_skill, target)

    if skills_backup.is_dir():
        shutil.rmtree(skills_backup)
    manifest.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
