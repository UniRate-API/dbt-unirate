# Changelog

## v0.1.0 — 2026-05-03

Initial release.

- Python model `unirate__exchange_rates` — pulls latest rates from `/api/rates`.
- Python model `unirate__historical_rates` — pulls a date range from `/api/historical/timeseries` (UniRate Pro).
- Macro `unirate.get_rate(from_currency, to_currency)` — returns a SQL fragment that looks up the latest rate.
- Macro `unirate.convert_currency(amount, from_currency, to_currency, [date_column])` — returns a SQL fragment that converts an amount, optionally dated.
- Macro `unirate.get_historical_rate(from_currency, to_currency, date_column)` — returns a SQL fragment that looks up a dated rate.
- Adapter coverage: tested on DuckDB. Should work on any adapter that supports `dbt-core>=1.6` Python models (Snowflake, Databricks, BigQuery) for the rate-fetching step. The macros themselves are pure SQL and adapter-agnostic.
