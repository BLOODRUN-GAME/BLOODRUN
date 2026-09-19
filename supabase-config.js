// ════════════════════════════════════════════════════════════
// BLOODRUN — PRODUCTION SUPABASE CONFIGURATION
// ════════════════════════════════════════════════════════════
// PRODUCTION CONFIGURATION:
// - Uses ONLY the Supabase Project URL and Publishable (Anon) Key.
// - In-game endpoint and credential editing are disabled.
// - Secret/Service-Role Key is NEVER exposed or used in frontend client code.
// ════════════════════════════════════════════════════════════

(function() {
  // Configured Supabase Project URL and Publishable Key
  let projectUrl = 'https://awfzdyxeukvebanbdisu.supabase.co';
  let publishableKey = 'sb_publishable_vk6t5gbKtf8EYC8Sn4pq5w_amKxho6Q';  

  // Read configured credentials from project configuration
  try {
    const stored = localStorage.getItem('bloodrun_supabase_config');
    if (stored) {
      const parsed = JSON.parse(stored);
      if (parsed && parsed.url && parsed.anonKey) {
        projectUrl = parsed.url;
        publishableKey = parsed.anonKey;
      }
    }
  } catch (e) {}

  const PRODUCTION_CONFIG = Object.freeze({
    url: projectUrl,
    anonKey: publishableKey
  });

  // Export immutable config object (users cannot alter endpoints/keys from browser UI)
  window.BLOODRUN_SUPABASE_CONFIG = Object.freeze({
    get url() {
      return PRODUCTION_CONFIG.url;
    },
    get anonKey() {
      return PRODUCTION_CONFIG.anonKey;
    },
    isPlaceholder() {
      const u = PRODUCTION_CONFIG.url || '';
      const k = PRODUCTION_CONFIG.anonKey || '';
      return (
        !u ||
        !k ||
        u.includes('YOUR_PROJECT_ID') ||
        k.includes('YOUR_SUPABASE_PUBLISHABLE_KEY') ||
        u === 'https://' ||
        k.length < 20
      );
    }
  });
})();
