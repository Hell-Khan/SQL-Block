-- 1. Таблица клиентов
CREATE TABLE customer_info (
    Id_client BIGINT PRIMARY KEY,
    Total_amount NUMERIC,
    Gender TEXT,
    Age INTEGER,
    Count_city INTEGER,
    Response_communcation INTEGER,
    Communication_3month INTEGER,
    Tenure INTEGER
);

-- 2. Таблица транзакций
CREATE TABLE transactions (
    date_new DATE,
    Id_check BIGINT,
    ID_client BIGINT,
    Count_products NUMERIC,
    Sum_payment NUMERIC
);

Select * from customer_info;

Select * from transactions;