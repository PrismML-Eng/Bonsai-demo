"""
title: Web Fetch
description: Fetch and read the text content of any URL
"""

import gzip
import html
import io
import ipaddress
import re
import socket
import threading
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

MAX_CHARS = 5000
MIN_READABLE_CHARS = 200
MAX_LINK_DENSITY = 0.60
MAX_BODY_BYTES = 2_000_000
MAX_DECOMPRESSED_BYTES = 4_000_000
MAX_REDIRECTS = 5

# Cap how many pages the model may fetch within a single chat. Each fetched page
# adds to the running context, and a wandering agent will otherwise read page after
# page - slow and context-bloating on a local model. When the cap is hit we return
# a short instruction to answer with what it already has, so the tool loop ends
# instead of retrying. Keyed by chat_id; state lives for the server's lifetime.
MAX_FETCHES_PER_CHAT = 3
_fetch_counts: dict = {}
_fetch_inflight: dict = {}
_fetch_lock = threading.Lock()

_DROP_TAGS = {
    "aside", "canvas", "footer", "form", "head", "header", "nav",
    "noscript", "script", "style", "svg", "template",
}
_BLOCK_TAGS = {
    "article", "blockquote", "br", "dd", "div", "dl", "dt", "figcaption",
    "figure", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "li", "main",
    "ol", "p", "pre", "section", "table", "td", "th", "tr", "ul",
}
_CONTENT_TAGS = {"article", "main"}
_DATE_META_NAMES = {
    "article:published_time", "date", "datepublished", "dc.date", "pubdate",
    "publish-date", "parsely-pub-date",
}


class _ReadableHTMLParser(HTMLParser):
    """Extract likely article text while discarding page chrome.

    This intentionally stays in the standard library because Open WebUI stores
    this tool as a standalone module. Text inside <article>/<main> is preferred;
    the cleaned page body is retained as a fallback for older sites.
    """

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.all_parts = []
        self.focus_parts = []
        self.title_parts = []
        self.all_chars = 0
        self.all_link_chars = 0
        self.focus_chars = 0
        self.focus_link_chars = 0
        self.content_depth = 0
        self.link_depth = 0
        self.drop_tag = None
        self.drop_depth = 0
        self.in_title = False
        self.published = ""

    def _break(self):
        self.all_parts.append("\n")
        if self.content_depth:
            self.focus_parts.append("\n")

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        attrs = {str(k).lower(): (v or "") for k, v in attrs}

        # Metadata lives in <head>, which is otherwise excluded.
        if tag == "title":
            # Only capture the document title from <head>. SVGs commonly contain
            # their own <title> nodes ("Menu", "Arrow", etc.).
            self.in_title = self.drop_tag == "head"
            return
        if tag == "meta" and not self.published:
            key = (attrs.get("property") or attrs.get("name") or "").lower()
            if key in _DATE_META_NAMES:
                self.published = attrs.get("content", "").strip()
            return

        if self.drop_tag:
            if tag == self.drop_tag:
                self.drop_depth += 1
            return
        if tag in _DROP_TAGS:
            self.drop_tag = tag
            self.drop_depth = 1
            return

        if tag in _CONTENT_TAGS:
            self.content_depth += 1
        if tag == "a":
            self.link_depth += 1
        if tag in _BLOCK_TAGS:
            self._break()

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag == "title":
            self.in_title = False
            return
        if self.drop_tag:
            if tag == self.drop_tag:
                self.drop_depth -= 1
                if self.drop_depth == 0:
                    self.drop_tag = None
            return

        if tag in _BLOCK_TAGS:
            self._break()
        if tag == "a" and self.link_depth:
            self.link_depth -= 1
        if tag in _CONTENT_TAGS and self.content_depth:
            self.content_depth -= 1

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_data(self, data):
        if self.in_title:
            self.title_parts.append(data)
            return
        if self.drop_tag:
            return
        visible = re.sub(r"\s+", " ", data)
        size = len(visible.strip())
        if not size:
            return
        self.all_parts.append(visible)
        self.all_chars += size
        if self.link_depth:
            self.all_link_chars += size
        if self.content_depth:
            self.focus_parts.append(visible)
            self.focus_chars += size
            if self.link_depth:
                self.focus_link_chars += size


def _normalize_text(parts) -> str:
    text = html.unescape("".join(parts)).replace("\r", "\n")
    text = re.sub(r"[ \t\f\v]+", " ", text)
    text = "\n".join(line.strip() for line in text.splitlines())
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def _extract_readable_html(source: str):
    parser = _ReadableHTMLParser()
    parser.feed(source)
    parser.close()

    focused = _normalize_text(parser.focus_parts)
    fallback = _normalize_text(parser.all_parts)
    if len(focused) >= MIN_READABLE_CHARS:
        text = focused
        chars = parser.focus_chars
        link_chars = parser.focus_link_chars
    else:
        text = fallback
        chars = parser.all_chars
        link_chars = parser.all_link_chars
    density = link_chars / max(chars, 1)
    title = _normalize_text(parser.title_parts)
    return text, title, parser.published, density


def _reserve_fetch(chat_id: str) -> bool:
    """Reserve a quota slot so parallel tool calls cannot exceed the cap."""
    with _fetch_lock:
        used = _fetch_counts.get(chat_id, 0)
        inflight = _fetch_inflight.get(chat_id, 0)
        if used + inflight >= MAX_FETCHES_PER_CHAT:
            return False
        _fetch_inflight[chat_id] = inflight + 1
        return True


def _finish_fetch(chat_id: str, success: bool) -> None:
    with _fetch_lock:
        inflight = _fetch_inflight.get(chat_id, 0) - 1
        if inflight > 0:
            _fetch_inflight[chat_id] = inflight
        else:
            _fetch_inflight.pop(chat_id, None)
        if success:
            _fetch_counts[chat_id] = _fetch_counts.get(chat_id, 0) + 1


class _Redirect(Exception):
    def __init__(self, location):
        self.location = location


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Turn redirects into a _Redirect exception so the caller re-validates the
    target before following it (prevents redirect-based SSRF)."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise _Redirect(newurl)


def _is_public_ip(ip_str: str) -> bool:
    try:
        ip = ipaddress.ip_address(ip_str)
    except ValueError:
        return False
    # is_global is the canonical "publicly routable unicast" check: it rejects
    # loopback, private LAN, link-local (169.254/16 -> cloud metadata), CGNAT
    # (100.64/10), reserved, multicast and unspecified in one go. Validating the
    # *resolved* IP also defeats obfuscation like "localhost", "0177.0.0.1",
    # decimal IPs, and "[::1]".
    return ip.is_global


def _check_url_public(url):
    """Return an error string if the URL is unsafe to fetch, else None."""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme not in ("http", "https"):
        return "Error: only http(s) URLs are supported."
    host = parts.hostname
    if not host:
        return "Error: could not parse host from URL."
    try:
        port = parts.port or (443 if parts.scheme == "https" else 80)
        infos = socket.getaddrinfo(host, port)
    except OSError as e:
        return f"Error: could not resolve host: {e}"
    for info in infos:
        ip_str = info[4][0]
        if not _is_public_ip(ip_str):
            return (
                f"Error: refusing to fetch {host} ({ip_str}) - it resolves to a "
                "non-public (loopback/private/link-local/reserved) address."
            )
    return None


def _read_capped(resp):
    """Read the body, capping the decompressed size to guard against zip bombs."""
    raw = resp.read(MAX_BODY_BYTES)
    ctype = resp.headers.get("Content-Type", "")
    charset = "utf-8"
    if hasattr(resp.headers, "get_content_charset"):
        charset = resp.headers.get_content_charset() or charset
    if resp.headers.get("Content-Encoding", "").lower() == "gzip":
        out = bytearray()
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as gz:
            while True:
                chunk = gz.read(65536)
                if not chunk:
                    break
                out.extend(chunk)
                if len(out) > MAX_DECOMPRESSED_BYTES:
                    break
        raw = bytes(out[:MAX_DECOMPRESSED_BYTES])
    return raw, ctype, charset


class Tools:
    def fetch_url(self, url: str, __chat_id__: str = "") -> str:
        """
        Fetch a web page and return its readable text content. Use this to open
        links the user provides or URLs found via web search.

        :param url: The full http(s) URL to fetch.
        :return: The page's text content (truncated if long).
        """
        # Reserve a slot before network I/O. Failed/unreadable requests release it,
        # while successful pages consume it. (__chat_id__ is injected by Open
        # WebUI; empty string groups cap-less calls under one bucket.)
        if not _reserve_fetch(__chat_id__):
            return (
                f"Fetch limit reached ({MAX_FETCHES_PER_CHAT} successful or "
                "in-progress pages this chat). Do not fetch more pages; answer "
                "using the content already gathered, and note any gaps."
            )

        success = False
        try:
            # Follow redirects manually so each hop is re-checked (a public URL can
            # 302 to an internal address). NOTE: this validates then connects, so it
            # is not proof against DNS rebinding (the IP changing between check and
            # connect) - acceptable for a local demo tool, not a hardened proxy.
            current = url
            raw = b""
            ctype = ""
            charset = "utf-8"
            for _ in range(MAX_REDIRECTS + 1):
                unsafe = _check_url_public(current)
                if unsafe:
                    return unsafe
                req = urllib.request.Request(
                    current,
                    headers={
                        "User-Agent": "Mozilla/5.0 (compatible; BonsaiDemo/1.0)",
                        "Accept": "text/html,application/xhtml+xml,text/plain,application/json",
                        "Accept-Encoding": "gzip",
                    },
                )
                try:
                    # ProxyHandler({}) disables env proxies (HTTP_PROXY etc.) — a
                    # proxy would connect on our behalf and bypass the IP check above.
                    opener = urllib.request.build_opener(
                        urllib.request.ProxyHandler({}), _NoRedirect
                    )
                    with opener.open(req, timeout=30) as r:
                        raw, ctype, charset = _read_capped(r)
                    break
                except _Redirect as redir:
                    current = urllib.parse.urljoin(current, redir.location)
                    continue
                except urllib.error.HTTPError as e:
                    return f"Fetch failed: HTTP {e.code}. Use the exact URL from search."
                except Exception as e:
                    return f"Fetch failed: {e}"
            else:
                return f"Fetch failed: too many redirects (>{MAX_REDIRECTS})."

            if not raw:
                return "Fetch failed: the page returned an empty body."
            try:
                decoded = raw.decode(charset, errors="replace")
            except LookupError:
                decoded = raw.decode("utf-8", errors="replace")

            media_type = ctype.split(";", 1)[0].strip().lower()
            looks_html = "html" in media_type or decoded.lstrip().startswith(("<", "<!"))
            supported_text = (
                not media_type
                or media_type.startswith("text/")
                or media_type in {"application/json", "application/xml"}
                or media_type.endswith("+xml")
            )
            if looks_html:
                text, title, published, link_density = _extract_readable_html(decoded)
                if len(text) < MIN_READABLE_CHARS:
                    return (
                        "Fetch failed: no readable article content was found "
                        f"({len(text)} characters after removing page chrome)."
                    )
                if link_density > MAX_LINK_DENSITY:
                    return (
                        "Fetch failed: the extracted page is mostly navigation or "
                        f"links ({link_density:.0%} link text), not readable evidence."
                    )
            elif supported_text:
                text = _normalize_text([decoded])
                title = ""
                published = ""
                if len(text) < MIN_READABLE_CHARS:
                    return f"Fetch failed: only {len(text)} readable characters were returned."
            else:
                return (
                    f"Fetch failed: unsupported content type {media_type or 'unknown'}; "
                    "this tool reads HTML and text pages only."
                )

            full_length = len(text)
            if full_length > MAX_CHARS:
                text = text[:MAX_CHARS].rsplit(" ", 1)[0]
                text += f"\n\n[truncated from {full_length} to {MAX_CHARS} characters]"

            # Report useful metadata and the final URL (which may differ after redirects).
            metadata = []
            if title:
                metadata.append(f"Title: {title}")
            if published:
                metadata.append(f"Published: {published}")
            metadata.append(f"Final URL: {current}")
            note = f"\nRedirected from: {url}" if current != url else ""
            success = True
            return "\n".join(metadata) + note + f"\n\nReadable content:\n{text}"
        finally:
            _finish_fetch(__chat_id__, success)
