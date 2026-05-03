"""Historical exchange rates from `/api/historical/timeseries` (UniRate Pro).

This model pulls a date range of rates and materialises a long-format
table with the same shape as `unirate__exchange_rates`:

    as_of_date | base_currency | target_currency | rate

It is **disabled by default** because the timeseries endpoint requires a
UniRate Pro plan (free-tier requests return HTTP 403). Enable with:

    vars:
      unirate_pro_enabled: true
      unirate_historical_start_date: '2024-01-01'
      unirate_historical_end_date:   '2024-12-31'

`unirate_target_currencies` is recommended in this mode — pulling the
full 800+ currency matrix for a year is a lot of rows.

The endpoint accepts a max 5-year span per call. For longer ranges,
chunk via multiple incremental runs (set start/end vars per run).
"""
from __future__ import annotations

import os


def _fetch_timeseries(
    api_key: str,
    base: str,
    start_date: str,
    end_date: str,
    currencies,
    timeout: int,
):
    import urllib.parse
    import urllib.request
    import json

    qs = {
        "api_key": api_key,
        "base": base,
        "start_date": start_date,
        "end_date": end_date,
    }
    if currencies:
        qs["currencies"] = ",".join(c.upper() for c in currencies)
    url = "https://api.unirateapi.com/api/historical/timeseries?" + urllib.parse.urlencode(qs)
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "dbt-unirate/0.1.0",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read().decode("utf-8")
        if resp.status != 200:
            raise RuntimeError(
                f"UniRate /api/historical/timeseries returned HTTP {resp.status}: {body[:200]}"
            )
        return json.loads(body)


def model(dbt, session):
    dbt.config(
        materialized="incremental",
        unique_key=["as_of_date", "base_currency", "target_currency"],
        on_schema_change="append_new_columns",
        packages=["pandas"],
    )

    base = (dbt.config.get("unirate_base_currency", "USD") or "USD").upper()
    start_date = dbt.config.get("unirate_historical_start_date", "")
    end_date = dbt.config.get("unirate_historical_end_date", "")
    targets = dbt.config.get("unirate_target_currencies", []) or []
    timeout = int(dbt.config.get("unirate_request_timeout", 30) or 30)

    if not start_date or not end_date:
        raise RuntimeError(
            "dbt-unirate: set 'unirate_historical_start_date' and "
            "'unirate_historical_end_date' (YYYY-MM-DD) when "
            "unirate_pro_enabled = true"
        )

    api_key = dbt.config.get("unirate_api_key") or os.environ.get(
        "UNIRATE_API_KEY"
    )
    if not api_key:
        raise RuntimeError(
            "dbt-unirate: set var 'unirate_api_key' or env var "
            "UNIRATE_API_KEY before running unirate__historical_rates"
        )

    payload = _fetch_timeseries(
        api_key, base, start_date, end_date, targets, timeout
    )

    import pandas as pd

    rows = []
    for as_of_date, day_rates in (payload.get("data") or {}).items():
        for code, value in day_rates.items():
            rows.append(
                {
                    "as_of_date": as_of_date,
                    "base_currency": base,
                    "target_currency": code.upper(),
                    "rate": float(value),
                }
            )

    return pd.DataFrame(rows)
