-- functions.sql: every function + the source_key column. Safe to run any number of times
-- (CREATE OR REPLACE / IF NOT EXISTS) and never touches your data.
-- start.sh runs this file on every start, so to change a function: edit this file, then run  bash start.sh
-- (or apply it right now:  docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' < functions.sql )

-- 1) Idempotency: one Telegram update + position in the message = one transaction
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS source_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_transactions_source_key
    ON transactions (source_key) WHERE source_key IS NOT NULL;

-- 2) Helpers
CREATE OR REPLACE FUNCTION fin_nz(x text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT NULLIF(NULLIF(NULLIF(btrim(x), ''), 'null'), 'undefined')
$$;

-- Rejection payload: reason + the lists the user needs to fix the message
CREATE OR REPLACE FUNCTION fin_reject(reason text, extra jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'status', 'rejected',
        'reason', reason,
        'available', jsonb_build_object(
            'budgets',  (SELECT coalesce(jsonb_agg(category ORDER BY category), '[]'::jsonb) FROM budgets),
            'accounts', (SELECT coalesce(jsonb_agg(account_name ORDER BY account_name), '[]'::jsonb) FROM accounts),
            'savings',  (SELECT coalesce(jsonb_agg(savings_name ORDER BY savings_name), '[]'::jsonb) FROM savings)
        )
    ) || extra
$$;

-- 2b) Expense category map ---------------------------------------------------------------
-- Used only to CLASSIFY what was bought (gym -> health_fitness). Your budgets stay free-form:
-- name them whatever you like; a budget is linked to a category through category_keywords
-- (budget "makan" -> food, budget "gym" -> health_fitness, budget "hobi" -> no category).
-- Add your own words any time, e.g.:
--   INSERT INTO category_keywords (keyword, category_key) VALUES ('lego', 'entertainment');
-- Move a default word:  UPDATE category_keywords SET category_key = 'food' WHERE keyword = 'kopi';
CREATE TABLE IF NOT EXISTS categories (
    category_key TEXT PRIMARY KEY,
    label        TEXT NOT NULL,
    suggest_name TEXT                      -- budget name suggested in the "budget missing" reply
);
CREATE TABLE IF NOT EXISTS category_keywords (
    keyword      TEXT PRIMARY KEY CHECK (keyword = lower(btrim(keyword))),
    category_key TEXT NOT NULL REFERENCES categories(category_key) ON DELETE CASCADE
);

INSERT INTO categories (category_key, label, suggest_name) VALUES
    ('food', 'Food', 'food'),
    ('transport', 'Transport', 'transport'),
    ('shopping', 'Shopping', 'shopping'),
    ('bills', 'Bills & Utilities', 'tagihan'),
    ('health_fitness', 'Health & Fitness', 'health'),
    ('entertainment', 'Entertainment', 'entertainment'),
    ('subscriptions', 'Subscriptions', 'langganan'),
    ('education', 'Education', 'education'),
    ('personal_care', 'Personal Care', 'skincare'),
    ('home', 'Home', 'rumah'),
    ('travel', 'Travel', 'travel'),
    ('gifts_donations', 'Gifts & Donations', 'hadiah'),
    ('pets', 'Pets', 'hewan'),
    ('other', 'Other', NULL)
ON CONFLICT (category_key) DO NOTHING;

INSERT INTO category_keywords (keyword, category_key) VALUES
    ('food', 'food'),
    ('makan', 'food'),
    ('minum', 'food'),
    ('ngopi', 'food'),
    ('kopi', 'food'),
    ('jajan', 'food'),
    ('sarapan', 'food'),
    ('lunch', 'food'),
    ('dinner', 'food'),
    ('brunch', 'food'),
    ('snack', 'food'),
    ('cemilan', 'food'),
    ('boba', 'food'),
    ('resto', 'food'),
    ('restoran', 'food'),
    ('warteg', 'food'),
    ('cafe', 'food'),
    ('kafe', 'food'),
    ('gofood', 'food'),
    ('grabfood', 'food'),
    ('shopeefood', 'food'),
    ('makanan', 'food'),
    ('kuliner', 'food'),
    ('groceries', 'food'),
    ('sembako', 'food'),
    ('supermarket', 'food'),
    ('belanja bulanan', 'food'),
    ('es teh', 'food'),
    ('transport', 'transport'),
    ('parkir', 'transport'),
    ('bensin', 'transport'),
    ('bbm', 'transport'),
    ('pertamax', 'transport'),
    ('pertalite', 'transport'),
    ('tol', 'transport'),
    ('e-toll', 'transport'),
    ('etoll', 'transport'),
    ('grab', 'transport'),
    ('gojek', 'transport'),
    ('ojol', 'transport'),
    ('ojek', 'transport'),
    ('taksi', 'transport'),
    ('taxi', 'transport'),
    ('krl', 'transport'),
    ('mrt', 'transport'),
    ('lrt', 'transport'),
    ('transjakarta', 'transport'),
    ('busway', 'transport'),
    ('kereta', 'transport'),
    ('bus', 'transport'),
    ('transportasi', 'transport'),
    ('service motor', 'transport'),
    ('servis motor', 'transport'),
    ('service mobil', 'transport'),
    ('servis mobil', 'transport'),
    ('cuci mobil', 'transport'),
    ('cuci motor', 'transport'),
    ('isi bensin', 'transport'),
    ('tambal ban', 'transport'),
    ('ganti oli', 'transport'),
    ('pajak kendaraan', 'transport'),
    ('pajak motor', 'transport'),
    ('pajak mobil', 'transport'),
    ('tiket kereta', 'transport'),
    ('shopping', 'shopping'),
    ('belanja', 'shopping'),
    ('baju', 'shopping'),
    ('kaos', 'shopping'),
    ('kemeja', 'shopping'),
    ('celana', 'shopping'),
    ('jaket', 'shopping'),
    ('sepatu', 'shopping'),
    ('sandal', 'shopping'),
    ('tas', 'shopping'),
    ('fashion', 'shopping'),
    ('tokopedia', 'shopping'),
    ('shopee', 'shopping'),
    ('lazada', 'shopping'),
    ('elektronik', 'shopping'),
    ('gadget', 'shopping'),
    ('charger', 'shopping'),
    ('headphone', 'shopping'),
    ('earphone', 'shopping'),
    ('aksesoris', 'shopping'),
    ('case hp', 'shopping'),
    ('jam tangan', 'shopping'),
    ('bills', 'bills'),
    ('bills & utilities', 'bills'),
    ('tagihan', 'bills'),
    ('listrik', 'bills'),
    ('pln', 'bills'),
    ('token', 'bills'),
    ('pdam', 'bills'),
    ('internet', 'bills'),
    ('wifi', 'bills'),
    ('indihome', 'bills'),
    ('pulsa', 'bills'),
    ('bpjs', 'bills'),
    ('cicilan', 'bills'),
    ('asuransi', 'bills'),
    ('pajak', 'bills'),
    ('paket data', 'bills'),
    ('biaya admin', 'bills'),
    ('health_fitness', 'health_fitness'),
    ('health fitness', 'health_fitness'),
    ('health & fitness', 'health_fitness'),
    ('health', 'health_fitness'),
    ('gym', 'health_fitness'),
    ('fitness', 'health_fitness'),
    ('yoga', 'health_fitness'),
    ('pilates', 'health_fitness'),
    ('zumba', 'health_fitness'),
    ('olahraga', 'health_fitness'),
    ('renang', 'health_fitness'),
    ('futsal', 'health_fitness'),
    ('badminton', 'health_fitness'),
    ('lari', 'health_fitness'),
    ('dokter', 'health_fitness'),
    ('obat', 'health_fitness'),
    ('apotek', 'health_fitness'),
    ('apotik', 'health_fitness'),
    ('klinik', 'health_fitness'),
    ('vitamin', 'health_fitness'),
    ('suplemen', 'health_fitness'),
    ('protein', 'health_fitness'),
    ('whey', 'health_fitness'),
    ('medical', 'health_fitness'),
    ('kesehatan', 'health_fitness'),
    ('sport', 'health_fitness'),
    ('sports', 'health_fitness'),
    ('kacamata', 'health_fitness'),
    ('softlens', 'health_fitness'),
    ('member gym', 'health_fitness'),
    ('sewa lapangan', 'health_fitness'),
    ('personal trainer', 'health_fitness'),
    ('rumah sakit', 'health_fitness'),
    ('cek kesehatan', 'health_fitness'),
    ('dokter gigi', 'health_fitness'),
    ('entertainment', 'entertainment'),
    ('bioskop', 'entertainment'),
    ('nonton', 'entertainment'),
    ('film', 'entertainment'),
    ('cinema', 'entertainment'),
    ('konser', 'entertainment'),
    ('game', 'entertainment'),
    ('gaming', 'entertainment'),
    ('steam', 'entertainment'),
    ('karaoke', 'entertainment'),
    ('hiburan', 'entertainment'),
    ('timezone', 'entertainment'),
    ('playstation', 'entertainment'),
    ('ps5', 'entertainment'),
    ('biliar', 'entertainment'),
    ('billiard', 'entertainment'),
    ('bowling', 'entertainment'),
    ('top up game', 'entertainment'),
    ('topup game', 'entertainment'),
    ('tiket konser', 'entertainment'),
    ('board game', 'entertainment'),
    ('taman hiburan', 'entertainment'),
    ('subscriptions', 'subscriptions'),
    ('langganan', 'subscriptions'),
    ('netflix', 'subscriptions'),
    ('spotify', 'subscriptions'),
    ('disney', 'subscriptions'),
    ('hbo', 'subscriptions'),
    ('vidio', 'subscriptions'),
    ('icloud', 'subscriptions'),
    ('chatgpt', 'subscriptions'),
    ('claude', 'subscriptions'),
    ('subscription', 'subscriptions'),
    ('canva', 'subscriptions'),
    ('notion', 'subscriptions'),
    ('youtube premium', 'subscriptions'),
    ('google one', 'subscriptions'),
    ('apple music', 'subscriptions'),
    ('disney+', 'subscriptions'),
    ('education', 'education'),
    ('kursus', 'education'),
    ('buku', 'education'),
    ('kuliah', 'education'),
    ('spp', 'education'),
    ('ukt', 'education'),
    ('sekolah', 'education'),
    ('les', 'education'),
    ('course', 'education'),
    ('udemy', 'education'),
    ('coursera', 'education'),
    ('seminar', 'education'),
    ('workshop', 'education'),
    ('bootcamp', 'education'),
    ('atk', 'education'),
    ('fotokopi', 'education'),
    ('pendidikan', 'education'),
    ('belajar', 'education'),
    ('toefl', 'education'),
    ('ielts', 'education'),
    ('alat tulis', 'education'),
    ('personal_care', 'personal_care'),
    ('personal care', 'personal_care'),
    ('skincare', 'personal_care'),
    ('salon', 'personal_care'),
    ('barbershop', 'personal_care'),
    ('cukur', 'personal_care'),
    ('kosmetik', 'personal_care'),
    ('makeup', 'personal_care'),
    ('spa', 'personal_care'),
    ('massage', 'personal_care'),
    ('pijat', 'personal_care'),
    ('parfum', 'personal_care'),
    ('shampoo', 'personal_care'),
    ('sampo', 'personal_care'),
    ('facial', 'personal_care'),
    ('manicure', 'personal_care'),
    ('pedicure', 'personal_care'),
    ('potong rambut', 'personal_care'),
    ('make up', 'personal_care'),
    ('home', 'home'),
    ('rumah', 'home'),
    ('furniture', 'home'),
    ('perabot', 'home'),
    ('kos', 'home'),
    ('kost', 'home'),
    ('kontrakan', 'home'),
    ('laundry', 'home'),
    ('gas', 'home'),
    ('lpg', 'home'),
    ('galon', 'home'),
    ('renovasi', 'home'),
    ('tukang', 'home'),
    ('alat rumah', 'home'),
    ('peralatan rumah', 'home'),
    ('sewa kos', 'home'),
    ('sewa rumah', 'home'),
    ('alat dapur', 'home'),
    ('cat tembok', 'home'),
    ('servis ac', 'home'),
    ('service ac', 'home'),
    ('travel', 'travel'),
    ('hotel', 'travel'),
    ('pesawat', 'travel'),
    ('traveling', 'travel'),
    ('travelling', 'travel'),
    ('liburan', 'travel'),
    ('wisata', 'travel'),
    ('villa', 'travel'),
    ('airbnb', 'travel'),
    ('penginapan', 'travel'),
    ('visa', 'travel'),
    ('staycation', 'travel'),
    ('tiket pesawat', 'travel'),
    ('tiket wisata', 'travel'),
    ('oleh oleh', 'travel'),
    ('gifts_donations', 'gifts_donations'),
    ('gifts donations', 'gifts_donations'),
    ('gifts & donations', 'gifts_donations'),
    ('hadiah', 'gifts_donations'),
    ('kado', 'gifts_donations'),
    ('donasi', 'gifts_donations'),
    ('sedekah', 'gifts_donations'),
    ('zakat', 'gifts_donations'),
    ('infaq', 'gifts_donations'),
    ('amplop', 'gifts_donations'),
    ('kondangan', 'gifts_donations'),
    ('sumbangan', 'gifts_donations'),
    ('angpao', 'gifts_donations'),
    ('angpau', 'gifts_donations'),
    ('hampers', 'gifts_donations'),
    ('pets', 'pets'),
    ('hewan', 'pets'),
    ('vet', 'pets'),
    ('kucing', 'pets'),
    ('anjing', 'pets'),
    ('steril', 'pets'),
    ('petshop', 'pets'),
    ('pakan kucing', 'pets'),
    ('makanan kucing', 'pets'),
    ('pasir kucing', 'pets'),
    ('dokter hewan', 'pets'),
    ('pakan anjing', 'pets'),
    ('makanan anjing', 'pets')
ON CONFLICT (keyword) DO NOTHING;

-- Decide which budget an expense belongs to. Order of trust:
--   1) a budget the user wrote themselves ("... kategori entertainment")
--   2) a keyword found in what was bought (notes / merchant): this CORRECTS the AI (gym is never entertainment)
--   3) the AI's category key (food, transport, health_fitness, ...)
-- Never guesses: no matching budget -> a rejection that says which category it is and what to do.
CREATE OR REPLACE FUNCTION fin_resolve_budget(p jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_text text := lower(btrim(concat_ws(' ', fin_nz(p->>'notes'), fin_nz(p->>'merchant'))));
    v_tail text := lower(btrim(coalesce(fin_nz(p->>'explicit_tail'), '')));
    v_ai   text := lower(btrim(coalesce(fin_nz(p->>'category'), '')));
    v_kw   text;
    v_ck   text;
    v_bid  int;
    v_label text;
    v_sug   text;
BEGIN
    -- 1) user-named budget (or a word that maps to a budget they have)
    IF v_tail <> '' THEN
        SELECT budget_id INTO v_bid FROM budgets
         WHERE v_tail = lower(category) OR v_tail LIKE lower(category) || ' %'
         ORDER BY length(category) DESC LIMIT 1;
        IF v_bid IS NULL THEN
            SELECT k.category_key INTO v_ck FROM category_keywords k
             WHERE v_tail = k.keyword OR v_tail LIKE k.keyword || ' %'
             ORDER BY length(k.keyword) DESC LIMIT 1;
            IF v_ck IS NOT NULL THEN
                SELECT b.budget_id INTO v_bid FROM budgets b
                  JOIN category_keywords bk ON bk.keyword = lower(b.category)
                 WHERE bk.category_key = v_ck ORDER BY b.budget_id LIMIT 1;
            END IF;
        END IF;
        IF v_bid IS NOT NULL THEN
            RETURN jsonb_build_object('budget_id', v_bid, 'via', 'explicit');
        END IF;
        RETURN jsonb_build_object('error', 'explicit_budget_not_found', 'name', split_part(v_tail, ' ', 1));
    END IF;

    -- 2) keyword in what was bought; the longest match wins ("makanan kucing" beats "makanan")
    SELECT k.keyword, k.category_key INTO v_kw, v_ck
      FROM category_keywords k
     WHERE v_text ~ ('(^|[^a-z0-9])' || regexp_replace(k.keyword, '([^a-z0-9 ])', '\\\1', 'g') || '([^a-z0-9]|$)')
     ORDER BY length(k.keyword) DESC, k.keyword LIMIT 1;

    -- 3) otherwise the AI's category key
    IF v_ck IS NULL AND v_ai <> '' THEN
        SELECT category_key INTO v_ck FROM categories WHERE category_key = v_ai;
        IF v_ck IS NULL THEN SELECT category_key INTO v_ck FROM category_keywords WHERE keyword = v_ai; END IF;
    END IF;
    IF v_ck = 'other' THEN v_ck := NULL; END IF;

    IF v_ck IS NULL THEN
        SELECT budget_id INTO v_bid FROM budgets WHERE lower(category) = v_ai;   -- AI named one of your custom budgets
        IF v_bid IS NOT NULL THEN RETURN jsonb_build_object('budget_id', v_bid, 'via', 'name'); END IF;
        RETURN jsonb_build_object('error', 'category_unknown',
                                  'name', coalesce(fin_nz(p->>'notes'), fin_nz(p->>'merchant'), nullif(v_ai, ''), '?'));
    END IF;

    -- budgets that belong to this category; prefer the one named like the word the user used
    SELECT b.budget_id INTO v_bid
      FROM budgets b
      JOIN category_keywords bk ON bk.keyword = lower(b.category)
     WHERE bk.category_key = v_ck
     ORDER BY (lower(b.category) = coalesce(v_kw, '')) DESC, (lower(b.category) = v_ck) DESC, b.budget_id
     LIMIT 1;
    IF v_bid IS NOT NULL THEN
        RETURN jsonb_build_object('budget_id', v_bid, 'via', 'category', 'kw', v_kw);
    END IF;

    SELECT label, suggest_name INTO v_label, v_sug FROM categories WHERE category_key = v_ck;
    RETURN jsonb_build_object('error', 'category_budget_missing',
                              'label', v_label, 'suggest', coalesce(v_sug, v_ck),
                              'subject', coalesce(v_kw, fin_nz(p->>'notes'), fin_nz(p->>'merchant'), v_label));
END;
$$;

-- 3) The function itself
CREATE OR REPLACE FUNCTION record_transaction(p jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    v_type      text := lower(coalesce(fin_nz(p->>'type'), ''));
    v_amount    bigint;
    v_cat       text := fin_nz(p->>'category');
    v_from_n    text := fin_nz(p->>'from_account');
    v_to_n      text := fin_nz(p->>'to_account');
    v_sav_n     text := fin_nz(p->>'savings_name');
    v_key       text := fin_nz(p->>'source_key');
    v_cat_def   boolean := false;
    v_res       jsonb;
    v_note      text := fin_nz(p->>'notes');
    v_no_budget boolean := false;
    v_unb_cat   text;
    v_sav_def   boolean := false;
    v_date      timestamp;
    v_date_bad  boolean := false;
    v_from      accounts%ROWTYPE;
    v_to        accounts%ROWTYPE;
    v_sav       savings%ROWTYPE;
    v_bud       budgets%ROWTYPE;
    v_tx        transactions%ROWTYPE;
    v_from_before bigint;
    v_to_before   bigint;
    v_ms        timestamp;
    v_spent     bigint;
    v_inc       bigint;
    v_inc_prev  bigint;
    v_sav_month bigint;
    v_out       jsonb;
BEGIN
    -- ---- basic validation -------------------------------------------------
    IF v_type NOT IN ('expenses', 'income', 'transfer', 'savings') THEN
        RETURN fin_reject('bad_type');
    END IF;

    BEGIN
        v_amount := round((p->>'amount')::numeric)::bigint;
    EXCEPTION WHEN others THEN
        v_amount := NULL;
    END;
    IF v_amount IS NULL OR v_amount <= 0 OR v_amount > 100000000000 THEN
        RETURN fin_reject('bad_amount');
    END IF;

    -- date: ignore (and flag) anything that is not a real date
    IF fin_nz(p->>'date') IS NOT NULL THEN
        BEGIN
            v_date := (p->>'date')::timestamp;
        EXCEPTION WHEN others THEN
            v_date := NULL; v_date_bad := true;
        END;
    END IF;

    -- duplicate delivery of the same Telegram update
    IF v_key IS NOT NULL AND EXISTS (SELECT 1 FROM transactions WHERE source_key = v_key) THEN
        RETURN jsonb_build_object('status', 'duplicate');
    END IF;

    -- ---- resolve accounts / budget / savings (case-insensitive) -----------
    IF v_type IN ('expenses', 'transfer', 'savings') THEN
        IF v_from_n IS NULL THEN RETURN fin_reject('from_account_missing'); END IF;
        SELECT * INTO v_from FROM accounts WHERE lower(account_name) = lower(v_from_n);
        IF NOT FOUND THEN RETURN fin_reject('from_account_not_found', jsonb_build_object('name', v_from_n)); END IF;
    END IF;

    IF v_type IN ('income', 'transfer') THEN
        IF v_to_n IS NULL THEN RETURN fin_reject('to_account_missing'); END IF;
        SELECT * INTO v_to FROM accounts WHERE lower(account_name) = lower(v_to_n);
        IF NOT FOUND THEN RETURN fin_reject('to_account_not_found', jsonb_build_object('name', v_to_n)); END IF;
    END IF;

    IF v_type = 'transfer' AND v_from.account_id = v_to.account_id THEN
        RETURN fin_reject('same_account', jsonb_build_object('name', v_from.account_name));
    END IF;

    IF v_type = 'expenses' THEN
        v_res := fin_resolve_budget(p);
        IF v_res ? 'error' THEN
            -- the user named a budget that does not exist: probably a typo, so keep rejecting
            IF v_res->>'error' = 'explicit_budget_not_found' THEN
                RETURN fin_reject(v_res->>'error', v_res - 'error');
            END IF;
            -- otherwise record it without a budget
            v_no_budget := true;
            v_unb_cat := lower(coalesce(
                CASE WHEN v_res->>'error' = 'category_budget_missing' THEN v_res->>'suggest' END,
                nullif(v_cat, ''), 'other'));
        ELSE
            SELECT * INTO v_bud FROM budgets WHERE budget_id = (v_res->>'budget_id')::int;
            -- keep what was actually bought in the notes ("ngopi" lands in food, notes = ngopi)
            IF v_note IS NULL AND fin_nz(v_res->>'kw') IS NOT NULL AND lower(v_res->>'kw') <> lower(v_bud.category) THEN
                v_note := v_res->>'kw';
            END IF;
        END IF;
    END IF;

    IF v_type = 'savings' THEN
        v_sav_def := (v_sav_n IS NULL);          -- no goal named -> 'general', and the reply says so
        v_sav_n := coalesce(v_sav_n, 'general');
        SELECT * INTO v_sav FROM savings WHERE lower(savings_name) = lower(v_sav_n);
        IF NOT FOUND THEN RETURN fin_reject('savings_not_found', jsonb_build_object('name', v_sav_n)); END IF;
    END IF;

    -- ---- lock the rows we are about to change, then re-read balances ------
    PERFORM 1 FROM accounts
     WHERE account_id IN (v_from.account_id, v_to.account_id)
     ORDER BY account_id FOR UPDATE;
    IF v_from.account_id IS NOT NULL THEN SELECT * INTO v_from FROM accounts WHERE account_id = v_from.account_id; END IF;
    IF v_to.account_id   IS NOT NULL THEN SELECT * INTO v_to   FROM accounts WHERE account_id = v_to.account_id;   END IF;

    -- cash, bank, e-wallet and other accounts cannot go below 0 (credit_card and loan may)
    IF v_from.account_id IS NOT NULL
       AND v_from.account_type NOT IN ('credit_card', 'loan')
       AND coalesce(v_from.balance, 0) < v_amount THEN
        RETURN fin_reject('insufficient_funds', jsonb_build_object(
            'name', v_from.account_name, 'balance', coalesce(v_from.balance, 0), 'amount', v_amount));
    END IF;

    -- ---- write (single transaction: all or nothing) -----------------------
    IF v_type = 'income' THEN
        v_cat_def := (v_cat IS NULL) OR lower(coalesce(p->>'category_is_default', 'false')) = 'true';
        v_cat := coalesce(v_cat, 'salary');
    ELSIF v_type = 'expenses' THEN
        v_cat := coalesce(v_bud.category, v_unb_cat);   -- canonical budget name, or the category when there is no budget
    ELSE
        v_cat := NULL;
    END IF;

    v_from_before := v_from.balance;
    v_to_before   := v_to.balance;

    INSERT INTO transactions (transaction_type, amount, category, merchant, location,
                              from_account_id, to_account_id, savings_id, notes,
                              transaction_date, source_key)
    VALUES (v_type, v_amount, v_cat, fin_nz(p->>'merchant'), fin_nz(p->>'location'),
            v_from.account_id, v_to.account_id, v_sav.savings_id, v_note,
            v_date, v_key)
    RETURNING * INTO v_tx;

    IF v_from.account_id IS NOT NULL THEN
        UPDATE accounts SET balance = coalesce(balance, 0) - v_amount, updated_at = NOW()
         WHERE account_id = v_from.account_id RETURNING * INTO v_from;
    END IF;
    IF v_to.account_id IS NOT NULL THEN
        UPDATE accounts SET balance = coalesce(balance, 0) + v_amount, updated_at = NOW()
         WHERE account_id = v_to.account_id RETURNING * INTO v_to;
    END IF;
    IF v_sav.savings_id IS NOT NULL THEN
        UPDATE savings SET current_amount = coalesce(current_amount, 0) + v_amount, updated_at = NOW()
         WHERE savings_id = v_sav.savings_id RETURNING * INTO v_sav;
    END IF;

    -- ---- read-back numbers for the reply (all from the database) ----------
    v_ms := date_trunc('month', coalesce(v_tx.transaction_date, v_tx.created_at));

    v_out := jsonb_build_object(
        'status', 'ok',
        'transaction_id', v_tx.transaction_id,
        'type', v_type,
        'amount', v_amount,
        'category', v_tx.category,
        'category_is_default', v_cat_def,
        'merchant', v_tx.merchant,
        'notes', v_tx.notes,
        'date', to_char(coalesce(v_tx.transaction_date, v_tx.created_at), 'YYYY-MM-DD'),
        'backdated', (to_char(coalesce(v_tx.transaction_date, v_tx.created_at), 'YYYY-MM-DD') <> to_char(localtimestamp, 'YYYY-MM-DD')),
        'date_ignored', v_date_bad,
        'month_start', to_char(v_ms, 'YYYY-MM-DD')
    );

    IF v_from.account_id IS NOT NULL THEN
        v_out := v_out || jsonb_build_object('from', jsonb_build_object(
            'name', v_from.account_name, 'type', v_from.account_type,
            'before', v_from_before, 'after', v_from.balance));
    END IF;
    IF v_to.account_id IS NOT NULL THEN
        v_out := v_out || jsonb_build_object('to', jsonb_build_object(
            'name', v_to.account_name, 'type', v_to.account_type,
            'before', v_to_before, 'after', v_to.balance));
    END IF;

    IF v_type = 'expenses' THEN
        IF v_no_budget THEN
            v_out := v_out || jsonb_build_object('no_budget', true);
        ELSE
            SELECT coalesce(sum(amount), 0) INTO v_spent
              FROM transactions
             WHERE transaction_type = 'expenses'
               AND lower(category) = lower(v_bud.category)
               AND coalesce(transaction_date, created_at) >= v_ms
               AND coalesce(transaction_date, created_at) <  v_ms + interval '1 month';
            v_out := v_out || jsonb_build_object('budget', jsonb_build_object(
                'category', v_bud.category,
                'limit', v_bud.limit_amount,
                'spent', v_spent,
                'remaining', v_bud.limit_amount - v_spent,
                'percent', CASE WHEN coalesce(v_bud.limit_amount, 0) > 0
                                THEN round(v_spent * 100.0 / v_bud.limit_amount, 1) END));
        END IF;
    ELSIF v_type = 'income' THEN
        SELECT coalesce(sum(amount), 0) INTO v_inc
          FROM transactions
         WHERE transaction_type = 'income'
           AND coalesce(transaction_date, created_at) >= v_ms
           AND coalesce(transaction_date, created_at) <  v_ms + interval '1 month';
        SELECT coalesce(sum(amount), 0) INTO v_inc_prev
          FROM transactions
         WHERE transaction_type = 'income'
           AND coalesce(transaction_date, created_at) >= v_ms - interval '1 month'
           AND coalesce(transaction_date, created_at) <  v_ms;
        v_out := v_out || jsonb_build_object('month_income', v_inc, 'prev_month_income', v_inc_prev);
    ELSIF v_type = 'savings' THEN
        SELECT coalesce(sum(amount), 0) INTO v_sav_month
          FROM transactions
         WHERE transaction_type = 'savings'
           AND coalesce(transaction_date, created_at) >= v_ms
           AND coalesce(transaction_date, created_at) <  v_ms + interval '1 month';
        v_out := v_out || jsonb_build_object('savings', jsonb_build_object(
            'name', v_sav.savings_name,
            'current', v_sav.current_amount,
            'target', v_sav.target_amount,
            'target_date', to_char(v_sav.target_date, 'YYYY-MM-DD'),
            'percent', CASE WHEN coalesce(v_sav.target_amount, 0) > 0
                            THEN round(v_sav.current_amount * 100.0 / v_sav.target_amount, 1) END),
            'savings_is_default', v_sav_def,
            'month_savings', v_sav_month);
    END IF;

    RETURN v_out;
END;
$$;


CREATE OR REPLACE FUNCTION finance_snapshot() RETURNS jsonb
LANGUAGE sql STABLE AS $$
WITH
m AS (
    SELECT date_trunc('month', localtimestamp) AS cur,
           date_trunc('month', localtimestamp) - interval '1 month' AS prev
),
tx AS (
    SELECT t.*, COALESCE(t.transaction_date, t.created_at) AS eff FROM transactions t
),
agg AS (   -- one pass: totals for the current and previous month
    SELECT
        COALESCE(SUM(amount) FILTER (WHERE transaction_type='income'   AND eff >= m.cur  AND eff < m.cur + interval '1 month'), 0) AS inc_cur,
        COALESCE(SUM(amount) FILTER (WHERE transaction_type='income'   AND eff >= m.prev AND eff < m.cur), 0) AS inc_prev,
        COALESCE(SUM(amount) FILTER (WHERE transaction_type='expenses' AND eff >= m.cur  AND eff < m.cur + interval '1 month'), 0) AS exp_cur,
        COALESCE(SUM(amount) FILTER (WHERE transaction_type='expenses' AND eff >= m.prev AND eff < m.cur), 0) AS exp_prev,
        COALESCE(SUM(amount) FILTER (WHERE transaction_type='savings'  AND eff >= m.cur  AND eff < m.cur + interval '1 month'), 0) AS sav_cur,
        COALESCE(SUM(amount) FILTER (WHERE transaction_type='income'), 0) AS inc_all,
        COUNT(*) FILTER (WHERE eff >= m.cur AND eff < m.cur + interval '1 month') AS tx_count
    FROM m LEFT JOIN tx ON true
),
bud AS (
    SELECT b.category, b.limit_amount AS lim,
           COALESCE((SELECT SUM(t.amount) FROM tx t, m
                      WHERE t.transaction_type='expenses' AND lower(t.category)=lower(b.category)
                        AND t.eff >= m.cur AND t.eff < m.cur + interval '1 month'), 0) AS spent
    FROM budgets b
),
sv AS (
    SELECT s.savings_name, s.current_amount AS cur_amt, s.target_amount, s.target_date,
           CASE WHEN s.target_date IS NOT NULL AND s.target_date > CURRENT_DATE
                THEN GREATEST(1, CEIL((s.target_date::date - CURRENT_DATE) / 30.0))::int END AS months_left
    FROM savings s
)
SELECT jsonb_build_object(
    'as_of', to_char(localtimestamp, 'YYYY-MM-DD'),
    'month', to_char((SELECT cur FROM m), 'YYYY-MM'),
    'accounts', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', account_name, 'type', account_type, 'balance', COALESCE(balance,0)) ORDER BY account_name), '[]'::jsonb) FROM accounts),
    'liquid_balance', (SELECT COALESCE(SUM(balance),0) FROM accounts WHERE account_type NOT IN ('credit_card','loan')),
    'debt_balance',   (SELECT COALESCE(SUM(balance),0) FROM accounts WHERE account_type IN ('credit_card','loan')),
    'budgets', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'category', category, 'limit', lim, 'spent', spent, 'remaining', lim - spent,
                    'percent', CASE WHEN COALESCE(lim,0) > 0 THEN round(spent*100.0/lim, 1) END,
                    'over_limit', spent > lim) ORDER BY category), '[]'::jsonb) FROM bud),
    'total_budget', (SELECT COALESCE(SUM(lim),0) FROM bud),
    'savings', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'name', savings_name, 'current', COALESCE(cur_amt,0), 'target', target_amount,
                    'percent', CASE WHEN COALESCE(target_amount,0) > 0 THEN round(COALESCE(cur_amt,0)*100.0/target_amount, 1) END,
                    'target_date', to_char(target_date, 'YYYY-MM-DD'),
                    'needed_per_month', CASE WHEN months_left IS NOT NULL AND target_amount > COALESCE(cur_amt,0)
                                             THEN CEIL((target_amount - COALESCE(cur_amt,0)) / months_left) END
                ) ORDER BY savings_name), '[]'::jsonb) FROM sv),
    'total_savings', (SELECT COALESCE(SUM(cur_amt),0) FROM sv),
    'this_month', (SELECT jsonb_build_object('income', inc_cur, 'expenses', exp_cur, 'savings_added', sav_cur,
                        'net_after_expenses_and_savings', inc_cur - exp_cur - sav_cur, 'transactions', tx_count) FROM agg),
    'last_month', (SELECT jsonb_build_object('income', inc_prev, 'expenses', exp_prev) FROM agg),
    'top_merchants_this_month', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
                    SELECT jsonb_build_object('merchant', t.merchant, 'total', SUM(t.amount)) AS x
                      FROM tx t, m
                     WHERE t.transaction_type='expenses' AND t.merchant IS NOT NULL
                       AND t.eff >= m.cur AND t.eff < m.cur + interval '1 month'
                     GROUP BY t.merchant ORDER BY SUM(t.amount) DESC LIMIT 3) q),
    -- unallocated money = cash you hold (excl. credit card/loan) minus this month's budget that is still unspent,
    -- i.e. money that has no job yet. Different from "money left" (= liquid_balance, what remains after spending).
    -- savings need no subtraction: a savings transaction already reduced the account balance.
    'unallocated_money', (SELECT COALESCE(SUM(balance),0) FROM accounts WHERE account_type NOT IN ('credit_card','loan'))
                       - (SELECT COALESCE(SUM(GREATEST(lim - spent, 0)),0) FROM bud)
)
$$;