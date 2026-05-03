-- Exercises unirate.get_rate. Expects the latest USD->EUR rate (0.92).
select
    {{ unirate.get_rate('USD', 'EUR', rates_relation=ref('mock_latest_rates')) }} as rate
