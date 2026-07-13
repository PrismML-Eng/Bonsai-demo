import importlib.util
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "scripts" / "openwebui" / "tool_web_fetch.py"
SPEC = importlib.util.spec_from_file_location("tool_web_fetch", TOOL_PATH)
web_fetch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(web_fetch)


class _Headers(dict):
    def get_content_charset(self):
        return "utf-8"


class _Response:
    def __init__(self, body, content_type="text/html; charset=utf-8"):
        self.body = body.encode("utf-8") if isinstance(body, str) else body
        self.headers = _Headers({"Content-Type": content_type})

    def read(self, limit):
        return self.body[:limit]

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


class _Opener:
    def __init__(self, response):
        self.response = response

    def open(self, request, timeout):
        return self.response


class WebFetchTests(unittest.TestCase):
    def setUp(self):
        web_fetch._fetch_counts.clear()
        web_fetch._fetch_inflight.clear()

    def _fetch_with_response(self, response, chat_id="chat-1"):
        with (
            mock.patch.object(web_fetch, "_check_url_public", return_value=None),
            mock.patch.object(
                web_fetch.urllib.request,
                "build_opener",
                return_value=_Opener(response),
            ),
        ):
            return web_fetch.Tools().fetch_url(
                "https://example.com/article", __chat_id__=chat_id
            )

    def test_prefers_article_and_returns_source_metadata(self):
        body = " ".join(
            [
                "The company reported higher revenue and stronger demand during the quarter."
                for _ in range(12)
            ]
        )
        source = f"""
            <html>
              <head>
                <title>Quarterly Results &amp; Outlook</title>
                <meta property="article:published_time" content="2026-07-09T12:30:00Z">
              </head>
              <body>
                <nav><a href="/one">Products</a><a href="/two">Markets</a></nav>
                <main><article><h1>Results</h1><p>{body}</p></article></main>
                <svg><title>Decorative Arrow Icon</title></svg>
                <footer>Copyright and privacy links</footer>
              </body>
            </html>
        """

        result = self._fetch_with_response(_Response(source))

        self.assertIn("Title: Quarterly Results & Outlook", result)
        self.assertNotIn("Decorative Arrow Icon", result)
        self.assertIn("Published: 2026-07-09T12:30:00Z", result)
        self.assertIn("Final URL: https://example.com/article", result)
        self.assertIn("stronger demand", result)
        self.assertNotIn("Products", result)
        self.assertNotIn("Copyright", result)
        self.assertEqual(web_fetch._fetch_counts["chat-1"], 1)
        self.assertNotIn("chat-1", web_fetch._fetch_inflight)

    def test_navigation_only_page_is_rejected_and_does_not_consume_quota(self):
        links = "".join(
            f'<a href="/{i}">Navigation destination number {i}</a>' for i in range(30)
        )
        source = f"<html><body><div>{links}</div></body></html>"

        result = self._fetch_with_response(_Response(source))

        self.assertIn("mostly navigation or links", result)
        self.assertNotIn("chat-1", web_fetch._fetch_counts)
        self.assertNotIn("chat-1", web_fetch._fetch_inflight)

    def test_unreadable_page_releases_slot_for_a_retry(self):
        first = self._fetch_with_response(_Response("<html><body>Sign in</body></html>"))
        self.assertIn("no readable article content", first)

        article = "<article><p>" + ("Verified reporting with useful detail. " * 20) + "</p></article>"
        second = self._fetch_with_response(_Response(article))

        self.assertIn("Readable content", second)
        self.assertEqual(web_fetch._fetch_counts["chat-1"], 1)

    def test_quota_reservations_include_parallel_inflight_calls(self):
        self.assertTrue(web_fetch._reserve_fetch("parallel"))
        self.assertTrue(web_fetch._reserve_fetch("parallel"))
        self.assertTrue(web_fetch._reserve_fetch("parallel"))
        self.assertFalse(web_fetch._reserve_fetch("parallel"))

        web_fetch._finish_fetch("parallel", success=False)
        self.assertTrue(web_fetch._reserve_fetch("parallel"))

    def test_binary_content_is_rejected_without_consuming_quota(self):
        result = self._fetch_with_response(
            _Response(b"%PDF-1.7 fake pdf bytes" * 20, "application/pdf")
        )

        self.assertIn("unsupported content type application/pdf", result)
        self.assertNotIn("chat-1", web_fetch._fetch_counts)


if __name__ == "__main__":
    unittest.main()
