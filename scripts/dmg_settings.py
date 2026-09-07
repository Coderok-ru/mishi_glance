# dmgbuild settings for the Mishi Glance installer.
# Invoked by make-dmg.sh; builds the styled window without any AppleScript,
# which matters because Finder scripting needs Accessibility permission.

import os.path

application = defines.get("app", "build/Mishi Glance.app")  # noqa: F821
appname = os.path.basename(application)

# --- disk image ------------------------------------------------------------
format = "UDZO"          # compressed, read-only
compression_level = 9
size = None              # let dmgbuild measure the payload

files = [application]
symlinks = {"Программы": "/Applications"}

# Volume icon: reuse the app's own icon.
icon = os.path.join(application, "Contents/Resources/AppIcon.icns")

# --- window ----------------------------------------------------------------
background = defines.get("background", "scripts/dmg-background.tiff")  # noqa: F821

window_rect = ((240, 160), (660, 420))
default_view = "icon-view"

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

# --- icon view -------------------------------------------------------------
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 12
icon_size = 112

# Must match APP_ICON / APPLICATIONS_ICON in dmg_background.py.
icon_locations = {
    appname: (170, 205),
    "Программы": (490, 205),
}
