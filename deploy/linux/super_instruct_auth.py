from pathlib import Path

from websockify.auth_plugins import BasicHTTPAuth


class FileHTTPAuth(BasicHTTPAuth):
    """Load Basic Auth credentials from a root-owned file."""

    def __init__(self, src=None):
        self.src = Path(src or "/etc/super-instruct/novnc.auth").read_text().strip()
