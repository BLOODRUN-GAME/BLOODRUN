-- ════════════════════════════════════════════════════════════
-- BLOODRUN — SUPABASE CLOUD PROGRESSION SCHEMA (PHASE 2 HARDENED)
-- ════════════════════════════════════════════════════════════
-- Run this entire script in your Supabase Project:
-- Dashboard → SQL Editor → New Query → Run
-- ════════════════════════════════════════════════════════════

-- 1. PROFILES TABLE
CREATE TABLE IF NOT EXISTS public.profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    runner_name TEXT NOT NULL CHECK (LENGTH(TRIM(runner_name)) BETWEEN 1 AND 20),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. PLAYER OUTFITS TABLE (Created before player_progress for FK constraint)
CREATE TABLE IF NOT EXISTS public.player_outfits (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    outfit_id TEXT NOT NULL CHECK (outfit_id IN (
        'DEFAULT', 'CRIMSON', 'HUNTER', 'PHANTOM', 'DREADNOUGHT',
        'GHOST', 'BLOODGOD', 'APOCALYPSE', 'WARLORD', 'VOID_WALKER'
    )),
    unlocked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, outfit_id)
);

-- 3. PLAYER PROGRESSION TABLE (With Composite FK on equipped_outfit)
CREATE TABLE IF NOT EXISTS public.player_progress (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    high_score INTEGER NOT NULL DEFAULT 0 CHECK (high_score >= 0 AND high_score <= 3000000),
    best_wave INTEGER NOT NULL DEFAULT 1 CHECK (best_wave >= 1 AND best_wave <= 16),
    best_rank TEXT NOT NULL DEFAULT 'D' CHECK (best_rank IN ('D', 'C', 'B', 'A', 'S', 'SS', 'SSS', 'BLOODGOD')),
    total_kills INTEGER NOT NULL DEFAULT 0 CHECK (total_kills >= 0),
    total_runs INTEGER NOT NULL DEFAULT 0 CHECK (total_runs >= 0),
    shots_fired INTEGER NOT NULL DEFAULT 0 CHECK (shots_fired >= 0),
    shots_hit INTEGER NOT NULL DEFAULT 0 CHECK (shots_hit >= 0),
    total_damage_taken INTEGER NOT NULL DEFAULT 0 CHECK (total_damage_taken >= 0),
    equipped_outfit TEXT NOT NULL DEFAULT 'DEFAULT' CHECK (equipped_outfit IN (
        'DEFAULT', 'CRIMSON', 'HUNTER', 'PHANTOM', 'DREADNOUGHT',
        'GHOST', 'BLOODGOD', 'APOCALYPSE', 'WARLORD', 'VOID_WALKER'
    )),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_equipped_outfit FOREIGN KEY (user_id, equipped_outfit)
        REFERENCES public.player_outfits(user_id, outfit_id)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

-- 4. PLAYER ACHIEVEMENTS TABLE (Strict Whitelist of 20 Achievements)
CREATE TABLE IF NOT EXISTS public.player_achievements (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    achievement_id TEXT NOT NULL CHECK (achievement_id IN (
        'FIRST_BLOOD', 'BOSS_SLAYER', 'BOSS_EXTERMINATOR', 'UNTOUCHED',
        'BLOODBATH', 'POINT_BLANK', 'COLLATERAL', 'CLOSE_CALL',
        'COUNTER_KILL', 'DEAD_EYE', 'OVERDRIVE', 'BLOODGOD',
        'NO_HEAL', 'WEAPON_MASTER', 'PERFECT_WAVE', 'HIGH_ROLLER',
        'SURVIVOR', 'APOCALYPSE', 'FULL_CLEAR', 'TRUE_RUNNER'
    )),
    unlocked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, achievement_id)
);

-- 5. PLAYER MEDALS TABLE (Strict Whitelist of 20 Medals)
CREATE TABLE IF NOT EXISTS public.player_medals (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    medal_id TEXT NOT NULL CHECK (medal_id IN (
        'FIRST_BLOOD', 'BOSS_SLAYER', 'BOSS_EXTERMINATOR', 'UNTOUCHED',
        'BLOODBATH', 'POINT_BLANK', 'COLLATERAL', 'CLOSE_CALL',
        'COUNTER_KILL', 'DEAD_EYE', 'OVERDRIVE', 'BLOODGOD',
        'NO_HEAL', 'WEAPON_MASTER', 'PERFECT_WAVE', 'HIGH_ROLLER',
        'SURVIVOR', 'APOCALYPSE', 'FULL_CLEAR', 'TRUE_RUNNER'
    )),
    unlocked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, medal_id)
);

-- 6. RUNS TABLE (Strict Bounds Checking & Server Timestamps)
CREATE TABLE IF NOT EXISTS public.runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    score INTEGER NOT NULL CHECK (score >= 0 AND score <= 3000000),
    wave INTEGER NOT NULL CHECK (wave >= 1 AND wave <= 16),
    rank TEXT NOT NULL CHECK (rank IN ('D', 'C', 'B', 'A', 'S', 'SS', 'SSS', 'BLOODGOD')),
    kills INTEGER NOT NULL DEFAULT 0 CHECK (kills >= 0 AND kills <= 5000),
    accuracy NUMERIC NOT NULL DEFAULT 0 CHECK (accuracy >= 0 AND accuracy <= 100),
    damage_taken INTEGER NOT NULL DEFAULT 0 CHECK (damage_taken >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. GLOBAL LEADERBOARD VIEW
CREATE OR REPLACE VIEW public.leaderboard AS
SELECT 
    r.id AS run_id,
    COALESCE(p.runner_name, 'BLOODRUNNER') AS name,
    r.score,
    r.wave,
    r.rank,
    r.kills,
    r.accuracy,
    r.created_at::date::text AS date
FROM public.runs r
LEFT JOIN public.profiles p ON r.user_id = p.user_id
ORDER BY r.score DESC;

-- ════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_medals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_outfits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.runs ENABLE ROW LEVEL SECURITY;

-- Profiles: Public read, owner insert & update
DROP POLICY IF EXISTS "Public profiles are readable" ON public.profiles;
CREATE POLICY "Public profiles are readable" ON public.profiles
    FOR SELECT TO authenticated, anon USING (true);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Player Progress: Strict read ownership. Direct writes blocked from clients.
DROP POLICY IF EXISTS "Users can view own progress" ON public.player_progress;
CREATE POLICY "Users can view own progress" ON public.player_progress
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Player Achievements: Strict read ownership. Direct writes blocked from clients.
DROP POLICY IF EXISTS "Users can view own achievements" ON public.player_achievements;
CREATE POLICY "Users can view own achievements" ON public.player_achievements
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Player Medals: Strict read ownership. Direct writes blocked from clients.
DROP POLICY IF EXISTS "Users can view own medals" ON public.player_medals;
CREATE POLICY "Users can view own medals" ON public.player_medals
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Player Outfits: Strict read ownership. Direct writes blocked from clients.
DROP POLICY IF EXISTS "Users can view own outfits" ON public.player_outfits;
CREATE POLICY "Users can view own outfits" ON public.player_outfits
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Runs: Public read (for leaderboard). Direct client writes blocked.
DROP POLICY IF EXISTS "Runs are viewable by everyone" ON public.runs;
CREATE POLICY "Runs are viewable by everyone" ON public.runs
    FOR SELECT TO authenticated, anon USING (true);

-- Drop legacy permissive policies if they exist
DROP POLICY IF EXISTS "Users can insert own progress" ON public.player_progress;
DROP POLICY IF EXISTS "Users can update own progress" ON public.player_progress;
DROP POLICY IF EXISTS "Users can insert own achievements" ON public.player_achievements;
DROP POLICY IF EXISTS "Users can insert own medals" ON public.player_medals;
DROP POLICY IF EXISTS "Users can insert own outfits" ON public.player_outfits;
DROP POLICY IF EXISTS "Users can insert own runs" ON public.runs;

-- ════════════════════════════════════════════════════════════
-- SECURE SERVER-SIDE PROCEDURES (SECURITY DEFINER)
-- ════════════════════════════════════════════════════════════

-- Helper: Rank Comparison Function
CREATE OR REPLACE FUNCTION public.compare_style_ranks(r1 TEXT, r2 TEXT)
RETURNS TEXT AS $$
DECLARE
    ranks TEXT[] := ARRAY['D', 'C', 'B', 'A', 'S', 'SS', 'SSS', 'BLOODGOD'];
    i1 INT := 1;
    i2 INT := 1;
BEGIN
    FOR i IN 1..array_length(ranks, 1) LOOP
        IF ranks[i] = r1 THEN i1 := i; END IF;
        IF ranks[i] = r2 THEN i2 := i; END IF;
    END LOOP;
    IF i1 >= i2 THEN RETURN r1; ELSE RETURN r2; END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 1. SECURE RUN SUBMISSION PROCEDURE
-- Validates bounds, prevents duplicates/replays, inserts run, and updates career stats atomically
CREATE OR REPLACE FUNCTION public.submit_run(
    p_score INTEGER,
    p_wave INTEGER,
    p_rank TEXT,
    p_kills INTEGER DEFAULT 0,
    p_accuracy NUMERIC DEFAULT 0,
    p_damage_taken INTEGER DEFAULT 0,
    p_shots_fired INTEGER DEFAULT 0,
    p_shots_hit INTEGER DEFAULT 0
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_run_id UUID;
    v_prog RECORD;
    v_new_high INT;
    v_new_wave INT;
    v_new_rank TEXT;
BEGIN
    -- Authentication check
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User must be authenticated to submit a run';
    END IF;

    -- Strict Bounds Validation
    IF p_score < 0 OR p_score > 3000000 THEN
        RAISE EXCEPTION 'Score % out of legitimate bounds (0 - 3,000,000)', p_score;
    END IF;

    IF p_wave < 1 OR p_wave > 16 THEN
        RAISE EXCEPTION 'Wave % out of bounds (1 - 16)', p_wave;
    END IF;

    IF p_rank NOT IN ('D', 'C', 'B', 'A', 'S', 'SS', 'SSS', 'BLOODGOD') THEN
        RAISE EXCEPTION 'Invalid style rank: %', p_rank;
    END IF;

    IF p_kills < 0 OR p_kills > 5000 THEN
        RAISE EXCEPTION 'Invalid kill count: %', p_kills;
    END IF;

    IF p_accuracy < 0 OR p_accuracy > 100 THEN
        RAISE EXCEPTION 'Invalid accuracy percentage: %', p_accuracy;
    END IF;

    IF p_damage_taken < 0 THEN
        RAISE EXCEPTION 'Invalid damage taken: %', p_damage_taken;
    END IF;

    -- Anti-Replay / Cooldown Enforcement
    -- Replay check: Identical run submitted within the last 30 seconds
    IF EXISTS (
        SELECT 1 FROM public.runs 
        WHERE user_id = v_uid 
          AND score = p_score 
          AND wave = p_wave 
          AND kills = p_kills 
          AND created_at > NOW() - INTERVAL '30 seconds'
    ) THEN
        RAISE EXCEPTION 'Duplicate run submission rejected (anti-replay active)';
    END IF;

    -- Rate-limit cooldown: At least 3 seconds between any run submissions
    IF EXISTS (
        SELECT 1 FROM public.runs 
        WHERE user_id = v_uid 
          AND created_at > NOW() - INTERVAL '3 seconds'
    ) THEN
        RAISE EXCEPTION 'Run submission rate limit exceeded (cooldown active)';
    END IF;

    -- Insert into runs table
    INSERT INTO public.runs (
        user_id, score, wave, rank, kills, accuracy, damage_taken, created_at
    ) VALUES (
        v_uid, p_score, p_wave, p_rank, p_kills, p_accuracy, p_damage_taken, NOW()
    ) RETURNING id INTO v_run_id;

    -- Atomic Progress Update
    SELECT * INTO v_prog FROM public.player_progress WHERE user_id = v_uid FOR UPDATE;
    
    IF FOUND THEN
        v_new_high := GREATEST(v_prog.high_score, p_score);
        v_new_wave := GREATEST(v_prog.best_wave, p_wave);
        v_new_rank := public.compare_style_ranks(v_prog.best_rank, p_rank);

        UPDATE public.player_progress SET
            high_score = v_new_high,
            best_wave = v_new_wave,
            best_rank = v_new_rank,
            total_kills = v_prog.total_kills + GREATEST(0, p_kills),
            total_runs = v_prog.total_runs + 1,
            shots_fired = v_prog.shots_fired + GREATEST(0, p_shots_fired),
            shots_hit = v_prog.shots_hit + GREATEST(0, p_shots_hit),
            total_damage_taken = v_prog.total_damage_taken + GREATEST(0, p_damage_taken),
            updated_at = NOW()
        WHERE user_id = v_uid;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'run_id', v_run_id,
        'high_score', v_new_high,
        'best_wave', v_new_wave,
        'best_rank', v_new_rank
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. SECURE ACHIEVEMENT & OUTFIT UNLOCK PROCEDURE
CREATE OR REPLACE FUNCTION public.unlock_achievement(p_achievement_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_linked_outfit TEXT := NULL;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User must be authenticated';
    END IF;

    -- Validate against official 20 achievements
    IF p_achievement_id NOT IN (
        'FIRST_BLOOD', 'BOSS_SLAYER', 'BOSS_EXTERMINATOR', 'UNTOUCHED',
        'BLOODBATH', 'POINT_BLANK', 'COLLATERAL', 'CLOSE_CALL',
        'COUNTER_KILL', 'DEAD_EYE', 'OVERDRIVE', 'BLOODGOD',
        'NO_HEAL', 'WEAPON_MASTER', 'PERFECT_WAVE', 'HIGH_ROLLER',
        'SURVIVOR', 'APOCALYPSE', 'FULL_CLEAR', 'TRUE_RUNNER'
    ) THEN
        RAISE EXCEPTION 'Invalid achievement ID: %', p_achievement_id;
    END IF;

    -- Map linked outfit reward
    CASE p_achievement_id
        WHEN 'FIRST_BLOOD' THEN v_linked_outfit := 'CRIMSON';
        WHEN 'BOSS_SLAYER' THEN v_linked_outfit := 'HUNTER';
        WHEN 'BOSS_EXTERMINATOR' THEN v_linked_outfit := 'DREADNOUGHT';
        WHEN 'CLOSE_CALL' THEN v_linked_outfit := 'PHANTOM';
        WHEN 'PERFECT_WAVE' THEN v_linked_outfit := 'GHOST';
        WHEN 'BLOODGOD' THEN v_linked_outfit := 'BLOODGOD';
        WHEN 'NO_HEAL' THEN v_linked_outfit := 'WARLORD';
        WHEN 'APOCALYPSE' THEN v_linked_outfit := 'APOCALYPSE';
        WHEN 'TRUE_RUNNER' THEN v_linked_outfit := 'VOID_WALKER';
        ELSE v_linked_outfit := NULL;
    END CASE;

    -- 1. Insert Achievement
    INSERT INTO public.player_achievements (user_id, achievement_id, unlocked_at)
    VALUES (v_uid, p_achievement_id, NOW())
    ON CONFLICT (user_id, achievement_id) DO NOTHING;

    -- 2. Insert Medal
    INSERT INTO public.player_medals (user_id, medal_id, unlocked_at)
    VALUES (v_uid, p_achievement_id, NOW())
    ON CONFLICT (user_id, medal_id) DO NOTHING;

    -- 3. Insert Outfit if linked
    IF v_linked_outfit IS NOT NULL THEN
        INSERT INTO public.player_outfits (user_id, outfit_id, unlocked_at)
        VALUES (v_uid, v_linked_outfit, NOW())
        ON CONFLICT (user_id, outfit_id) DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'achievement_id', p_achievement_id,
        'unlocked_outfit', v_linked_outfit
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. SECURE OUTFIT EQUIP PROCEDURE (Enforces Ownership Check)
CREATE OR REPLACE FUNCTION public.equip_outfit(p_outfit_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User must be authenticated';
    END IF;

    -- Verify the outfit is an approved shell
    IF p_outfit_id NOT IN (
        'DEFAULT', 'CRIMSON', 'HUNTER', 'PHANTOM', 'DREADNOUGHT',
        'GHOST', 'BLOODGOD', 'APOCALYPSE', 'WARLORD', 'VOID_WALKER'
    ) THEN
        RAISE EXCEPTION 'Invalid outfit ID: %', p_outfit_id;
    END IF;

    -- Verify player actually owns the outfit
    IF NOT EXISTS (
        SELECT 1 FROM public.player_outfits 
        WHERE user_id = v_uid AND outfit_id = p_outfit_id
    ) THEN
        RAISE EXCEPTION 'Cannot equip outfit %: Outfit not owned by runner', p_outfit_id;
    END IF;

    -- Update progress
    UPDATE public.player_progress
    SET equipped_outfit = p_outfit_id,
        updated_at = NOW()
    WHERE user_id = v_uid;

    RETURN jsonb_build_object('success', true, 'equipped_outfit', p_outfit_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. SECURE OFFLINE SYNCHRONIZATION PROCEDURE (Safe Non-Destructive Merge)
CREATE OR REPLACE FUNCTION public.sync_offline_progress(
    p_high_score INTEGER,
    p_best_wave INTEGER,
    p_best_rank TEXT,
    p_ach_ids TEXT[] DEFAULT ARRAY[]::TEXT[]
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_prog RECORD;
    v_ach_id TEXT;
    v_sanitized_score INT;
    v_sanitized_wave INT;
    v_sanitized_rank TEXT;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User must be authenticated';
    END IF;

    -- Sanitize & Clamp Inputs
    v_sanitized_score := LEAST(GREATEST(COALESCE(p_high_score, 0), 0), 3000000);
    v_sanitized_wave := LEAST(GREATEST(COALESCE(p_best_wave, 1), 1), 16);
    
    IF p_best_rank IN ('D', 'C', 'B', 'A', 'S', 'SS', 'SSS', 'BLOODGOD') THEN
        v_sanitized_rank := p_best_rank;
    ELSE
        v_sanitized_rank := 'D';
    END IF;

    -- Update personal bests using GREATEST (cloud progress is never downgraded)
    SELECT * INTO v_prog FROM public.player_progress WHERE user_id = v_uid FOR UPDATE;
    
    IF FOUND THEN
        UPDATE public.player_progress SET
            high_score = GREATEST(v_prog.high_score, v_sanitized_score),
            best_wave = GREATEST(v_prog.best_wave, v_sanitized_wave),
            best_rank = public.compare_style_ranks(v_prog.best_rank, v_sanitized_rank),
            updated_at = NOW()
        WHERE user_id = v_uid;
    END IF;

    -- Safely unlock legitimate achievements passed from offline
    IF p_ach_ids IS NOT NULL AND array_length(p_ach_ids, 1) > 0 THEN
        FOREACH v_ach_id IN ARRAY p_ach_ids LOOP
            IF v_ach_id IN (
                'FIRST_BLOOD', 'BOSS_SLAYER', 'BOSS_EXTERMINATOR', 'UNTOUCHED',
                'BLOODBATH', 'POINT_BLANK', 'COLLATERAL', 'CLOSE_CALL',
                'COUNTER_KILL', 'DEAD_EYE', 'OVERDRIVE', 'BLOODGOD',
                'NO_HEAL', 'WEAPON_MASTER', 'PERFECT_WAVE', 'HIGH_ROLLER',
                'SURVIVOR', 'APOCALYPSE', 'FULL_CLEAR', 'TRUE_RUNNER'
            ) THEN
                PERFORM public.unlock_achievement(v_ach_id);
            END IF;
        END LOOP;
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════
-- AUTOMATIC SIGNUP TRIGGER (Profile, Progress, Default Outfit)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    initial_runner_name TEXT;
BEGIN
    initial_runner_name := COALESCE(
        NEW.raw_user_meta_data->>'runner_name',
        split_part(NEW.email, '@', 1),
        'RUNNER'
    );

    -- 1. Create Profile
    INSERT INTO public.profiles (user_id, runner_name, created_at, updated_at)
    VALUES (NEW.id, UPPER(SUBSTRING(initial_runner_name FROM 1 FOR 16)), NOW(), NOW())
    ON CONFLICT (user_id) DO NOTHING;

    -- 2. Unlock Default Starter Outfit FIRST (satisfies FK constraint)
    INSERT INTO public.player_outfits (user_id, outfit_id, unlocked_at)
    VALUES (NEW.id, 'DEFAULT', NOW())
    ON CONFLICT (user_id, outfit_id) DO NOTHING;

    -- 3. Create Progress Record
    INSERT INTO public.player_progress (user_id, high_score, best_wave, best_rank, equipped_outfit, updated_at)
    VALUES (NEW.id, 0, 1, 'D', 'DEFAULT', NOW())
    ON CONFLICT (user_id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ════════════════════════════════════════════════════════════
-- PERMISSIONS
-- ════════════════════════════════════════════════════════════

-- Public read permissions for leaderboard
GRANT SELECT ON public.leaderboard TO anon, authenticated;
GRANT SELECT ON public.runs TO anon, authenticated;
GRANT SELECT ON public.profiles TO anon, authenticated;

-- Function execution permissions
GRANT EXECUTE ON FUNCTION public.submit_run TO authenticated;
GRANT EXECUTE ON FUNCTION public.unlock_achievement TO authenticated;
GRANT EXECUTE ON FUNCTION public.equip_outfit TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_offline_progress TO authenticated;
GRANT EXECUTE ON FUNCTION public.compare_style_ranks TO authenticated, anon;
