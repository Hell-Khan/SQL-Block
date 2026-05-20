DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    Id_client            INT PRIMARY KEY,
    Total_amount         NUMERIC,
    Gender               VARCHAR(10),   -- 'F', 'M', NULL → будет 'NA'
    Age                  INT,           -- может быть NULL
    Count_city           INT,
    Response_communcation INT,
    Communication_3month  INT,
    Tenure               INT
);

CREATE TABLE transactions (
    date_new        DATE,
    Id_check        BIGINT,
    ID_client       INT,
    Count_products  NUMERIC,
    Sum_payment     NUMERIC
);


-- ЗАДАНИЕ 1. Клиенты с НЕПРЕРЫВНОЙ историей за год

WITH period_txn AS (
    SELECT *
    FROM transactions
    WHERE date_new BETWEEN '2015-06-01' AND '2016-06-01'
),
-- Месяцы, в которых клиент совершал операции
client_months AS (
    SELECT
        ID_client,
        DATE_TRUNC('month', date_new)::DATE AS txn_month
    FROM period_txn
    GROUP BY ID_client, DATE_TRUNC('month', date_new)
),
-- Считаем количество различных месяцев у каждого клиента
client_month_count AS (
    SELECT
        ID_client,
        COUNT(DISTINCT txn_month) AS months_present
    FROM client_months
    GROUP BY ID_client
),
-- Клиенты, у которых покрыты ВСЕ 13 месяцев периода
continuous_clients AS (
    SELECT ID_client
    FROM client_month_count
    WHERE months_present = 13   -- Jun'15, Jul'15, ..., Jun'16
),
-- Агрегаты по этим клиентам
client_agg AS (
    SELECT
        t.ID_client,
        COUNT(*)                                          AS total_operations,
        SUM(t.Sum_payment)                               AS total_sum,
        AVG(t.Sum_payment)                               AS avg_check,          -- средний чек
        SUM(t.Sum_payment) / 13.0                        AS avg_monthly_sum     -- ср. сумма за месяц
    FROM period_txn t
    JOIN continuous_clients cc ON t.ID_client = cc.ID_client
    GROUP BY t.ID_client
)
SELECT
    ca.ID_client,
    c.Gender,
    c.Age,
    ca.total_operations,
    ROUND(ca.avg_check::NUMERIC, 2)       AS avg_check,
    ROUND(ca.avg_monthly_sum::NUMERIC, 2) AS avg_monthly_sum,
    ROUND(ca.total_sum::NUMERIC, 2)       AS total_sum
FROM client_agg ca
LEFT JOIN customer_info c ON ca.ID_client = c.Id_client
ORDER BY ca.ID_client;


-- ЗАДАНИЕ 2. Аналитика В РАЗРЕЗЕ МЕСЯЦЕВ


WITH period_txn AS (
    SELECT
        ID_client,
        Id_check,
        Sum_payment,
        DATE_TRUNC('month', date_new)::DATE AS txn_month
    FROM transactions
    WHERE date_new BETWEEN '2015-06-01' AND '2016-06-01'
),
-- Общие итоги за весь год (для долей)
year_totals AS (
    SELECT
        COUNT(*)           AS year_ops,
        SUM(Sum_payment)   AS year_sum
    FROM period_txn
),
-- Месячные агрегаты
monthly_agg AS (
    SELECT
        txn_month,
        COUNT(*)                        AS ops_in_month,
        SUM(Sum_payment)                AS sum_in_month,
        AVG(Sum_payment)                AS avg_check_month,
        COUNT(DISTINCT ID_client)       AS uniq_clients_month
    FROM period_txn
    GROUP BY txn_month
)
-- 2.1 Средний чек, 2.2 ср. кол-во операций (агрегаты уже на уровне месяца),
-- 2.3 ср. кол-во клиентов, 2.4 доля операций и суммы за год
SELECT
    ma.txn_month,
    ma.ops_in_month,
    ROUND(ma.avg_check_month::NUMERIC, 2)                              AS avg_check,
    ma.uniq_clients_month,
    -- Доля от общего кол-ва операций за год, %
    ROUND(100.0 * ma.ops_in_month  / yt.year_ops,  2)                 AS pct_ops_of_year,
    -- Доля от общей суммы операций за год, %
    ROUND(100.0 * ma.sum_in_month  / yt.year_sum,  2)                 AS pct_sum_of_year
FROM monthly_agg ma
CROSS JOIN year_totals yt
ORDER BY ma.txn_month;

-- 2.5 Доля M / F / NA по количеству и сумме в каждом месяце
WITH period_txn AS (
    SELECT
        t.ID_client,
        t.Sum_payment,
        DATE_TRUNC('month', t.date_new)::DATE AS txn_month,
        COALESCE(c.Gender, 'NA')               AS gender
    FROM transactions t
    LEFT JOIN customer_info c ON t.ID_client = c.Id_client
    WHERE t.date_new BETWEEN '2015-06-01' AND '2016-06-01'
),
month_gender AS (
    SELECT
        txn_month,
        gender,
        COUNT(*)         AS ops_cnt,
        SUM(Sum_payment) AS ops_sum
    FROM period_txn
    GROUP BY txn_month, gender
),
month_totals AS (
    SELECT
        txn_month,
        SUM(ops_cnt) AS month_ops,
        SUM(ops_sum) AS month_sum
    FROM month_gender
    GROUP BY txn_month
)
SELECT
    mg.txn_month,
    mg.gender,
    mg.ops_cnt,
    ROUND(100.0 * mg.ops_cnt / mt.month_ops, 2) AS pct_ops,
    ROUND(mg.ops_sum::NUMERIC, 2)               AS ops_sum,
    ROUND(100.0 * mg.ops_sum / mt.month_sum, 2) AS pct_sum
FROM month_gender mg
JOIN month_totals mt ON mg.txn_month = mt.txn_month
ORDER BY mg.txn_month, mg.gender;


-- ЗАДАНИЕ 3. Возрастные группы (шаг 10 лет) + клиенты без Age
--   3a. Итого за весь период: сумма и кол-во операций
--   3b. По кварталам: средние показатели и %-доли


-- Вспомогательная маркировка возрастной группы
WITH period_txn AS (
    SELECT
        t.ID_client,
        t.Sum_payment,
        t.date_new,
        DATE_TRUNC('quarter', t.date_new)::DATE AS txn_quarter,
        CASE
            WHEN c.Age IS NULL THEN 'Unknown'
            WHEN c.Age < 20    THEN '<20'
            WHEN c.Age < 30    THEN '20-29'
            WHEN c.Age < 40    THEN '30-39'
            WHEN c.Age < 50    THEN '40-49'
            WHEN c.Age < 60    THEN '50-59'
            WHEN c.Age < 70    THEN '60-69'
            ELSE                    '70+'
        END AS age_group
    FROM transactions t
    LEFT JOIN customer_info c ON t.ID_client = c.Id_client
    WHERE t.date_new BETWEEN '2015-06-01' AND '2016-06-01'
),

-- 3a. Итого за весь период по возрастным группам
period_totals AS (
    SELECT
        age_group,
        COUNT(*)         AS total_ops,
        SUM(Sum_payment) AS total_sum
    FROM period_txn
    GROUP BY age_group
),
grand_totals AS (
    SELECT SUM(total_ops) AS g_ops, SUM(total_sum) AS g_sum FROM period_totals
)
SELECT
    pt.age_group,
    pt.total_ops,
    ROUND(pt.total_sum::NUMERIC, 2)                          AS total_sum,
    ROUND(100.0 * pt.total_ops / gt.g_ops, 2)               AS pct_ops,
    ROUND(100.0 * pt.total_sum / gt.g_sum, 2)               AS pct_sum
FROM period_totals pt
CROSS JOIN grand_totals gt
ORDER BY pt.age_group;

-- 3b. По кварталам: средние показатели и %-доли
WITH period_txn AS (
    SELECT
        t.ID_client,
        t.Sum_payment,
        DATE_TRUNC('quarter', t.date_new)::DATE AS txn_quarter,
        CASE
            WHEN c.Age IS NULL THEN 'Unknown'
            WHEN c.Age < 20    THEN '<20'
            WHEN c.Age < 30    THEN '20-29'
            WHEN c.Age < 40    THEN '30-39'
            WHEN c.Age < 50    THEN '40-49'
            WHEN c.Age < 60    THEN '50-59'
            WHEN c.Age < 70    THEN '60-69'
            ELSE                    '70+'
        END AS age_group
    FROM transactions t
    LEFT JOIN customer_info c ON t.ID_client = c.Id_client
    WHERE t.date_new BETWEEN '2015-06-01' AND '2016-06-01'
),
-- Агрегат квартал × возрастная группа
qtr_age AS (
    SELECT
        txn_quarter,
        age_group,
        COUNT(*)           AS ops_cnt,
        SUM(Sum_payment)   AS ops_sum,
        AVG(Sum_payment)   AS avg_check
    FROM period_txn
    GROUP BY txn_quarter, age_group
),
-- Итоги по кварталу (для долей)
qtr_totals AS (
    SELECT
        txn_quarter,
        SUM(ops_cnt) AS qtr_ops,
        SUM(ops_sum) AS qtr_sum
    FROM qtr_age
    GROUP BY txn_quarter
)
SELECT
    qa.txn_quarter,
    qa.age_group,
    qa.ops_cnt,
    ROUND(qa.ops_sum::NUMERIC, 2)                              AS ops_sum,
    ROUND(qa.avg_check::NUMERIC, 2)                            AS avg_check,
    ROUND(100.0 * qa.ops_cnt / qt.qtr_ops, 2)                 AS pct_ops_in_qtr,
    ROUND(100.0 * qa.ops_sum / qt.qtr_sum, 2)                 AS pct_sum_in_qtr
FROM qtr_age qa
JOIN qtr_totals qt ON qa.txn_quarter = qt.txn_quarter
ORDER BY qa.txn_quarter, qa.age_group;