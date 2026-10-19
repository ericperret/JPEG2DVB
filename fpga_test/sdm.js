/*
================================================================================
  Nom        : sdm.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : référence au bit près de la sortie sigma-delta (cahier des charges
               § 5.4, point P3) : symboles QPSK (étape 13) → filtre SRRC calculé
               directement à 640 MS/s (64 phases) → modulateur sigma-delta 1 bit
               d'ordre 3 par voie, 8 bits par cycle de 80 MHz ; écrit le flux de
               référence, le paquetage sdm_coef_pkg et contrôle le spectre
  Auteur     : Eric PERRET
  Date       : 2026-10-19
  Version    : 2.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node sdm.js                     → qpsk.bin, 20 000 symboles → sd_iq.bin
               node sdm.js ENTREE.bin N SORTIE.bin
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-10-19  création (CIC × 8 puis boucle, états 24 bits)
               1.1  2026-10-19  bornage des états une fois par groupe de 8 bits
               2.0  2026-10-19  entrée par table : SRRC à 640 MS/s depuis les
                     symboles (plus de CIC) ; états réduits à 16 bits (FS = 2¹⁰) ;
                     décision des 8 bits d'un cycle par anticipation (formulation
                     du VHDL, vérifiée égale à la boucle pas à pas) ; garde de
                     débordement par remise à zéro ; génère sdm_coef_pkg

  Arithmétique (entière, identique au VHDL) :
    Symboles : bit 0 → +1, bit 1 → −1 ; fenêtre des 13 derniers symboles reçus
      (positions d = 0 à 12, d = 12 le plus récent ; avant le premier symbole,
      la fenêtre est remplie de +1). Chaque symbole reçu produit 64 instants
      (8 cycles q de 8 instants r) : u(8q + r) = Σ_d H(8q + r)(d) · sym(d).
    H : filtre SRRC de la page 14 (α = 0,35, 12 symboles, fenêtre de Kaiser
      β = 5,65) échantillonné à 64 phases, mis à l'échelle pour une crête de
      0,47 FS et arrondi à l'entier ; FS = 2¹⁰.
    Sigma-delta CIFB d'ordre 3 (coefficients 1/16, 3/8, 1, états multipliés
      par 16) : s = +1 si x3 ≥ 0, sinon −1 ;
        x3 ← x3 + x2 − 16·FS·s
        x2 ← x2 + x1 − 6·FS·s
        x1 ← x1 + u − FS·s
    Garde : si un état dépasse ±2¹⁵ en début de cycle, les 8 bits du cycle sont
      produits normalement puis les états repartent de zéro.
    Bit émis : 1 pour s = +1, 0 pour s = −1.
  Anticipation (VHDL) : au début d'un cycle, Pk = C(k,2)·x1 + k·x2 + x3 + Ink
    (Ink : apport des entrées du cycle) ; sk = 1 si Pk ≥ Dk(s0…sk−1), avec
    Dk = Σj c(k−1−j)·sj et c(m) = C(m,2)·FS + 6m·FS + 16·FS ; état suivant
    X8 = M⁸·X + U − T(s0…s7) (T : table de 256 entrées).
  Format de SORTIE : pour chaque cycle, un octet I puis un octet Q ; le bit 7
    est le premier bit émis.
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');
const { section } = require('./fusion.js');

const F = 10, FS = 1 << F;                    // pleine échelle
const SPS = 64, SPAN = 12, AL = 0.35, NT = SPAN * SPS + 1;
const BETA = 0.1102 * (60 - 8.7);             // Kaiser, comme la page 14
const GARDE = 1 << 15;                        // garde de débordement des états
const A1 = FS, A2 = 6 * FS, A3 = 16 * FS;     // retours (états × 16)
const FH = 640e6, BANDE = 6.75e6;

const entree = process.argv[2] || path.join(__dirname, 'qpsk.bin');
const NSYM = +(process.argv[3] || 20000);
const sortie = process.argv[4] || path.join(__dirname, 'sd_iq.bin');

/* coefficients — E : — → T : SRRC fenêtré à 64 phases, échelle 0,47 FS →
   S : H flottant et H entier [phase][d] */
function coefficients() {
    const I0 = x => { let s = 1, t = 1; const q = (x / 2) * (x / 2); for (let k = 1; k < 25; k++) { t *= q / (k * k); s += t; if (t < 1e-12 * s) { break; } } return s; };
    const srrc = t => {
        if (Math.abs(t) < 1e-12) { return 1 - AL + 4 * AL / Math.PI; }
        if (Math.abs(Math.abs(t) - 1 / (4 * AL)) < 1e-12) {
            return AL / Math.SQRT2 * ((1 + 2 / Math.PI) * Math.sin(Math.PI / (4 * AL)) + (1 - 2 / Math.PI) * Math.cos(Math.PI / (4 * AL)));
        }
        const p = Math.PI * t, f = 4 * AL * t;
        return (Math.sin(p * (1 - AL)) + f * Math.cos(p * (1 + AL))) / (p * (1 - f * f));
    };
    const h = new Float64Array(NT);
    for (let i = 0; i < NT; i++) { const x = 2 * i / (NT - 1) - 1; h[i] = srrc((i - (NT - 1) / 2) / SPS) * I0(BETA * Math.sqrt(1 - x * x)) / I0(BETA); }
    const Hf = [];
    let mx = 0;
    for (let p = 0; p < SPS; p++) {
        const r = [];
        let s = 0;
        for (let d = 0; d < 13; d++) { const i = p + 768 - 64 * d; const v = (i >= 0 && i < NT) ? h[i] : 0; r.push(v); s += Math.abs(v); }
        Hf.push(r); mx = Math.max(mx, s);
    }
    const K = 0.47 * FS / mx;
    return { Hf: Hf.map(r => r.map(v => v * K)), H: Hf.map(r => r.map(v => Math.round(v * K))) };
}

/* lireSymboles — E : fichier de l'étape 13 (I, Q signés 8 bits par symbole), N
   → S : symboles ±1 des voies I et Q */
function lireSymboles(f, n) {
    const b = fs.readFileSync(f), m = Math.min(n, b.length >> 1), I = new Int8Array(m), Q = new Int8Array(m);
    for (let k = 0; k < m; k++) { I[k] = b.readInt8(2 * k) < 0 ? -1 : 1; Q[k] = b.readInt8(2 * k + 1) < 0 ? -1 : 1; }
    return { I: I, Q: Q };
}

/* onde — E : symboles, H → T : fenêtre glissante de 13 symboles (+1 avant le
   premier), 64 instants par symbole reçu → S : entrée du sigma-delta */
function onde(sym, H) {
    const u = new Float64Array(sym.length * SPS), w = new Int8Array(13).fill(1);
    for (let m = 0; m < sym.length; m++) {
        w.copyWithin(0, 1); w[12] = sym[m];
        for (let p = 0; p < SPS; p++) { let v = 0; for (let d = 0; d < 13; d++) { v += H[p][d] * w[d]; } u[m * SPS + p] = v; }
    }
    return u;
}

/* boucle — E : entrée u entière → T : sigma-delta pas à pas, garde en début
   de cycle → S : bits (±1), maxima des états, nombre de remises à zéro */
function boucle(u) {
    const v = new Int8Array(u.length);
    let x1 = 0, x2 = 0, x3 = 0, m = 0, raz = 0;
    for (let g = 0; g < u.length / 8; g++) {
        const ovf = Math.abs(x1) > GARDE || Math.abs(x2) > GARDE || Math.abs(x3) > GARDE;
        for (let r = 0; r < 8; r++) {
            const n = 8 * g + r, s = x3 >= 0 ? 1 : -1;
            v[n] = s;
            const n3 = x3 + x2 - A3 * s, n2 = x2 + x1 - A2 * s, n1 = x1 + u[n] - A1 * s;
            x3 = n3; x2 = n2; x1 = n1;
            m = Math.max(m, Math.abs(x1), Math.abs(x2), Math.abs(x3));
        }
        if (ovf) { x1 = 0; x2 = 0; x3 = 0; raz++; }
    }
    return { v: v, m: m, raz: raz };
}

/* anticipation — E : entrée u entière → T : formulation du VHDL : Pk, seuils
   Dk, tables T et R par motif de 8 bits → S : bits (±1), maxima de |P|, |Q| */
function anticipation(u) {
    const C2 = k => k * (k - 1) / 2, c = m => C2(m) * A1 + m * A2 + A3;
    // T(s) : correction de l'état après 8 pas, motif b (bit 7 = s0)
    const T = [];
    for (let b = 0; b < 256; b++) {
        let t1 = 0, t2 = 0, t3 = 0;
        for (let j = 0; j < 8; j++) {
            const s = (b >> (7 - j)) & 1 ? 1 : -1, m = 7 - j;
            t1 += A1 * s; t2 += (m * A1 + A2) * s; t3 += (C2(m) * A1 + m * A2 + A3) * s;
        }
        T.push([t1, t2, t3]);
    }
    const v = new Int8Array(u.length), G = u.length / 8;
    const inn = g => { const r = []; for (let k = 0; k < 8; k++) { let s = 0; for (let j = 0; j < k; j++) { s += C2(k - 1 - j) * u[8 * g + j]; } r.push(s); } return r; };
    let X = [0, 0, 0], P = inn(0), mp = 0, mq = 0;
    for (let g = 0; g < G; g++) {
        // décisions
        let b = 0;
        for (let k = 0; k < 8; k++) {
            let D = 0;
            for (let j = 0; j < k; j++) { D += c(k - 1 - j) * ((b >> (k - 1 - j)) & 1 ? 1 : -1); }
            const s = P[k] >= D ? 1 : 0;
            b = (b << 1) | s;
            v[8 * g + k] = s ? 1 : -1;
            mp = Math.max(mp, Math.abs(P[k]));
        }
        // état suivant
        let U1 = 0, U2 = 0, U3 = 0;
        for (let j = 0; j < 8; j++) { const w = u[8 * g + j], m = 7 - j; U1 += w; U2 += m * w; U3 += C2(m) * w; }
        const Y = [X[0] + U1, 8 * X[0] + X[1] + U2, 28 * X[0] + 8 * X[1] + X[2] + U3];
        const ovf = Math.abs(X[0]) > GARDE || Math.abs(X[1]) > GARDE || Math.abs(X[2]) > GARDE;
        const X8 = [Y[0] - T[b][0], Y[1] - T[b][1], Y[2] - T[b][2]];
        const In = g + 1 < G ? inn(g + 1) : [0, 0, 0, 0, 0, 0, 0, 0];
        if (ovf) { X = [0, 0, 0]; P = In; }
        else {
            X = X8;
            P = [];
            for (let k = 0; k < 8; k++) {
                const q = C2(k) * Y[0] + k * Y[1] + Y[2] + In[k];
                mq = Math.max(mq, Math.abs(q));
                P.push(q - (C2(k) * T[b][0] + k * T[b][1] + T[b][2]));
            }
        }
    }
    return { v: v, mp: mp, mq: mq };
}

/* ecrire — E : bits I et Q → T : 8 bits par octet, premier bit en poids fort,
   I puis Q → S : fichier de référence */
function ecrire(f, vi, vq) {
    const n = vi.length / 8, b = Buffer.alloc(2 * n);
    for (let k = 0; k < n; k++) {
        let oi = 0, oq = 0;
        for (let r = 0; r < 8; r++) { oi = (oi << 1) | (vi[8 * k + r] > 0 ? 1 : 0); oq = (oq << 1) | (vq[8 * k + r] > 0 ? 1 : 0); }
        b[2 * k] = oi; b[2 * k + 1] = oq;
    }
    fs.writeFileSync(f, b);
}

/* fft — E : parties réelle et imaginaire (longueur 2^k) → S : transformée sur place */
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

/* spectre — E : bits I/Q, onde idéale I/Q (H flottant) → T : FFT de 2²⁰
   points de I + jQ, gain complexe et retard ajustés dans ±6,75 MHz → S :
   rapport signal sur bruit en bande, densité hors bande relative */
function spectre(vi, vq, ui, uq) {
    const L = 1 << 20, o = 13 * SPS, kb = Math.floor(BANDE / FH * L);
    const ar = new Float64Array(L), ai = new Float64Array(L), br = new Float64Array(L), bi = new Float64Array(L);
    for (let n = 0; n < L; n++) { ar[n] = vi[o + n]; ai[n] = vq[o + n]; br[n] = ui[o + n]; bi[n] = uq[o + n]; }
    fft(ar, ai); fft(br, bi);
    let snr = -Infinity;
    for (let d = 0; d < 12; d++) {
        let xr = 0, xi = 0, yy = 0, xx = 0;
        for (let k = -kb; k <= kb; k++) {
            const kk = (k + L) % L, w = -2 * Math.PI * k * d / L, cs = Math.cos(w), sn = Math.sin(w);
            const ur = br[kk] * cs - bi[kk] * sn, uj = br[kk] * sn + bi[kk] * cs;
            xr += ar[kk] * ur + ai[kk] * uj; xi += ai[kk] * ur - ar[kk] * uj;
            yy += ur * ur + uj * uj; xx += ar[kk] * ar[kk] + ai[kk] * ai[kk];
        }
        const g2 = (xr * xr + xi * xi) / yy;
        snr = Math.max(snr, 10 * Math.log10(g2 / (xx - g2)));
    }
    const dens = f => {
        const k0 = Math.round(f / FH * L);
        let s = 0;
        for (let k = k0 - 64; k <= k0 + 64; k++) { const kk = (k + L) % L; s += ar[kk] * ar[kk] + ai[kk] * ai[kk]; }
        return s / 129;
    };
    const d0 = dens(0);
    return { snr: snr, hb: [20e6, 50e6, 100e6, 200e6, 300e6].map(f => [f, 10 * Math.log10(dens(f) / d0)]) };
}

/* paquetage — E : H entier → S : texte VHDL de sdm_coef_pkg */
function paquetage(H) {
    let t = '--==============================================================================\n' +
        '--  Nom        : sdm_coef_pkg.vhd\n' +
        '--  Objet      : coefficients du filtre SRRC à 640 MS/s pour la sortie\n' +
        '--               sigma-delta (fichier généré par fpga_test/sdm.js)\n' +
        '--  Paramètres : α = 0,35, 12 symboles, 64 phases × 13 symboles, fenêtre de\n' +
        '--               Kaiser β = 5,65, crête 0,47 FS, FS = 2^' + F + '\n' +
        '--  Principe   : u(8q + r) = somme sur d de SDM_H(8q + r)(d) · sym(d), d = 12\n' +
        '--               le symbole le plus récent, sym = ±1\n' +
        '--==============================================================================\n' +
        'library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n\n' +
        'package sdm_coef_pkg is\n' +
        '    constant SDM_F   : natural := ' + F + ';\n' +
        '    type sdm_phase_t is array (0 to 12) of integer range -32768 to 32767;\n' +
        '    type sdm_coef_t  is array (0 to 63) of sdm_phase_t;\n' +
        '    constant SDM_H : sdm_coef_t := (\n';
    t += H.map((r, p) => '        ' + String(p).padStart(2) + ' => (' + r.map(v => String(v).padStart(5)).join(', ') + ')').join(',\n') + '\n    );\nend package sdm_coef_pkg;\n';
    return t;
}

// ---------------------------------------------------------------------------
const co = coefficients();
const sy = lireSymboles(entree, NSYM);
const ui = onde(sy.I, co.H), uq = onde(sy.Q, co.H);
const bi = boucle(ui), bq = boucle(uq);
const ai = anticipation(ui), aq = anticipation(uq);
let ecarts = 0;
for (let n = 0; n < ui.length; n++) { if (ai.v[n] !== bi.v[n] || aq.v[n] !== bq.v[n]) { ecarts++; } }
ecrire(sortie, bi.v, bq.v);
section('sdm_coef_pkg.vhd', paquetage(co.H));
const sp = spectre(bi.v, bq.v, onde(sy.I, co.Hf), onde(sy.Q, co.Hf));
let pk = 0;
for (const r of co.H) { let s = 0; for (const v of r) { s += Math.abs(v); } pk = Math.max(pk, s); }
const fr = (v, d) => v.toFixed(d).replace('.', ',');
const bits = v => Math.ceil(Math.log2(v + 1)) + 1;

console.log('entrée     : ' + path.basename(entree) + ', ' + sy.I.length + ' symboles I/Q → ' + ui.length + ' instants à 640 MS/s par voie');
console.log('SRRC       : 64 phases × 13 symboles, crête de u ' + pk + ' (' + fr(pk / FS, 3) + ' FS), FS = 2^' + F);
console.log('états      : max ' + Math.max(bi.m, bq.m) + ' (' + bits(Math.max(bi.m, bq.m)) + ' bits signés), garde ±' + GARDE + ', remises à zéro : ' + (bi.raz + bq.raz));
console.log('anticipation : ' + (ecarts ? ecarts + ' bits DIFFÉRENTS de la boucle' : 'flux identique à la boucle pas à pas') +
    ' ; |P| ≤ ' + Math.max(ai.mp, aq.mp) + ' (' + bits(Math.max(ai.mp, aq.mp)) + ' bits), |Q| ≤ ' + Math.max(ai.mq, aq.mq) + ' (' + bits(Math.max(ai.mq, aq.mq)) + ' bits)');
console.log('spectre    : signal sur bruit dans ±6,75 MHz ' + fr(sp.snr, 1) + ' dB (contre le SRRC idéal)');
console.log('hors bande : ' + sp.hb.map(h => fr(h[0] / 1e6, 0) + ' MHz ' + fr(h[1], 1) + ' dB').join(', '));
console.log('sortie     : ' + path.basename(sortie) + ', ' + fs.statSync(sortie).size + ' octets ; paquetage sdm_coef_pkg réécrit');
if (ecarts) { process.exit(1); }
