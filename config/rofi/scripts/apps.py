#!/usr/bin/env python3
"""Rofi app launcher with a web-search fallback.

This is a custom rofi *script mode* (see rofi-script(5)), loosely modelled on
the quickshell launcher in ~/.config/quickshell/Launcher.qml:

  * lists every installed application from the XDG .desktop files
  * filters in rofi itself as you type (name, GenericName, Comment, Keywords)
  * if what you typed matches no application at all and you press Enter,
    it is opened in your default browser: directly when it looks like a URL,
    otherwise as a Google search

Rofi calls the script three ways:
  ROFI_RETV=0  -> print one row per application (what rofi shows)
  ROFI_RETV=1  -> an application was picked; ROFI_INFO holds its .desktop path
  ROFI_RETV=2  -> custom text was typed; $1 is that text

Run it directly to see the rows it would give rofi (useful for debugging).
"""

from __future__ import annotations

import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

# Change these if you ever want a different engine / browser behaviour.
# The URL template may be overridden with $ROFI_APP_SEARCH_URL; use {query}.
SEARCH_TEMPLATE = os.environ.get(
    "ROFI_APP_SEARCH_URL", "https://www.google.com/search?q={query}"
)
SEARCH_NAME = "Google"

# Used only if xdg-open is missing.
FALLBACK_BROWSERS = ("firefox", "helium", "zen", "chromium", "google-chrome")

RE_SCHEME = re.compile(r"^[a-z][a-z0-9+.-]*://", re.IGNORECASE)
RE_LOCALHOST = re.compile(r"^localhost(?::\d+)?(?:/.*)?$", re.IGNORECASE)
RE_IPV4 = re.compile(r"^\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?(?:/.*)?$")
RE_DOMAIN = re.compile(
    r"^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?::\d+)?(?:/.*)?$",
    re.IGNORECASE,
)

# Field codes that may appear in an Exec= line.
RE_FIELD_CODE = re.compile(r"%[fFuUidDnNvmck]")


def xdg_data_home() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")


def application_dirs() -> list[Path]:
    """Return application dirs in XDG priority order (highest priority first)."""
    dirs: list[Path] = []
    data_home = xdg_data_home()
    data_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"

    for base in [data_home, *(Path(p) for p in data_dirs.split(":") if p)]:
        d = base / "applications"
        if d.is_dir() and d not in dirs:
            dirs.append(d)
    return dirs


def current_locales() -> list[str]:
    """Locale names to try for localized keys, most specific first."""
    raw = (
        os.environ.get("LANGUAGE")
        or os.environ.get("LC_ALL")
        or os.environ.get("LC_MESSAGES")
        or os.environ.get("LANG")
        or ""
    )
    locales: list[str] = []
    for item in raw.split(":"):
        item = item.split(".")[0].split("@")[0]
        if not item or item in ("C", "POSIX"):
            continue
        if item not in locales:
            locales.append(item)
        base = item.split("_")[0]
        if base and base not in locales:
            locales.append(base)
    return locales


def unescape(value: str) -> str:
    """Undo the escaping used in .desktop values."""
    out: list[str] = []
    i = 0
    while i < len(value):
        c = value[i]
        if c == "\\" and i + 1 < len(value):
            n = value[i + 1]
            mapping = {"s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\"}
            out.append(mapping.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def clean(text: str) -> str:
    """Make text safe for a single rofi row."""
    return (
        text.replace("\x00", "")
        .replace("\x1f", " ")
        .replace("\r", " ")
        .replace("\n", " ")
        .strip()
    )


class DesktopApp:
    __slots__ = ("name", "path", "icon", "meta")

    def __init__(self, name: str, path: Path, icon: str, meta: str) -> None:
        self.name = name
        self.path = path
        self.icon = icon
        self.meta = meta


def parse_desktop_file(path: Path, locales: list[str]) -> DesktopApp | None:
    """Parse the [Desktop Entry] group of a .desktop file."""
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    entries: dict[str, str] = {}
    in_group = False
    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            in_group = stripped == "[Desktop Entry]"
            continue
        if not in_group or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        # Keep the first occurrence; that is what the spec says.
        if key and key not in entries:
            entries[key] = unescape(value.strip())

    def get(key: str) -> str:
        value = entries.get(key, "")
        if value.lower() == "true":
            return "true"
        return value

    if get("Type") not in ("Application", ""):
        return None
    if get("Hidden") == "true" or get("NoDisplay") == "true":
        return None

    desktops = {
        d.strip()
        for d in (os.environ.get("XDG_CURRENT_DESKTOP") or "").split(":")
        if d.strip()
    }
    only = {d.strip() for d in entries.get("OnlyShowIn", "").split(";") if d.strip()}
    not_show = {
        d.strip() for d in entries.get("NotShowIn", "").split(";") if d.strip()
    }
    if only and not (only & desktops):
        return None
    if not_show and (not_show & desktops):
        return None

    try_exec = entries.get("TryExec", "").strip()
    if try_exec and not shutil.which(try_exec) and not Path(try_exec).is_file():
        return None

    name = ""
    for locale in locales:
        localized = entries.get(f"Name[{locale}]")
        if localized:
            name = localized
            break
    name = name or entries.get("Name", "")
    if not name:
        return None

    generic = ""
    for locale in locales:
        generic = entries.get(f"GenericName[{locale}]", "")
        if generic:
            break
    generic = generic or entries.get("GenericName", "")

    comment = ""
    for locale in locales:
        comment = entries.get(f"Comment[{locale}]", "")
        if comment:
            break
    comment = comment or entries.get("Comment", "")

    keywords = " ".join(
        k.strip() for k in entries.get("Keywords", "").split(";") if k.strip()
    )

    meta = clean(" ".join(part for part in (generic, comment, keywords) if part))
    icon = entries.get("Icon", "").strip()

    return DesktopApp(clean(name), path, icon, meta)


def list_apps() -> list[DesktopApp]:
    """All visible applications, deduplicated by desktop file id, A-Z sorted."""
    locales = current_locales()
    seen: set[str] = set()
    apps: list[DesktopApp] = []

    for directory in application_dirs():
        for path in directory.glob("*.desktop"):
            file_id = path.name
            if file_id in seen:
                continue
            app = parse_desktop_file(path, locales)
            if app is None:
                continue
            seen.add(file_id)
            apps.append(app)

    apps.sort(key=lambda a: (a.name.casefold(), a.name))
    return apps


def is_url_like(text: str) -> bool:
    """True when the input looks like an address instead of search terms."""
    if not text or re.search(r"\s", text):
        return False
    if RE_SCHEME.match(text):
        return True
    if RE_LOCALHOST.match(text):
        return True
    if RE_IPV4.match(text):
        return True
    return bool(RE_DOMAIN.match(text))


def fallback_url(text: str) -> str:
    """URL to open: the address itself, or a search-engine query URL."""
    if is_url_like(text):
        if RE_SCHEME.match(text):
            return text
        # Local addresses are almost always plain HTTP.
        if RE_LOCALHOST.match(text) or RE_IPV4.match(text):
            return "http://" + text
        return "https://" + text
    return SEARCH_TEMPLATE.replace("{query}", quote(text, safe=""))


def spawn(argv: list[str]) -> None:
    """Launch something detached from rofi so it outlives the script."""
    subprocess.Popen(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )


def terminal_command() -> list[str] | None:
    terminal = os.environ.get("TERMINAL")
    if terminal:
        try:
            parts = shlex.split(terminal)
        except ValueError:
            parts = []
        if parts and shutil.which(parts[0]):
            return parts + ["-e"]

    for candidate in ("alacritty", "ghostty", "foot", "kitty", "xterm"):
        if shutil.which(candidate):
            return [candidate, "-e"]
    return None


def desktop_values(path: Path) -> dict[str, str]:
    """Raw values of the [Desktop Entry] group, for launching."""
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}

    values: dict[str, str] = {}
    in_group = False
    for line in raw.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_group = stripped == "[Desktop Entry]"
            continue
        if not in_group or not stripped or stripped.startswith("#"):
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            values.setdefault(key.strip(), unescape(value.strip()))
    return values


def is_terminal_app(path: Path) -> bool:
    values = desktop_values(path)
    return (
        values.get("Terminal", "").lower() == "true"
        and values.get("DBusActivatable", "").lower() != "true"
    )


def exec_from_desktop(path: Path) -> list[str] | None:
    """Expand Exec= ourselves (used for terminal apps and without gio)."""
    values = desktop_values(path)
    exec_line = values.get("Exec", "")
    if not exec_line:
        return None

    # %c -> app name, %k -> file, %i -> "--icon <icon>" or nothing,
    # everything else (files/URLs) drops out because we pass no arguments.
    exec_line = exec_line.replace("%c", values.get("Name", ""))
    exec_line = exec_line.replace("%k", str(path))
    icon = values.get("Icon", "")
    exec_line = exec_line.replace("%i", f"--icon {icon}" if icon else "")
    exec_line = exec_line.replace("%%", "%")
    exec_line = RE_FIELD_CODE.sub("", exec_line)

    try:
        argv = shlex.split(exec_line)
    except ValueError:
        return None
    if not argv:
        return None

    if values.get("Terminal", "").lower() == "true":
        prefix = terminal_command()
        if prefix is None:
            return None
        argv = prefix + argv
    return argv


def launch_app(desktop_path: str) -> None:
    path = Path(desktop_path)
    if not path.is_file():
        return

    # GIO relies on the desktop's configured terminal (xdg-terminal-exec or
    # gsettings), which is often missing. Start terminal apps ourselves so
    # they use the same terminal as the quickshell launcher.
    if is_terminal_app(path):
        argv = exec_from_desktop(path)
        if argv:
            spawn(argv)
            return

    if shutil.which("gio"):
        spawn(["gio", "launch", str(path)])
        return

    argv = exec_from_desktop(path)
    if argv:
        spawn(argv)


def open_in_browser(text: str) -> None:
    url = fallback_url(text)
    if shutil.which("xdg-open"):
        spawn(["xdg-open", url])
        return
    for browser in (os.environ.get("BROWSER", ""), *FALLBACK_BROWSERS):
        if browser and shutil.which(browser):
            spawn([browser, url])
            return


def print_rows(apps: list[DesktopApp]) -> None:
    # Mode option: prompt shown in the rofi input bar.
    sys.stdout.write("\x00prompt\x1fApps\n")
    for app in apps:
        parts = [app.name]
        if app.icon:
            parts.append("icon\x1f" + app.icon)
        if app.meta:
            parts.append("meta\x1f" + app.meta)
        parts.append("info\x1f" + str(app.path))
        sys.stdout.write("\x00".join(parts) + "\n")


def main(argv: list[str]) -> int:
    retv = os.environ.get("ROFI_RETV")
    apps = list_apps()

    # Direct invocation (no rofi): behave like the initial call, which is
    # handy for checking the list.
    if retv is None or retv == "0":
        print_rows(apps)
        return 0

    if retv == "1":
        chosen = os.environ.get("ROFI_INFO", "")
        if chosen:
            launch_app(chosen)
            return 0
        # Very old rofi versions may not pass the info field; fall back to the
        # visible text, which is the (unique enough) application name.
        text = argv[0] if argv else ""
        for app in apps:
            if app.name == text:
                launch_app(str(app.path))
                return 0
        return 0

    if retv == "2":
        text = (argv[0] if argv else "").strip()
        if text:
            open_in_browser(text)
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
