hl.on("hyprland.start", function()
	-- Quickshell owns org.freedesktop.Notifications (dunst is no longer started).
	-- The gtk3 platform theme makes QIcon follow the Adwaita fallback chain,
	-- matching dunst's icon_theme setting for notification/default icons.
	hl.exec_cmd("waybar & udiskie & dunst")
	hl.exec_cmd("hyprsunset -t 4000")
	hl.exec_cmd("~/.local/bin/batteryNotify & ~/.local/bin/startupWallpaper")
	hl.exec_cmd("wl-paste --type text --watch cliphist store &  wl-paste --type image --watch cliphist store")
end)
