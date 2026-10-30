// Original procedural mechanical sounds. No recordings, external assets or network requests.
(function () {
    'use strict';
    let context, generation = 0, spin = null, noiseBuffer = null;
    const voices = new Set(), last = new Map();
    const known = new Set(['hit', 'wall', 'ring_out', 'burst', 'countdown_tick', 'launch_go', 'round_end', 'spin']);
    const bounded = (v, lo, hi, fallback) => Number.isFinite(Number(v)) ? Math.max(lo, Math.min(hi, Number(v))) : fallback;
    // Spin whistle that follows the watched top's rotation (level 0..1 from client/effects.lua). One voice at most,
    // silenced by level 0, by stop, or after 1.5 s without news (lost messages never leave it playing).
    function stopSpin(fade) {
        if (!spin) return;
        const s = spin; spin = null;
        try {
            s.gain.gain.cancelScheduledValues(context.currentTime);
            s.gain.gain.setTargetAtTime(0, context.currentTime, fade || 0.05);
        } catch (_) {}
        for (const o of s.nodes) { try { o.stop(context.currentTime + (fade || 0.05) * 5); } catch (_) {} }
        if (s.timer && typeof clearTimeout === 'function') clearTimeout(s.timer);
        // While it fades out, it is an ordinary voice: stopAll() cuts it at once
        voices.add(s);
        s.nodes[0].onended = () => { s.nodes[0].disconnect(); s.gain.disconnect(); voices.delete(s); };
    }
    function spinLevel(level, volume) {
        if (level <= 0) { stopSpin(0.12); return; }
        const now = context.currentTime;
        if (!spin) {
            const gain = context.createGain();
            gain.gain.setValueAtTime(0.0001, now);
            gain.connect(context.destination);
            const nodes = [];
            for (const [type, ratio] of [['sine', 1], ['triangle', 2.01]]) {
                const o = context.createOscillator();
                o.type = type;
                o.frequency.setValueAtTime(200 * ratio, now);
                o.connect(gain);
                o.onended = () => { o.disconnect(); };
                o.start(now);
                o.stop(now + 120);   // hard bound, even if every stop message is lost
                nodes.push(o);
            }
            spin = {gain, nodes, timer: null};
        }
        const f = 140 + 900 * Math.pow(level, 1.3);
        spin.nodes[0].frequency.setTargetAtTime(f, now, 0.08);
        spin.nodes[1].frequency.setTargetAtTime(f * 2.01, now, 0.08);
        spin.gain.gain.setTargetAtTime(Math.max(0.0001, volume * 0.012 * level), now, 0.1);
        if (typeof setTimeout === 'function') {
            if (spin.timer && typeof clearTimeout === 'function') clearTimeout(spin.timer);
            const mine = spin;
            spin.timer = setTimeout(() => { if (spin === mine) stopSpin(0.2); }, 1500);
        }
    }
    // Short band-passed noise burst: metal scrape / click. Needs createBuffer + createBiquadFilter, otherwise skipped.
    function noise(duration, amplitude, frequency, q) {
        if (voices.size >= 12 || typeof context.createBuffer !== 'function' || typeof context.createBiquadFilter !== 'function') return;
        const now = context.currentTime;
        if (!noiseBuffer) {
            const n = Math.floor((context.sampleRate || 44100) * 0.4);
            noiseBuffer = context.createBuffer(1, n, context.sampleRate || 44100);
            const data = noiseBuffer.getChannelData(0);
            for (let i = 0; i < n; i++) data[i] = Math.random() * 2 - 1;
        }
        const source = context.createBufferSource(), filter = context.createBiquadFilter(), gain = context.createGain();
        source.buffer = noiseBuffer;
        filter.type = 'bandpass';
        filter.frequency.setValueAtTime(frequency, now);
        filter.Q.setValueAtTime(q, now);
        gain.gain.setValueAtTime(Math.max(0.0001, amplitude), now);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + duration);
        source.connect(filter); filter.connect(gain); gain.connect(context.destination);
        const voice = {gain, nodes: [source]};
        voices.add(voice);
        source.onended = () => { source.disconnect(); filter.disconnect(); gain.disconnect(); voices.delete(voice); };
        source.start(now);
        source.stop(now + duration + 0.02);
    }
    function stopAll() {
        generation++;
        if (context) stopSpin(0.008);
        for (const voice of voices) {
            try { voice.gain.gain.cancelScheduledValues(context.currentTime); voice.gain.gain.setTargetAtTime(0, context.currentTime, 0.008); } catch (_) {}
            for (const oscillator of voice.nodes) { try { oscillator.stop(context.currentTime + 0.04); } catch (_) {} }
        }
        voices.clear();
        last.clear();
    }
    function tone(frequency, duration, amplitude, ratios, endFrequency) {
        if (voices.size >= 12) return;
        const now = context.currentTime, gain = context.createGain();
        gain.gain.setValueAtTime(0.0001, now);
        gain.gain.exponentialRampToValueAtTime(Math.max(0.0001, amplitude / ratios.length), now + 0.008);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + duration);
        gain.connect(context.destination);
        const voice = {gain, nodes: []};
        voices.add(voice);
        let remaining = ratios.length;
        for (const ratio of ratios) {
            const oscillator = context.createOscillator();
            oscillator.type = 'sine';
            oscillator.frequency.setValueAtTime(frequency * ratio, now);
            if (endFrequency) oscillator.frequency.exponentialRampToValueAtTime(endFrequency * ratio, now + duration);
            oscillator.connect(gain);
            oscillator.onended = () => {
                oscillator.disconnect();
                if (--remaining === 0) { gain.disconnect(); voices.delete(voice); }
            };
            voice.nodes.push(oscillator);
            oscillator.start(now);
            oscillator.stop(now + duration + 0.02);
        }
    }
    async function receive(message) {
        if (!message || message.type !== 'spin_arena_audio') return;
        if (message.key === 'stop') { stopAll(); return; }
        if (!known.has(message.key)) return;
        const volume = bounded(message.volume, 0, 1, 0.35);
        if (volume === 0) return;
        const Audio = window.AudioContext || window.webkitAudioContext;
        if (!Audio) return;
        try {
            if (!context) context = new Audio();
            const session = generation;
            if (context.state === 'suspended') await context.resume();
            if (session !== generation || context.state !== 'running') return;
            const key = message.key, now = context.currentTime;
            if (key === 'spin') { spinLevel(bounded(message.level, 0, 1, 0), volume); return; }
            const interval = key === 'hit' || key === 'wall' ? 0.09 : 0.12;
            if (last.has(key) && now - last.get(key) < interval) return;
            last.set(key, now);
            const strength = bounded(message.intensity, 0.15, 1, 0.65);
            const amplitude = volume * strength * 0.07;
            if (key === 'hit') {
                tone(820, 0.24, amplitude, [1, 1.43, 2.76], 490);
                noise(0.05, amplitude * 1.6, 3200, 1.2);   // metal click of the clash
            } else if (key === 'wall') {
                tone(470, 0.16, amplitude * 0.45, [1, 2.13], 310);
                noise(0.14, amplitude * 1.1, 2400, 2.5);   // scrape against the bowl wall
            }
            else if (key === 'ring_out') tone(610, 0.6, amplitude, [1, 1.49], 100);
            else if (key === 'burst') tone(180, 0.5, amplitude, [1, 2.01, 3.3], 60);   // 29/10 : verrou qui cède
            else if (key === 'countdown_tick') tone(540, 0.09, amplitude * 0.7, [1]);
            else if (key === 'round_end') tone(440, 0.7, amplitude, [1, 1.25, 1.5]);
            else if (key === 'launch_go') {
                tone(230, 0.4, amplitude, [1, 1.91], 950);
                // The spin bed now follows the real rotation: 'spin' messages (see spinLevel above).
            }
        } catch (_) { /* Audio availability must never block gameplay. */ }
    }
    window.addEventListener('message', event => { void receive(event.data); });
    window.addEventListener('beforeunload', stopAll);
    window.addEventListener('pointerdown', () => {
        if (context && context.state === 'suspended') context.resume().catch(() => {});
    });
})();
