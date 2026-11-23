"""Keep the exact names of the XCUITest screenshot attachments in the result bundle."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

LANGUAGES = ("en", "zh-Hans", "zh-Hant")
SCENES = ("01-tonight", "02-menu", "03-logged", "04-widget-preview", "05-share")
REQUIRED = {f"store-{language}-{scene}.png" for language in LANGUAGES for scene in SCENES}
REQUIRED.add("paid-01-paywall.png")
NAME = re.compile(r"^(store-(?:en|zh-Hans|zh-Hant)-\d{2}-[a-z-]+|paid-01-paywall)(?=[_.]|$)")


def copy_named_screenshots(exported, output):
    exported = exported.resolve()
    manifest = json.loads((exported / "manifest.json").read_text(encoding="utf-8"))
    paths = {}
    for test in manifest:
        for attachment in test.get("attachments", []):
            match = NAME.match(attachment.get("suggestedHumanReadableName", ""))
            file = attachment.get("exportedFileName", "")
            if not match or not file.lower().endswith(".png"):
                continue
            filename = match[1] + ".png"
            if filename not in REQUIRED:
                continue
            source = (exported / file).resolve()
            if not source.is_relative_to(exported):
                raise ValueError(f"Screenshot attachment is outside the export folder: {file}")
            if not source.is_file():
                raise FileNotFoundError(source)
            if filename in paths:
                raise ValueError(f"Multiple attachments use {filename}")
            paths[filename] = source

    missing = REQUIRED - paths.keys()
    if missing:
        raise ValueError("Missing screenshot attachments: " + ", ".join(sorted(missing)))
    output.mkdir(parents=True, exist_ok=True)
    for filename, source in paths.items():
        target = output / filename
        if target.resolve() != source:
            shutil.copy2(source, target)
    return len(paths)


def export(result, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    # Keep xcresult's original names separate so stale shots cannot mask a missing attachment.
    from tempfile import TemporaryDirectory
    with TemporaryDirectory(dir=output.parent) as directory:
        raw = Path(directory)
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", result,
                        "--output-path", str(raw)], check=True)
        count = copy_named_screenshots(raw, output)
        print(f"Exported {count} named screenshots to {output}.")


if __name__ == "__main__":
    export(sys.argv[1], Path(sys.argv[2]))
