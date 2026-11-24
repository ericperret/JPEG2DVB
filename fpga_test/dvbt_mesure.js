/*
================================================================================
  Nom        : dvbt_mesure.js
  Projet     : JPEG2DVB, mode DVB-T réduit
  Objet      : mesure de bout en bout de la référence dvbt_ref.js : cellules →
               FFT → filtre 35/3 → maintien ×8 → sigma-delta 1 bit d'ordre 3 (boucle
               de sdm.js) → démodulation OFDM des bits (MER) et spectre
  Auteur     : Eric PERRET
  Date       : 2026-11-24
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node dvbt_mesure.js [N_SYMBOLES]
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-24  création
================================================================================
*/
'use strict';
const R = require('./dvbt_ref.js');
const FS = 1 << 10, A1 = FS, A2 = 6 * FS, A3 = 16 * FS, GARDE = 1 << 15;

function boucle(u) {
    const v = new Int8Array(u.length);
    let x1 = 0, x2 = 0, x3 = 0, raz = 0;
    for (let g = 0; g < u.length / 8; g++) {
        const ovf = Math.abs(x1) > GARDE || Math.abs(x2) > GARDE || Math.abs(x3) > GARDE;
        for (let r = 0; r < 8; r++) {
            const n = 8 * g + r, s = x3 >= 0 ? 1 : -1;
            v[n] = s;
            const n3 = x3 + x2 - A3 * s, n2 = x2 + x1 - A2 * s, n1 = x1 + u[n] - A1 * s;
            x3 = n3; x2 = n2; x1 = n1;
        }
        if (ovf) { x1 = 0; x2 = 0; x3 = 0; raz++; }
    }
    return { v: v, raz: raz };
}
function fft(re, im) {
    const n = re.length;
    for (let i = 1, j = 0; i < n; i++) {
        let b = n >> 1;
        for (; j & b; b >>= 1) { j ^= b; }
        j ^= b;
        if (i < j) { let t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
    }
    for (let len = 2; len <= n; len <<= 1) {
        const a = -2 * Math.PI / len, wr = Math.cos(a), wi = Math.sin(a);
        for (let i = 0; i < n; i += len) {
            let cr = 1, ci = 0;
            for (let j = 0; j < len / 2; j++) {
                const p = i + j, q = p + len / 2;
                const tr = re[q] * cr - im[q] * ci, ti = re[q] * ci + im[q] * cr;
                re[q] = re[p] - tr; im[q] = im[p] - ti; re[p] += tr; im[p] += ti;
                const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
            }
        }
    }
}

const NS = +(process.argv[2] || 6);
let seed = 4242;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed >> 16; };
const mots = new Uint8Array(NS * R.NPAY);
for (let i = 0; i < mots.length; i++) { mots[i] = rnd() & 3; }
const ch = R.chaine(mots, NS);
const fl = R.filtre(Int32Array.from(ch.flux.re), Int32Array.from(ch.flux.im));
const nv = fl.vr.length;
const ui = new Float64Array(nv * 8), uq = new Float64Array(nv * 8);
for (let o = 0; o < nv; o++) { for (let r = 0; r < 8; r++) { ui[8 * o + r] = fl.vr[o]; uq[8 * o + r] = fl.vi[o]; } }
const bi = boucle(ui), bq = boucle(uq);
console.log('sigma-delta : ' + nv + ' groupes, remises à zéro ' + (bi.raz + bq.raz));

// ---- spectre des bits (FFT 2^20) -----------------------------------------------------------
{
    const L = 1 << 20, o0 = 60000;
    const ar = new Float64Array(L), ai = new Float64Array(L);
    for (let n = 0; n < L; n++) { const w = 0.5 - 0.5 * Math.cos(2 * Math.PI * n / L); ar[n] = w * bi.v[o0 + n]; ai[n] = w * bq.v[o0 + n]; }
    fft(ar, ai);
    const df = 640e6 / L;
    const dens = (f0, f1) => { let s = 0, c = 0; for (let f = f0; f <= f1; f += df) { const k = ((Math.round(f / df)) + L) % L; s += ar[k] ** 2 + ai[k] ** 2; c++; } return s / c; };
    const d0 = dens(-2.5e6, 2.5e6);
    const rel = (a, b) => (10 * Math.log10(dens(a, b) / d0)).toFixed(1);
    console.log('spectre (dB rel. bande utile) : 3,1–3,4 MHz ' + rel(3.1e6, 3.4e6) + ' ; 3,5–4 MHz ' + rel(3.5e6, 4e6) + ' ; 4,2–5 MHz ' + rel(4.2e6, 5e6) + ' ; 6–9 MHz ' + rel(6e6, 9e6) +
        ' ; 10–30 MHz ' + rel(1e7, 3e7) + ' ; 77–83 MHz ' + rel(77e6, 83e6) + ' ; −83…−77 MHz ' + rel(-83e6, -77e6) + ' ; 100–200 MHz ' + rel(1e8, 2e8));
}

// ---- démodulation OFDM d'un symbole à partir des bits ------------------------------------------
function demod(s, delta) {
    // fenêtre utile : instants de flux t = s·2112 + 64 .. + 2048 (unités d'échantillon d'entrée) ; t_j = (j + 0,5)/93,333 − 7,5 − delta
    const ratio = 640e6 / (48e6 / 7);
    const t0 = s * 2112 + 64, j0 = Math.ceil((t0 + 7.5 + delta) * ratio - 0.5), j1 = Math.floor((t0 + 2048 + 7.5 + delta) * ratio - 0.5);
    const X = [];
    const K = []; for (let k = 0; k < R.NACT; k++) { K.push(k - 852); }
    const xr = new Float64Array(R.NACT), xi = new Float64Array(R.NACT);
    for (let ki = 0; ki < R.NACT; ki++) {
        const th = -2 * Math.PI * K[ki] / 2048, cr0 = Math.cos(th), ci0 = Math.sin(th);
        // e^{th · (t_j − t0)}, t_j − t0 = (j + .5)/ratio − 7.5 − delta − t0 ; pas : th / ratio
        const sr = Math.cos(th / ratio), si = Math.sin(th / ratio);
        let t = (j0 + 0.5) / ratio - 7.5 - delta - t0;
        let cr = Math.cos(th * t), ci = Math.sin(th * t), ar = 0, ai = 0;
        for (let j = j0; j <= j1; j++) {
            const b1 = bi.v[j], b2 = bq.v[j];
            ar += b1 * cr - b2 * ci; ai += b1 * ci + b2 * cr;
            const nr = cr * sr - ci * si; ci = cr * si + ci * sr; cr = nr;
        }
        xr[ki] = ar / (j1 - j0 + 1); xi[ki] = ai / (j1 - j0 + 1);
    }
    return { xr: xr, xi: xi };
}
function mer(s, delta) {
    const d = demod(s, delta), c = ch.cells[s];
    // pente de phase résiduelle (retard), puis gain complexe
    let zr = new Float64Array(R.NACT), zi = new Float64Array(R.NACT);
    for (let k = 0; k < R.NACT; k++) { zr[k] = d.xr[k] * c.I[k] + d.xi[k] * c.Q[k]; zi[k] = d.xi[k] * c.I[k] - d.xr[k] * c.Q[k]; }
    let gr = 0, gi = 0, rr = 0;
    for (let k = 0; k < R.NACT; k++) { gr += zr[k]; gi += zi[k]; rr += c.I[k] ** 2 + c.Q[k] ** 2; }
    gr /= rr; gi /= rr;
    let e = 0, p = 0;
    for (let k = 0; k < R.NACT; k++) {
        const pr = gr * c.I[k] - gi * c.Q[k], pi = gr * c.Q[k] + gi * c.I[k];
        e += (d.xr[k] - pr) ** 2 + (d.xi[k] - pi) ** 2; p += pr * pr + pi * pi;
    }
    return { mer: 10 * Math.log10(p / e), gain: Math.hypot(gr, gi), ph: Math.atan2(gi, gr) };
}
// recherche du retard (pas de 0,25 échantillon d'entrée, puis affinage)
{
    const s = 2;
    let best = null;
    for (let dl = -0.5; dl <= 1.5; dl += 0.5) { const m = mer(s, dl); if (!best || m.mer > best.m.mer) { best = { dl: dl, m: m }; } }
    for (const step of [0.25, 0.1, 0.05]) {
        const c0 = best.dl;
        for (const dl of [c0 - step, c0 + step]) { const m = mer(s, dl); if (m.mer > best.m.mer) { best = { dl: dl, m: m }; } }
    }
    console.log('MER symbole ' + s + ' : ' + best.m.mer.toFixed(1) + ' dB (retard ' + best.dl.toFixed(2) + ' échantillon, gain ' + best.m.gain.toFixed(4) + ')');
    if (NS > 4) { const m = mer(4, best.dl); console.log('MER symbole 4 : ' + m.mer.toFixed(1) + ' dB'); }
}
