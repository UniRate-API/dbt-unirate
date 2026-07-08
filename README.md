# dbt-unirate

Currency conversion in dbt, powered by [UniRateAPI](https://unirateapi.com).

`dbt-unirate` ships:

- A Python model that **fetches the live rate matrix** from `/api/rates`
  and materialises it as a long table (`as_of_date`, `base_currency`,
  `target_currency`, `rate`).
- An optional Python model that **back-fills history** from
  `/api/historical/timeseries` (UniRate Pro plan).
- Three Jinja macros — `unirate.get_rate`, `unirate.get_historical_rate`,
  and `unirate.convert_currency` — that emit adapter-agnostic SQL and
  drop into your existing models inline.

The motivating use case is dbt Discourse [#364 — Currency
Conversions][discourse-364] (one of the most-viewed evergreen forum
threads), where the recommended pattern is "build your own rates table
plus a `convert_currency` macro." This package is that pattern,
batteries-included, with a real rate source.

[discourse-364]: https://discourse.getdbt.com/t/currency-conversions-in-dbt/364

## Quick start

### 1. Install the package

Add to `packages.yml`:

```yaml
packages:
  - package: UniRate-API/dbt-unirate
    version: [">=0.1.0", "<0.2.0"]
```

Then `dbt deps`.

### 2. Configure the API key

Get a free key at <https://unirateapi.com>. Either set the
`UNIRATE_API_KEY` environment variable, or pass it as a dbt variable in
`dbt_project.yml`:

```yaml
vars:
  unirate_api_key: "{{ env_var('UNIRATE_API_KEY') }}"
  unirate_base_currency: "USD"          # default
  unirate_target_currencies: []          # [] = all 800+ rates
```

### 3. Build the rates table

```bash
dbt run --select unirate__exchange_rates
```

This calls `/api/rates` from the warehouse's Python runtime and writes a
fresh snapshot to `unirate__exchange_rates`. Re-run on whatever cadence
you want (UniRate updates rates roughly every minute; an hourly dbt
Cloud job is plenty for most analytics use cases).

### 4. Use the macros

```sql
-- models/orders_eur.sql
select
  o.order_id,
  o.amount,
  {{ unirate.convert_currency('o.amount', 'USD', 'EUR') }} as amount_eur
from {{ ref('orders') }} o
```

That's it. The macro emits a correlated subquery that pulls the most
recent USD→EUR rate from `unirate__exchange_rates`.

## Macros

### `unirate.convert_currency(amount, from_currency, to_currency, [date_column], [rates_relation])`

Returns a SQL expression that converts `amount` from `from_currency` to
`to_currency`.

Without `date_column` it uses the latest rate from
`ref('unirate__exchange_rates')`.

With `date_column` it uses the rate as of that date from
`ref('unirate__historical_rates')` (Pro-gated).

When `from == to`, the macro short-circuits and returns `amount`
verbatim — no subquery is generated, so passthrough conversions are
free.

```sql
-- live rate
{{ unirate.convert_currency('amount', 'USD', 'EUR') }}

-- dated, per-row historical rate
{{ unirate.convert_currency('amount', 'USD', 'EUR',
                            date_column='order_date') }}

-- bring your own rates table
{{ unirate.convert_currency('amount', 'USD', 'EUR',
                            rates_relation=ref('my_fx_rates')) }}
```

### `unirate.get_rate(from_currency, to_currency, [rates_relation])`

Returns the latest rate as a SQL scalar subquery. Useful when you want
the rate itself, not a converted amount.

```sql
select {{ unirate.get_rate('USD', 'EUR') }} as usd_eur_rate
```

### `unirate.get_historical_rate(from_currency, to_currency, date_column, [rates_relation])`

Same as `get_rate` but resolves the rate as of `date_column` (a SQL
expression in the outer query). Picks the latest available rate on or
before the given date — weekends and holidays fall back to the previous
business day's snapshot.

## Models

### `unirate__exchange_rates` (always enabled)

Long table, one row per (date, base, target). Materialised
`incremental` with composite unique key — re-running appends a new
daily snapshot. Free-tier UniRate is fine.

| column | type | description |
|---|---|---|
| `as_of_date` | date | When the snapshot was fetched (UTC). |
| `base_currency` | varchar | ISO-4217 (or crypto ticker), uppercase. |
| `target_currency` | varchar | ISO-4217 (or crypto ticker), uppercase. |
| `rate` | double | Units of `target_currency` per 1 unit of `base_currency`. |

### `unirate__historical_rates` (Pro-gated, disabled by default)

Same shape, but populated from `/api/historical/timeseries` —
**requires a UniRate Pro plan** (free-tier returns HTTP 403).

Enable with:

```yaml
vars:
  unirate_pro_enabled: true
  unirate_historical_start_date: "2024-01-01"
  unirate_historical_end_date:   "2024-12-31"
  unirate_target_currencies: ["EUR", "GBP", "JPY"]   # recommended
```

The endpoint accepts a max 5-year span per call. For longer ranges,
chunk via multiple incremental runs (vary the start/end vars per run).

## Variables

| var | default | purpose |
|---|---|---|
| `unirate_api_key` | (env `UNIRATE_API_KEY`) | UniRate API key. |
| `unirate_base_currency` | `"USD"` | Base for the rates matrix. |
| `unirate_target_currencies` | `[]` | Filter — `[]` means "all". |
| `unirate_pro_enabled` | `false` | Enable `unirate__historical_rates`. |
| `unirate_historical_start_date` | `""` | Pro-only. `YYYY-MM-DD`. |
| `unirate_historical_end_date` | `""` | Pro-only. `YYYY-MM-DD`. |
| `unirate_request_timeout` | `30` | HTTP timeout in seconds. |

## Adapter coverage

The Jinja macros are pure SQL — `correlated SELECT … LIMIT 1` patterns
that run on any adapter (Snowflake, Databricks, BigQuery, Postgres,
Redshift, DuckDB).

The Python models need a Python-capable adapter — Snowflake, Databricks,
or BigQuery. On Snowflake, the warehouse needs an [external access
integration][sf-eai] that allows traffic to `api.unirateapi.com`. On
Databricks, regular notebook clusters can reach external endpoints by
default.

[sf-eai]: https://docs.snowflake.com/en/developer-guide/external-network-access/external-network-access-overview

If your warehouse can't reach the public internet — or you're on
Postgres / Redshift / a stock dbt Core install — pull rates locally
with the official Python client and load them via `dbt seed`:

```bash
pip install unirate-api
python - <<'PY'
import csv, datetime, os, unirate
client = unirate.UnirateClient(os.environ['UNIRATE_API_KEY'])
rates = client.get_rate(from_currency='USD')
today = datetime.date.today().isoformat()
with open('seeds/unirate__exchange_rates.csv', 'w') as f:
    w = csv.writer(f)
    w.writerow(['as_of_date', 'base_currency', 'target_currency', 'rate'])
    for code, value in rates.items():
        w.writerow([today, 'USD', code, value])
PY
dbt seed --select unirate__exchange_rates
```

Run that on whatever cadence your scheduler supports. The macros work
the same way regardless of how the rates table got there.

## Versioning

Semantic versioning. v0.x is pre-1.0 — minor bumps may include breaking
changes; pin to a range (`>=0.1.0, <0.2.0`) until v1.0.

<!-- unirate-ecosystem-footer:start -->
## UniRate ecosystem

UniRate ships official integrations for 40+ ecosystems, all maintained under the
[UniRate-API](https://github.com/UniRate-API) org.

**Core clients (9 languages)**
[Python](https://github.com/UniRate-API/unirate-api-python) ·
[Node.js / TypeScript](https://github.com/UniRate-API/unirate-api-nodejs) ·
[Go](https://github.com/UniRate-API/unirate-api-go) ·
[Rust](https://github.com/UniRate-API/unirate-api-rust) ·
[Java](https://github.com/UniRate-API/unirate-api-java) ·
[Ruby](https://github.com/UniRate-API/unirate-api-ruby) ·
[PHP](https://github.com/UniRate-API/unirate-api-php) ·
[.NET](https://github.com/UniRate-API/unirate-api-dotnet) ·
[Swift](https://github.com/UniRate-API/unirate-api-swift)

**JavaScript / TypeScript**
[React](https://github.com/UniRate-API/react-unirate) ·
[Next.js](https://github.com/UniRate-API/next-unirate) ·
[Remix](https://github.com/UniRate-API/remix-unirate) ·
[SvelteKit](https://github.com/UniRate-API/sveltekit-unirate) ·
[Vue](https://github.com/UniRate-API/vue-unirate) ·
[Angular](https://github.com/UniRate-API/angular-unirate) ·
[Nuxt](https://github.com/UniRate-API/nuxt-unirate) ·
[NestJS](https://github.com/UniRate-API/nestjs-unirate) ·
[tRPC](https://github.com/UniRate-API/trpc-unirate)

**Static-site generators**
[Astro](https://github.com/UniRate-API/astro-unirate) ·
[Eleventy](https://github.com/UniRate-API/eleventy-unirate) ·
[Hugo](https://github.com/UniRate-API/hugo-unirate) ·
[Jekyll](https://github.com/UniRate-API/jekyll-unirate)

**CMS & e-commerce**
[Wagtail](https://github.com/UniRate-API/wagtail-unirate) ·
[WordPress](https://github.com/UniRate-API/unirate-currency-converter) ·
[WooCommerce](https://github.com/UniRate-API/unirate-woocs) ·
[Drupal](https://github.com/UniRate-API/drupal-unirate) ·
[Strapi](https://github.com/UniRate-API/strapi-plugin-unirate) ·
[Medusa](https://github.com/UniRate-API/medusa-plugin-unirate) ·
[Symfony](https://github.com/UniRate-API/unirate-bundle) ·
[Laravel](https://github.com/UniRate-API/laravel-money-unirate) ·
[Directus](https://github.com/UniRate-API/directus-extension-unirate)

**Data, AI & backend**
[LangChain (Python)](https://github.com/UniRate-API/langchain-unirate) ·
[LangChain.js](https://github.com/UniRate-API/langchain-js-unirate) ·
[FastAPI](https://github.com/UniRate-API/fastapi-unirate) ·
[Flask](https://github.com/UniRate-API/flask-unirate) ·
[Django REST Framework](https://github.com/UniRate-API/djangorestframework-unirate) ·
[Apache Airflow](https://github.com/UniRate-API/airflow-provider-unirate) ·
[dbt](https://github.com/UniRate-API/dbt-unirate)

**Platform & tools**
[MCP server](https://github.com/UniRate-API/unirate-mcp) ·
[CLI](https://github.com/UniRate-API/unirate-cli) ·
[Cloudflare Workers](https://github.com/UniRate-API/cloudflare-workers-unirate) ·
[Home Assistant](https://github.com/UniRate-API/unirate-home-assistant) ·
[n8n](https://github.com/UniRate-API/n8n-nodes-unirate) ·
[Google Sheets](https://github.com/UniRate-API/unirate-sheets) ·
[VS Code](https://github.com/UniRate-API/vscode-unirate) ·
[Obsidian](https://github.com/UniRate-API/obsidian-currency)

**Money library bridges**
[money gem (Ruby)](https://github.com/UniRate-API/money-unirate-api) ·
[NodaMoney (.NET)](https://github.com/UniRate-API/UniRateApi.NodaMoney)

Get a free API key at [unirateapi.com](https://unirateapi.com).
<!-- unirate-ecosystem-footer:end -->

## License

MIT. See [LICENSE](LICENSE).

## Related projects

- [UniRateAPI Python client](https://github.com/UniRate-API/unirate-api-python)
- [UniRateAPI Node client](https://github.com/UniRate-API/unirate-api-nodejs)
- [LangChain `langchain-unirate`](https://github.com/UniRate-API/langchain-unirate)
- [Apache Airflow `airflow-provider-unirate`](https://github.com/UniRate-API)
- [`unirate-mcp` (Model Context Protocol)](https://github.com/UniRate-API/unirate-mcp)

## Disclosure

This package is built and maintained by the UniRateAPI team. It calls
the UniRateAPI service. The Jinja macros and database schema are
adapter-agnostic — you can point `rates_relation` at any table with the
same shape if you want to plug in a different rate source.