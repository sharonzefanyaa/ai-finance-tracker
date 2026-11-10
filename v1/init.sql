
-- Finance Tracker database schema
-- Based on db_structure.xlsx

CREATE TABLE IF NOT EXISTS accounts (
    account_id SERIAL PRIMARY KEY,
    account_name VARCHAR(100) NOT NULL,
    account_type VARCHAR(100) NOT NULL
        CHECK (account_type IN ('cash', 'bank', 'credit_card', 'e-wallet', 'loan', 'other')),
    balance BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS budgets (
    budget_id SERIAL PRIMARY KEY,
    category VARCHAR(100) NOT NULL,
    limit_amount BIGINT DEFAULT 0 NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS savings (
    savings_id SERIAL PRIMARY KEY,
    savings_name VARCHAR(100) NOT NULL,
    target_amount BIGINT DEFAULT 0,
    current_amount BIGINT DEFAULT 0,
    target_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transactions (
    transaction_id SERIAL PRIMARY KEY,
    transaction_type VARCHAR(100) NOT NULL
        CHECK (transaction_type IN ('expenses', 'income', 'transfer', 'savings')),
    amount BIGINT NOT NULL,
    category VARCHAR(100),
    merchant VARCHAR(100),
    location VARCHAR(100),
    from_account_id INTEGER REFERENCES accounts(account_id)
        ON DELETE SET NULL,
    to_account_id INTEGER REFERENCES accounts(account_id)
        ON DELETE SET NULL,
    savings_id INTEGER REFERENCES savings(savings_id)
        ON DELETE SET NULL,
    notes TEXT,
    transaction_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transactions_created_at
    ON transactions(created_at);

CREATE INDEX IF NOT EXISTS idx_transactions_category
    ON transactions(category);

CREATE INDEX IF NOT EXISTS idx_transactions_type
    ON transactions(transaction_type);

CREATE UNIQUE INDEX IF NOT EXISTS uq_accounts_name ON accounts (LOWER(account_name));
CREATE UNIQUE INDEX IF NOT EXISTS uq_budgets_category  ON budgets  (LOWER(category));
CREATE UNIQUE INDEX IF NOT EXISTS uq_savings_name  ON savings  (LOWER(savings_name));