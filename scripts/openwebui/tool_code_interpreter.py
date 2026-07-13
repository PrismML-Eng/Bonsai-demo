"""
title: Python Code Interpreter
description: Run Python for calculations, data analysis, and plots using Jupyter
"""

import json
import re


MAX_STDOUT_CHARS = 5000
MAX_WARNING_CHARS = 1000

_ANSI_RE = re.compile(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
_PROGRESS_RE = re.compile(r"^\[\*+[^\]]*\]\s+\d+\s+of\s+\d+\s+completed$", re.I)
_ERROR_LINE_RE = re.compile(
    r"^(?:(?:[A-Za-z_][\w.]*)?Error|Exception|KeyboardInterrupt|SystemExit):?\s*"
)
_OUTPUT_IMAGE_RE = re.compile(
    r"^!\[Output Image\]\(/api/v1/files/[^\s)]+/content\)$",
    re.MULTILINE,
)
_OUTPUT_IMAGE_URL_RE = re.compile(
    r"^!\[Output Image\]\((/api/v1/files/([^\s/)]+)/content)\)$",
    re.MULTILINE,
)


def _truncate(text: str, limit: int) -> str:
    text = text or ""
    if len(text) <= limit:
        return text
    return text[:limit].rstrip() + f"\n[truncated from {len(text)} to {limit} characters]"


def _clean_stderr(stderr: str) -> str:
    """Remove ANSI styling and harmless progress bars from Jupyter stderr."""
    text = _ANSI_RE.sub("", stderr or "").replace("\r", "\n")
    lines = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or _PROGRESS_RE.match(line):
            continue
        if not lines or line != lines[-1]:
            lines.append(line)
    return "\n".join(lines)


def _error_summary(stderr: str) -> str:
    lines = [line.strip() for line in stderr.splitlines() if line.strip(" -")]
    for line in reversed(lines):
        if _ERROR_LINE_RE.match(line):
            return line
    return lines[-1] if lines else "Python execution failed."


def _has_execution_error(stderr: str) -> bool:
    if not stderr:
        return False
    lower = stderr.lower()
    return (
        "traceback (most recent call last)" in lower
        or "execution timed out" in lower
        or any(_ERROR_LINE_RE.match(line.strip()) for line in stderr.splitlines())
    )


def _suggested_fix(error: str) -> str:
    """Return a targeted correction for common, confidently identified errors."""
    if "unsupported format string passed to Series.__format__" in error:
        return (
            "The formatted value is a pandas Series, not a scalar. If it came "
            "from yf.download() for one ticker, retry with "
            "multi_level_index=False. Otherwise inspect the columns and shape, "
            "then extract exactly one value before formatting (for example with "
            ".item() only after confirming it contains one element)."
        )
    return ""


def _extract_artifact_markdown(result: str) -> str:
    """Extract only uploaded image markdown produced by the builtin tool."""
    return "\n".join(_OUTPUT_IMAGE_RE.findall(result or ""))


async def _attach_artifacts(response: dict, event_emitter) -> None:
    """Attach generated images using Native-compatible Open WebUI file events."""
    result = response.get("result", "")
    artifact_markdown = _extract_artifact_markdown(result)
    if not artifact_markdown:
        return

    files = [
        {
            "id": file_id,
            "name": "generated-image.png",
            "filename": "generated-image.png",
            "type": "image",
            "url": url,
        }
        for url, file_id in _OUTPUT_IMAGE_URL_RE.findall(artifact_markdown)
    ]
    if event_emitter is not None:
        try:
            await event_emitter(
                {
                    "type": "files",
                    "data": {"files": files},
                }
            )
            # The attachment is now carried by Open WebUI's message metadata, so
            # hide its internal URL from the LLM-facing tool result.
            response.pop("result", None)
        except Exception:
            # Keep the original result as a plain fallback outside normal WebUI use.
            pass


def _normalize_execution(stdout: str, stderr: str, result: str) -> dict:
    """Distinguish clean success, useful partial output, and genuine failure."""
    stdout = _truncate((stdout or "").strip(), MAX_STDOUT_CHARS)
    result = (result or "").strip()
    cleaned_stderr = _clean_stderr(stderr)
    failed = _has_execution_error(cleaned_stderr)

    response = {}
    if failed and result:
        response["status"] = "partial_success"
        response["error"] = _error_summary(cleaned_stderr)
    elif failed:
        response["status"] = "error"
        response["error"] = _error_summary(cleaned_stderr)
    else:
        response["status"] = "success"
        if cleaned_stderr:
            response["warnings"] = _truncate(cleaned_stderr, MAX_WARNING_CHARS)

    if failed:
        suggested_fix = _suggested_fix(response["error"])
        if suggested_fix:
            response["suggested_fix"] = suggested_fix

    if stdout:
        response["stdout"] = stdout
    if result:
        response["result"] = result
    return response


class Tools:
    async def execute_code(
        self,
        code: str,
        __request__=None,
        __user__: dict = None,
        __event_emitter__=None,
        __event_call__=None,
        __chat_id__: str = None,
        __message_id__: str = None,
        __metadata__: dict = None,
    ) -> str:
        """
        Execute Python in a fresh Jupyter kernel. Make each call self-contained.
        Open WebUI attaches displayed plots and generated images to the chat. For
        matplotlib, call plt.show(); do not copy, invent, or modify internal file
        URLs. In this Open WebUI setup, only the latest plot attachment from an
        assistant turn remains visible. When the user requests a chart, do the
        analysis first, then create one final figure (with subplots if needed) in
        the final plotting call; avoid exploratory plot attachments. If status is
        partial_success, keep any attachment and retry only essential missing
        work. Read errors and suggested_fix before retrying.

        For unfamiliar or version-sensitive APIs, it is okay to make a small
        discovery call that prints help() or inspect.signature() before the main
        work. Use what it returns in the next self-contained call. Generated
        images are attached automatically to the chat.

        :param code: Complete Python code to execute.
        :return: Compact JSON with status, output, and any generated result.
        """
        try:
            # Delegate execution, code sanitization, import restrictions, and image
            # uploads to the pinned Open WebUI implementation. Only normalize the
            # JSON it returns to the model.
            from open_webui.tools.builtin import execute_code as builtin_execute_code

            raw = await builtin_execute_code(
                code,
                __request__=__request__,
                __user__=__user__,
                __event_emitter__=__event_emitter__,
                __event_call__=__event_call__,
                __chat_id__=__chat_id__,
                __message_id__=__message_id__,
                __metadata__=__metadata__,
            )
            output = json.loads(raw)
            if output.get("error") and not output.get("stdout") and not output.get("result"):
                return json.dumps(
                    {
                        "status": "error",
                        "error": str(output["error"]),
                    },
                    ensure_ascii=False,
                )
            response = _normalize_execution(
                output.get("stdout", ""),
                output.get("stderr", ""),
                output.get("result", ""),
            )
            await _attach_artifacts(response, __event_emitter__)
            return json.dumps(response, ensure_ascii=False)
        except Exception as exc:
            return json.dumps(
                {
                    "status": "error",
                    "error": f"Code interpreter unavailable: {exc}",
                },
                ensure_ascii=False,
            )
