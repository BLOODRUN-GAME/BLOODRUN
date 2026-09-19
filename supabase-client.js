// ════════════════════════════════════════════════════════════
// BLOODRUN — SUPABASE AUTHENTICATION CLIENT
// ════════════════════════════════════════════════════════════
// Dedicated authentication and session controller module.
// Uses @supabase/supabase-js (v2) with Publishable Key only.
// ════════════════════════════════════════════════════════════

(function() {
  let supabaseInstance = null;
  let currentSession = null;
  let currentUser = null;
  const authListeners = [];

  function createClient() {
    const config = window.BLOODRUN_SUPABASE_CONFIG;
    if (!config) {
      console.warn('[BloodrunAuth] Configuration module not found.');
      return null;
    }

    if (config.isPlaceholder()) {
      console.info('[BloodrunAuth] Supabase credentials not configured in supabase-config.js.');
      return null;
    }

    if (!window.supabase || typeof window.supabase.createClient !== 'function') {
      console.warn('[BloodrunAuth] @supabase/supabase-js library not loaded in window.supabase.');
      return null;
    }

    try {
      supabaseInstance = window.supabase.createClient(config.url, config.anonKey, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true,
          storage: window.localStorage
        }
      });
      console.log('[BloodrunAuth] Supabase client initialized successfully.');
      return supabaseInstance;
    } catch (err) {
      console.error('[BloodrunAuth] Failed to initialize Supabase client:', err);
      supabaseInstance = null;
      return null;
    }
  }

  function notifyListeners(event, session, user) {
    currentSession = session || null;
    currentUser = user || (session ? session.user : null);
    const runnerName = BloodrunAuth.getRunnerName(currentUser);

    authListeners.forEach(listener => {
      try {
        listener({ event, session: currentSession, user: currentUser, runnerName });
      } catch (e) {
        console.error('[BloodrunAuth] Listener error:', e);
      }
    });
  }

  const BloodrunAuth = {
    get client() {
      if (!supabaseInstance) createClient();
      return supabaseInstance;
    },

    isConfigured() {
      const config = window.BLOODRUN_SUPABASE_CONFIG;
      return config && !config.isPlaceholder();
    },

    getRunnerName(user) {
      const u = user || currentUser;
      if (!u) return 'GUEST';
      return (
        (u.user_metadata && (u.user_metadata.runner_name || u.user_metadata.full_name)) ||
        (u.email ? u.email.split('@')[0].toUpperCase() : 'RUNNER')
      );
    },

    async init() {
      createClient();
      if (!supabaseInstance) {
        notifyListeners('INITIAL_GUEST', null, null);
        return { session: null, user: null };
      }

      try {
        // Subscribe to auth lifecycle changes
        supabaseInstance.auth.onAuthStateChange((event, session) => {
          console.log('[BloodrunAuth] Auth event:', event);
          notifyListeners(event, session, session ? session.user : null);
        });

        // Restore active session across page refreshes
        const { data, error } = await supabaseInstance.auth.getSession();
        if (error) {
          console.warn('[BloodrunAuth] Error restoring session:', error.message);
          notifyListeners('RESTORE_FAILED', null, null);
          return { session: null, user: null };
        }

        const session = data ? data.session : null;
        currentSession = session;
        currentUser = session ? session.user : null;
        notifyListeners(session ? 'INITIAL_SESSION' : 'INITIAL_GUEST', session, currentUser);
        return { session: currentSession, user: currentUser };
      } catch (err) {
        console.error('[BloodrunAuth] Init exception:', err);
        notifyListeners('INIT_ERROR', null, null);
        return { session: null, user: null, error: err };
      }
    },

    async signUp(email, password, runnerName) {
      if (!this.isConfigured()) {
        return {
          error: { message: 'Supabase credentials are not configured. Click CONFIG tab to enter your Project URL and Publishable Key.' }
        };
      }
      const client = this.client;
      if (!client) {
        return { error: { message: 'Supabase client could not be created. Check URL and Key.' } };
      }

      const cleanName = (runnerName || '').trim() || (email ? email.split('@')[0] : 'RUNNER');

      try {
        const { data, error } = await client.auth.signUp({
          email: email.trim(),
          password: password,
          options: {
            data: {
              runner_name: cleanName
            }
          }
        });

        if (error) return { error };

        // If email confirmation is enabled in Supabase, user exists but session might be null until confirmed
        if (data.session) {
          currentSession = data.session;
          currentUser = data.user;
          notifyListeners('SIGNED_IN', currentSession, currentUser);
        }

        return { data };
      } catch (err) {
        return { error: { message: err.message || 'Unexpected sign up error.' } };
      }
    },

    async signIn(email, password) {
      if (!this.isConfigured()) {
        return {
          error: { message: 'Supabase credentials are not configured. Click CONFIG tab to enter your Project URL and Publishable Key.' }
        };
      }
      const client = this.client;
      if (!client) {
        return { error: { message: 'Supabase client could not be created. Check URL and Key.' } };
      }

      try {
        const { data, error } = await client.auth.signInWithPassword({
          email: email.trim(),
          password: password
        });

        if (error) return { error };

        currentSession = data.session;
        currentUser = data.user;
        notifyListeners('SIGNED_IN', currentSession, currentUser);
        return { data };
      } catch (err) {
        return { error: { message: err.message || 'Unexpected login error.' } };
      }
    },

    async requestPasswordReset(email, redirectTo) {
      if (!this.isConfigured()) {
        return {
          error: { message: 'Supabase credentials are not configured.' }
        };
      }
      const client = this.client;
      if (!client) {
        return { error: { message: 'Supabase client could not be created. Check URL and Key.' } };
      }

      try {
        const { data, error } = await client.auth.resetPasswordForEmail(
          email.trim(),
          { redirectTo: redirectTo }
        );
        if (error) return { error };
        return { data };
      } catch (err) {
        return { error: { message: err.message || 'Unexpected password reset error.' } };
      }
    },

    async updatePassword(password) {
      if (!this.isConfigured()) {
        return {
          error: { message: 'Supabase credentials are not configured.' }
        };
      }
      const client = this.client;
      if (!client) {
        return { error: { message: 'Supabase client could not be created. Check URL and Key.' } };
      }

      try {
        const { data, error } = await client.auth.updateUser({ password });
        if (error) return { error };
        return { data };
      } catch (err) {
        return { error: { message: err.message || 'Unexpected password update error.' } };
      }
    },

    async signOut() {
      if (!supabaseInstance) {
        currentSession = null;
        currentUser = null;
        notifyListeners('SIGNED_OUT', null, null);
        return { success: true };
      }

      try {
        const { error } = await supabaseInstance.auth.signOut();
        currentSession = null;
        currentUser = null;
        notifyListeners('SIGNED_OUT', null, null);
        if (error) return { error };
        return { success: true };
      } catch (err) {
        currentSession = null;
        currentUser = null;
        notifyListeners('SIGNED_OUT', null, null);
        return { error: err };
      }
    },

    onAuthStateChange(callback) {
      if (typeof callback === 'function') {
        authListeners.push(callback);
        // Immediately notify with current known state
        callback({
          event: currentUser ? 'CURRENT_STATE' : 'GUEST_STATE',
          session: currentSession,
          user: currentUser,
          runnerName: this.getRunnerName(currentUser)
        });
      }
    },

    async reloadConfig() {
      // In-game configuration editing is disabled in production
      supabaseInstance = null;
      return await this.init();
    },

    getCurrentUser() {
      return currentUser;
    },

    getCurrentSession() {
      return currentSession;
    }
  };

  window.BloodrunAuth = BloodrunAuth;
})();
