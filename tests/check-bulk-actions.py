from pathlib import Path
import re
ui = (Path(__file__).resolve().parents[1] / 'package/contents/ui/main.qml').read_text()
assert ui.count('text: i18n("Mark all seen")') == 1
assert ui.count('text: i18n("Mark all unseen")') == 1
assert 'text: i18n("More seen actions")' not in ui
assert 'seenActionsMenu.popup()' not in ui
assert 'Controls.MenuItem' not in ui
assert re.search(r'Controls\.Button\s*\{\s*text: i18n\("Mark all unseen"\)\s*enabled: root\.totalStoredVideos > root\.unseen\s*onClicked: \{\s*dataStore\.markAllUnseen\(\)\s*root\.reload\(\)', ui)
assert re.search(r'Controls\.Button\s*\{\s*text: i18n\("Mark all seen"\)\s*enabled: root\.unseen > 0\s*onClicked: \{\s*dataStore\.markAllSeen\(\)\s*root\.reload\(\)', ui)
print('PASS bulk status buttons are direct, enabled appropriately, and call the existing database operations')
