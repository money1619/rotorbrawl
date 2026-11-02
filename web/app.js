(function () {
    "use strict";

    var state = {
        open: false,
        tab: "home",
        focusUid: null,
        data: {
            catalog: {
                slots: ["core", "ring", "frame", "tip"],
                slotLabels: { core: "Noyau", ring: "Lame", frame: "Verrou", tip: "Embout" },
                budget: 100,
                wearMax: 40,
                wearFree: 10,
                paints: []
            },
            selectedTopUid: null,
            tops: [],
            challenges: { incoming: [], outgoing: null },
            leaderboard: { season: 1, me: null, top: [] },
            tournaments: { mine: null, tournaments: [] },
            shop: null
        },
        shopCat: null,
        shopTab: "tops",
        shopSlot: "ring",
        shopSel: null
    };

    var appEl = document.getElementById("arena-app");
    var bannerEl = document.getElementById("status-banner");
    var badgeEl = document.getElementById("nav-challenges-badge");
    var footerEquippedEl = document.getElementById("footer-equipped");

    function getResourceName() {
        if (typeof window.GetParentResourceName === "function") {
            try {
                return window.GetParentResourceName();
            } catch (_e) {}
        }
        return "Chaos_Arena";
    }

    function esc(str) {
        if (str === null || str === undefined) return "";
        return String(str)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#39;");
    }

    function showBanner(msg, kind) {
        if (!bannerEl) return;
        if (!msg) {
            bannerEl.className = "status-banner hidden";
            bannerEl.textContent = "";
            return;
        }
        bannerEl.className = "status-banner " + (kind || "info");
        bannerEl.textContent = String(msg);
    }

    function postNui(endpoint, payload, cb) {
        var url = "https://" + getResourceName() + "/" + endpoint;
        fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json; charset=UTF-8" },
            body: JSON.stringify(payload || {})
        })
            .then(function (r) {
                return r.json();
            })
            .then(function (res) {
                if (res && res.closed) {
                    state.open = false;
                    if (appEl) appEl.classList.add("hidden");
                    return;
                }
                if (res && res.data && state.open) {
                    applySnapshot(res.data);
                }
                if (typeof cb === "function" && (state.open || endpoint === "nui:close")) {
                    cb(res);
                }
            })
            .catch(function () {
                if (typeof cb === "function" && state.open) cb({ ok: false, code: "network_error" });
            });
    }

    function closeUi() {
        state.open = false;
        if (appEl) appEl.classList.add("hidden");
        showBanner(null);
        postNui("nui:close", {});
    }

    function switchTab(tab, extra) {
        state.tab = tab || "home";
        if (extra && extra.focusUid) {
            state.focusUid = extra.focusUid;
        }
        showBanner(null);
        renderAll();
        postNui("nui:switchTab", {
            tab: state.tab,
            focusUid: state.focusUid
        });
    }

    function applySnapshot(data) {
        if (!data || typeof data !== "object") return;
        state.data = {
            catalog: data.catalog || state.data.catalog,
            selectedTopUid: data.selectedTopUid || null,
            tops: Array.isArray(data.tops) ? data.tops : [],
            challenges: data.challenges || { incoming: [], outgoing: null },
            leaderboard: data.leaderboard || { season: 1, me: null, top: [] },
            tournaments: data.tournaments || { mine: null, tournaments: [] },
            shop: (data.shop && typeof data.shop === "object") ? data.shop : null
        };
        if (data.focusUid) {
            state.focusUid = data.focusUid;
        }
        if (!state.focusUid && state.data.tops.length > 0) {
            state.focusUid = state.data.selectedTopUid || state.data.tops[0].uid;
        }
        renderAll();
    }

    function getUnlockedCompleteTops() {
        return (state.data.tops || []).filter(function (t) {
            return t && !t.locked && t.complete;
        });
    }

    function buildTopSelectHtml(selectId) {
        var unlocked = getUnlockedCompleteTops();
        if (unlocked.length === 0) {
            return '<select id="' + esc(selectId) + '" class="select" disabled><option value="">Aucune toupie complète disponible</option></select>';
        }
        var html = '<select id="' + esc(selectId) + '" class="select">';
        for (var i = 0; i < unlocked.length; i++) {
            var t = unlocked[i];
            var sel = (t.uid === state.data.selectedTopUid || t.isSelected) ? " selected" : "";
            html += '<option value="' + esc(t.uid) + '"' + sel + ">" +
                esc(t.name) + " [" + esc(t.uid) + "] — " + esc(t.familyLabel) + " (" + esc(t.cost) + "/" + esc(t.budget) + " pts)" +
                "</option>";
        }
        html += "</select>";
        return html;
    }

    function renderHeaderAndFooter() {
        var navBtns = document.querySelectorAll(".nav-btn[data-tab]");
        for (var i = 0; i < navBtns.length; i++) {
            var btn = navBtns[i];
            var t = btn.getAttribute("data-tab");
            if (t === state.tab) {
                btn.classList.add("active");
            } else {
                btn.classList.remove("active");
            }
        }

        var incCount = (state.data.challenges && Array.isArray(state.data.challenges.incoming))
            ? state.data.challenges.incoming.length
            : 0;
        if (badgeEl) {
            if (incCount > 0) {
                badgeEl.textContent = String(incCount);
                badgeEl.classList.remove("hidden");
            } else {
                badgeEl.classList.add("hidden");
            }
        }

        var navShop = document.getElementById("nav-shop");
        if (navShop) {
            if (state.data.shop) navShop.classList.remove("hidden"); else navShop.classList.add("hidden");
        }

        var views = ["home", "challenges", "leaderboard", "tournaments", "shop"];
        for (var v = 0; v < views.length; v++) {
            var el = document.getElementById("view-" + views[v]);
            if (el) {
                if (views[v] === state.tab) {
                    el.classList.remove("hidden");
                } else {
                    el.classList.add("hidden");
                }
            }
        }

        if (footerEquippedEl) {
            var eq = null;
            var tops = state.data.tops || [];
            for (var k = 0; k < tops.length; k++) {
                if (tops[k].uid === state.data.selectedTopUid || tops[k].isSelected) {
                    eq = tops[k];
                    break;
                }
            }
            footerEquippedEl.textContent = eq
                ? ("Toupie équipée : " + eq.name + " [" + eq.uid + "] (" + eq.cost + "/" + eq.budget + " pts)")
                : "Toupie équipée : Aucune";
        }
    }

    function renderHome() {
        var container = document.getElementById("view-home");
        if (!container) return;

        var tops = state.data.tops || [];
        var inc = (state.data.challenges && state.data.challenges.incoming) || [];
        var out = state.data.challenges && state.data.challenges.outgoing;
        var budget = (state.data.catalog && state.data.catalog.budget) || 100;
        var slotsCount = (state.data.catalog && Array.isArray(state.data.catalog.slots))
            ? state.data.catalog.slots.length
            : 4;

        var activeTop = null;
        for (var i = 0; i < tops.length; i++) {
            if (tops[i].uid === state.data.selectedTopUid || tops[i].isSelected) {
                activeTop = tops[i];
                break;
            }
        }

        var summaryHtml = '<div class="card">' +
            '<div class="card-title">' +
            '<span>État du lanceur &amp; équipement</span>' +
            '<span class="pill">' + esc(tops.length) + ' toupie(s) possédée(s)</span>' +
            '</div>' +
            '<div class="card-desc">' +
            (activeTop
                ? ('Toupie active : <strong>' + esc(activeTop.name) + ' [' + esc(activeTop.uid) + ']</strong> • Famille : ' +
                    esc(activeTop.familyLabel) + ' • Budget : ' + esc(activeTop.cost) + '/' + esc(activeTop.budget) +
                    ' pts • Usure : ' + esc(activeTop.wear) + '/' + esc(activeTop.wearMax))
                : 'Aucune toupie complète équipée. Rends-toi auprès du <strong>vendeur RotorBrawl sur la carte</strong> (cible <em>ox_target</em>) pour acheter une toupie, un lanceur ou des pièces, puis assemble-la dans ton <strong>inventaire</strong> en glissant les pièces sur la toupie.') +
            "</div></div>";

        var gridHtml = '<div class="home-grid">' +
            '<div class="card card-interactive" data-goto-tab="challenges">' +
            '<div class="card-title"><span>Défis en cours</span><span class="pill">' + esc(inc.length) + ' reçu(s)' + (out ? ' • 1 envoyé' : '') + '</span></div>' +
            '<div class="card-desc">Accepte ou refuse les invitations reçues, annule un défi envoyé ou lance un défi direct avec ta toupie équipée.</div>' +
            "</div>" +
            '<div class="card card-interactive" data-goto-tab="leaderboard">' +
            '<div class="card-title"><span>Classement Elo</span><span class="pill">Saison ' + esc((state.data.leaderboard && state.data.leaderboard.season) || 1) + '</span></div>' +
            '<div class="card-desc">Consulte ta cote Elo, ton bilan Victoires / Défaites / Nuls et les 20 meilleurs bladers de la saison.</div>' +
            "</div>" +
            '<div class="card card-interactive" data-goto-tab="tournaments">' +
            '<div class="card-title"><span>Tournois</span><span class="pill">Élimination directe</span></div>' +
            '<div class="card-desc">Inscris ta toupie à un tournoi ouvert, suis l\'arbre des rencontres ou organise une compétition.</div>' +
            "</div>" +
            "</div>";

        container.innerHTML = summaryHtml + gridHtml;
    }

    function renderChallenges() {
        var container = document.getElementById("view-challenges");
        if (!container) return;

        var inc = (state.data.challenges && Array.isArray(state.data.challenges.incoming)) ? state.data.challenges.incoming : [];
        var out = state.data.challenges && state.data.challenges.outgoing;

        var topSelectHtml = buildTopSelectHtml("select-challenge-top");

        var sendCard = '<div class="card" style="margin-bottom:14px;">' +
            '<div class="card-title"><span>Toupie de combat &amp; Défi direct</span></div>' +
            '<div class="card-desc" style="margin-bottom:10px;">Choisis ta toupie complète possédée pour envoyer ou accepter un défi (tu peux aussi viser un joueur proche avec ox_target).</div>' +
            '<div class="inline-form">' +
            '<label for="select-challenge-top" class="card-desc">Toupie :</label>' +
            topSelectHtml +
            '<input type="number" id="input-challenge-target" class="input" min="1" step="1" placeholder="ID serveur du joueur" style="width:170px;" />' +
            '<button type="button" class="btn btn-primary" data-action="send-challenge">Défier ce joueur</button>' +
            "</div></div>";

        var outCard = "";
        if (out) {
            outCard = '<div class="card" style="margin-bottom:14px; border-color:var(--border-orange);">' +
                '<div class="card-title">' +
                '<span>Défi envoyé en attente (#' + esc(out.id) + ')</span>' +
                '<span class="pill pill-orange">Cible : ' + esc(out.toName) + '</span>' +
                '</div>' +
                '<div class="inline-form" style="margin-top:8px;">' +
                '<span class="card-desc">Toupie engagée : <strong>' + esc(out.top) + '</strong></span>' +
                '<button type="button" class="btn btn-orange" data-cancel-challenge="' + esc(out.id) + '">Annuler le défi</button>' +
                "</div></div>";
        }

        var incHtml = '<div class="card">' +
            '<div class="card-title"><span>Défis reçus (' + esc(inc.length) + ')</span></div>';
        if (inc.length === 0) {
            incHtml += '<div class="card-desc">Aucun défi entrant en attente.</div>';
        } else {
            for (var i = 0; i < inc.length; i++) {
                var item = inc[i];
                incHtml += '<div class="candidate-row" style="margin-top:8px;">' +
                    '<div>' +
                    '<strong>' + esc(item.fromName) + '</strong> (ID #' + esc(item.from) + ') — Défi #' + esc(item.id) +
                    '<div class="slot-mods">Toupie adverse : ' + esc(item.top) + '</div>' +
                    '</div>' +
                    '<div class="inline-form">' +
                    '<button type="button" class="btn btn-primary" data-respond-id="' + esc(item.id) + '" data-respond-accept="true">Accepter</button>' +
                    '<button type="button" class="btn" data-respond-id="' + esc(item.id) + '" data-respond-accept="false">Refuser</button>' +
                    "</div></div>";
            }
        }
        incHtml += "</div>";

        container.innerHTML = sendCard + outCard + incHtml;
    }

    function renderLeaderboard() {
        var container = document.getElementById("view-leaderboard");
        if (!container) return;

        var lb = state.data.leaderboard || { season: 1, me: null, top: [] };
        var me = lb.me;
        var rows = Array.isArray(lb.top) ? lb.top : [];

        var meCard = "";
        if (me) {
            var rating = Math.round(Number(me.rating) || 1000);
            meCard = '<div class="card" style="margin-bottom:14px;">' +
                '<div class="card-title">' +
                '<span>Mon classement — Saison ' + esc(lb.season || 1) + '</span>' +
                '<span class="pill">' + (me.rank ? ('Rang #' + esc(me.rank)) : 'Non classé') + ' • ' + esc(rating) + ' Elo</span>' +
                '</div>' +
                '<div class="card-desc">' +
                'Joueur : <strong>' + esc(me.name || "?") + '</strong> • Bilan : ' +
                esc(me.wins || 0) + ' victoire(s), ' + esc(me.losses || 0) + ' défaite(s), ' + esc(me.draws || 0) + ' nul(s).' +
                "</div></div>";
        }

        var tableHtml = '<div class="card">' +
            '<div class="card-title"><span>Top Bladers — Saison ' + esc(lb.season || 1) + '</span></div>';
        if (rows.length === 0) {
            tableHtml += '<div class="card-desc">Aucun match classé enregistré pour cette saison.</div>';
        } else {
            tableHtml += '<table class="data-table"><thead><tr>' +
                '<th>Rang</th><th>Joueur</th><th>Cote Elo</th><th>Victoires</th><th>Défaites</th><th>Nuls</th>' +
                '</tr></thead><tbody>';
            for (var i = 0; i < rows.length; i++) {
                var r = rows[i];
                var rk = r.rank || (i + 1);
                var rt = Math.round(Number(r.rating) || 1000);
                tableHtml += "<tr>" +
                    "<td><strong>#" + esc(rk) + "</strong></td>" +
                    "<td>" + esc(r.name || "?") + "</td>" +
                    '<td><span class="pill">' + esc(rt) + "</span></td>" +
                    "<td>" + esc(r.wins || 0) + "</td>" +
                    "<td>" + esc(r.losses || 0) + "</td>" +
                    "<td>" + esc(r.draws || 0) + "</td>" +
                    "</tr>";
            }
            tableHtml += "</tbody></table>";
        }
        tableHtml += "</div>";

        container.innerHTML = meCard + tableHtml;
    }

    function renderTournaments() {
        var container = document.getElementById("view-tournaments");
        if (!container) return;

        var tr = state.data.tournaments || { mine: null, tournaments: [] };
        var list = Array.isArray(tr.tournaments) ? tr.tournaments : [];
        var mineId = tr.mine;

        var topSelectHtml = buildTopSelectHtml("select-tournament-top");

        var createCard = '<div class="card" style="margin-bottom:14px;">' +
            '<div class="card-title"><span>Inscription &amp; Organisation de tournoi</span></div>' +
            '<div class="inline-form" style="margin-bottom:10px;">' +
            '<label for="select-tournament-top" class="card-desc">Toupie d\'inscription :</label>' +
            topSelectHtml +
            (mineId
                ? ('<button type="button" class="btn btn-orange" data-action="leave-tournament">Quitter le tournoi #' + esc(mineId) + '</button>')
                : '') +
            '</div>' +
            '<div class="inline-form">' +
            '<input type="text" id="input-tourney-name" class="input" maxlength="32" placeholder="Nom du tournoi (organisateur)" style="width:220px;" />' +
            '<select id="select-tourney-size" class="select">' +
            '<option value="4">4 joueurs</option>' +
            '<option value="8">8 joueurs</option>' +
            '<option value="16">16 joueurs</option>' +
            '</select>' +
            '<input type="number" id="input-tourney-minutes" class="input" min="1" max="60" value="2" style="width:90px;" title="Minutes d\'inscription" />' +
            '<button type="button" class="btn" data-action="create-tournament">Créer un tournoi</button>' +
            "</div></div>";

        var listHtml = '<div class="card">' +
            '<div class="card-title"><span>Tournois actifs (' + esc(list.length) + ')</span></div>';
        if (list.length === 0) {
            listHtml += '<div class="card-desc">Aucun tournoi actif en ce moment.</div>';
        } else {
            for (var i = 0; i < list.length; i++) {
                var t = list[i];
                var players = Array.isArray(t.players) ? t.players : [];
                var canJoin = (t.state === "signup" && !mineId);
                listHtml += '<div class="candidate-row" style="margin-top:8px;">' +
                    '<div>' +
                    '<strong>#' + esc(t.id) + ' — ' + esc(t.name) + '</strong> ' +
                    '<span class="pill">' + esc(t.state) + ' (' + esc(players.length) + '/' + esc(t.size || 4) + ')</span>' +
                    '<div class="slot-mods">Organisateur : ' + esc(t.organizer || "?") +
                    (players.length > 0 ? (' • Inscrits : ' + esc(players.join(", "))) : '') +
                    (t.winner ? (' • Vainqueur : ' + esc(t.winner)) : '') +
                    '</div></div>' +
                    '<div class="inline-form">' +
                    (canJoin
                        ? ('<button type="button" class="btn btn-primary" data-join-tournament="' + esc(t.id) + '">S\'inscrire</button>')
                        : '') +
                    "</div></div>";
            }
        }
        listHtml += "</div>";

        container.innerHTML = createCard + listHtml;
    }

    // ---------- Boutique unique : une seule boutique, catégories en onglets internes
    var SHOP_ERRORS = {
        no_money: "Argent liquide insuffisant.",
        inventory_full: "Pas assez de place dans l'inventaire.",
        too_far: "Rapproche-toi du vendeur pour acheter.",
        shop_closed: "La boutique est fermée.",
        db_unavailable: "Les toupies ne sont pas disponibles pour le moment.",
        rate_limited: "Trop d'achats d'affilée, patiente un instant.",
        busy: "Une autre action est en cours.",
        invalid: "Article ou quantité refusés."
    };

    function formatMoney(n) {
        var v = Math.max(0, Math.floor(Number(n) || 0));
        return "$" + String(v).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
    }

    // ---------- Boutique (écran dédié, d'après la maquette de Money) ----------
    // Données : catalogue serveur (prix, identifiants) + décoration client (nom affiché, couleur, assemblage, barres,
    // effets des pièces) calculée depuis SpinArena.Parts. Rien d'inventé : une valeur absente s'affiche « — ».
    // Visuels : dessins SVG originaux PROVISOIRES, en attendant les rendus de nos modèles 3D.
    // Catégories de la barre latérale, à plat (les pièces par type) ; une catégorie sans article n'apparaît pas
    var SHOP_TABS = [
        { key: "tops", label: "Toupies", icon: "top" },
        { key: "core", label: "Noyaux", icon: "gear", slot: "core" },
        { key: "ring", label: "Lames", icon: "gear", slot: "ring" },
        { key: "frame", label: "Verrous", icon: "gear", slot: "frame" },
        { key: "tip", label: "Embouts", icon: "gear", slot: "tip" },
        { key: "launchers", label: "Lanceurs", icon: "launcher" },
        { key: "repair", label: "Entretien", icon: "pack" }
    ];
    var SLOT_NAMES = { core: "Noyaux", ring: "Lames", frame: "Verrous", tip: "Embouts" };
    var SHOP_ICONS = {
        top: '<circle cx="12" cy="11" r="7"/><circle cx="12" cy="11" r="3"/><path d="M12 18v3"/>',
        gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/>',
        launcher: '<path d="M4 15h9l4-4h3v6h-3l-2-2H4z"/><path d="M7 15v4"/>',
        acc: '<circle cx="12" cy="12" r="8"/><path d="M12 8v8M8 12h8"/>',
        pack: '<path d="M3 8l9-5 9 5v8l-9 5-9-5z"/><path d="M3 8l9 5 9-5M12 13v8"/>',
        cart: '<path d="M3 4h2l2.4 11h10.2L20 7H6.2"/><circle cx="9" cy="19" r="1.5"/><circle cx="17" cy="19" r="1.5"/>',
        wallet: '<rect x="3" y="6" width="18" height="13" rx="2"/><path d="M16 12h5v4h-5a2 2 0 0 1 0-4z"/>'
    };
    var SLOT_ORDER = ["core", "ring", "frame", "tip"];
    var BAR_LABELS = [["attack", "Attaque"], ["defense", "Défense"], ["endurance", "Endurance"], ["stability", "Stabilité"], ["mobility", "Mobilité"]];
    var SLOT_COLORS = { core: "#f1c40f", ring: "#1e8bff", frame: "#9aa6b8", tip: "#ff4757" };

    function icon(name, cls) {
        return '<svg class="sx-ic ' + (cls || '') + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (SHOP_ICONS[name] || '') + '</svg>';
    }
    function safeColor(c, fallback) { return /^#[0-9a-fA-F]{6}$/.test(String(c || '')) ? c : fallback; }

    // Toupie stylisée (SVG original, provisoire) : couronne crantée, anneau, noyau lumineux, pointe
    function topSvg(color, big) {
        var c = safeColor(color, "#1e8bff"), id = "g" + Math.random().toString(36).slice(2, 8);
        var teeth = "";
        for (var i = 0; i < 12; i++) {
            var a = (i / 12) * Math.PI * 2, x = 50 + Math.cos(a) * 38, y = 46 + Math.sin(a) * 14;
            teeth += '<circle cx="' + x.toFixed(1) + '" cy="' + y.toFixed(1) + '" r="4.2" fill="#2a3242" stroke="' + c + '" stroke-width="1"/>';
        }
        return '<svg class="sx-top-svg' + (big ? ' big' : '') + '" viewBox="0 0 100 80" aria-hidden="true">' +
            '<defs><radialGradient id="' + id + '" cx="50%" cy="40%" r="60%"><stop offset="0%" stop-color="#ffffff" stop-opacity=".9"/>' +
            '<stop offset="35%" stop-color="' + c + '"/><stop offset="100%" stop-color="#0b1220"/></radialGradient></defs>' +
            '<ellipse cx="50" cy="72" rx="30" ry="5" fill="' + c + '" opacity=".25"/>' +
            '<path d="M44 58 L50 74 L56 58 Z" fill="#8a96a8"/>' +
            '<ellipse cx="50" cy="50" rx="40" ry="16" fill="#1a2130" stroke="#4a5568" stroke-width="1.5"/>' + teeth +
            '<ellipse cx="50" cy="44" rx="30" ry="12" fill="url(#' + id + ')" stroke="' + c + '" stroke-width="1.5"/>' +
            '<ellipse cx="50" cy="40" rx="11" ry="5" fill="#0b1220" stroke="' + c + '" stroke-width="2"/>' +
            '<ellipse cx="50" cy="39" rx="4" ry="2" fill="' + c + '"/></svg>';
    }
    // Pièce stylisée selon son emplacement (SVG original, provisoire)
    var PART_PALETTE = ["#c3cad4", "#1e8bff", "#ff4757", "#f1c40f", "#9b59ff", "#2ecc71"];
    function partSvg(slot, index) {
        var c = typeof index === "number" ? PART_PALETTE[index % PART_PALETTE.length] : (SLOT_COLORS[slot] || "#9aa6b8"), body;
        if (slot === "tip") body = '<path d="M38 24h24l-8 30h-8z" fill="#2a3242" stroke="' + c + '" stroke-width="2"/><circle cx="50" cy="56" r="3" fill="' + c + '"/>';
        else if (slot === "core") body = '<ellipse cx="50" cy="38" rx="22" ry="12" fill="#2a3242" stroke="' + c + '" stroke-width="2"/><ellipse cx="50" cy="36" rx="9" ry="5" fill="' + c + '"/>';
        else if (slot === "frame") body = '<path d="M20 40 L50 26 L80 40 L50 54 Z" fill="#2a3242" stroke="' + c + '" stroke-width="2"/><ellipse cx="50" cy="40" rx="8" ry="4" fill="#0b1220" stroke="' + c + '"/>';
        else body = '<ellipse cx="50" cy="40" rx="30" ry="13" fill="none" stroke="' + c + '" stroke-width="6"/><ellipse cx="50" cy="40" rx="30" ry="13" fill="none" stroke="#e9eef5" stroke-width="1" stroke-dasharray="4 5"/>';
        return '<svg class="sx-part-svg" viewBox="0 0 100 70" aria-hidden="true">' + body + '</svg>';
    }
    function launcherSvg() {
        return '<svg class="sx-part-svg" viewBox="0 0 100 70" aria-hidden="true"><path d="M14 40h46l14-12h12v26H74L62 44H14z" fill="#2a3242" stroke="#1e8bff" stroke-width="2"/><path d="M26 44v14" stroke="#1e8bff" stroke-width="3"/></svg>';
    }
    function kitSvg() {
        return '<svg class="sx-part-svg" viewBox="0 0 100 70" aria-hidden="true"><rect x="22" y="22" width="56" height="32" rx="4" fill="#2a3242" stroke="#2ecc71" stroke-width="2"/><path d="M42 22v-6h16v6M50 30v16M42 38h16" stroke="#2ecc71" stroke-width="3"/></svg>';
    }

    // Rendu de nos modèles si Fermi l'a livré (web/img/manifest.js), sinon le SVG provisoire. L'identifiant vient
    // du catalogue serveur : seuls [a-z0-9_] sont admis dans le chemin, et une image absente n'est jamais demandée.
    function itemImageKey(it) {
        if (!it) return null;
        var m = /^(launchers|repair):([a-z0-9_]+)$/.exec(String(it.id || ""));
        var key = it.kit ? "tops/" + it.kit : it.part ? "parts/" + it.part : m ? m[1] + "/" + m[2] : null;
        return key && /^[a-z]+\/[a-z0-9_]+$/.test(key) ? key : null;
    }
    function itemVisual(it, svg, big) {
        var imgs = (typeof window !== "undefined" && window.SPIN_IMAGES) || {};
        var key = itemImageKey(it);
        if (!key || !imgs[key]) return svg;
        // Image non servie (fichier absent, manifeste) : le dessin provisoire réapparaît et l'échec est signalé en
        // console (F8 / nui_devtools), pour ne pas masquer le défaut
        return '<span class="sx-vis">' +
            '<img class="sx-img' + (big ? ' big' : '') + '" src="img/' + key + '.webp" alt="" loading="lazy" decoding="async" draggable="false" ' +
            'onerror="this.parentNode.classList.add(\'img-failed\');console.error(\'ROTORBRAWL : image non servie \' + this.getAttribute(\'src\'))">' +
            svg + '</span>';
    }

    function shopCategory(shop, key) {
        var cats = (shop && shop.categories) || [];
        for (var i = 0; i < cats.length; i++) if (cats[i].key === key) return cats[i];
        return null;
    }
    function shopItems(shop, key) { var c = shopCategory(shop, key); return (c && Array.isArray(c.items)) ? c.items : []; }
    function findItem(shop, id) {
        var cats = (shop && shop.categories) || [];
        for (var i = 0; i < cats.length; i++) {
            var items = cats[i].items || [];
            for (var j = 0; j < items.length; j++) if (items[j].id === id) return items[j];
        }
        return null;
    }
    function itemTitle(it) { return it.display || it.label || it.id; }
    // Articles du rayon affiché (et de la sous-catégorie pour les pièces) : la fiche ne montre jamais un article caché
    function tabItems(shop, key) {
        for (var i = 0; i < SHOP_TABS.length; i++) {
            var t = SHOP_TABS[i];
            if (t.key !== key) continue;
            if (t.slot) return shopItems(shop, "parts").filter(function (it) { return it.slot === t.slot; });
            return shopItems(shop, key);
        }
        return [];
    }
    function visibleItems(shop) { return tabItems(shop, state.shopTab || "tops"); }
    function svgFor(it, big) {
        if (it.kit) return topSvg(it.color, big);
        if (it.part) { var sv = partSvg(it.slot); return big ? sv.replace('sx-part-svg', 'sx-part-svg big') : sv; }
        return /^repair:/.test(String(it.id || "")) ? kitSvg() : launcherSvg();
    }
    function itemSubtitle(it) {
        if (it.kit) return it.family ? ("Famille " + it.family) : "";
        if (it.part) return (it.cost != null ? it.cost + " pts" : "");
        return /^repair:/.test(String(it.id || "")) ? "Entretien" : "Lanceur";
    }
    // Carte : un seul geste, la sélection (l'achat se fait depuis la fiche, une seule fois)
    function cardHtml(it) {
        var sel = state.shopSel === it.id;
        return '<button type="button" class="shp-card' + (sel ? ' selected' : '') + '" data-shop-select="' + esc(it.id) + '" aria-pressed="' + (sel ? 'true' : 'false') + '">' +
            '<span class="shp-card-visual">' + itemVisual(it, svgFor(it, true), true) + '</span>' +
            '<span class="shp-card-name">' + esc(itemTitle(it)) + '</span>' +
            '<span class="shp-card-meta"><span class="shp-card-sub">' + esc(itemSubtitle(it)) + '</span>' +
            '<span class="shp-price">' + esc(formatMoney(it.price)) + '</span></span></button>';
    }

    function barsHtml(bars) {
        var out = '<div class="sx-bars">';
        for (var i = 0; i < BAR_LABELS.length; i++) {
            var v = bars ? bars[BAR_LABELS[i][0]] : null, ok = typeof v === "number";
            out += '<div class="sx-bar"><span class="sx-bar-label">' + esc(BAR_LABELS[i][1]) + '</span>' +
                '<span class="sx-bar-track"><span class="sx-bar-fill" style="width:' + (ok ? Math.max(0, Math.min(100, v)) : 0) + '%"></span></span>' +
                '<span class="sx-bar-val">' + (ok ? esc(v) : '—') + '</span></div>';
        }
        return out + '</div>';
    }
    function detailHtml(shop) {
        var it = state.shopSel ? findItem(shop, state.shopSel) : null;
        if (!it) return '<aside class="shp-detail"><p class="shp-muted">Choisis un article pour voir sa fiche.</p></aside>';
        var body = '';
        if (it.kit) {
            var parts = Array.isArray(it.parts) ? it.parts : [];
            body += '<p class="shp-desc">' + esc(it.family ? 'Famille ' + it.family + '. ' : '') + 'Assemblage de départ : ' +
                parts.map(function (p) { return esc(p.label); }).join(', ') + '.</p>' + barsHtml(it.bars) +
                '<p class="shp-note">Coût en points ' + esc(it.cost != null ? it.cost : '—') + ' / ' + esc(it.budget != null ? it.budget : '—') +
                ' · barres indicatives, calculées à partir des pièces.</p>';
        } else if (it.part) {
            var eff = Array.isArray(it.effects) ? it.effects : [];
            body += '<p class="shp-desc">' + esc(it.slotLabel || '') + (it.cost != null ? ' · ' + esc(it.cost) + ' pts' : '') + '</p>' +
                '<ul class="shp-effects">' + (eff.length ? eff.map(function (e) {
                    return '<li class="' + (e.value >= 0 ? 'up' : 'down') + '"><span>' + esc(e.label) + '</span><strong>' + esc(e.text) + '</strong></li>';
                }).join('') : '<li><span>Aucun modificateur (pièce standard)</span></li>') + '</ul>';
        } else if (it.launcher) {
            // Lanceur (29/10) : effets décidés par le serveur, bonus en vert, défauts en rouge
            var leff = Array.isArray(it.effects) ? it.effects : [];
            body += '<p class="shp-desc">' + esc(it.description || '') + '</p>' +
                '<ul class="shp-effects">' + (leff.length ? leff.map(function (e) {
                    return '<li class="' + (e.good ? 'up' : 'down') + '"><span>' + esc(e.label) + '</span><strong>' + esc(e.text) + '</strong></li>';
                }).join('') : '<li><span>Aucun bonus ni défaut (lanceur de base)</span></li>') + '</ul>' +
                '<p class="shp-note">Le premier lanceur de ton inventaire (emplacement le plus bas) est celui utilisé en match.</p>';
        } else {
            body += '<p class="shp-desc">' + esc(/^repair:/.test(String(it.id || "")) ? "Remet l'usure d'une toupie à zéro : glisse le kit sur la toupie dans ton inventaire." : "Nécessaire pour lancer une toupie en combat.") + '</p>';
        }
        var qtyVal = Math.max(1, Math.min(10, Number(state.shopQty) || 1));
        if (it.single) qtyVal = 1;
        var total = (Number(it.price) || 0) * qtyVal;
        var money = typeof shop.money === "number" ? shop.money : null;
        var tooPoor = money !== null && money < total;
        var qty = it.single ? '' :
            '<div class="shp-qty" role="group" aria-label="Quantité">' +
            '<button type="button" class="shp-step" data-shop-qty-step="-1" aria-label="Moins"' + (qtyVal <= 1 ? ' disabled' : '') + '>−</button>' +
            '<input type="number" class="shp-qty-input" min="1" max="10" value="' + qtyVal + '" data-shop-qty="' + esc(it.id) + '" aria-label="Quantité">' +
            '<button type="button" class="shp-step" data-shop-qty-step="1" aria-label="Plus"' + (qtyVal >= 10 ? ' disabled' : '') + '>+</button></div>';
        return '<aside class="shp-detail">' +
            '<div class="shp-detail-visual">' + itemVisual(it, svgFor(it, true), true) + '</div>' +
            '<h2 class="shp-detail-title">' + esc(itemTitle(it)) + '</h2>' + body +
            '<div class="shp-buybar">' + qty +
            '<button type="button" class="shp-buy" data-shop-buy="' + esc(it.id) + '"' + (tooPoor ? ' disabled' : '') + '>' +
            'Acheter · ' + esc(formatMoney(total)) + '</button></div>' +
            (tooPoor ? '<p class="shp-warn">Il te manque ' + esc(formatMoney(total - money)) + '.</p>' : '') +
            '</aside>';
    }

    function renderShop() {
        var container = document.getElementById("view-shop");
        var win = document.getElementById("arena-window");
        if (win && win.classList) {
            if (state.tab === "shop") win.classList.add("shop-mode"); else win.classList.remove("shop-mode");
        }
        if (!container) return;
        var shop = state.data.shop;
        if (!shop || !Array.isArray(shop.categories) || shop.categories.length === 0) {
            container.innerHTML = '<div class="shop-empty">La boutique est fermée pour le moment.</div>';
            return;
        }
        // Catégorie affichée : celle choisie si elle a des articles, sinon la première qui en a
        var tabs = SHOP_TABS.filter(function (t) { return tabItems(shop, t.key).length > 0; });
        var tab = state.shopTab;
        if (!tabs.some(function (t) { return t.key === tab; })) tab = state.shopTab = tabs[0] ? tabs[0].key : "tops";
        var items = visibleItems(shop);
        // La fiche suit toujours un article VISIBLE : changer de catégorie sélectionne le premier
        if (!items.some(function (it) { return it.id === state.shopSel; })) { state.shopSel = items[0] ? items[0].id : null; state.shopQty = 1; }
        var side = '<nav class="shp-side" aria-label="Catégories">' +
            '<div class="shp-title"><span class="shp-title-main">ROTORBRAWL</span>' +
            '<span class="shp-title-sub">Boutique' + (shop.label ? ' · ' + esc(shop.label) : '') + '</span></div><div class="shp-cats" role="tablist">';
        for (var i = 0; i < tabs.length; i++) {
            var t = tabs[i], on = t.key === tab;
            side += '<button type="button" role="tab" class="shp-cat' + (on ? ' active' : '') + '" data-shop-tab="' + t.key + '" aria-selected="' + (on ? 'true' : 'false') + '">' +
                icon(t.icon) + '<span class="shp-cat-label">' + esc(t.label) + '</span><span class="shp-cat-count">' + tabItems(shop, t.key).length + '</span></button>';
        }
        side += '</div><div class="shp-wallet" title="Argent liquide">' + icon("wallet") + '<span>' + (typeof shop.money === "number" ? esc(formatMoney(shop.money)) : '—') + '</span></div></nav>';
        var cur = tabs.filter(function (t) { return t.key === tab; })[0];
        var grid = items.length ? '<div class="shp-grid">' + items.map(cardHtml).join('') + '</div>'
            : '<p class="shp-muted">Aucun article dans cette catégorie pour le moment.</p>';
        container.innerHTML = '<div class="shp">' + side +
            '<section class="shp-main"><h2 class="shp-main-title">' + esc(cur ? cur.label : '') + '<span>' + items.length + ' article' + (items.length > 1 ? 's' : '') + '</span></h2>' + grid + '</section>' +
            detailHtml(shop) + '</div>';
    }

    function renderAll() {
        renderHeaderAndFooter();
        renderShop();
        renderHome();
        renderChallenges();
        renderLeaderboard();
        renderTournaments();
    }

    // Quantité saisie au clavier : le total du bouton d'achat suit
    document.addEventListener("change", function (ev) {
        var t = ev && ev.target;
        if (t && t.getAttribute && t.getAttribute("data-shop-qty")) {
            state.shopQty = Math.max(1, Math.min(10, Math.floor(Number(t.value) || 1)));
            renderShop();
        }
    });

    // Délégation globale des clics
    document.addEventListener("click", function (ev) {
        var target = ev.target;
        if (!target) return;

        // Clic sur le fond sombre hors de la boîte
        if (target === appEl) {
            closeUi();
            return;
        }

        var btn = target.closest("button, [data-goto-tab], [data-action], [data-shop-select]");
        if (!btn) return;

        if (btn.id === "btn-close") {
            closeUi();
            return;
        }

        if (btn.id === "btn-refresh") {
            postNui("nui:refresh", { tab: state.tab }, function (res) {
                if (res && res.ok) showBanner("Données actualisées.", "info");
            });
            return;
        }

        var shopTab = btn.getAttribute("data-shop-tab");
        if (shopTab) {
            state.shopTab = shopTab;
            state.shopSel = null;
            renderShop();
            return;
        }
        var shopSlot = btn.getAttribute("data-shop-slot");
        if (shopSlot) {
            state.shopSlot = shopSlot;
            state.shopSel = null;
            renderShop();
            return;
        }
        var qtyStep = btn.getAttribute("data-shop-qty-step");
        if (qtyStep) {
            state.shopQty = Math.max(1, Math.min(10, (Number(state.shopQty) || 1) + Number(qtyStep)));
            renderShop();
            return;
        }

        var shopSel = btn.getAttribute("data-shop-select");
        if (shopSel) {
            if (state.shopSel !== shopSel) state.shopQty = 1;
            state.shopSel = shopSel;
            renderShop();
            return;
        }

        var shopCat = btn.getAttribute("data-shop-cat");
        if (shopCat) {
            state.shopCat = shopCat;
            renderShop();
            return;
        }

        var buyId = btn.getAttribute("data-shop-buy");
        if (buyId) {
            var qtyEl = document.querySelector('[data-shop-qty="' + buyId.replace(/"/g, '') + '"]');
            var qty = qtyEl ? Math.max(1, Math.min(10, Math.floor(Number(qtyEl.value) || 1))) : 1;
            btn.disabled = true;
            postNui("nui:shopBuy", { item: buyId, count: qty }, function (res) {
                btn.disabled = false;
                if (res && typeof res.money === "number" && state.data.shop) state.data.shop.money = res.money;
                if (res && res.ok) {
                    var bought = findItem(state.data.shop, buyId);
                    showBanner("Achat effectué : " + (res.count || qty) + " × " + (bought ? itemTitle(bought) : "article") + " pour " + formatMoney(res.paid || 0) + ".", "success");
                } else {
                    showBanner(SHOP_ERRORS[res && res.code] || ("Achat refusé (" + ((res && res.code) || "erreur") + ")."), "error");
                }
                renderShop();
            });
            return;
        }

        var navTab = btn.getAttribute("data-tab") || btn.getAttribute("data-goto-tab");
        if (navTab) {
            switchTab(navTab);
            return;
        }

        var action = btn.getAttribute("data-action");
        if (action === "send-challenge") {
            var targetInput = document.getElementById("input-challenge-target");
            var topSel = document.getElementById("select-challenge-top");
            var targetId = targetInput ? Number(targetInput.value) : 0;
            var chosenTop = topSel ? topSel.value : state.data.selectedTopUid;
            postNui("nui:challengePlayer", { targetId: targetId, top: chosenTop }, function (res) {
                if (res && res.ok) {
                    showBanner("Défi envoyé au joueur #" + targetId + ".", "success");
                } else {
                    showBanner("Défi refusé (" + ((res && res.code) || "erreur") + ").", "error");
                }
            });
            return;
        }

        var cancelId = btn.getAttribute("data-cancel-challenge");
        if (cancelId) {
            postNui("nui:cancelChallenge", { id: Number(cancelId) }, function (res) {
                if (res && res.ok) {
                    showBanner("Défi annulé.", "info");
                } else {
                    showBanner("Annulation refusée (" + ((res && res.code) || "erreur") + ").", "error");
                }
            });
            return;
        }

        var respondId = btn.getAttribute("data-respond-id");
        if (respondId) {
            var accept = btn.getAttribute("data-respond-accept") === "true";
            var topSelect = document.getElementById("select-challenge-top");
            var topVal = topSelect ? topSelect.value : state.data.selectedTopUid;
            postNui("nui:respondChallenge", { id: Number(respondId), accept: accept, top: topVal }, function (res) {
                if (res && res.closed) {
                    state.open = false;
                    if (appEl) appEl.classList.add("hidden");
                    return;
                }
                if (res && res.ok) {
                    showBanner(accept ? "Défi accepté." : "Défi refusé.", "info");
                } else {
                    showBanner("Action refusée (" + ((res && res.code) || "erreur") + ").", "error");
                }
            });
            return;
        }

        if (action === "create-tournament") {
            var nameEl = document.getElementById("input-tourney-name");
            var sizeEl = document.getElementById("select-tourney-size");
            var minEl = document.getElementById("input-tourney-minutes");
            postNui("nui:createTournament", {
                name: nameEl ? nameEl.value.trim() : "",
                size: sizeEl ? Number(sizeEl.value) : 4,
                minutes: minEl ? Number(minEl.value) : 2
            }, function (res) {
                if (res && res.ok) {
                    showBanner("Tournoi créé (#" + (res.id || "?") + ").", "success");
                } else {
                    showBanner("Création refusée (" + ((res && res.code) || "erreur") + ").", "error");
                }
            });
            return;
        }

        if (action === "leave-tournament") {
            postNui("nui:leaveTournament", {}, function (res) {
                if (res && res.ok) {
                    showBanner("Désinscription confirmée.", "info");
                } else {
                    showBanner("Action refusée (" + ((res && res.code) || "erreur") + ").", "error");
                }
            });
            return;
        }

        var joinTid = btn.getAttribute("data-join-tournament");
        if (joinTid) {
            var tTopSel = document.getElementById("select-tournament-top");
            var tTop = tTopSel ? tTopSel.value : state.data.selectedTopUid;
            postNui("nui:joinTournament", { id: Number(joinTid), top: tTop }, function (res) {
                if (res && res.ok) {
                    showBanner("Inscription au tournoi #" + joinTid + " validée.", "success");
                } else {
                    showBanner("Inscription refusée (" + ((res && res.code) || "erreur") + ").", "error");
                }
            });
        }
    });

    // Touche Échap toujours disponible pour fermer et rendre le focus
    window.addEventListener("keydown", function (ev) {
        if (ev.key === "Escape" && state.open) {
            ev.preventDefault();
            closeUi();
        }
    });

    // Réception des messages Lua (SendNUIMessage)
    window.addEventListener("message", function (ev) {
        var msg = ev.data;
        if (!msg || typeof msg !== "object") return;

        if (msg.action === "open") {
            state.open = true;
            state.tab = msg.tab || "home";
            showBanner(null);
            if (msg.data) {
                applySnapshot(msg.data);
            } else {
                renderAll();
            }
            if (appEl) appEl.classList.remove("hidden");
        } else if (msg.action === "update") {
            if (!state.open) return;
            if (msg.tab) state.tab = msg.tab;
            if (msg.data) applySnapshot(msg.data);
        } else if (msg.action === "close") {
            state.open = false;
            showBanner(null);
            if (appEl) appEl.classList.add("hidden");
        }
    });
})();
