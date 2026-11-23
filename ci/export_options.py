"""Render main-app and widget signing options without reading credentials."""
import os
from pathlib import Path
import plistlib
import sys

data = plistlib.loads(Path(__file__).with_name("ExportOptions.plist").read_bytes())
data["teamID"] = os.environ["TEAM_ID"]
app = os.environ.get("APP_ID", "com.hgsldswk.mealrotation")
data["provisioningProfiles"] = {
    app: os.environ.get("APP_PROFILE", "MealRotation AppStore"),
    app + ".widget": os.environ.get("WIDGET_PROFILE", "MealRotation Widget AppStore"),
}
sys.stdout.buffer.write(plistlib.dumps(data))
