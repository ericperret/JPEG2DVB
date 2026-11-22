#!/usr/bin/env node
/*
 * ══════════════════════════════════════════════════════════════
 *  Nom      : pic14.js
 *  Projet   : JPEG2DVB — chantier 2 : programme du PIC16F18323 (U6)
 *  Objet    : assembleur + simulateur PIC 14 bits (cœur « enhanced mid-range »),
 *             limité aux instructions de pll_boot.asm ; produit pic_fw.h
 *  Auteur   : Eric PERRET
 *  Date     : 2026-11-21
 *  Version  : 1.0.0
 *  Usage    : node pic14.js asm <source.asm> <pic_fw.h>
 *             node pic14.js sim <source.asm> <image_hex_26_octets> [...]
 *  Dépend.  : Node.js seul, aucune bibliothèque
 * ══════════════════════════════════════════════════════════════
 */
'use strict';
const fs = require('fs');
const path = require('path');

// ── Composant cible : PIC16F18323 (DS40001799) ──
const COMPOSANT = {
  nom: 'PIC16F18323',
  devid: 0x3067,
  flash: 2048,
  config: { 0x8007: 0x2977, 0x8008: 0x3AEF, 0x8009: 0x2003, 0x800A: 0x0003 } // masques des bits implémentés
};

// ══════════════════════════════════════════════════════════════
//  ASSEMBLEUR
// ══════════════════════════════════════════════════════════════

// Jeu d'instructions retenu (codage 14 bits, DS40001799 tableau 34-3)
const JEU = {
  addwf:  { t: 'fd', op: 0x0700 },
  clrf:   { t: 'f',  op: 0x0180 },
  decfsz: { t: 'fd', op: 0x0B00 },
  movf:   { t: 'fd', op: 0x0800 },
  movwf:  { t: 'f',  op: 0x0080 },
  lslf:   { t: 'fd', op: 0x3500 },
  bcf:    { t: 'fb', op: 0x1000 },
  bsf:    { t: 'fb', op: 0x1400 },
  btfsc:  { t: 'fb', op: 0x1800 },
  btfss:  { t: 'fb', op: 0x1C00 },
  movlw:  { t: 'k8', op: 0x3000 },
  xorlw:  { t: 'k8', op: 0x3A00 },
  goto:   { t: 'k11', op: 0x2800 },
  call:   { t: 'k11', op: 0x2000 },
  movlb:  { t: 'k5', op: 0x0020 },
  return: { t: '-',  op: 0x0008 },
  nop:    { t: '-',  op: 0x0000 },
  moviw:  { t: 'iw', op: 0x0010 }
};

function erreur(ligne, msg) {
  throw new Error('ligne ' + ligne + ' : ' + msg);
}

function nombre(txt, sym, ligne) {
  const s = txt.trim();
  if (/^0x[0-9a-f]+$/i.test(s)) return parseInt(s, 16);
  if (/^[0-9]+$/.test(s)) return parseInt(s, 10);
  const k = s.toLowerCase();
  if (Object.prototype.hasOwnProperty.call(sym, k)) return sym[k];
  erreur(ligne, 'valeur ou symbole inconnu « ' + s + ' »');
}

function assembler(source) {
  const lignes = source.split(/\r?\n/);
  const sym = {};
  const prog = [];      // { adr, ligne, mnem, ops, texte }
  const config = {};
  const entete = { date: '', version: '' };
  let adr = 0;

  // passe 1 : symboles et adresses
  lignes.forEach((brut, i) => {
    const n = i + 1;
    const mCart = brut.match(/^;\s*(Date|Version)\s*:\s*(.+)$/);
    if (mCart) entete[mCart[1].toLowerCase()] = mCart[2].trim();
    let l = brut.replace(/;.*$/, '').trim();
    if (!l) return;
    const mEqu = l.match(/^([A-Za-z_]\w*)\s+equ\s+(.+)$/i);
    if (mEqu) { sym[mEqu[1].toLowerCase()] = nombre(mEqu[2], sym, n); return; }
    const mEtiq = l.match(/^([A-Za-z_]\w*):\s*(.*)$/);
    if (mEtiq) {
      const e = mEtiq[1].toLowerCase();
      if (Object.prototype.hasOwnProperty.call(sym, e)) erreur(n, 'étiquette en double « ' + mEtiq[1] + ' »');
      sym[e] = adr;
      l = mEtiq[2].trim();
      if (!l) return;
    }
    const mots = l.split(/\s+/);
    const mnem = mots[0].toLowerCase();
    const ops = l.slice(mots[0].length).split(',').map(s => s.trim()).filter(s => s.length);
    if (mnem === 'org') { adr = nombre(ops[0], sym, n); return; }
    if (mnem === 'end') return;
    if (mnem === '__config') { prog.push({ dir: 'config', ops, ligne: n }); return; }
    if (!JEU[mnem]) erreur(n, 'instruction non prise en charge « ' + mnem + ' »');
    prog.push({ adr, ligne: n, mnem, ops, texte: l });
    adr++;
  });

  // passe 2 : codage
  const mots = new Map();
  const listing = [];
  for (const p of prog) {
    if (p.dir === 'config') {
      const a = nombre(p.ops[0], sym, p.ligne);
      const v = nombre(p.ops[1], sym, p.ligne);
      if (!(a in COMPOSANT.config)) erreur(p.ligne, 'adresse de configuration invalide');
      config[a] = v & 0x3FFF;
      continue;
    }
    const d = JEU[p.mnem];
    let code = d.op;
    const reg = (s) => {
      const v = nombre(s, sym, p.ligne);
      if (v > 0xFFF) erreur(p.ligne, 'adresse de registre hors plage');
      return v & 0x7F;
    };
    const dest = (s) => {
      const t = (s || '').toLowerCase();
      if (t === 'f' || t === '1') return 0x80;
      if (t === 'w' || t === '0') return 0x00;
      erreur(p.ligne, 'destination attendue (f ou w)');
    };
    switch (d.t) {
      case 'fd': code |= dest(p.ops[1]) | reg(p.ops[0]); break;
      case 'f':  code |= reg(p.ops[0]); break;
      case 'fb': {
        const b = nombre(p.ops[1], sym, p.ligne);
        if (b > 7) erreur(p.ligne, 'numéro de bit > 7');
        code |= (b << 7) | reg(p.ops[0]);
        break;
      }
      case 'k8': {
        const k = nombre(p.ops[0], sym, p.ligne);
        if (k > 0xFF) erreur(p.ligne, 'littéral > 255');
        code |= k;
        break;
      }
      case 'k11': {
        const k = nombre(p.ops[0], sym, p.ligne);
        if (k > 0x7FF) erreur(p.ligne, 'adresse de saut > 7FFh');
        code |= k;
        break;
      }
      case 'k5': {
        const k = nombre(p.ops[0], sym, p.ligne);
        if (k > 31) erreur(p.ligne, 'banque > 31');
        code |= k;
        break;
      }
      case 'iw': {
        const m = (p.ops[0] || '').toLowerCase().replace(/\s+/g, '').match(/^(\+\+|--)?fsr([01])(\+\+|--)?$/);
        if (!m || (m[1] && m[3]) || (!m[1] && !m[3])) erreur(p.ligne, 'moviw : forme attendue FSRn++, FSRn--, ++FSRn ou --FSRn');
        const mode = m[1] === '++' ? 0 : m[1] === '--' ? 1 : m[3] === '++' ? 2 : 3;
        code |= (parseInt(m[2], 10) << 2) | mode;
        break;
      }
      default: break;
    }
    if (p.adr >= COMPOSANT.flash) erreur(p.ligne, 'programme hors de la mémoire flash');
    if (mots.has(p.adr)) erreur(p.ligne, 'adresse ' + p.adr + ' déjà occupée');
    mots.set(p.adr, code & 0x3FFF);
    listing.push({ adr: p.adr, code: code & 0x3FFF, texte: p.texte });
  }
  for (const a of Object.keys(COMPOSANT.config)) {
    if (!(a in config)) throw new Error('mot de configuration ' + Number(a).toString(16) + 'h absent');
  }
  const taille = mots.size ? Math.max(...mots.keys()) + 1 : 0;
  const image = new Array(taille).fill(0x3FFF);
  for (const [a, v] of mots) image[a] = v;
  listing.sort((x, y) => x.adr - y.adr);
  return { image, config, listing, sym, entete };
}

function hex(v, n) {
  return v.toString(16).toUpperCase().padStart(n, '0');
}

function generer_h(res, source) {
  const parListe = new Map(res.listing.map(l => [l.adr, l.texte]));
  const o = [];
  o.push('/*');
  o.push(' * ══════════════════════════════════════════════════════════════');
  o.push(' *  Nom      : pic_fw.h');
  o.push(' *  Projet   : JPEG2DVB — chantier 2 : programme du PIC16F18323 (U6)');
  o.push(' *  Objet    : programme du PIC en mots de 14 bits + 4 mots de configuration');
  o.push(' *  Auteur   : Eric PERRET');
  o.push(' *  Date     : ' + (res.entete.date || ''));
  o.push(' *  Version  : ' + (res.entete.version || ''));
  o.push(' *  Origine  : produit par outils/pic14.js à partir de ' + source + ' (ne pas modifier)');
  o.push(' * ══════════════════════════════════════════════════════════════');
  o.push(' */');
  o.push('#pragma once');
  o.push('#include <stdint.h>');
  o.push('');
  o.push('#define PIC_FW_DEVID     0x' + hex(COMPOSANT.devid, 4) + 'u   /* ' + COMPOSANT.nom + ' (DS40001799) */');
  o.push('#define PIC_FW_NB_MOTS   ' + res.image.length + 'u');
  o.push('#define PIC_FW_FLASH     ' + COMPOSANT.flash + 'u');
  o.push('');
  o.push('/* mémoire programme, à partir de 0000h (mot non utilisé = 3FFFh) */');
  o.push('static const uint16_t pic_fw_mots[PIC_FW_NB_MOTS] = {');
  res.image.forEach((v, a) => {
    const t = parListe.get(a) || '';
    o.push('  /* ' + hex(a, 4) + ' */ 0x' + hex(v, 4) + (a < res.image.length - 1 ? ',' : ' ') + '   /* ' + t.replace(/\*\//g, '') + ' */');
  });
  o.push('};');
  o.push('');
  o.push('/* mots de configuration 8007h à 800Ah, et masques des bits implémentés */');
  const adrs = Object.keys(COMPOSANT.config).map(Number).sort((a, b) => a - b);
  o.push('static const uint16_t pic_fw_config[4] = { ' + adrs.map(a => '0x' + hex(res.config[a], 4)).join(', ') + ' };');
  o.push('static const uint16_t pic_fw_config_masque[4] = { ' + adrs.map(a => '0x' + hex(COMPOSANT.config[a], 4)).join(', ') + ' };');
  o.push('');
  return o.join('\n');
}

// ══════════════════════════════════════════════════════════════
//  SIMULATEUR
// ══════════════════════════════════════════════════════════════

class Simulateur {
  constructor(image, eeprom) {
    this.flash = new Array(COMPOSANT.flash).fill(0x3FFF);
    image.forEach((v, a) => { this.flash[a] = v; });
    this.ee = new Array(256).fill(0xFF);
    eeprom.forEach((v, a) => { this.ee[a] = v & 0xFF; });
    this.ram = new Uint8Array(32 * 128);
    this.core = { status: 0x18, fsr0l: 0, fsr0h: 0, fsr1l: 0, fsr1h: 0, bsr: 0, w: 0, pclath: 0, intcon: 0 };
    this.pc = 0;
    this.pile = [];
    this.cycles = 0;
    this.ld = 0;
    // valeurs au reset (DS40001799)
    this.sfr = { 0x08C: 0x3F, 0x08E: 0x3F, 0x10C: 0x00, 0x10E: 0x00, 0x18C: 0x37, 0x18E: 0x3F };
    this.broches = this.etat_broches();
    this.registre_spi = 0;
    this.nb_bits = 0;
    this.mots = [];       // { valeur, bits, cycle }
    this.fronts_clk = 0;
    this.trace_pdbrf = [];
  }
  // adresse de registre complète pour l'opérande f
  adresse(f) {
    return (this.core.bsr << 7) | f;
  }
  lire(adr) {
    const off = adr & 0x7F;
    if (off < 0x0C) return this.lire_core(off);
    if (off >= 0x70) return this.ram[0x70 + (off - 0x70)];
    switch (adr) {
      case 0x00C: { // PORTA
        let v = 0;
        const tris = this.sfr[0x08C], ansel = this.sfr[0x18C], lat = this.sfr[0x10C];
        for (let b = 0; b < 6; b++) {
          let niveau;
          if (b === 3 || (tris >> b) & 1) niveau = (b === 2) ? this.ld : 0;
          else niveau = (lat >> b) & 1;
          if (b !== 3 && (ansel >> b) & 1) niveau = 0; // broche analogique : lue à 0
          v |= niveau << b;
        }
        return v;
      }
      case 0x08C: case 0x08E: case 0x10C: case 0x10E: case 0x18C: case 0x18E:
        return this.sfr[adr];
      default:
        if (off >= 0x20 && off < 0x70) return this.ram[adr];
        throw new Error('lecture d\'un registre non simulé ' + hex(adr, 3) + 'h à PC=' + hex(this.pc, 4));
    }
  }
  ecrire(adr, v) {
    v &= 0xFF;
    const off = adr & 0x7F;
    if (off < 0x0C) { this.ecrire_core(off, v); return; }
    if (off >= 0x70) { this.ram[0x70 + (off - 0x70)] = v; return; }
    switch (adr) {
      case 0x08C: this.sfr[adr] = (v & 0x37) | 0x08; break;   // RA3 toujours en entrée
      case 0x08E: this.sfr[adr] = v & 0x3F; break;
      case 0x10C: this.sfr[adr] = v & 0x37; break;
      case 0x10E: this.sfr[adr] = v & 0x3F; break;
      case 0x18C: this.sfr[adr] = v & 0x37; break;
      case 0x18E: this.sfr[adr] = v & 0x3F; break;
      default:
        if (off >= 0x20 && off < 0x70) { this.ram[adr] = v; return; }
        throw new Error('écriture d\'un registre non simulé ' + hex(adr, 3) + 'h à PC=' + hex(this.pc, 4));
    }
    this.maj_broches();
  }
  lire_core(off) {
    const c = this.core;
    switch (off) {
      case 0x00: return this.lire_fsr((c.fsr0h << 8) | c.fsr0l);
      case 0x02: return this.pc & 0xFF;
      case 0x03: return c.status;
      case 0x04: return c.fsr0l;
      case 0x05: return c.fsr0h;
      case 0x08: return c.bsr;
      case 0x09: return c.w;
      case 0x0A: return c.pclath;
      case 0x0B: return c.intcon;
      default: throw new Error('registre cœur non simulé ' + off);
    }
  }
  ecrire_core(off, v) {
    const c = this.core;
    switch (off) {
      case 0x03: c.status = (c.status & 0x18) | (v & 0x07); break;
      case 0x04: c.fsr0l = v; break;
      case 0x05: c.fsr0h = v; break;
      case 0x08: c.bsr = v & 0x1F; break;
      case 0x09: c.w = v; break;
      case 0x0A: c.pclath = v & 0x7F; break;
      case 0x0B: c.intcon = v; break;
      default: throw new Error('écriture cœur non simulée ' + off);
    }
  }
  lire_fsr(a) {
    if (a >= 0x7000 && a <= 0x70FF) return this.ee[a - 0x7000];   // EEPROM (lecture seule)
    if (a < 0x1000) return this.lire(a);
    throw new Error('accès FSR non simulé ' + hex(a, 4) + 'h');
  }
  etat_broches() {
    const tris = this.sfr[0x08E], lat = this.sfr[0x10E];
    const b = {};
    for (let i = 0; i < 6; i++) b[i] = ((tris >> i) & 1) ? null : (lat >> i) & 1; // null = haute impédance
    return b;
  }
  maj_broches() {
    const av = this.broches, ap = this.etat_broches();
    const front = (n) => av[n] === 0 && ap[n] === 1;
    if (front(0)) {             // CLK : la donnée est lue au front montant
      if (ap[1] === null) throw new Error('front CLK avec DATA en haute impédance');
      this.registre_spi = ((this.registre_spi << 1) | ap[1]) >>> 0;
      this.nb_bits++;
      this.fronts_clk++;
    }
    if (front(2)) {             // LE : chargement du mot
      this.mots.push({ valeur: this.registre_spi >>> 0, bits: this.nb_bits, cycle: this.cycles });
      this.registre_spi = 0;
      this.nb_bits = 0;
    }
    const pd = ap[3] === null ? 0 : ap[3];   // R46 tire PDBRF à 0
    const pdav = av[3] === null ? 0 : av[3];
    if (pd !== pdav) this.trace_pdbrf.push({ cycle: this.cycles, v: pd });
    this.broches = ap;
  }
  pdbrf() {
    return this.broches[3] === null ? 0 : this.broches[3];
  }
  z(v) {
    if ((v & 0xFF) === 0) this.core.status |= 0x04; else this.core.status &= ~0x04;
  }
  pas() {
    const op = this.flash[this.pc];
    const f = op & 0x7F, d = (op >> 7) & 1, b = (op >> 7) & 7;
    let suivant = this.pc + 1, cyc = 1;
    const dst = (v) => { if (d) this.ecrire(this.adresse(f), v); else this.core.w = v & 0xFF; };
    if ((op & 0x3F00) === 0x0700) {          // ADDWF
      const a = this.lire(this.adresse(f)), r = a + this.core.w;
      this.core.status = (this.core.status & ~0x03) | (r > 0xFF ? 1 : 0) | (((a & 0xF) + (this.core.w & 0xF)) > 0xF ? 2 : 0);
      this.z(r); dst(r & 0xFF);
    } else if ((op & 0x3F80) === 0x0180) {   // CLRF
      this.ecrire(this.adresse(f), 0); this.z(0);
    } else if ((op & 0x3F00) === 0x0B00) {   // DECFSZ
      const r = (this.lire(this.adresse(f)) - 1) & 0xFF; dst(r);
      if (r === 0) { suivant++; cyc = 2; }
    } else if ((op & 0x3F00) === 0x0800) {   // MOVF
      const r = this.lire(this.adresse(f)); this.z(r); dst(r);
    } else if ((op & 0x3F80) === 0x0080) {   // MOVWF
      this.ecrire(this.adresse(f), this.core.w);
    } else if ((op & 0x3F00) === 0x3500) {   // LSLF
      const a = this.lire(this.adresse(f)), r = (a << 1) & 0xFF;
      this.core.status = (this.core.status & ~0x01) | ((a >> 7) & 1);
      this.z(r); dst(r);
    } else if ((op & 0x3C00) === 0x1000) {   // BCF
      this.ecrire(this.adresse(f), this.lire(this.adresse(f)) & ~(1 << b));
    } else if ((op & 0x3C00) === 0x1400) {   // BSF
      this.ecrire(this.adresse(f), this.lire(this.adresse(f)) | (1 << b));
    } else if ((op & 0x3C00) === 0x1800) {   // BTFSC
      if (((this.lire(this.adresse(f)) >> b) & 1) === 0) { suivant++; cyc = 2; }
    } else if ((op & 0x3C00) === 0x1C00) {   // BTFSS
      if (((this.lire(this.adresse(f)) >> b) & 1) === 1) { suivant++; cyc = 2; }
    } else if ((op & 0x3F00) === 0x3000) {   // MOVLW
      this.core.w = op & 0xFF;
    } else if ((op & 0x3F00) === 0x3A00) {   // XORLW
      this.core.w = (this.core.w ^ op) & 0xFF; this.z(this.core.w);
    } else if ((op & 0x3800) === 0x2800) {   // GOTO
      suivant = ((this.core.pclath & 0x78) << 8) | (op & 0x7FF); cyc = 2;
    } else if ((op & 0x3800) === 0x2000) {   // CALL
      if (this.pile.length >= 16) throw new Error('débordement de pile');
      this.pile.push(this.pc + 1);
      suivant = ((this.core.pclath & 0x78) << 8) | (op & 0x7FF); cyc = 2;
    } else if ((op & 0x3FE0) === 0x0020) {   // MOVLB
      this.core.bsr = op & 0x1F;
    } else if (op === 0x0008) {              // RETURN
      if (!this.pile.length) throw new Error('pile vide sur RETURN');
      suivant = this.pile.pop(); cyc = 2;
    } else if ((op & 0x3FF8) === 0x0010) {   // MOVIW
      const n = (op >> 2) & 1, mode = op & 3;
      if (n !== 0) throw new Error('MOVIW FSR1 non simulé');
      let a = (this.core.fsr0h << 8) | this.core.fsr0l;
      if (mode === 0) a = (a + 1) & 0xFFFF;
      if (mode === 1) a = (a - 1) & 0xFFFF;
      const v = this.lire_fsr(a);
      this.core.w = v; this.z(v);
      if (mode === 2) a = (a + 1) & 0xFFFF;
      if (mode === 3) a = (a - 1) & 0xFFFF;
      this.core.fsr0h = a >> 8; this.core.fsr0l = a & 0xFF;
    } else if (op === 0x0000) {              // NOP
    } else {
      throw new Error('instruction non simulée ' + hex(op, 4) + 'h à ' + hex(this.pc, 4) + 'h');
    }
    this.pc = suivant & 0x7FFF;
    if (this.pc >= COMPOSANT.flash) throw new Error('PC hors mémoire');
    this.cycles += cyc;
  }
  courir(cycles) {
    const fin = this.cycles + cycles;
    while (this.cycles < fin) this.pas();
  }
}

const TCY_US = 4; // HFINTOSC 1 MHz
const ms = (t) => Math.round(t * 1000 / TCY_US);

function analyser_image(txt) {
  const h = txt.replace(/[^0-9a-f]/gi, '');
  if (h.length !== 52) throw new Error('image EEPROM : 26 octets attendus (52 chiffres hexadécimaux)');
  const o = [];
  for (let i = 0; i < 26; i++) o.push(parseInt(h.substr(i * 2, 2), 16));
  return o;
}

function image_valide(o) {
  let s = 0;
  for (const v of o) s = (s + v) & 0xFF;
  return s === 0 && o[0x18] === 0x4A;
}

function tester_valide(image, ee) {
  const err = [];
  const sim = new Simulateur(image, ee);
  const attendus = [];
  for (let i = 0; i < 6; i++) attendus.push(((ee[i * 4] << 24) | (ee[i * 4 + 1] << 16) | (ee[i * 4 + 2] << 8) | ee[i * 4 + 3]) >>> 0);
  sim.ld = 0;
  sim.courir(ms(60));
  if (sim.mots.length !== 6) err.push(sim.mots.length + ' mots écrits au lieu de 6');
  sim.mots.forEach((m, i) => {
    if (m.bits !== 32) err.push('mot ' + i + ' : ' + m.bits + ' bits au lieu de 32');
    if (attendus[i] !== undefined && m.valeur !== attendus[i]) err.push('mot ' + i + ' (R' + (5 - i) + ') : ' + hex(m.valeur, 8) + ' au lieu de ' + hex(attendus[i], 8));
  });
  if (sim.mots.length && sim.mots[0].cycle * TCY_US < 20000) err.push('premier mot écrit avant 20 ms');
  if (sim.pdbrf() !== 0) err.push('PDBRF à 1 alors que LD = 0');
  sim.ld = 1; sim.courir(ms(3));
  if (sim.pdbrf() !== 1) err.push('PDBRF ne suit pas LD = 1');
  sim.ld = 0; sim.courir(ms(3));
  if (sim.pdbrf() !== 0) err.push('PDBRF ne suit pas LD = 0');
  // période de recopie ~1 ms
  sim.ld = 1;
  const c0 = sim.cycles;
  while (sim.pdbrf() === 0 && sim.cycles - c0 < ms(5)) sim.pas();
  const retard = (sim.cycles - c0) * TCY_US;
  if (retard > 1300) err.push('recopie LD → PDBRF trop lente (' + retard + ' µs)');
  const avant = sim.mots.length;
  sim.courir(ms(20));
  if (sim.mots.length !== avant) err.push('écriture SPI après la séquence de démarrage');
  return { err, sim, retard };
}

function tester_invalide(image, ee, nom) {
  const err = [];
  const sim = new Simulateur(image, ee);
  sim.ld = 1;
  sim.courir(ms(100));
  if (sim.mots.length || sim.fronts_clk) err.push(nom + ' : SPI actif (' + sim.mots.length + ' mots, ' + sim.fronts_clk + ' fronts CLK)');
  if (sim.pdbrf() !== 0 || sim.trace_pdbrf.length) err.push(nom + ' : PDBRF passé à 1');
  return err;
}

function principal() {
  const [cmd, src, ...reste] = process.argv.slice(2);
  if (!cmd || !src || (cmd !== 'asm' && cmd !== 'sim')) {
    console.error('Usage : node pic14.js asm <source.asm> <pic_fw.h>');
    console.error('        node pic14.js sim <source.asm> <image_hex_26_octets> [...]');
    process.exit(2);
  }
  const res = assembler(fs.readFileSync(src, 'utf8'));
  if (cmd === 'asm') {
    if (!reste[0]) { console.error('fichier de sortie attendu'); process.exit(2); }
    fs.writeFileSync(reste[0], generer_h(res, 'pic/' + path.basename(src)));
    console.log('pic14 : ' + res.image.length + ' mots, configuration ' +
      Object.keys(res.config).map(a => hex(Number(a), 4) + 'h=' + hex(res.config[a], 4) + 'h').join(' ') +
      ' → ' + reste[0]);
    return;
  }
  // sim
  if (!reste.length) { console.error('au moins une image EEPROM attendue'); process.exit(2); }
  let echecs = 0;
  for (const txt of reste) {
    const ee = analyser_image(txt);
    if (!image_valide(ee)) { console.log('ÉCHEC image fournie invalide (signature ou somme) : ' + txt); echecs++; continue; }
    const r = tester_valide(res.image, ee);
    if (r.err.length) { echecs++; console.log('ÉCHEC ' + txt + '\n  - ' + r.err.join('\n  - ')); }
    else console.log('OK   ' + txt + '  (6 mots R5→R0 conformes, 1er mot à ' +
      (r.sim.mots[0].cycle * TCY_US / 1000).toFixed(1) + ' ms, recopie LD→PDBRF ' + r.retard + ' µs)');
  }
  // images invalides dérivées de la première image
  const base = analyser_image(reste[0]);
  const sig = base.slice(); sig[0x18] = 0x4B; sig[0x19] = (sig[0x19] - 1) & 0xFF;      // somme juste, signature fausse
  const som = base.slice(); som[0x19] = (som[0x19] + 1) & 0xFF;                        // signature juste, somme fausse
  const vierge = new Array(26).fill(0xFF);
  const zero = new Array(26).fill(0x00);
  const inv = [['signature fausse', sig], ['somme fausse', som], ['EEPROM vierge (FFh)', vierge], ['EEPROM à 00h', zero]];
  for (const [nom, ee] of inv) {
    const e = tester_invalide(res.image, ee, nom);
    if (e.length) { echecs++; console.log('ÉCHEC ' + e.join('\n  - ')); }
    else console.log('OK   ' + nom + ' : aucune écriture SPI, PDBRF reste à 0');
  }
  if (echecs) { console.log('pic14 : ' + echecs + ' échec(s)'); process.exit(1); }
  console.log('pic14 : simulation conforme');
}

try {
  principal();
} catch (e) {
  console.error('pic14 : ' + e.message);
  process.exit(1);
}
