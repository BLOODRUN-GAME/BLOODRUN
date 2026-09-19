// ════════════════════════════════════════════════════════════
// BLOODRUN — SUPABASE CLOUD DATABASE CONTROLLER (PHASE 2 HARDENED)
// ════════════════════════════════════════════════════════════
// Manages cloud persistence, profiles, career statistics,
// achievements, medals, outfits, run history, and global leaderboard.
// Uses server-side SECURITY DEFINER RPCs for tamper-proof submissions,
// anti-replay rate-limiting, and strict ownership validation.
// ════════════════════════════════════════════════════════════

(function() {
  // Dedicated Guest Storage Keys (Isolated from authenticated player state)
  const GUEST_KEYS = {
    HIGH_SCORE: 'bloodrun_guest_highscore',
    BEST_WAVE: 'bloodrun_guest_bestwave',
    BEST_RANK: 'bloodrun_guest_bestrank',
    PLAYER_NAME: 'bloodrun_guest_playername',
    ACHIEVEMENTS: 'bloodrun_guest_achievements',
    MEDALS: 'bloodrun_guest_medals',
    OUTFITS: 'bloodrun_guest_outfits',
    EQUIPPED: 'bloodrun_guest_equipped'
  };

  const GUEST_DEFAULTS = {
    highScore: 0,
    bestWave: 1,
    bestRank: 'D',
    playerName: 'BLOODRUNNER',
    unlockedAchs: [],
    unlockedMedals: [],
    unlockedOutfits: ['DEFAULT'],
    equippedOutfit: 'DEFAULT'
  };

  function getLocalGuestState() {
    try {
      // Support dedicated guest keys with legacy fallback
      const hs = localStorage.getItem(GUEST_KEYS.HIGH_SCORE) || localStorage.getItem('bloodrun_highscore') || '0';
      const bw = localStorage.getItem(GUEST_KEYS.BEST_WAVE) || localStorage.getItem('bloodrun_bestwave') || '1';
      const br = localStorage.getItem(GUEST_KEYS.BEST_RANK) || localStorage.getItem('bloodrun_bestrank') || 'D';
      const pn = localStorage.getItem(GUEST_KEYS.PLAYER_NAME) || localStorage.getItem('bloodrun_playername') || 'BLOODRUNNER';
      const achs = localStorage.getItem(GUEST_KEYS.ACHIEVEMENTS) || localStorage.getItem('bloodrun_achievements') || '[]';
      const meds = localStorage.getItem(GUEST_KEYS.MEDALS) || localStorage.getItem('bloodrun_medals') || '[]';
      const outfs = localStorage.getItem(GUEST_KEYS.OUTFITS) || localStorage.getItem('bloodrun_outfits') || '["DEFAULT"]';
      const eq = localStorage.getItem(GUEST_KEYS.EQUIPPED) || localStorage.getItem('bloodrun_equipped_outfit') || 'DEFAULT';

      return {
        highScore: parseInt(hs, 10) || 0,
        bestWave: parseInt(bw, 10) || 1,
        bestRank: br,
        playerName: pn,
        unlockedAchs: JSON.parse(achs),
        unlockedMedals: JSON.parse(meds),
        unlockedOutfits: JSON.parse(outfs),
        equippedOutfit: eq
      };
    } catch (e) {
      return { ...GUEST_DEFAULTS };
    }
  }

  function clearLocalGuestProgress() {
    try {
      localStorage.removeItem(GUEST_KEYS.HIGH_SCORE);
      localStorage.removeItem(GUEST_KEYS.BEST_WAVE);
      localStorage.removeItem(GUEST_KEYS.BEST_RANK);
      localStorage.removeItem(GUEST_KEYS.ACHIEVEMENTS);
      localStorage.removeItem(GUEST_KEYS.MEDALS);
      localStorage.removeItem(GUEST_KEYS.OUTFITS);
      localStorage.removeItem(GUEST_KEYS.EQUIPPED);
      localStorage.removeItem('bloodrun_highscore');
      localStorage.removeItem('bloodrun_bestwave');
      localStorage.removeItem('bloodrun_bestrank');
      localStorage.removeItem('bloodrun_achievements');
      localStorage.removeItem('bloodrun_medals');
      localStorage.removeItem('bloodrun_outfits');
      localStorage.removeItem('bloodrun_equipped_outfit');
    } catch (e) {}
  }

  function compareRanks(r1, r2) {
    const ranks = ['D', 'C', 'B', 'A', 'S', 'SS', 'SSS', 'BLOODGOD'];
    const i1 = ranks.indexOf(r1 || 'D');
    const i2 = ranks.indexOf(r2 || 'D');
    return i1 >= i2 ? r1 : r2;
  }

  const BloodrunDB = {
    get client() {
      return window.BloodrunAuth ? window.BloodrunAuth.client : null;
    },

    getUser() {
      return window.BloodrunAuth ? window.BloodrunAuth.getCurrentUser() : null;
    },

    isOnline() {
      return !!(this.client && this.getUser());
    },

    // ── 1. SELF-HEALING PROFILE INITIALIZER ───────────────────────
    async ensureProfileAndProgress(user) {
      if (!this.client || !user) return false;
      const client = this.client;
      const userId = user.id;

      try {
        const { data: profile } = await client
          .from('profiles')
          .select('runner_name')
          .eq('user_id', userId)
          .maybeSingle();

        if (!profile) {
          const runnerName = (
            (user.user_metadata && user.user_metadata.runner_name) ||
            (user.email ? user.email.split('@')[0] : 'RUNNER')
          ).toUpperCase().slice(0, 16);

          await client.from('profiles').upsert({
            user_id: userId,
            runner_name: runnerName,
            updated_at: new Date().toISOString()
          });
        }
        return true;
      } catch (err) {
        console.warn('[BloodrunDB] ensureProfile warning:', err.message);
        return false;
      }
    },

    // ── 2. LOAD PROGRESSION & SECURE OFFLINE MERGE ─────────────────
    async loadPlayerProgression(user) {
      if (!this.client || !user) return null;
      const client = this.client;
      const userId = user.id;

      await this.ensureProfileAndProgress(user);

      try {
        // 1. Check if there was prior unmigrated offline/guest progress
        const local = getLocalGuestState();
        const localAchIds = (local.unlockedAchs || []).map(a => typeof a === 'string' ? a : a.id).filter(Boolean);

        if (local.highScore > 0 || localAchIds.length > 0 || local.bestWave > 1) {
          // Perform server-side safe sync via RPC
          try {
            await client.rpc('sync_offline_progress', {
              p_high_score: local.highScore,
              p_best_wave: local.bestWave,
              p_best_rank: local.bestRank,
              p_ach_ids: localAchIds
            });
            // Once migrated into User's cloud account, clear local guest unlocks to prevent cross-account bleed
            clearLocalGuestProgress();
          } catch (rpcErr) {
            console.warn('[BloodrunDB] sync_offline_progress RPC warning:', rpcErr.message);
          }
        }

        // 2. Fetch authoritative cloud records
        const [
          profRes,
          progRes,
          achsRes,
          medsRes,
          outfsRes
        ] = await Promise.all([
          client.from('profiles').select('runner_name').eq('user_id', userId).maybeSingle(),
          client.from('player_progress').select('*').eq('user_id', userId).maybeSingle(),
          client.from('player_achievements').select('achievement_id, unlocked_at').eq('user_id', userId),
          client.from('player_medals').select('medal_id, unlocked_at').eq('user_id', userId),
          client.from('player_outfits').select('outfit_id, unlocked_at').eq('user_id', userId)
        ]);

        const cloudProfile = profRes.data || {};
        const cloudProg = progRes.data || {};
        const cloudAchs = (achsRes.data || []).map(r => ({ id: r.achievement_id, unlockedAt: r.unlocked_at }));
        const cloudMeds = (medsRes.data || []).map(r => ({ id: r.medal_id, unlockedAt: r.unlocked_at }));
        const cloudOutfs = (outfsRes.data || []).map(r => r.outfit_id);
        if (!cloudOutfs.includes('DEFAULT')) cloudOutfs.unshift('DEFAULT');

        const activeHighScore = cloudProg.high_score || 0;
        const activeBestWave = cloudProg.best_wave || 1;
        const activeBestRank = cloudProg.best_rank || 'D';
        const activeEquipped = cloudProg.equipped_outfit || 'DEFAULT';

        // 3. Update in-game variables via global bridge
        if (typeof window.applyCloudProgression === 'function') {
          window.applyCloudProgression({
            runnerName: cloudProfile.runner_name || user.email.split('@')[0],
            highScore: activeHighScore,
            bestWave: activeBestWave,
            bestRank: activeBestRank,
            unlockedAchs: cloudAchs,
            unlockedMedals: cloudMeds,
            unlockedOutfits: cloudOutfs,
            equippedOutfit: activeEquipped
          });
        }

        console.log('[BloodrunDB] Cloud progression verified for', user.email);
        return {
          highScore: activeHighScore,
          bestWave: activeBestWave,
          bestRank: activeBestRank,
          unlockedAchs: cloudAchs,
          unlockedMedals: cloudMeds,
          unlockedOutfits: cloudOutfs,
          equippedOutfit: activeEquipped
        };
      } catch (err) {
        console.error('[BloodrunDB] loadPlayerProgression error:', err);
        return null;
      }
    },

    // ── 3. SAVE ACHIEVEMENT & REWARDS VIA SECURE RPC ─────────────
    async saveAchievement(achievementId, tier, title, outfitId) {
      if (!this.isOnline()) return;
      const client = this.client;

      try {
        // Call server-side RPC procedure (validates whitelist, awards medals and linked outfits)
        const { data, error } = await client.rpc('unlock_achievement', {
          p_achievement_id: achievementId
        });

        if (error) {
          console.warn('[BloodrunDB] unlock_achievement RPC warning:', error.message);
        } else {
          console.log('[BloodrunDB] Cloud achievement recorded:', achievementId, data);
        }
      } catch (err) {
        console.warn('[BloodrunDB] saveAchievement error:', err.message);
      }
    },

    // ── 4. EQUIP OUTFIT VIA SECURE RPC (OWNERSHIP VERIFICATION) ───
    async saveEquippedOutfit(outfitId) {
      if (!this.isOnline()) return;
      const client = this.client;

      try {
        // Server checks whether runner owns outfit in player_outfits before updating
        const { data, error } = await client.rpc('equip_outfit', {
          p_outfit_id: outfitId
        });

        if (error) {
          console.warn('[BloodrunDB] equip_outfit RPC rejected:', error.message);
        } else {
          console.log('[BloodrunDB] Cloud outfit equipped:', outfitId);
        }
      } catch (err) {
        console.warn('[BloodrunDB] saveEquippedOutfit error:', err.message);
      }
    },

    // ── 5. RECORD RUN VIA SECURE RPC (BOUNDS & ANTI-REPLAY) ───────
    async recordRun(run) {
      // Always submit locally as fallback
      if (typeof window.submitScoreToLeaderboard === 'function') {
        window.submitScoreToLeaderboard(run.name, run.score, run.wave, run.rank);
      }

      if (!this.isOnline()) return;
      const client = this.client;

      try {
        // Secure server-side RPC: bounds validation, anti-replay, rate limit, and stats aggregation
        const { data, error } = await client.rpc('submit_run', {
          p_score: Math.floor(run.score || 0),
          p_wave: Math.floor(run.wave || 1),
          p_rank: run.rank || 'D',
          p_kills: Math.floor(run.kills || 0),
          p_accuracy: parseFloat((run.accuracy || 0).toFixed(1)),
          p_damage_taken: Math.floor(run.damageTaken || 0),
          p_shots_fired: Math.floor(run.shotsFired || 0),
          p_shots_hit: Math.floor(run.shotsHit || 0)
        });

        if (error) {
          console.warn('[BloodrunDB] submit_run RPC rejected:', error.message);
        } else {
          console.log('[BloodrunDB] Run successfully recorded in Supabase cloud:', data);
        }
      } catch (err) {
        console.warn('[BloodrunDB] recordRun error:', err.message);
      }
    },

    // ── 6. FETCH GLOBAL LEADERBOARD (READ-ONLY VIEW) ─────────────
    async fetchLeaderboard(limit = 25) {
      if (!this.client || !window.BLOODRUN_SUPABASE_CONFIG || window.BLOODRUN_SUPABASE_CONFIG.isPlaceholder()) {
        return null;
      }

      try {
        const { data, error } = await this.client
          .from('leaderboard')
          .select('*')
          .limit(limit);

        if (!error && Array.isArray(data) && data.length > 0) {
          return data.map(r => ({
            name: (r.name || 'BLOODRUNNER').toUpperCase(),
            score: r.score,
            wave: r.wave,
            rank: r.rank,
            date: r.date || (r.created_at ? r.created_at.slice(0, 10) : '-')
          }));
        }
      } catch (err) {
        console.warn('[BloodrunDB] fetchLeaderboard warning, falling back to local:', err.message);
      }
      return null;
    },

    resetToGuest() {
      const guest = getLocalGuestState();
      if (typeof window.applyCloudProgression === 'function') {
        window.applyCloudProgression({
          runnerName: guest.playerName,
          highScore: guest.highScore,
          bestWave: guest.bestWave,
          bestRank: guest.bestRank,
          unlockedAchs: guest.unlockedAchs,
          unlockedMedals: guest.unlockedMedals,
          unlockedOutfits: guest.unlockedOutfits,
          equippedOutfit: guest.equippedOutfit
        });
      }
      console.log('[BloodrunDB] Player memory completely reset to isolated local guest state.');
    }
  };

  window.BloodrunDB = BloodrunDB;
})();
