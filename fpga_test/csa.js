/*
================================================================================
  Nom        : csa.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : référence au bit près de l'embrouillage DVB-CSA (algorithme
               commun d'embrouillage DVB) des paquets TS d'un PID, clé fixe
               (BISS-1) : compose l'entrée du banc csa (csa_in.bin : paquets
               de ts_v.bin et paquets d'essai aux limites), la chiffre, écrit
               la référence ts_csa.bin et le paquetage csa_tab_pkg de
               vhdl/jpeg2dvb_fpga.vhd ; autotest sur deux vecteurs publics
               (jeu d'essai de libdvbcsa)
  Auteur     : Eric PERRET
  Date       : 2026-11-11
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node csa.js                            → csa_in.bin et ts_csa.bin (banc csa)
               node csa.js ENTREE.bin SORTIE.bin CW PID  → chiffre un fichier TS (CW : 16
                                                          chiffres hexadécimaux, PID en hexadécimal)
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-11  création

  Algorithme (même formulation que le VHDL, module csa_enc) :
    Paquet : un paquet du PID, avec charge utile, non déjà embrouillé et d'au
      moins 8 octets de charge, est chiffré à partir de la fin de son en-tête
      (4 octets, plus le champ d'adaptation) ; transport_scrambling_control
      passe à « 10 » (clé paire). Les autres paquets passent inchangés.
    Blocs : la charge est découpée en blocs de 8 octets ; du dernier bloc
      entier au premier, bloc ← E(bloc ⊕ bloc suivant chiffré) (le dernier sans
      ⊕). E : 56 tours ; tour i : S = SBOX[k(i) ⊕ W7] ; W1…W7, W0 ←
      W2⊕W0, W3⊕W0, W4⊕W0, W5, W6⊕perm(S), W7, W0⊕S, W1.
      Clé : K6 = mot de contrôle (octet 0 en poids faible), K(i−1) =
      permutation de bits de K(i) ; k(8i + j) = octet j de K(i), ⊕ i.
    Flux : registres A et B de 10 quartets, X, Y, Z, D, E, F de 4 bits, P, Q,
      C de 1 bit ; A et B chargés par le mot de contrôle, quartets de chaque
      octet échangés. Le premier bloc chiffré, laissé tel quel, initialise le
      flux (4 tours par octet) ; ensuite 4 tours donnent 8 bits de flux par
      octet, ajoutés (⊕) aux octets suivants, blocs chiffrés puis résidu.
      Tour : A ← A décalé, quartet entrant A9 ⊕ X (⊕ D ⊕ entrée à
      l'initialisation) ; B ← B décalé, quartet entrant B6 ⊕ B9 ⊕ Y (⊕ entrée),
      tourné d'un bit si P ; D ← E ⊕ Z ⊕ sélection de B ; E ← F ;
      F ← Z + E + C (avec retenue C) si Q, sinon E ; X, Y, Z, P, Q ← 7 boîtes
      de 5 bits de A ; bits de sortie : D3 ⊕ D2, D1 ⊕ D0.
  Mot de contrôle BISS-1 : 6 octets de clé de session S0…S5 →
    CW = S0 S1 S2 (S0+S1+S2) S3 S4 S5 (S3+S4+S5), sommes modulo 256.
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');
const { section } = require('./fusion.js');

// ---------------------------------------------------------------------------
// Tables de l'algorithme (forme directe, reprises dans csa_tab_pkg)
//   KPERM : permutation de la clé, le bit i va en KPERM[i]
//   BPERM : permutation de la sortie de la boîte S, le bit i va en BPERM[i]
//   SBOX  : boîte S du chiffrement par blocs
//   F_BSEL : bits de B (après décalage) ajoutés à chaque bit de D
//   F_IN, F_OUT, F_TAB : boîtes du flux : 5 bits de A (après décalage, le
//     premier en poids faible de l'indice), 2 bits de sortie parmi X (0 à 3),
//     Y (4 à 7), Z (8 à 11), P (12), Q (13), table (chiffre = 2·bit F_OUT[1]
//     + bit F_OUT[0])
// ---------------------------------------------------------------------------
const KPERM = [19, 27, 55, 46, 1, 15, 36, 22, 56, 61, 39, 21, 54, 58, 50, 28, 7, 29, 51, 6, 33, 35, 20, 16, 47, 30, 32, 63, 10, 11, 4, 38, 62, 26, 40, 18, 12, 52, 37, 53, 23, 59, 41, 17, 31, 0, 25, 43, 44, 14, 2, 13, 45, 48, 3, 60, 49, 8, 34, 5, 9, 42, 57, 24];
const BPERM = [1, 7, 5, 4, 2, 6, 0, 3];
const SBOX = Buffer.from(
    '3aea68fe33e9881a83cfe17fbae23812' +
    'e82761950c36e570a206827c17a32649' +
    'be7a6d47c1518ff3cc5b67bdcd1808c9' +
    'ff69ef034e484a843fb41004dcf55cc6' +
    '16abac4cf16a2f3c3bd4d594d0c46362' +
    '71a1f94f2eaac556e33993ce6564e458' +
    '6c194279ddee96f68aec1e855345debb' +
    '7e0a9a132a9dc25e5a1f32359ca87330' +
    '293de792871b2b4ba557974015e6bc0e' +
    'ebc3342db84425a41cc723ed906e5000' +
    '999e4dd9da8d6f5f3ed7217486df6b05' +
    '8e5d3711d22875d6a77724bff0b002b7' +
    'f8fc8109b10176917d0fc8a0f2cb7860' +
    'd1f7e0b59822b3201da6db7b599fae31' +
    'fbd3b6ca437207f4d84114550d548bb9' +
    'ad460baf80522cfa8c8966fdb2a99bc0', 'hex');
const F_BSEL = [[13,27,32,38],[16,21,23,34],[15,18,24,33],[12,25,30,39]];
const F_IN = [[9,14,27,28,37],[19,22,24,33,38],[13,17,20,30,39],[6,16,25,31,36],[7,8,21,23,26],[5,11,15,18,32],[10,12,29,34,35]];
const F_OUT = [[1,11],[6,8],[7,9],[0,10],[2,4],[3,5],[12,13]];
const F_TAB = [
    '33201301001230232230310213210112',
    '20213103032332100130203113022112',
    '02021320203121131311203332020130',
    '13011212213030230131321220030320',
    '21122330100132230310300321321201',
    '31031021201032021220033231231031',
    '02313021132202103003021313302121'];
const ESSAIS = [
    { cw: '07e01b02c9e045ee',
      clair: 'afbefbefbefbefbefbefbefbe6b5ad7cf9f3e5b16c7cf9f3e6b5ad6b5f3e7cf96c5b1f3e7cf9ad6b5ad7cf9f3e5b16c7cf9f3e6b5ad6b5f3e7cf96c5b1f3e7cf9ad6b5ad7cf9f3e5b16c7cf9f3e6b5ad6b5f3e7cf96c5b1f3e7cf9ad6b5ad7cf9f3e5b16c7cf9f3e6b5ad6b5f3e7cf96c5b1f3e7cf9ad6b5ad7cf9f3e5b16c7cf9f3e6b5ad6b5f3e7cf96c5b1f3e7cf9ad6b5ad7cf9f3e5b16c7cf9f3e6b5ad6b5f3e7cf96c5b1f3e7cf9ad000000000fffc440066b11111',
      chiffre: 'decf0a0db2d7c440de5d63185a9817aac9bc27c6cb494048fd20b7055b27cbeb9af0ac456d56f47b6fa057f39bf7a2c7d46824002f28139694a87cf46f072a0ee8a1ebc780ac1f79bf5db6107c2e52e9342ca83901730424a81edb5bcb24f631ab026bf9f6f7e952adcf620f42f6665dc086f27b4020a9bd1ffd16ad2e75a6a085f39c31204efb956178ce10c1485fd3610512f4e204aee086015655b10fa633952092f0be3931e12af793b4f7e4f185ae50f163d45d9c6c' },
    { cw: '0706050403020100',
      clair: '2d0a472018119c8ad12a656b89e4352bc2b59061d17e02e13f4670cf77912f2293c16cfe49ad7cc2af861ba329beaa64f022b95e98aa60efdfd64477e6bfbb94b20a630e5cf2acb449cc9e4f944c3012e855c244a452cb6181c9b6a66befafa6711d7b582ffad10c079d1f3587be029f20c6608f1c300f96d071d65110df5bf6442f8028b7ec23594b940b9a74a11ff79e76b4dfbb3c8c88972256731605acf94f779d38a06b05d2e61501b15cc962a99b1a6a1acfe6a8ba',
      chiffre: '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7' }];

/* motControle — E : clé de session BISS-1 (12 chiffres hexadécimaux) → S : mot
   de contrôle de 8 octets, avec ses deux sommes */
function motControle(sw) {
    const s = Buffer.from(sw, 'hex');
    return Buffer.from([s[0], s[1], s[2], (s[0] + s[1] + s[2]) & 255, s[3], s[4], s[5], (s[3] + s[4] + s[5]) & 255]);
}

/* cleBlocs — E : mot de contrôle → T : K6 = mot, K(i−1) = permutation de K(i)
   → S : les 56 octets de clé des tours */
function cleBlocs(cw) {
    let k = new Uint8Array(64);
    for (let i = 0; i < 64; i++) { k[i] = (cw[i >> 3] >> (i & 7)) & 1; }
    const K = [];
    K[6] = k;
    for (let i = 6; i > 0; i--) { const n = new Uint8Array(64); for (let b = 0; b < 64; b++) { n[KPERM[b]] = K[i][b]; } K[i - 1] = n; }
    const kk = [];
    for (let i = 0; i < 7; i++) { for (let j = 0; j < 8; j++) { let o = 0; for (let b = 0; b < 8; b++) { o |= K[i][8 * j + b] << b; } kk.push(o ^ i); } }
    return kk;
}

/* perm — E : sortie de la boîte S → S : ses bits permutés */
function perm(s) { let r = 0; for (let b = 0; b < 8; b++) { r |= ((s >> b) & 1) << BPERM[b]; } return r; }

/* chiffreBloc — E : clé des tours, bloc de 8 octets → T : 56 tours → S : bloc chiffré */
function chiffreBloc(kk, bloc) {
    const W = Array.from(bloc);
    for (let i = 0; i < 56; i++) {
        const S = SBOX[kk[i] ^ W[7]], L = W[1];
        W[1] = W[2] ^ W[0]; W[2] = W[3] ^ W[0]; W[3] = W[4] ^ W[0]; W[4] = W[5];
        W[5] = W[6] ^ perm(S); W[6] = W[7]; W[7] = W[0] ^ S; W[0] = L;
    }
    return W;
}

/* fluxInit — E : mot de contrôle → S : état du flux (A, B en bits, quartets
   de chaque octet échangés ; le reste à zéro) */
function fluxInit(cw) {
    const e = { a: new Uint8Array(40), b: new Uint8Array(40), x: 0, y: 0, z: 0, d: 0, e: 0, f: 0, p: 0, q: 0, c: 0 };
    for (let j = 0; j < 4; j++) { for (let b = 0; b < 8; b++) { e.a[8 * j + b] = (cw[j] >> ((b + 4) & 7)) & 1; e.b[8 * j + b] = (cw[4 + j] >> ((b + 4) & 7)) & 1; } }
    return e;
}

/* fluxTour — E : état, initialisation ou non, quartets d'entrée pour A et B →
   T : un tour → S : état mis à jour (sur place) */
function fluxTour(e, init, ivA, ivB) {
    const quartet = (r, n) => r[n] | (r[n + 1] << 1) | (r[n + 2] << 2) | (r[n + 3] << 3);
    let na = quartet(e.a, 36) ^ e.x, tb = quartet(e.b, 24) ^ quartet(e.b, 36) ^ e.y;
    if (init) { na ^= e.d ^ ivA; tb ^= ivB; }
    if (e.p) { tb = ((tb << 1) | (tb >> 3)) & 15; }
    e.a.copyWithin(4, 0, 36); e.b.copyWithin(4, 0, 36);
    for (let b = 0; b < 4; b++) { e.a[b] = (na >> b) & 1; e.b[b] = (tb >> b) & 1; }
    let bs = 0;
    for (let o = 0; o < 4; o++) { let v = 0; for (const i of F_BSEL[o]) { v ^= e.b[i]; } bs |= v << o; }
    const d = e.e ^ e.z ^ bs, ee = e.f;
    if (e.q) { const s = e.z + e.e + e.c; e.f = s & 15; e.c = s >> 4; } else { e.f = e.e; }
    e.d = d; e.e = ee;
    let res = 0;
    for (let k = 0; k < 7; k++) {
        let v = 0;
        for (let m = 0; m < 5; m++) { v |= e.a[F_IN[k][m]] << m; }
        const t = +F_TAB[k][v];
        res |= ((t & 1) << F_OUT[k][0]) | ((t >> 1) << F_OUT[k][1]);
    }
    e.x = res & 15; e.y = (res >> 4) & 15; e.z = (res >> 8) & 15; e.p = (res >> 12) & 1; e.q = (res >> 13) & 1;
}

/* chiffre — E : mot de contrôle, charge utile (tableau d'octets, modifié sur
   place) → T : blocs en chaîne depuis la fin, puis flux → S : charge chiffrée */
function chiffre(cw, d) {
    const n = d.length >> 3;
    if (n === 0) { return; }
    const kk = cleBlocs(cw);
    let suivant = [0, 0, 0, 0, 0, 0, 0, 0];
    for (let i = n - 1; i >= 0; i--) {
        const w = chiffreBloc(kk, d.slice(8 * i, 8 * i + 8).map((v, j) => v ^ suivant[j]));
        for (let j = 0; j < 8; j++) { d[8 * i + j] = w[j]; }
        suivant = w;
    }
    const e = fluxInit(cw);
    for (let i = 0; i < 8; i++) {
        const h = d[i] >> 4, l = d[i] & 15;
        fluxTour(e, true, h, l); fluxTour(e, true, l, h); fluxTour(e, true, h, l); fluxTour(e, true, l, h);
    }
    for (let i = 8; i < d.length; i++) {
        let o = 0;
        for (let r = 0; r < 4; r++) { fluxTour(e, false, 0, 0); o = (o << 2) | ((((e.d >> 3) ^ (e.d >> 2)) & 1) << 1) | ((e.d ^ (e.d >> 1)) & 1); }
        d[i] ^= o;
    }
}

/* paquet — E : mot de contrôle, PID, paquet TS de 188 octets (modifié sur
   place) → T : règle de l'en-tête, chiffrement de la charge → S : vrai si le
   paquet a été embrouillé */
function paquet(cw, pid, p) {
    if ((((p[1] & 0x1F) << 8) | p[2]) !== pid || !(p[3] & 0x10) || (p[3] & 0xC0)) { return false; }
    let h = 4;
    if (p[3] & 0x20) { h = 5 + p[4]; }
    if (h > 180) { return false; }
    const d = Array.from(p.subarray(h, 188));
    chiffre(cw, d);
    for (let i = 0; i < d.length; i++) { p[h + i] = d[i]; }
    p[3] = (p[3] & 0x3F) | 0x80;
    return true;
}

/* autotest — E : ESSAIS → T : chiffrement des deux charges de 184 octets → S :
   erreur si un octet diffère */
function autotest() {
    ESSAIS.forEach((t, k) => {
        const d = Array.from(Buffer.from(t.clair, 'hex')), c = Buffer.from(t.chiffre, 'hex');
        chiffre(Buffer.from(t.cw, 'hex'), d);
        for (let i = 0; i < c.length; i++) { if (d[i] !== c[i]) { throw new Error('autotest ' + (k + 1) + ' : octet ' + i + ' différent'); } }
    });
}

/* paquetage — E : tables → S : texte VHDL de csa_tab_pkg */
function paquetage() {
    const liste = (a, w) => a.map(v => String(v).padStart(w)).join(', ');
    const sb = [];
    for (let i = 0; i < 256; i += 16) { sb.push('        ' + Array.from(SBOX.subarray(i, i + 16)).map(v => 'x"' + v.toString(16).toUpperCase().padStart(2, '0') + '"').join(', ')); }
    const kp = [];
    for (let i = 0; i < 64; i += 16) { kp.push('        ' + liste(KPERM.slice(i, i + 16), 2)); }
    return `--==============================================================================
--  Nom        : csa_tab_pkg.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : tables de l'embrouillage DVB-CSA, en forme directe :
--               boîte S et permutations du chiffrement par blocs, permutation
--               de la clé, sélections de bits et boîtes du chiffrement de flux
--               (fichier généré par fpga_test/csa.js)
--  Auteur     : Eric PERRET
--  Date       : 2026-11-11
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-11-11  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package csa_tab_pkg is
    -- chiffrement par blocs : boîte S ; le bit i de sa sortie va en CSA_BPERM(i)
    type csa_sbox_t is array (0 to 255) of std_logic_vector(7 downto 0);
    constant CSA_SBOX : csa_sbox_t := (
${sb.join(',\n')});
    type csa_bperm_t is array (0 to 7) of natural range 0 to 7;
    constant CSA_BPERM : csa_bperm_t := (${liste(BPERM, 1)});
    -- clé : le bit i va en CSA_KPERM(i)
    type csa_kperm_t is array (0 to 63) of natural range 0 to 63;
    constant CSA_KPERM : csa_kperm_t := (
${kp.join(',\n')});
    -- flux : bits de B (après décalage) ajoutés au bit o de D
    type csa_bsel_t is array (0 to 3, 0 to 3) of natural range 0 to 39;
    constant CSA_BSEL : csa_bsel_t := (
${F_BSEL.map(l => '        (' + liste(l, 2) + ')').join(',\n')});
    -- flux : 7 boîtes ; entrées : 5 bits de A (après décalage, le premier en
    --   poids faible de l'indice) ; sorties : 2 bits parmi X (0 à 3), Y (4 à 7),
    --   Z (8 à 11), P (12), Q (13) ; tables d'un bit par sortie, indice de
    --   gauche à droite : CSA_F_T1 → CSA_F_OUT(k, 1), CSA_F_T0 → CSA_F_OUT(k, 0)
    type csa_f_in_t is array (0 to 6, 0 to 4) of natural range 0 to 39;
    constant CSA_F_IN : csa_f_in_t := (
${F_IN.map(l => '        (' + liste(l, 2) + ')').join(',\n')});
    type csa_f_out_t is array (0 to 6, 0 to 1) of natural range 0 to 13;
    constant CSA_F_OUT : csa_f_out_t := (
${F_OUT.map(l => '        (' + liste(l, 2) + ')').join(',\n')});
    type csa_f_tab_t is array (0 to 6) of std_logic_vector(0 to 31);
    constant CSA_F_T1 : csa_f_tab_t := (
${F_TAB.map(s => '        "' + [...s].map(c => +c >> 1).join('') + '"').join(',\n')});
    constant CSA_F_T0 : csa_f_tab_t := (
${F_TAB.map(s => '        "' + [...s].map(c => +c & 1).join('') + '"').join(',\n')});
end package csa_tab_pkg;
`;
}

/* entreeBanc — E : ts_v.bin → T : paquets 240 à 399 (PAT, PMT, PCR, vidéo,
   nuls), puis paquets d'essai du PID vidéo : charges de 0 à 17 octets derrière
   un champ d'adaptation, paquet déjà embrouillé, paquet sans charge, autre
   PID → S : flux d'entrée du banc */
function entreeBanc() {
    const src = fs.readFileSync(path.join(__dirname, 'ts_v.bin')), l = [src.subarray(188 * 240, 188 * 400)];
    let g = 0x1234;
    const alea = () => { g = (g * 75 + 74) % 65537; return g & 255; };
    const essai = (pidv, ctrl, charge) => {
        const p = Buffer.alloc(188, 0xFF);
        p[0] = 0x47; p[1] = pidv >> 8; p[2] = pidv & 255; p[3] = ctrl | (l.length & 15);
        let h = 4;
        if (ctrl & 0x20) { p[4] = 183 - charge; if (p[4] > 0) { p[5] = 0; } h = 188 - charge; }
        for (let i = h; i < 188; i++) { p[i] = alea(); }
        l.push(p);
    };
    for (const c of [0, 1, 7, 8, 9, 15, 16, 17, 23, 24, 25, 100, 183]) { essai(0x0101, 0x30, c); }
    essai(0x0101, 0x20, 0);          // champ d'adaptation seul
    essai(0x0101, 0x90, 184);        // déjà embrouillé
    essai(0x0102, 0x10, 184);        // autre PID
    essai(0x0101, 0x10, 184);        // charge entière
    return Buffer.concat(l);
}

// ---------------------------------------------------------------------------
const banc = process.argv.length < 4;
const sortie = banc ? path.join(__dirname, 'ts_csa.bin') : process.argv[3];
const cw = process.argv[4] ? Buffer.from(process.argv[4], 'hex') : motControle('482148214821');
const pid = parseInt(process.argv[5] || '0101', 16);

autotest();
const ts = banc ? entreeBanc() : Buffer.from(fs.readFileSync(process.argv[2]));
if (banc) { fs.writeFileSync(path.join(__dirname, 'csa_in.bin'), ts); }
let nb = 0, residu = 0, courts = 0;
for (let k = 0; k < Math.floor(ts.length / 188); k++) {
    const p = ts.subarray(188 * k, 188 * k + 188);
    const h = (p[3] & 0x20) ? 5 + p[4] : 4;
    if (paquet(cw, pid, p)) { nb++; if ((188 - h) & 7) { residu++; } }
    else if ((((p[1] & 0x1F) << 8) | p[2]) === pid && (p[3] & 0x10) && !(p[3] & 0xC0)) { courts++; }
}
fs.writeFileSync(sortie, ts);
if (banc) { section('csa_tab_pkg.vhd', paquetage()); }
console.log('autotest   : 2 vecteurs de 184 octets identiques');
console.log('mot de contrôle : ' + cw.toString('hex').toUpperCase() + ', PID 0x' + pid.toString(16).toUpperCase().padStart(4, '0'));
console.log('entrée     : ' + (banc ? 'csa_in.bin' : path.basename(process.argv[2])) + ', ' + Math.floor(ts.length / 188) + ' paquets ; embrouillés : ' + nb + ' (dont ' + residu + ' avec résidu), charge de moins de 8 octets laissée en clair : ' + courts);
console.log('sortie     : ' + path.basename(sortie) + ', ' + ts.length + ' octets' + (banc ? ' ; paquetage csa_tab_pkg réécrit' : ''));
