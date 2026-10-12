# dmgbuild settings for the WindFree Bar disk image: the app on the left, Applications on the
# right, an arrow between them, no toolbars. dmgbuild writes the Finder layout directly, so this
# builds headlessly (no Finder scripting).
import os.path

application = defines["app"]  # noqa: F821 (provided by dmgbuild)
appname = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]  # noqa: F821
background = defines["background"]  # noqa: F821 (a matching @2x.png is used for Retina)

window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
icon_size = 128
text_size = 13
icon_locations = {appname: (165, 190), "Applications": (495, 190)}
