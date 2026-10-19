<!--
  Nom      : LISEZMOI.md
  Objet    : portage FPGA de JPEG2DVB (émetteur DVB-S 23 cm), VHDL-2008
  Auteur   : Eric PERRET
  Date     : 2026-10-19
  Licence  : CC BY-NC 4.0
-->

# JPEG2DVB — portage FPGA en VHDL-2008

🇬🇧 [English version: README.md](README.md)

Modules VHDL de l'émetteur DVB-S 23 cm (FPGA Microchip PolarFire MPF100TC, cahier des charges v0.4). Chaque module reproduit **au bit près** une étape de JPEG2DVB 2.x ; chaque banc de test GHDL lit les fichiers produits par JPEG2DVB (dossier `ref/`) et compare la sortie du module octet par octet, ou échantillon par échantillon.

VHDL-2008 synthétisable, bibliothèque `ieee` seule, interfaces en flux `valid` / `ready` (contrôle de flux éprouvé par des trous aléatoires dans tous les bancs).

## Modules

| Module | Fonction | Étape JPEG2DVB | Banc | État |
|---|---|---|---|---|
| `dct8x8_int` | DCT 8 × 8 entière (2 passes, 8 multiplieurs par passe) | 02, virgule fixe | `tb_bloc` | ✔ identique |
| `quant_intra` | Quantification intra, matrice par défaut, division exacte par table d'inverses | 03 (code fixe) | `tb_bloc` | ✔ codes 1, 8, 31 |
| `zigzag` | Balayage zigzag, deux bancs en alternance | 04 | `tb_bloc` | ✔ identique |
| `vlc_enc` + `vlc_tab_pkg` | VLC MPEG-2 : DC différentiel, B.14, échappement, fin de bloc | 05 | `tb_vlc` | ✔ bits et longueurs |
| `es_mux` + `bit_packer` | Flux élémentaire : en-têtes, GOP de 12, slices, fin de séquence | 06 | `tb_es` | ✔ 3 images |
| `ts_mux` | PES (PTS) et Transport Stream à débit constant : PAT/PMT 80 ms, PCR 30 ms, paquets nuls | 07, 08 | `tb_octets` | ✔ 881 paquets |
| `prbs_disp` | Dispersion d'énergie | 09 | `tb_octets` | ✔ identique |
| `rs_enc` | RS(204,188) | 10 | `tb_octets` | ✔ identique |
| `interleaver` | Entrelaceur de Forney I = 12, M = 17 | 11 | `tb_octets` | ✔ identique |
| `conv_enc` | Codeur convolutif K = 7, 171/133, poinçonnage 1/2 à 7/8 | 12 | `tb_conv` | ✔ les 5 taux |
| `qpsk_map` | QPSK, bit 0 → +1 | 13 | `tb_qpsk` | ✔ identique |
| `srrc_poly` + `srrc_coef_pkg` | SRRC α = 0,35, 8 phases × 13 coefficients 16 bits, sans multiplieur | 14 (`.cs16`) | `tb_srrc` | ✔ 160 000 échantillons |
| `tx_backend` | Chaîne arrière : TS → I/Q (09 à 14 assemblées) | 08 → 14 | `tb_backend` | ✔ 160 000 échantillons, un par cycle |
| `mire_gen` + `mire_pkg` | Mire animée 16 couleurs, carré mobile et compteur, macroblocs 4:2:0 | 01 (`ref/mire.png`, option mobile) | `tb_mire` | ✔ 2 images |
| `video_enc` | Tête de chaîne : mire → DCT → quantification → zigzag → VLC → ES → TS | 01 → 08 | `tb_dvbs` | ✔ 769 paquets TS |
| `dvbs_tx` | Émetteur complet : mire → I/Q (`video_enc` + `tx_backend`) | 01 → 14 | `tb_dvbs` | ✔ 160 000 échantillons |

Tous les modules passent `ghdl --synth` sans verrou (contrôle de synthétisabilité ; la synthèse réelle se fait dans Libero SoC).

## Lancer les tests

```
sudo apt-get install ghdl        # GHDL 4.x
cd vhdl
./run_tests.sh                   # tous les bancs + contrôle de synthèse
./run_tests.sh conv              # les bancs dont le nom contient « conv »
```

Chaque ligne affiche `OK …` (sortie identique à JPEG2DVB) ou `ECHEC …` (premiers écarts signalés).

## Références

Le dossier `ref/` contient des extraits des sorties de JPEG2DVB 2.x (1,3 Mo pour la vidéo, 1 Mo pour la chaîne arrière) :

- chaîne arrière : 64 paquets TS d'une seconde de flux (photo, 25 images, FEC 1/2, α = 0,35), et leurs sorties aux étapes 09 à 14 ; `node scripts/refs.js DOSSIER` les extrait et génère `rtl/srrc_coef_pkg.vhd` ; les références des taux 2/3 à 7/8 viennent de la page 12 réglée sur ces taux ;
- côté vidéo : 3 images, DCT en virgule fixe, quantification à code fixe ; `node scripts/refs_video.js DOSSIER` ; les codes 1 et 31 viennent de la page 03 ;
- `node scripts/gen_vlc.js` régénère les tables VLC depuis la page 05.

## Débit

- Horloge : 80 MHz = 8 × débit symbole (10 MS/s). Un créneau TS de 1 504 bits dure exactement 13 056 cycles.
- Le filtre SRRC sort un échantillon par cycle ; la chaîne arrière suit sans trou une fois le flux établi (1 136 cycles d'amorçage, dont la mise à zéro de l'entrelaceur).
- DCT : 192 cycles par bloc (26,7 millions de coefficients par seconde à 80 MHz, pour 15,6 millions nécessaires en 720 × 576 à 25 images/s).

## Reste à faire

1. Régulation de débit TM5 en arithmétique entière, d'abord dans la page 03 de JPEG2DVB (point P7 du cahier des charges), puis en VHDL.
2. Modulateur sigma-delta 1 bit d'ordre 3, interpolation × 8, sérialiseurs LVDS (point P3).
3. Mise en mémoire LSRAM : lecture synchrone de la mémoire de l'entrelaceur (1 122 octets) ; découpage en étages des chemins longs (quantification, VLC) après la première synthèse Libero.
4. Mode 720 × 576 (doublement de la mire, 45 macroblocs par slice).

Remarque sur la mire : pour que la chrominance 4:2:0 du FPGA soit exacte, les frontières de couleur de la mire 16 couleurs doivent tomber sur des coordonnées paires ; la chrominance de chaque bloc 2 × 2 est alors celle de la palette. Le carré mobile et le compteur respectent déjà cette règle.

## Historique

| Date | Évolution |
|---|---|
| 2026-10-19 | Chaîne arrière (09 à 14) et côté vidéo (02 à 08) au bit près, 19 bancs de test ; page 08 de JPEG2DVB en 2.4 (instants du multiplexage en entiers exacts) |
| 2026-10-19 | Mire animée (`scripts/mire.js` : PNG pour la page 01 et `rtl/mire_pkg.vhd`), tête de chaîne `video_enc` et émetteur complet `dvbs_tx` : de la mire aux échantillons I/Q, identiques à JPEG2DVB ; 22 bancs de test |

## Licence

CC BY-NC 4.0 — **Eric PERRET**
