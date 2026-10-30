/* Résumé de fin de match (encart bref, sans focus ni curseur) : affiché chez les deux duellistes seulement, fermé
   tout seul après quelques secondes. Données serveur uniquement (matchEnd.summary) ; une valeur absente n'est pas
   affichée. Message reçu (SendNUIMessage) : matchSummary { winner, reason, score, names, side, summary, holdMs }. */
(function (root) {
    'use strict';
    const REASONS = {
        ring_out: 'Sortie', spin_out: 'Arrêt', burst: 'Éclat', turbo_out: 'Turbo', stall: 'immobilisation', prepare_timeout: 'pas lancée à temps',
        forfeit: 'abandon', disconnect: 'déconnexion', timeout: 'temps écoulé', draw: 'égalité',
    };
    const FRIENDLY = {
        arena_not_official: 'table non officielle', test_top: 'toupie de test', same_identity: 'même joueur', no_contest: 'sans résultat',
        pair_limit: 'trop de matchs contre ce joueur', invalid: 'résumé invalide',
    };
    const text = s => String(s == null ? '' : s);
    const esc = s => text(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
    // names arrive du Lua : tableau JSON (indices 0 et 1) ou objet { a, b } ; 29/10 : n[1] lisait le 2e nom (titre et noms inversés)
    function nameOf(m, side) {
        const n = m.names || {};
        const v = Array.isArray(n) ? n[side - 1] : (side === 1 ? (n.a || n[1]) : (n.b || n[2]));
        return text(v || ('Joueur ' + side));
    }
    function title(m) {
        if (m.winner !== 1 && m.winner !== 2) return m.reason === 'no_contest' ? 'Match annulé' : 'Égalité';
        if (m.side === 1 || m.side === 2) return m.winner === m.side ? 'Victoire' : 'Défaite';
        return 'Victoire : ' + nameOf(m, m.winner);
    }
    // HTML de l'encart (pur, testable) ; null si le message ne concerne pas un duelliste
    function render(m) {
        if (!m || (m.side !== 1 && m.side !== 2)) return null;
        const sc = Array.isArray(m.score) ? m.score : [m.score && m.score.a, m.score && m.score.b];
        const sum = m.summary || {};
        let rows = '';
        (Array.isArray(sum.rounds) ? sum.rounds : []).forEach((r, i) => {
            const w = r && (r.winner === 1 || r.winner === 2) ? esc(nameOf(m, r.winner)) + ' gagne' : 'manche nulle';
            const why = r && REASONS[r.reason] ? ' · ' + REASONS[r.reason] : '';
            const pts = r && typeof r.points === 'number' && r.winner ? ' · +' + r.points + ' pt' + (r.points > 1 ? 's' : '') : '';
            const dur = r && typeof r.durationS === 'number' ? ' · ' + r.durationS.toFixed(1).replace('.', ',') + ' s' : '';
            rows += '<li><span>Manche ' + (i + 1) + '</span><span>' + w + esc(why) + esc(pts) + esc(dur) + '</span></li>';
        });
        const me = m.side === 1 ? 'a' : 'b';
        const extra = [];
        if (sum.ejections && typeof sum.ejections[me] === 'number') extra.push('Éjections subies : ' + sum.ejections[me]);
        if (sum.wear && typeof sum.wear[me] === 'number' && sum.wear[me] > 0) extra.push('Usure de ta toupie : +' + sum.wear[me]);
        if (sum.practice) extra.push('Entraînement : ni usure ni classement');
        // Homologation : certificat signé par le serveur (classement) ou match amical (jamais classé)
        const hom = sum.homologation;
        let badge = '';
        if (hom && hom.status === 'homologated') {
            badge = '<p class="ms-cert ok">MATCH HOMOLOGUÉ' + (typeof hom.certId === 'string' ? ' · n° ' + esc(hom.certId.slice(0, 8).toUpperCase()) : '') + '</p>';
        } else if (hom && hom.status === 'friendly') {
            badge = '<p class="ms-cert">MATCH AMICAL · ' + esc(FRIENDLY[hom.reason] || 'non classé') + '</p>';
        }
        const won = (m.winner === m.side);
        return '<div class="ms-head ' + (m.winner === 1 || m.winner === 2 ? (won ? 'win' : 'loss') : 'even') + '">' + esc(title(m)) + '</div>' +
            '<div class="ms-score"><span>' + esc(nameOf(m, 1)) + '</span><strong>' + esc(sc[0] != null ? sc[0] : '—') + ' – ' + esc(sc[1] != null ? sc[1] : '—') + '</strong><span>' + esc(nameOf(m, 2)) + '</span></div>' +
            (rows ? '<ul class="ms-rounds">' + rows + '</ul>' : '') +
            (extra.length ? '<p class="ms-extra">' + extra.map(esc).join(' · ') + '</p>' : '') + badge;
    }
    const api = { render, REASONS };
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (!root || !root.document) return;
    const box = root.document.getElementById('match-summary');
    if (!box) return;
    let timer = null;
    root.addEventListener('message', e => {
        const m = e.data || {};
        if (m.action === 'matchSummaryClose') { box.classList.add('hidden'); return; }
        if (m.action !== 'matchSummary') return;
        const html = render(m);
        if (!html) return;
        box.innerHTML = html;
        box.classList.remove('hidden');
        if (timer) clearTimeout(timer);
        timer = setTimeout(() => box.classList.add('hidden'), Math.max(3000, Math.min(15000, Number(m.holdMs) || 8000)));
    });
})(typeof window !== 'undefined' ? window : undefined);
