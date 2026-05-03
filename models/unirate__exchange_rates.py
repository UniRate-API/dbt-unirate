"""Latest exchange rates from the UniRateAPI `/api/rates` endpoint.

This Python model fetches the current rate map for a single base currency
and materialises it as a long-format table:

    as_of_date | base_currency | target_currency | rate

Re-running the model appends today's snapshot. Configure how often it runs
via dbt scheduling (e.g. an hourly Cloud job) — UniRate updates rates
roughly every minute.

Required vars:
    unirate_api_key: your UniRateAPI key. Read from the env var
        `UNIRATE_API_KEY` if the var is unset.

Optional vars:
    unirate_base_currency  (default 'USD')
    unirate_target_currencies (default []) — empty list = "all 800+ rates"
    unirate_request_timeout (default 30 seconds)

Adapter notes:
    Python models require dbt-core>=1.6 and a Python-capable adapter
    (Snowflake / Databricks / BigQuery). For warehouses that lack
    egress (e.g. Snowflake without an external access integration),
    use the equivalent CLI workflow: run
    `python -m unirate.refresh_rates --out rates.csv` and load via
    `dbt seed`. See the README for the full pattern.
"""
from __future__ import annotations

import os
from datetime import date


def _fetch_rates(api_key: str, base_currency: str, timeout: int):
    import urllib.parse
    import urllib.request
    import json

    params = urllib.parse.urlencode({"api_key": api_key, "from": base_currency})
    url = f"https://api.unirateapi.com/api/rates?{params}"
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "dbt-unirate/0.1.0",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        if resp.status != 200:
            raise RuntimeError(
                f"UniRate /api/rates returned HTTP {resp.status}"
            )
        return json.loads(resp.read().decode("utf-8"))


def model(dbt, session):
    dbt.config(
        materialized="incremental",
        unique_key=["as_of_date", "base_currency", "target_currency"],
        on_schema_change="append_new_columns",
        packages=["pandas"],
    )

    base = dbt.config.get("unirate_base_currency", "USD") or "USD"
    targets = dbt.config.get("unirate_target_currencies", []) or []
    timeout = int(dbt.config.get("unirate_request_timeout", 30) or 30)

    api_key = dbt.config.get("unirate_api_key") or os.environ.get(
        "UNIRATE_API_KEY"
    )
    if not api_key:
        raise RuntimeError(
            "dbt-unirate: set var 'unirate_api_key' or env var "
            "UNIRATE_API_KEY before running unirate__exchange_rates"
        )

    payload = _fetch_rates(api_key, base.upper(), timeout)
    rates = payload.get("rates") or {}
    if targets:
        wanted = {c.upper() for c in targets}
        rates = {k: v for k, v in rates.items() if k.upper() in wanted}

    today = date.today().isoformat()

    import pandas as pd

    df = pd.DataFrame(
        [
            {
                "as_of_date": today,
                "base_currency": base.upper(),
                "target_currency": code.upper(),
                "rate": float(value),
            }
            for code, value in rates.items()
        ]
    )

    return df
