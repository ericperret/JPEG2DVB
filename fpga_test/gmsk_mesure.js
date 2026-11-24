/*
================================================================================
  Nom        : gmsk_mesure.js
  Projet     : JPEG2DVB, mode GMSK
  Objet      : mesures par calcul de gmsk_ref.js : (1) erreur de la forme d'onde entière
               contre la forme idéale flottante ; (2) largeur occupée à 80 MS/s ;
               (3) bout en bout : maintien ×8 → sigma-delta 1 bit d'ordre 3 (boucle de
               sdm.js, FS = 1024) → filtre passe-bas idéal 6 MHz → EVM contre la forme
               idéale et taux d'erreur de bit (décision sur la variation de phase)
  Auteur     : Eric PERRET
  Date       : 2026-11-24
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node gmsk_mesure.js [PUISSANCE_DE_2_CYCLES]   (17 par défaut)
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-24  création
================================================================================
*/
'use strict';
const G = require('./gmsk_ref.js');
const LG = +(process.argv[2] || 17), NC = 1 << LG;
let seed = 31415;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed >> 16; };
const nb = Math.ceil(NC * G.PAS / G.PER) + 8;
const bits = Array.from({ length: nb }, () => (rnd() & 1) ? 1 : -1);

function fft(re, im, inv) {
    const n = re.length;
    for (let i = 1, j = 0; i < n; i++) { let b = n >> 1; for (; j & b; b >>= 1) { j ^= b; } j ^= b; if (i < j) { let t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; } }
    for (let len = 2; len <= n; len <<= 1) {
        const a = (inv ? 2 : -2) * Math.PI / len, wr = Math.cos(a), wi = Math.sin(a), h = len >> 1;
        const cr = new Float64Array(h), ci = new Float64Array(h);
        for (let k = 0; k < h; k++) { cr[k] = Math.cos(a * k); ci[k] = Math.sin(a * k); }
        for (let i = 0; i < n; i += len) {
            for (let k = 0; k < h; k++) {
                const x = i + k, y = x + h;
                const tr = re[y] * cr[k] - im[y] * ci[k], ti = re[y] * ci[k] + im[y] * cr[k];
                re[y] = re[x] - tr; im[y] = im[x] - ti; re[x] += tr; im[x] += ti;
            }
        }
    }
    if (inv) { for (let i = 0; i < n; i++) { re[i] /= n; im[i] /= n; } }
}
function boucle(u) {
    const FS = 1 << 10, A1 = FS, A2 = 6 * FS, A3 = 16 * FS, GARDE = 1 << 15;
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
// occupation : puissance cumulée autour de 0 (fraction) → largeur en MHz ; fe en MHz
function occupation(re, im, fe, fracs) {
    const N = 1 << 16, P = new Float64Array(N);
    let cnt = 0;
    for (let st = 0; st + N <= re.length; st += N / 2) {
        const a = new Float64Array(N), b = new Float64Array(N);
        for (let i = 0; i < N; i++) { const w = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / N); a[i] = re[st + i] * w; b[i] = im[st + i] * w; }
        fft(a, b, false);
        for (let i = 0; i < N; i++) { P[i] += a[i] * a[i] + b[i] * b[i]; }
        cnt++;
    }
    let tot = 0; for (let i = 0; i < N; i++) { tot += P[i]; }
    const res = {};
    for (const f of fracs) {
        let acc = P[0];
        for (let k = 1; k < N / 2; k++) { acc += P[k] + P[N - k]; if (acc >= f * tot) { res[f] = 2 * k * fe / N; break; } }
    }
    // niveau relatif (dB) de la densité à ±df autour du pic : moyenne de |f| dans [df, df+0,5 MHz]
    const pic = Math.max(...Array.from(P.slice(0, N / 64)).concat(Array.from(P.slice(N - N / 64))));
    const niv = df => { let s = 0, c = 0; for (let k = 1; k < N / 2; k++) { const f = k * fe / N; if (f >= df && f < df + 0.5) { s += P[k] + P[N - k]; c += 2; } } return 10 * Math.log10(s / c / pic); };
    return { res: res, niv: niv };
}

// -------- (1) forme d'onde entière contre idéale (80 MS/s)
const m = G.modulate(bits, NC, false), id = G.ideal(bits, NC);
let e = 0, p = 0;
for (let n = 100; n < NC - 100; n++) { e += (m.vi[n] - id.vi[n]) ** 2 + (m.vq[n] - id.vq[n]) ** 2; p += id.vi[n] ** 2 + id.vq[n] ** 2; }
console.log('(1) EVM de la quantification (80 MS/s) : ' + (10 * Math.log10(e / p)).toFixed(1) + ' dB');

// -------- (2) occupation à 80 MS/s
const fr = [0.9, 0.99, 0.999];
const o80 = occupation(Float64Array.from(m.vi), Float64Array.from(m.vq), 80, fr);
console.log('(2) largeur occupée à 80 MS/s : 90 % ' + o80.res[0.9].toFixed(2) + ' MHz, 99 % ' + o80.res[0.99].toFixed(2) + ' MHz, 99,9 % ' + o80.res[0.999].toFixed(2) + ' MHz');
console.log('    densité relative (dB) à 3 / 4 / 5 / 6 / 8 MHz : ' + [3, 4, 5, 6, 8].map(d => o80.niv(d).toFixed(1)).join(' / '));

// -------- (3) bout en bout : maintien ×8, sigma-delta, passe-bas idéal 6 MHz
const NM = NC * 8;
const ui = new Float64Array(NM), uq = new Float64Array(NM);
for (let n = 0; n < NC; n++) { for (let r = 0; r < 8; r++) { ui[8 * n + r] = m.vi[n]; uq[8 * n + r] = m.vq[n]; } }
const bi = boucle(ui), bq = boucle(uq);
let yr = new Float64Array(NM), yi = new Float64Array(NM);
for (let i = 0; i < NM; i++) { yr[i] = bi.v[i] * 1024; yi[i] = bq.v[i] * 1024; }
const sdo = occupation(Float64Array.from(yr), Float64Array.from(yi), 640, fr);
console.log('(3) sigma-delta : remises à zéro ' + bi.raz + '/' + bq.raz + ', densité relative (dB) à 3 / 5 / 6 / 8 / 20 / 80 MHz : ' + [3, 5, 6, 8, 20, 80].map(d => sdo.niv(d).toFixed(1)).join(' / '));
// passe-bas idéal 6 MHz (FFT sur tout l'enregistrement)
fft(yr, yi, false);
const fc = 6 / 640 * NM;
for (let k = 0; k < NM; k++) { const kk = k <= NM / 2 ? k : NM - k; if (kk > fc) { yr[k] = 0; yi[k] = 0; } }
fft(yr, yi, true);
// forme idéale à 640 MS/s, retard d'un demi-cycle (maintien) ; décalage fin balayé
function ideal640(d) {
    const ar = new Float64Array(NM), ai = new Float64Array(NM);
    const bf = i => (i < 0 ? 1 : (i < bits.length ? bits[i] : 1));
    const Af = k => { let a = 0; for (let i = -3; i <= k - 4; i++) { a += bf(i); } return ((a % 4) + 4) % 4; };
    const cacheA = new Map();
    for (let mm = 0; mm < NM; mm++) {
        const t = mm / 8 - d, pos = t * G.PAS / G.PER;
        const k = Math.floor(pos), u = pos - k;
        if (!cacheA.has(k)) { cacheA.set(k, Af(k)); }
        let s = cacheA.get(k);
        for (let j = 0; j < G.NJ; j++) { s += bf(k - j) * G.TQ.Q(j + u); }
        const th = 2 * Math.PI * s / 4;
        ar[mm] = G.R * Math.cos(th); ai[mm] = G.R * Math.sin(th);
    }
    return { re: ar, im: ai };
}
// Af est en O(k) : le cumul est précalculé par incréments
let best = null;
{
    const cum = new Int32Array(nb + 8); // cum[k+3] = somme des bits de −3 à k (k ≥ −3)
    let a = 0; for (let k = -3; k < nb; k++) { a += (k < 0 ? 1 : bits[k]); cum[k + 3] = a; }
    const Af = k => { if (k < -3) { return 0; } return (((k - 4 >= -3 ? cum[k - 4 + 3] : 0) % 4) + 4) % 4; };
    const bf = i => (i < 0 ? 1 : (i < bits.length ? bits[i] : 1));
    const eval640 = d => {
        const ar = new Float64Array(NM), ai = new Float64Array(NM);
        for (let mm = 0; mm < NM; mm++) {
            const t = mm / 8 - d, pos = t * G.PAS / G.PER;
            const k = Math.floor(pos), u = pos - k;
            let s = Af(k);
            for (let j = 0; j < G.NJ; j++) { s += bf(k - j) * G.TQ.Q(j + u); }
            const th = 2 * Math.PI * s / 4;
            ar[mm] = G.R * Math.cos(th); ai[mm] = G.R * Math.sin(th);
        }
        return { re: ar, im: ai };
    };
    const scoreOf = (d, id2) => {
        // gain complexe optimal puis erreur relative sur la partie centrale
        let sxx = 0, sxy_r = 0, sxy_i = 0, syy = 0;
        for (let i = NM / 8; i < NM - NM / 8; i++) {
            const xr = id2.re[i], xi = id2.im[i];
            sxx += xr * xr + xi * xi; sxy_r += yr[i] * xr + yi[i] * xi; sxy_i += yi[i] * xr - yr[i] * xi; syy += yr[i] * yr[i] + yi[i] * yi[i];
        }
        const g = Math.sqrt(sxy_r * sxy_r + sxy_i * sxy_i) / sxx;
        const err = syy - (sxy_r * sxy_r + sxy_i * sxy_i) / sxx;
        return { d: d, g: g, evm: 10 * Math.log10(err / syy), re: sxy_r / sxx, im: sxy_i / sxx };
    };
    for (const d of [-0.5, -0.25, 0, 0.25, 0.5, 0.75, 1.0]) {
        const r = scoreOf(d, eval640(d));
        if (best === null || r.evm < best.evm) { best = r; best.id = null; }
    }
    best.id2 = eval640(best.d);
}
console.log('(3) EVM bout en bout (passe-bas 6 MHz, retard ' + best.d + ' cycle, gain ' + best.g.toFixed(3) + ') : ' + best.evm.toFixed(1) + ' dB');

// décision sur la variation de phase pendant [(k+1,5)T, (k+2,5)T] (impulsion centrée en kT + 2T)
{
    const Tm = 8 * G.PER / G.PAS;                          // échantillons à 640 MS/s par symbole
    const ref = best.id2, dly = best.d;
    // phase du signal filtré, corrigée de la rotation complexe de gain
    const ph = i => Math.atan2(yi[i], yr[i]);
    let err = 0, n = 0;
    for (let k = 20; k < bits.length - 30; k++) {
        const t1 = Math.round((k + 1.5) * Tm + dly * 8), t2 = Math.round((k + 2.5) * Tm + dly * 8);
        if (t2 >= NM - 100 || t1 < 100) { continue; }
        let d = ph(t2) - ph(t1); while (d > Math.PI) { d -= 2 * Math.PI; } while (d < -Math.PI) { d += 2 * Math.PI; }
        const dec = d > 0 ? 1 : -1;
        if (dec !== bits[k]) { err++; } n++;
    }
    console.log('    décisions de bit : ' + n + ', erreurs ' + err);
}
