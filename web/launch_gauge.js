/* Lanceur à tirette (affichage seulement). Le serveur seul calcule la qualité du lancer, à la réception :
   ce module dessine l'aiguille avec les paramètres reçus (periodMs, phase, target, width), la jauge de tirage et
   l'inclinaison choisie, et signale UN geste volontaire par manche. Aucun envoi automatique au délai, aucune force
   ni horodatage envoyés par la page.
   Messages reçus (SendNUIMessage) : launchOpen { round, deadlineInMs, gauge, pull, tilt, rules, notice, practice, opponent },
   launchTilt { tilt }, launchGrip { grade, pull }, launchReady { ready: [bool, bool] }, launchSent {},
   launchResult { grade, grip, pull }, launchNotice { code }, launchCountdown { startsInMs }, launchClose { reason }.
   Rappel envoyé : nui:launchRelease {} (rien d'autre ; appui rapide à la souris). La prise et le tirage passent par les
   touches du jeu (Lua) : la page ne se met jamais d'elle-même en attente, pour qu'un appui refusé (trop tôt,
   réarmement) ne la bloque pas. */
(function (root) {
    'use strict';
    const TAU = Math.PI * 2;

    // Même forme que le serveur : 0,5 + 0,5·sin(2π·(t − départ)/période + phase), dans [0, 1]
    function position(elapsedMs, gauge) {
        const period = Math.max(1, Number(gauge && gauge.periodMs) || 1400);
        const phase = Number(gauge && gauge.phase) || 0;
        return 0.5 + 0.5 * Math.sin(TAU * elapsedMs / period + phase);
    }
    function zone(gauge) {
        const target = Math.max(0, Math.min(1, Number(gauge && gauge.target)));
        const width = Math.max(0, Math.min(1, Number(gauge && gauge.width) || 0));
        return { from: Math.max(0, target - width), to: Math.min(1, target + width), target };
    }
    // Fenêtre de tirage reçue du serveur (affichage) : la barre va de 0 à maxMs + fadeMs, la zone verte de minMs à maxMs
    function pullWindow(pull) {
        const min = Math.max(0, Number(pull && pull.minMs) || 150);
        const max = Math.max(min, Number(pull && pull.maxMs) || 450);
        const fade = Math.max(1, Number(pull && pull.fadeMs) || 600);
        return { min, max, total: max + fade };
    }
    function clampTilt(v) { v = Math.round(Number(v) || 0); return v < -1 ? -1 : v > 1 ? 1 : v; }
    const GRADES = { perfect: 'PARFAIT', good: 'BON', fair: 'MOYEN', weak: 'FAIBLE' };
    const NOTICES = {
        too_early: 'Trop tôt : laisse l\'aiguille courir un instant',
        expired: 'Visée expirée : nouvelle jauge',
        bad_nonce: 'Visée refusée : nouvelle jauge',
        rate_limited: 'Trop de tentatives : réessaie dans une seconde',
    };
    // Règle du délai, envoyée par le serveur (Money exige qu'elle soit affichée)
    function rulesText(rules) {
        if (!rules) return '';
        const sec = Math.round((Number(rules.prepareMs) || 0) / 1000);
        const later = rules.later === 'forfeit_round' ? 'manche perdue par qui n\'a pas lancé' : 'match sans résultat';
        return 'Délai ' + sec + ' s · sans lancer : manche 1 → match annulé, ensuite → ' + later;
    }
    function detailText(msg) {
        const g = GRADES[msg && msg.grip], p = GRADES[msg && msg.pull];
        return g && p ? ('Prise ' + g + ' · Tirage ' + p) : '';
    }

    // Contrôleur sans dépendance au DOM réel : els = { root, needle, zone, label, timer, ready } (objets avec style/textContent),
    // plus, facultatifs : tilt (dataset), holdFill, holdBand, detail
    function createController(els, opts) {
        const now = (opts && opts.now) || (() => Date.now());
        const post = (opts && opts.post) || (() => {});
        let s = { open: false };
        // data-tilt sur le sélecteur ET sur la fenêtre : le CSS incline le lanceur sans :has() (CEF ancien)
        function showTilt() {
            const v = String(s.tilt || 0);
            if (els.tilt && els.tilt.dataset) els.tilt.dataset.tilt = v;
            if (els.root && els.root.dataset) els.root.dataset.tilt = v;
        }
        function setPhaseClass(name) {
            if (!els.root || !els.root.classList) return;
            for (const c of ['is-gripped', 'is-pulled']) els.root.classList.remove(c);
            if (name) els.root.classList.add(name);
        }
        // state : 'early' (avant la zone verte), 'ok' (dans la zone), 'late' (zone dépassée : la tirette retombe)
        // cord : longueur du cordon (0..1), posée en --cord sur la fenêtre pour le dessin du lanceur
        // Consigne en clair pendant le tirage (29/10) : la barre seule ne disait pas quand relâcher
        const HINTS = { early: 'TIRE… CONTINUE', ok: 'RELÂCHE MAINTENANT !', late: 'TROP LONG : RELÂCHE !' };
        function showHint(k, state) {
            if (!els.hint) return;
            const text = k > 0 ? HINTS[state] || '' : '';
            els.hint.textContent = text;
            if (els.hint.classList) {
                els.hint.classList[state === 'ok' && k > 0 ? 'add' : 'remove']('go');
                els.hint.classList[state === 'late' && k > 0 ? 'add' : 'remove']('late');
            }
        }
        function showHold(k, state, cord) {
            showHint(k, state);
            if (els.holdFill && els.holdFill.style) {
                els.holdFill.style.width = (Math.max(0, Math.min(1, k)) * 100).toFixed(1) + '%';
                if (els.holdFill.classList) {
                    els.holdFill.classList[state === 'ok' ? 'add' : 'remove']('ok');
                    els.holdFill.classList[state === 'late' ? 'add' : 'remove']('late');
                }
            }
            if (els.root && els.root.style && typeof els.root.style.setProperty === 'function') {
                els.root.style.setProperty('--cord', Math.max(0, Math.min(1, cord || 0)).toFixed(3));
            }
        }
        // Même courbe que le cordon en jeu (client/launcher.lua) : tendu jusqu'à pullMaxMs, puis il retombe de 45 %
        function cordAt(heldMs, w) {
            if (heldMs <= w.max) { const k = Math.max(0, heldMs / w.max); return 1 - (1 - k) * (1 - k); }
            return 1 - 0.45 * Math.min(1, (heldMs - w.max) / (w.total - w.max));
        }
        // Lanceur utilisé (envoyé par le client d'après la réponse du serveur) : nom court dans le titre, effets dans les règles
        function launcherTitle(l) {
            if (!l || typeof l.label !== 'string' || !l.label) return '';
            return ' · ' + l.label.replace(/^Lanceur\s+/i, '').toUpperCase();
        }
        function launcherText(l) {
            if (!l || !Array.isArray(l.effects) || !l.effects.length) return '';
            return ' · ' + l.effects.map(e => String(e.label) + ' ' + String(e.text)).join(', ');
        }
        function render() {
            if (!s.open) return;
            const t = now();
            if (s.phase === 'countdown') {
                const left = s.goAt - t;
                if (left > 0) { els.label.textContent = 'Départ dans ' + Math.ceil(left / 1000) + '…'; els.timer.textContent = ''; if (els.label.classList) els.label.classList.remove('rip'); }
                else { s.phase = 'go'; els.label.textContent = 'LANCEZ !'; if (els.label.classList) els.label.classList.add('go'); }
                return;
            }
            if (s.phase === 'aim' || s.phase === 'grip') {
                if (s.phase === 'aim') {
                    const p = position(t - s.openedAt, s.gauge);
                    els.needle.style.left = (p * 100).toFixed(2) + '%';
                } else {
                    const w = pullWindow(s.pull), held = t - s.gripAt;
                    showHold(held / w.total, held < w.min ? 'early' : held <= w.max ? 'ok' : 'late', cordAt(held, w));
                }
                const left = Math.max(0, s.deadlineAt - t);
                els.timer.textContent = Math.ceil(left / 1000) + ' s';
                if (left <= 0) { s.phase = 'timeout'; els.label.textContent = 'Temps écoulé : manche non lancée'; }
            }
        }
        return {
            open(msg) {
                const g = msg && msg.gauge;
                s = { open: true, phase: 'aim', gauge: g, round: msg.round, openedAt: now(), tilt: clampTilt(msg.tilt),
                      pull: msg.pull, deadlineAt: now() + Math.max(0, Number(msg.deadlineInMs) || 0), sent: false };
                const z = zone(g);
                els.zone.style.left = (z.from * 100).toFixed(2) + '%';
                els.zone.style.width = ((z.to - z.from) * 100).toFixed(2) + '%';
                const aim = 'Manche ' + (Number(msg.round) || 1) + ' : tiens ESPACE quand l\'aiguille est dans la zone, puis relâche d\'un coup sec';
                els.label.textContent = NOTICES[msg.notice] ? (NOTICES[msg.notice] + ' · ' + aim) : aim;
                els.ready.textContent = '';
                if (els.rules) els.rules.textContent = rulesText(msg.rules) + launcherText(msg.launcher);
                if (els.detail) els.detail.textContent = '';
                if (els.holdBand && els.holdBand.style) {
                    const w = pullWindow(msg.pull);
                    els.holdBand.style.left = (w.min / w.total * 100).toFixed(1) + '%';
                    els.holdBand.style.width = ((w.max - w.min) / w.total * 100).toFixed(1) + '%';
                    // Étiquettes sous la barre : « mou » à gauche, « parfait » au centre de la zone, « trop long » à droite
                    if (els.holdPerfect && els.holdPerfect.style) els.holdPerfect.style.left = (((w.min + w.max) / 2) / w.total * 100).toFixed(1) + '%';
                }
                setPhaseClass(null);
                showHold(0, 'early', 0);
                showTilt();
                // Entraînement admin : adversaire simulé par le serveur, sans récompense ni classement
                if (els.title) els.title.textContent = (msg.practice ? 'ENTRAÎNEMENT' : 'LANCEMENT') + launcherTitle(msg.launcher);
                if (els.ready && msg.practice) els.ready.textContent = 'Contre : ' + String(msg.opponent || 'adversaire simulé');
                els.root.classList.remove('hidden');
                render();
            },
            // Appui rapide à la souris, transmis au Lua (qui seul décide de l'envoi) ; rien pendant l'attente ou après le délai
            release() {
                if (!s.open || s.phase !== 'aim' || now() > s.deadlineAt) return false;
                post('nui:launchRelease', {});
                return true;
            },
            // Inclinaison choisie (commandes du jeu) : bord −1, droit 0, centre 1
            tilt(msg) {
                if (!s.open) return;
                s.tilt = clampTilt(msg && msg.tilt);
                showTilt();
            },
            // Tirette saisie : l'aiguille se fige, la jauge de tirage démarre (le serveur mesure de son côté)
            grip(msg) {
                if (!s.open || s.phase !== 'aim') return false;
                s.phase = 'grip'; s.gripAt = now();
                if (msg && msg.pull) s.pull = msg.pull;
                const g = GRADES[msg && msg.grade];
                els.label.textContent = (g ? 'Prise ' + g + ' · ' : '') + 'relâche d\'un coup sec dans la zone verte';
                setPhaseClass('is-gripped');
                render();
                return true;
            },
            notice(msg) {
                if (!s.open) return;
                const n = NOTICES[msg && msg.code];
                els.label.textContent = n || ('Lancement refusé (' + String((msg && msg.code) || 'erreur') + ')');
                if (s.phase === 'grip') { s.phase = 'aim'; setPhaseClass(null); showHold(0, 'early', 0); }
            },
            // Lancer parti par la touche du jeu (Lua) : la page passe en attente sans rien envoyer elle-même
            markSent() {
                if (!s.open || (s.phase !== 'aim' && s.phase !== 'grip')) return false;
                s.sent = true; s.phase = 'sent';
                els.label.textContent = 'Lancer envoyé : en attente de l\'adversaire…';
                setPhaseClass('is-pulled');
                return true;
            },
            ready(msg) {
                if (!s.open) return;
                const r = (msg && msg.ready) || [];
                els.ready.textContent = 'Prêts : ' + (r.filter(Boolean).length) + ' / 2';
            },
            result(msg) {
                if (!s.open) return;
                const g = GRADES[msg && msg.grade];
                els.label.textContent = g ? ('Lancer ' + g) : 'Lancer reçu';
                if (els.detail) els.detail.textContent = detailText(msg);
            },
            // Départ commun fixé par le serveur : GO seulement à l'heure du départ (startsInMs), pas à la réception
            countdown(msg) {
                if (!s.open) return;
                s.phase = 'countdown';
                s.goAt = now() + Math.max(0, Number(msg && msg.startsInMs) || 0);
                render();
            },
            close() { s = { open: false }; setPhaseClass(null); els.root.classList.add('hidden'); },
            tick: render,
            state: () => ({ ...s }),
        };
    }

    const api = { position, zone, rulesText, pullWindow, detailText, createController };
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (!root || !root.document) return;
    const d = root.document;
    const el = id => d.getElementById(id);
    if (!el('launch-ui')) return;
    const ctl = createController({ root: el('launch-ui'), needle: el('launch-needle'), zone: el('launch-zone'),
        label: el('launch-label'), timer: el('launch-timer'), ready: el('launch-ready'), rules: el('launch-rules'),
        tilt: el('launch-tilt'), holdFill: el('launch-hold-fill'), holdBand: el('launch-hold-band'), detail: el('launch-detail'), hint: el('launch-hint'), holdPerfect: el('launch-hold-perfect'),
        title: d.querySelector('#launch-ui .launch-title') }, {
        post: (name, body) => {
            const res = typeof root.GetParentResourceName === 'function' ? root.GetParentResourceName() : 'Chaos_Arena';
            return root.fetch('https://' + res + '/' + name, { method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body || {}) }).catch(() => {});
        },
    });
    // Sons de la tirette, synthétisés ici (aucun fichier) : clic de prise, sifflement du tirage. Sans effet si l'audio
    // du navigateur n'est pas disponible.
    let audio = null;
    function sound(kind) {
        try {
            const AC = root.AudioContext || root.webkitAudioContext;
            if (!AC) return;
            audio = audio || new AC();
            const t0 = audio.currentTime, o = audio.createOscillator(), g = audio.createGain();
            o.connect(g); g.connect(audio.destination);
            if (kind === 'grip') {
                o.type = 'square'; o.frequency.setValueAtTime(520, t0); o.frequency.exponentialRampToValueAtTime(260, t0 + 0.05);
                g.gain.setValueAtTime(0.06, t0); g.gain.exponentialRampToValueAtTime(0.001, t0 + 0.07); o.stop(t0 + 0.08);
            } else {
                o.type = 'sawtooth'; o.frequency.setValueAtTime(180, t0); o.frequency.exponentialRampToValueAtTime(1500, t0 + 0.22);
                g.gain.setValueAtTime(0.07, t0); g.gain.exponentialRampToValueAtTime(0.001, t0 + 0.3); o.stop(t0 + 0.32);
            }
            o.start(t0);
        } catch (e) { /* pas d'audio : le lancer n'en dépend pas */ }
    }
    root.addEventListener('message', e => {
        const m = e.data || {};
        if (m.action === 'launchOpen') ctl.open(m);
        else if (m.action === 'launchTilt') ctl.tilt(m);
        else if (m.action === 'launchGrip') { if (ctl.grip(m)) sound('grip'); }
        else if (m.action === 'launchReady') ctl.ready(m);
        else if (m.action === 'launchSent') { if (ctl.markSent()) sound('pull'); }
        else if (m.action === 'launchResult') ctl.result(m);
        else if (m.action === 'launchNotice') ctl.notice(m);
        else if (m.action === 'launchCountdown') ctl.countdown(m);
        else if (m.action === 'launchClose') ctl.close();
    });
    root.addEventListener('keydown', e => { if (e.code === 'Space' && ctl.release()) e.preventDefault(); });
    el('launch-ui').addEventListener('pointerdown', () => ctl.release());
    (function loop() { ctl.tick(); if (root.requestAnimationFrame) root.requestAnimationFrame(loop); })();
})(typeof window !== 'undefined' ? window : undefined);
