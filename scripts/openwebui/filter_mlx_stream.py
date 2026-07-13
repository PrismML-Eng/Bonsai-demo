"""
title: MLX Stream Chunk Normalizer
description: mlx_vlm.server emits "timings": null in every SSE chunk; Open WebUI's stream handler does raw_usage.update(data.get("timings", {})) which raises TypeError on null and silently drops every content delta. This filter strips null timings/usage before that line runs.
version: 0.1.0
"""


class Filter:
    def stream(self, event: dict) -> dict:
        if isinstance(event, dict):
            if "timings" in event and event["timings"] is None:
                del event["timings"]
            if "usage" in event and event["usage"] is None:
                del event["usage"]
        return event
