/* Window geometry is local presentation only; no gameplay data or server requests. */
(function (root) {
    'use strict';
    const finite = (v, fallback) => Number.isFinite(v) ? v : fallback;
    const clamp = (v, low, high) => Math.max(low, Math.min(high, v));
    function constrain(rect, viewport) {
        const vw = Math.max(1, finite(viewport.width, 1920));
        const vh = Math.max(1, finite(viewport.height, 1080));
        const margin = Math.min(12, vw / 10, vh / 10);
        const maxW = vw - margin * 2, maxH = vh - margin * 2;
        const width = clamp(finite(rect.width, 680), Math.min(360, maxW), maxW);
        const height = clamp(finite(rect.height, 450), Math.min(300, maxH), maxH);
        return {
            x: clamp(finite(rect.x, (vw - width) / 2), margin, vw - width - margin),
            y: clamp(finite(rect.y, (vh - height) / 2), margin, vh - height - margin),
            width, height,
        };
    }
    function defaults(viewport, profile) {
        // Boutique (maquette de Money) : écran large par défaut, toujours déplaçable et redimensionnable
        // Boutique : taille raisonnable et centrée (plafonnée pour les écrans larges et ultra-larges), toujours redimensionnable
        if (profile === 'shop') return constrain({width: Math.min(1180, viewport.width * 0.9), height: Math.min(700, viewport.height * 0.86)}, viewport);
        return constrain({width: Math.min(680, viewport.width * 0.78), height: Math.min(450, viewport.height * 0.64)}, viewport);
    }
    function relative(rect, viewport) {
        return {version: 1, x: rect.x / viewport.width, y: rect.y / viewport.height,
            width: rect.width / viewport.width, height: rect.height / viewport.height};
    }
    function restore(saved, viewport, profile) {
        if (!saved || saved.version !== 1 || !['x','y','width','height'].every(k => Number.isFinite(saved[k]))) return defaults(viewport, profile);
        return constrain({x: saved.x * viewport.width, y: saved.y * viewport.height,
            width: saved.width * viewport.width, height: saved.height * viewport.height}, viewport);
    }
    const api = {constrain, defaults, relative, restore};
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (!root || !root.document) return;
    const document = root.document;
    const shell = document.getElementById('arena-window');
    const drag = document.getElementById('window-drag-handle');
    const resize = document.getElementById('window-resize-handle');
    const reset = document.getElementById('window-reset');
    if (!shell || !drag || !resize || !reset) return;
    // Deux géométries mémorisées séparément : fenêtre Arena et écran de boutique
    const KEYS = {arena: 'spin_arena.window.v1', shop: 'spin_arena.shop_window.v1'};
    let profile = 'arena';
    const viewport = () => ({width: root.innerWidth, height: root.innerHeight});
    function load(p) {
        let stored;
        try { stored = JSON.parse(root.localStorage.getItem(KEYS[p])); } catch (_) {}
        return restore(stored, viewport(), p);
    }
    let rect = load(profile), interaction = null;
    function apply() {
        rect = constrain(rect, viewport());
        Object.assign(shell.style, {left: rect.x + 'px', top: rect.y + 'px', width: rect.width + 'px', height: rect.height + 'px'});
        shell.classList.add('window-managed');
        shell.classList.toggle('window-narrow', rect.width < 580);
        resize.setAttribute('aria-label', 'Redimensionner la fenêtre Arena : ' + Math.round(rect.width) + ' × ' + Math.round(rect.height));
    }
    function save() {
        try { root.localStorage.setItem(KEYS[profile], JSON.stringify(relative(rect, viewport()))); } catch (_) {}
    }
    function finish(event) {
        if (!interaction || (event && event.pointerId !== undefined && event.pointerId !== interaction.id)) return;
        const previous = interaction;
        interaction = null;
        try { previous.handle.releasePointerCapture(previous.id); } catch (_) {}
        shell.classList.remove('window-moving');
        save();
    }
    function begin(event, mode, handle) {
        if (event.button !== 0 || (event.isPrimary === false)) return;
        finish();
        interaction = {mode, handle, id: event.pointerId, x: event.clientX, y: event.clientY, rect: {...rect}};
        try { handle.setPointerCapture(event.pointerId); } catch (_) {}
        shell.classList.add('window-moving');
        event.preventDefault();
    }
    drag.addEventListener('pointerdown', event => begin(event, 'move', drag));
    resize.addEventListener('pointerdown', event => begin(event, 'resize', resize));
    root.addEventListener('pointermove', event => {
        if (!interaction || event.pointerId !== interaction.id) return;
        const dx = event.clientX - interaction.x, dy = event.clientY - interaction.y;
        const start = interaction.rect;
        rect = interaction.mode === 'move'
            ? {...start, x: start.x + dx, y: start.y + dy}
            : {...start, width: start.width + dx, height: start.height + dy};
        apply();
    });
    root.addEventListener('pointerup', finish);
    root.addEventListener('pointercancel', finish);
    root.addEventListener('blur', () => finish());
    drag.addEventListener('lostpointercapture', finish);
    resize.addEventListener('lostpointercapture', finish);
    function keyboard(event, mode) {
        const delta = {ArrowLeft: [-1,0], ArrowRight: [1,0], ArrowUp: [0,-1], ArrowDown: [0,1]}[event.key];
        if (!delta) return;
        const step = event.altKey ? 1 : 16;
        const changeSize = mode === 'resize' || event.shiftKey;
        rect = changeSize
            ? {...rect, width: rect.width + delta[0] * step, height: rect.height + delta[1] * step}
            : {...rect, x: rect.x + delta[0] * step, y: rect.y + delta[1] * step};
        event.preventDefault(); apply(); save();
    }
    drag.addEventListener('keydown', event => keyboard(event, 'move'));
    resize.addEventListener('keydown', event => keyboard(event, 'resize'));
    reset.addEventListener('click', () => {finish(); rect = defaults(viewport(), profile); apply(); save();});
    let previousViewport = viewport();
    root.addEventListener('resize', () => {
        finish();
        rect = restore(relative(rect, previousViewport), viewport(), profile);
        previousViewport = viewport();
        apply(); save();
    });
    root.addEventListener('message', event => {
        if (event.data && event.data.action === 'close') finish();
        const wanted = event.data && (event.data.action === 'open' || event.data.action === 'update') && event.data.tab
            ? (event.data.tab === 'shop' ? 'shop' : 'arena') : null;
        if (wanted && wanted !== profile) { finish(); profile = wanted; rect = load(profile); apply(); }
        if (event.data && event.data.action === 'open') {apply(); previousViewport = viewport();}
    });
    apply();
})(typeof window !== 'undefined' ? window : undefined);
