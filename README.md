# AI Finance Tracker: Telegram + n8n + Postgres

A personal finance assistant you talk to in plain language on Telegram. Send messages like `makan sushi 120rb pakai BCA` or `sisa uangku berapa?` and an LLM-powered n8n workflow works out what you mean, records the data in PostgreSQL, and replies in chat.

Built as an AI engineering portfolio project: **LLM intent routing, structured extraction, deterministic validation, and a real database**, all self-hosted with Docker Compose.

> Inputs work in Indonesian, English, or a mix of both (shorthand such as `rb`/`k` = thousand, `jt` = million and `M` = billion is understood). Replies are currently in Indonesian.

## Features

| Capability | What you can say (examples) |
|---|---|
| **Record transactions** (expense, income, transfer, savings deposit) | `makan sushi 120rb pakai BCA`, `gaji masuk 10jt ke BCA`, `transfer 500rb dari BCA ke OVO`, `tabung 1jt dari BCA ke dana darurat` |
| **Backdated transactions** | `makan malam 80rb pakai OVO kemarin`, `bayar listrik 300rb pakai BCA 5 hari lalu` (up to 60 days back; future dates such as `besok` are rejected) |
| **Income with a source** | `freelance 1,5jt ke OVO`, `gaji masuk 8jt ke BCA`; the source (`gaji`, `bonus`, `freelance`, `cashback`, `jual ...`) becomes the category, and the bot asks for it when it is missing |
| **Expenses with or without a budget** | If a budget exists, the reply shows its usage; if not, the expense is still recorded and the bot offers to create the budget |
| **Manage setup** (accounts, budgets, savings goals: create, update, increase, decrease, delete) | `buat akun OVO tipe e-wallet saldo awal 500rb`, `buat budget food 500rb`, `naikkan budget food 600rb`, `hapus savings rumah` |
| **Financial insights** | `sisa uangku berapa?`, `status budget bulan ini`, `kalau aku beli laptop 15jt, aman?` |
| **Transaction tables** | `rincikan pengeluaran bulan ini`, `apa aja pengeluaranku di kategori shopping?` print a monospace table straight from the database |
| **Built-in guide, no AI** | `/start` (how the bot works), `/help` (formats and keywords), plus `halo` and `kamu bisa apa?` |
| **Budget alerts** | After an expense the bot reports budget usage and warns past 80% |
| **Validation with helpful errors** | An unknown account, a missing create word or an out-of-range date returns a specific message and the balance stays unchanged |
| **Multi-intent messages** | `gaji masuk 10jt ke BCA terus buat budget food 500rb` runs both actions |
| **Activity log** | Every reply the bot sends is stored in `activity_log` (message, detected intents, status) |

## How it works

```
Telegram message
      |
      v
Telegram Trigger (restricted to your user ID)
      |
      v
Command check (regex, no AI) --> /start, /help, greetings, "kamu bisa apa?" --> fixed text reply
      |
      v
AI Intent Router (LLM) --> intents: record_transaction | financial_setup | financial_insight
      |
      +--> record_transaction --> LLM parser --> date + amount normalization (code)
      |                              --> record_transaction() in Postgres (validate, insert, update balances)
      |                              --> formatter --> reply
      +--> financial_setup    --> LLM parser --> safety nets (code) --> validate against DB
      |                              --> create / update / adjust / delete --> formatter --> reply
      +--> financial_insight  --> finance_snapshot() + transactions --> facts computed in code
      |                              --> LLM writes the words --> numeric check --> reply (+ table or breakdown printed by the app)
      +--> (no intent)        --> "unmatched input" help message

Every reply --> activity_log
```

### Design principles

- **The LLM interprets, code and SQL decide.** Models only classify and extract fields or phrase an answer. Existence checks, balance updates, budget math, date arithmetic and totals are done by deterministic SQL and code.
- **Never invent values.** Parser prompts return `null` for anything the user did not state, and the code adds guards on top of the prompts:
  - relative dates ("kemarin", "5 hari lalu") are resolved in code and limited to 60 days back; future words ("besok", "lusa", "3 hari lagi") are rejected instead of being recorded as today
  - an income whose category the model left empty is filled from a small source-word list (`gaji`, `freelance`, `bonus` ...) applied to the user's own text
  - a budget counts as chosen on purpose only with `kategori <name>` or `masuk ke budget <name>`; if it does not exist the expense is rejected, while a plain mention such as `budget coffee` falls back to keyword matching (`kopi` lands in food)
  - a setup `create` only runs when the message contains a create word (`buat`, `bikin`, `set` ...), so a vague message cannot create anything by accident
  - an account named "BCA Saving" is not mistaken for a savings goal
  - every `Rp` amount in an insight answer must exist in the data, otherwise the reply is flagged
  - transaction tables and calculation breakdowns are printed by the app from database rows, never typed by the model
- **Insights are grounded.** The analytics prompt answers only from the facts computed from Postgres.
- **Idempotent writes.** Each transaction gets a `source_key` (Telegram update ID + position), so a re-delivered update cannot record twice.

## Tech stack

- **n8n 2.x** (self-hosted): orchestration, 73-node workflow
- **OpenAI `gpt-4o-mini`**: intent routing, transaction parsing, setup parsing, insight intent, analytics wording
- **PostgreSQL 15**: finance data, SQL functions and n8n's own storage
- **Telegram Bot API**: chat interface (webhook)
- **Cloudflare Tunnel**: exposes the local n8n webhook over HTTPS, no port forwarding needed
- **Docker Compose**: one-command local deployment

## Database

Schema in [`init.sql`](./init.sql), applied automatically the first time the Postgres volume is created. Functions in [`functions.sql`](./functions.sql), applied on every `start.sh` (safe to repeat, never touches data).

| Table | Purpose |
|---|---|
| `accounts` | Cash, bank, e-wallet, credit card, loan and other accounts, with current balance |
| `budgets` | One monthly limit per spending category (`category` is unique, case-insensitive) |
| `savings` | Savings goals with target amount, current amount and optional target date |
| `transactions` | The ledger: expense, income, transfer and savings deposit, distinguished by `transaction_type` |
| `activity_log` | One row per bot reply: message, detected intents, status (`succeeded`, `rejected`, `mixed`, `error`) |
| `categories`, `category_keywords` | Maps what was bought (`ngopi`, `parkir`, `netflix` ...) to a category, so an expense lands in the right budget |

| Function | Purpose |
|---|---|
| `record_transaction(jsonb)` | Validates and records one transaction in a single SQL transaction (all or nothing), updates balances and returns the numbers for the reply |
| `fin_resolve_budget(jsonb)` | Decides which budget an expense belongs to: the budget the user named, then a keyword in what was bought, then the AI's category |
| `finance_snapshot()` | Balances, budget usage, savings progress and monthly totals used by insights |

Rules enforced in SQL: amounts between Rp1 and Rp100 billion (an expense larger than the balance is rejected for insufficient funds before the size matters); cash, bank, e-wallet and other accounts cannot go below zero (credit cards and loans can); a transfer needs two different accounts.

## Getting started

### Prerequisites

- Docker and Docker Compose
- A Telegram bot token from [@BotFather](https://t.me/BotFather)
- Your Telegram user ID (for example from [@userinfobot](https://t.me/userinfobot))
- An OpenAI API key (set a spending limit on the account)
- On Windows, run the shell script from Git Bash or WSL

### 1. Configure

```bash
cp .env.example .env
```

Fill in `.env`:

- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
- `N8N_ENCRYPTION_KEY`: generate with `openssl rand -hex 32` and **back it up**. If it is lost, saved n8n credentials cannot be decrypted.

Avoid a bare `$` in values (Compose treats `$name` as a variable). Use `$$` or wrap the value in single quotes.

### 2. Start the stack

```bash
bash start.sh
```

The script starts the Cloudflare quick tunnel, reads its public URL, starts Postgres, applies `functions.sql`, then starts n8n with `WEBHOOK_URL` set to that URL so Telegram can reach your webhook.

> Quick tunnel URLs change every time the tunnel starts, so always start the project with `start.sh` rather than a plain `docker compose up`.

### 3. Set up n8n

1. Open `http://localhost:5678` and create the owner account with a strong password.
2. Import [`finance-tracker.json`](./finance-tracker.json) (three-dot menu, then **Import from file**).
3. Create three credentials and attach them to the nodes that use them:
   - **Telegram**: your bot token
   - **OpenAI**: your API key
   - **Postgres**: host `postgres`, port `5432`, and the database, user and password from `.env`
4. In the **Telegram Trigger** node, replace `YOUR_TELEGRAM_USER_ID` in **Restrict to User IDs** with your own Telegram user ID. Until you do, the bot ignores everyone.
5. **Publish** the workflow (in older n8n versions: toggle **Active**).

After every restart the tunnel URL changes: unpublish and publish the workflow again so Telegram registers the new webhook.

### 4. Try it

Records need existing accounts, so set up first. Send these to your bot in order:

| # | Message | What to expect |
|---|---|---|
| 1 | `/start` | Welcome text: how the bot works and its rules (no AI) |
| 2 | `buat akun BCA tipe bank saldo awal 10jt` | Account created |
| 3 | `buat akun OVO tipe e-wallet saldo awal 500rb` | Second account created |
| 4 | `buat budget food 1jt` | Budget created |
| 5 | `buat savings dana darurat target 20jt` | Savings goal created |
| 6 | `gaji masuk 8jt ke BCA` | Income recorded, balance before and after |
| 7 | `makan siang 50rb pakai BCA` | Expense recorded under the food budget, with usage and remaining budget |
| 8 | `beli ram laptop 3jt pakai BCA` | No shopping budget exists: the expense is still recorded and the bot offers to create one |
| 9 | `transfer 1jt dari BCA ke OVO` | Transfer recorded, both balances shown |
| 10 | `tabung 2jt dari BCA ke dana darurat` | Savings deposit with progress toward the target |
| 11 | `ngopi 25rb pakai Mandiri` | Rejected: account not found, lists the accounts that exist, balance unchanged |
| 12 | `makan malam 80rb pakai OVO kemarin` | Recorded with yesterday's date |
| 13 | `sisa uangku berapa?` | Insight: money on hand and unallocated money, computed in code |
| 14 | `rincikan pengeluaran bulan ini` | A table of this month's expenses printed from the database |
| 15 | `kalau aku beli laptop 15jt, budgetku aman?` | A simulation only; nothing is recorded |

Extras worth showing: `halo`, `/help`, `buat budget gym` (incomplete command, helpful error), `hapus akun OVO` (deletes one named item; bulk delete is refused) and `makan 40rb dan parkir 10rb pakai BCA` (two transactions in one message).

Check the data any time:

```bash
docker compose exec postgres sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT * FROM transactions;"'
```

## Testing

The workflow was verified with manual test plans sent through Telegram, each checked in three places: the Telegram reply, the n8n Executions tab and the database. The latest round has 57 messages in six groups (fixed commands, setup and the create-word guard, transactions, negative cases, insights and tables, combined messages), each with SQL checkpoints for balances and row counts. 56 passed on the first run; the one miss (`besok` recorded as today) was fixed by rejecting future dates.

Reset the finance tables between phases instead of rebuilding Docker:

```bash
docker compose exec postgres sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB -c "TRUNCATE transactions, savings, budgets, accounts, activity_log RESTART IDENTITY CASCADE;"'
```

Do not truncate `categories` or `category_keywords`; they hold the keyword map that `functions.sql` seeds.

## Operating the project

| Goal | Command |
|---|---|
| Stop everything, keep all data | `docker compose stop` |
| Resume | `bash start.sh` |
| Remove containers, keep data | `docker compose down` |
| **Delete all data** (volumes) | `docker compose down -v` |
| Change a SQL function | edit `functions.sql`, then `bash start.sh` |
| Back up the database | `docker compose exec -T postgres sh -c 'pg_dump -U $POSTGRES_USER $POSTGRES_DB > /tmp/backup.sql'` then `docker compose cp postgres:/tmp/backup.sql ./backups/backup.sql` |

Containers are disposable; data lives in the `postgres_data` and `n8n_data` volumes.

The n8n image is not pinned to a version. Pin a tag in `docker-compose.yml` (for example `docker.n8n.io/n8nio/n8n:2.x.y`) if you want reproducible upgrades, and back up before upgrading.

## Security notes

- n8n is bound to `127.0.0.1`, and Postgres publishes no ports.
- The Telegram Trigger is restricted to an allowed user ID.
- `.env` is git-ignored. Never commit it, backups, or real IDs and tokens.
- Before exporting the workflow to a public repo, run `bash sanitize-workflow.sh <export.json>`. It replaces your Telegram user ID and removes the n8n instance ID, then refuses to finish if something that looks like a token, API key or tunnel URL is still in the file. n8n exports never contain credential secrets, only credential names.
- The quick tunnel also exposes the n8n editor URL. Use a strong owner password and stop the tunnel when you are not using the bot: `docker compose stop cloudflared`.

## Known limitations

- **Single user.** Enforced by the Telegram user ID restriction; there is no multi-user separation in the database.
- **Multiple transactions in one message** are supported (up to 10), but the LLM can misread a long message, for example merging two amounts. One transaction per message is the most reliable.
- **Recorded transactions cannot be edited or undone yet.** Correct a mistake with a new transaction.
- **Backdating is limited to 60 days.** Vague dates ("bulan lalu") are rejected.
- **Transfer fees are not calculated.** Record a real fee as a separate expense (for example `biaya admin 2500 pakai BCA`).
- **Rupiah only.** Supported shorthand: `rb`, `ribu`, `k`, `jt`, `juta`, `M`, `miliar`.
- **LLM classification can misfire** on unusual phrasing. Parsing is guarded by validation and code, but not perfect.
- **Income source words are a fixed list.** An unlisted word (for example `fee desain`) is recorded as `other` and the bot asks for the source.
- **Advice answers are free text.** The wording can vary or repeat a budget name; the numbers in them are checked against the data, the wording is not.
- **Quick tunnel URL changes on every start**, so the workflow must be unpublished and published again after a restart.
- Some SQL nodes build queries by interpolating parsed text. The user-ID restriction limits exposure, but parameterized queries are on the roadmap.

## Roadmap

- Parameterized queries in all Postgres nodes
- Cross-check parsed transaction amounts against the numbers in the original message
- Edit and undo for recorded transactions
- Structured (JSON schema) output for the intent router, plus an evaluation set with accuracy metrics
- Per-intent text segmentation so each parser sees only its part of a multi-intent message
- Optional transfer fee field
- English replies and multi-currency support
- Named Cloudflare tunnel or VPS deployment for a stable URL

## Project structure

```
.
├── docker-compose.yml       # postgres + n8n + cloudflared
├── start.sh                 # starts tunnel, applies functions.sql, then n8n with the right WEBHOOK_URL
├── init.sql                 # database schema (first run only)
├── functions.sql            # SQL functions, categories and keyword map (applied on every start)
├── finance-tracker.json     # n8n workflow export (no secrets)
├── sanitize-workflow.sh     # makes an n8n export safe to commit
├── .env.example             # configuration template
├── .gitignore
└── README.md
```

## License

This project is licensed under the MIT License. See the LICENSE file.
