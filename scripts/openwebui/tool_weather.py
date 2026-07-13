"""
title: Weather
description: Current weather and daily forecast for any location (open-meteo, no key)
"""

import json
import urllib.parse
import urllib.request


def _get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "BonsaiDemo/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


class Tools:
    def get_weather(self, location: str, days: int = 7) -> str:
        """
        Get current weather and a daily forecast for a city or place name.

        :param location: City or place name, e.g. "Lisbon" or "Maui, Hawaii".
        :param days: Number of forecast days (1-16, default 7).
        :return: Current conditions and a daily forecast table (temps in °C, wind km/h).
        """
        try:
            days = max(1, min(int(days), 16))
        except (TypeError, ValueError):
            days = 7
        try:
            geo = _get(
                "https://geocoding-api.open-meteo.com/v1/search?count=1&name="
                + urllib.parse.quote(location)
            )
            hits = geo.get("results") or []
            if not hits:
                return f"Location not found: {location}"
            g = hits[0]
            place = ", ".join(
                str(g[k]) for k in ("name", "admin1", "country") if g.get(k)
            )
            fc = _get(
                "https://api.open-meteo.com/v1/forecast"
                f"?latitude={g['latitude']}&longitude={g['longitude']}"
                "&current=temperature_2m,apparent_temperature,relative_humidity_2m,"
                "precipitation,wind_speed_10m"
                "&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,"
                "precipitation_probability_max,wind_speed_10m_max"
                f"&timezone=auto&forecast_days={days}"
            )
        except Exception as e:
            return f"Weather lookup failed: {e}"

        c = fc.get("current", {})
        out = [
            f"Weather for {place} ({g['latitude']:.2f}, {g['longitude']:.2f}):",
            (
                f"Now: {c.get('temperature_2m')}°C"
                f" (feels {c.get('apparent_temperature')}°C),"
                f" humidity {c.get('relative_humidity_2m')}%,"
                f" wind {c.get('wind_speed_10m')} km/h,"
                f" precipitation {c.get('precipitation')} mm"
            ),
            "",
            "date | min°C | max°C | rain mm | rain % | max wind km/h",
        ]
        d = fc.get("daily", {})
        for i, day in enumerate(d.get("time", [])):
            out.append(
                f"{day} | {d['temperature_2m_min'][i]} | {d['temperature_2m_max'][i]}"
                f" | {d['precipitation_sum'][i]} | {d['precipitation_probability_max'][i]}"
                f" | {d['wind_speed_10m_max'][i]}"
            )
        return "\n".join(out)
