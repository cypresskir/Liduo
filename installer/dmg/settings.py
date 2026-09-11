from pathlib import Path

assets = Path(defines["assets"])
app = Path(defines["app"])

format = "UDZO"
filesystem = "HFS+"
files = [str(app), (str(assets / "install.html"), "Установка.html")]
symlinks = {"Программы": "/Applications"}
icon = str(app / "Contents/Resources/AppIcon.icns")
background = str(assets / "background.tiff")
window_rect = ((200, 160), (680, 460))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
icon_size = 96
text_size = 14
label_pos = "bottom"
hide_extensions = ["Установка.html"]
icon_locations = {
    "Liduo.app": (184, 210),
    "Программы": (496, 210),
    "Установка.html": (340, 366),
}
