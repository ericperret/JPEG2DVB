<!--
  Nom      : LISEZMOI.md
  Objet    : portage FPGA de JPEG2DVB (émetteur DVB-S 23 cm), VHDL-2008
  Auteur   : Eric PERRET
  Date     : 2026-11-10
  Licence  : CC BY-NC 4.0
-->

# JPEG2DVB — portage FPGA en VHDL-2008

🇬🇧 [English version: README.md](README.md)

Modules VHDL de l'émetteur DVB-S 23 cm (FPGA Microchip PolarFire MPF100TC, cahier des charges v0.4). Tous les modules sont dans un seul fichier, `jpeg2dvb_fpga.vhd` (synthèse), et tous les bancs dans `jpeg2dvb_fpga_tb.vhd` (simulation). Chaque module reproduit **au bit près** une étape de JPEG2DVB 2.x ; chaque banc de test GHDL lit les fichiers produits par JPEG2DVB (dossier [`fpga_test/`](../fpga_test/)) et compare la sortie du module octet par octet, ou échantillon par échantillon.

VHDL-2008 synthétisable, bibliothèque `ieee` seule, interfaces en flux `valid` / `ready` (contrôle de flux éprouvé par des trous aléatoires dans tous les bancs).

## Modules

| Module | Fonction | Étape JPEG2DVB | Banc | État |
|---|---|---|---|---|
| `dct8x8_int` | DCT 8 × 8 entière (2 passes, 8 multiplieurs par passe) | 02 (DCT entière) | `tb_bloc` | ✔ identique |
| `quant_intra` | Quantification intra, matrice par défaut, division exacte par table d'inverses ; code d'échelle lu avec chaque coefficient (un code par rangée) | 03 | `tb_bloc` | ✔ codes par rangée, codes 1 et 31 |
| `rate_ctrl` | Régulation de débit TM5 en entiers : un quantiser_scale_code par rangée de macroblocs, vanne de rangée entre la DCT et la quantification, comptage exact des bits VLC, division en 5 pas | 03 (TM5) | `tb_rc` | ✔ 54 codes, vanne contrôlée |
| `zigzag` | Balayage zigzag, deux bancs en alternance | 04 | `tb_bloc` | ✔ identique |
| `vlc_enc` + `vlc_tab_pkg` | VLC MPEG-2 : DC différentiel, B.14, échappement, fin de bloc | 05 | `tb_vlc` | ✔ bits et longueurs |
| `es_mux` + `bit_packer` | Flux élémentaire : en-têtes, GOP de 12, slices avec leur code d'échelle, fin de séquence | 06 | `tb_es` | ✔ 3 images |
| `ts_mux` | PES (PTS) et Transport Stream à débit constant : PAT/PMT 80 ms, PCR 30 ms, paquets nuls | 07, 08 | `tb_octets` | ✔ 976 paquets |
| `prbs_disp` | Dispersion d'énergie | 09 | `tb_octets` | ✔ identique |
| `rs_enc` | RS(204,188) | 10 | `tb_octets` | ✔ identique |
| `interleaver` | Entrelaceur de Forney I = 12, M = 17 | 11 | `tb_octets` | ✔ identique |
| `conv_enc` | Codeur convolutif K = 7, 171/133, poinçonnage 1/2 à 7/8 | 12 | `tb_conv` | ✔ les 5 taux |
| `qpsk_map` | QPSK, bit 0 → +1 | 13 | `tb_qpsk` | ✔ identique |
| `srrc_poly` + `srrc_coef_pkg` | SRRC α = 0,35, 8 phases × 13 coefficients 16 bits, sans multiplieur | 14 (`.cs16`) | `tb_srrc` | ✔ 160 000 échantillons |
| `tx_backend` | Chaîne arrière : TS → I/Q (09 à 14 assemblées) | 08 → 14 | `tb_backend` | ✔ 160 000 échantillons, un par cycle |
| `mire_gen` + `mire_pkg` | Mire animée 16 couleurs, carré mobile et compteur, macroblocs 4:2:0 | 01 (`fpga_test/mire.png`, option mobile) | `tb_mire` | ✔ 2 images |
| `video_enc` | Tête de chaîne : mire → DCT → régulation TM5 → quantification → zigzag → VLC → ES → TS | 01 → 08 | `tb_dvbs` | ✔ 791 paquets TS |
| `dvbs_tx` | Émetteur complet : mire → I/Q (`video_enc` + `tx_backend`) | 01 → 14 | `tb_dvbs` | ✔ 160 000 échantillons |
| `bt656_rx` | Récepteur BT.656 du décodeur TVP5150AM1 : codes SAV / EAV, trame, ligne, couples Cb Y Cr Y, horloge SCLK 27 MHz | entrée PAL | `tb_bt656` | ✔ 414 720 couples (4 trames, couleur et noir et blanc) |
| `i2c_maitre` + `tvp_ctrl` | Pilotage du TVP5150AM1 : démarrage, identification, PAL forcé, VBI coupé, choix automatique ou imposé AIP1A / AIP1B, garde et libération du bus I²C | entrée PAL | `tb_tvp` (modèle `tb_tvp5150`) | ✔ 4 scénarios |
| `dvbs_sd` | Émetteur de la mire aux bits sigma-delta (`video_enc` → canal → `sigma_delta`) | 01 → 14 | blocs vérifiés par `video`, `chaine`, `sdm` | ✔ composé |
| `regs_i2c` + `jpeg2dvb_top` | Entité de tête : PLL, remise à zéro, LVDS, décodeur, registres du microcontrôleur, LED | carte | `tb_top` (modèles `jpeg2dvb_ip_sim.vhd`) | ✔ registres, LED, 45 262 groupes LVDS |

Tous les modules passent `ghdl --synth` sans verrou (contrôle de synthétisabilité ; la synthèse réelle se fait dans Libero SoC).

## Entrée vidéo PAL (TVP5150AM1)

Câblage imposé par `tvp_ctrl` :

- RESETB et PDN pilotées par le FPGA (`tvp_resetb`, `tvp_pdn`), pas de réseau RC : le reset doit suivre l'horloge XTAL1, produite par la PLL du FPGA (14,31818 MHz) ;
- SCL et SDA vers deux broches du FPGA (drain ouvert : `scl_oe`, `sda_oe`), rappels de 4,7 kΩ au 3,3 V ;
- YOUT7/I2CSEL : rappel de 10 kΩ à la masse (adresse B8h) ; INTREQ/GPCL/VBLK : 10 kΩ à la masse ;
- SCLK (27 MHz) : horloge de `bt656_rx` ; YOUT[7:0] : son entrée `d` ;
- AIP1A et AIP1B : deux entrées composites PAL (couleur ou noir et blanc), la première verrouillée est retenue.

`video_ok` signale un décodeur verrouillé en lignes et en trames ; sinon la mire est émise.

## Entité de tête de la carte (`jpeg2dvb_top`)

Horloges : oscillateur MEMS 50 MHz (DSC1001) → PLL `PF_CCC_SYS` (80 MHz, 320 MHz des sérialiseurs) et PLL `PF_CCC_TVP` (14,318182 MHz exacts : VCO 1 575 MHz / 110) vers XTAL1 du décodeur. Remise à zéro tenue tant que les deux PLL ne sont pas verrouillés. Sorties LVDS I et Q à 640 Mbit/s (sérialiseurs 8:1). LED actives à 1 : PLL verrouillés, décodeur présent, vidéo verrouillée.

Registres du microcontrôleur (bus I²C séparé, FPGA esclave à l'adresse 2Ah, `regs_i2c`) :

| Adresse | Nom | Accès | Défaut | Rôle |
|---|---|---|---|---|
| 00h | ID | lecture | 4Ah | identifiant du FPGA |
| 01h | VERSION | lecture | 01h | version des registres |
| 02h | MODE | lecture / écriture | 00h | norme, FEC, débit symbole |
| 03h | ENTREE | lecture / écriture | 00h | source vidéo |
| 04h | ETAT | lecture | — | état de la carte |
| 05h à FFh | — | — | 00h | lus 00h, écritures ignorées |

MODE (02h) :

| Bits | Champ | Valeurs |
|---|---|---|
| 7..5 | — | ignorés à l'écriture, lus 0 |
| 4 | DEBIT | 0 : 10 MS/s ; 1 : 2,5 MS/s |
| 3..1 | FEC | DVB-S : 000 = 1/2, 001 = 2/3, 010 = 3/4, 011 = 5/6, 100 = 7/8, 101 à 111 réservés ; DVB-S2 : ignorés (QPSK 1/4) |
| 0 | NORME | 0 : DVB-S ; 1 : DVB-S2 (QPSK 1/4, trames longues, pilotes, CCM) |

| MODE | Norme | FEC | Débit symbole |
|---|---|---|---|
| 00h | DVB-S | 1/2 | 10 MS/s |
| 02h | DVB-S | 2/3 | 10 MS/s |
| 04h | DVB-S | 3/4 | 10 MS/s |
| 06h | DVB-S | 5/6 | 10 MS/s |
| 08h | DVB-S | 7/8 | 10 MS/s |
| 10h | DVB-S | 1/2 | 2,5 MS/s |
| 12h | DVB-S | 2/3 | 2,5 MS/s |
| 14h | DVB-S | 3/4 | 2,5 MS/s |
| 16h | DVB-S | 5/6 | 2,5 MS/s |
| 18h | DVB-S | 7/8 | 2,5 MS/s |
| 01h | DVB-S2 | 1/4 | 10 MS/s |
| 11h | DVB-S2 | 1/4 | 2,5 MS/s |

ENTREE (03h) :

| Bits | Champ | Valeurs |
|---|---|---|
| 7..2 | — | ignorés à l'écriture, lus 0 |
| 1..0 | SOURCE | 00 : automatique (AIP1A, puis AIP1B si A n'est pas verrouillée) ; 01 : AIP1A imposée ; 10 : AIP1B imposée ; 11 : mire |

ETAT (04h, lecture seule) :

| Bit | Champ | Valeurs |
|---|---|---|
| 7..4 | — | 0 |
| 3 | ENTREE | entrée du décodeur en cours : 0 = AIP1A, 1 = AIP1B |
| 2 | VIDEO | 1 : décodeur verrouillé en lignes et en trames |
| 1 | DECODEUR | 1 : TVP5150AM1 identifié |
| 0 | PLL | 1 : les deux PLL verrouillés |

Écriture : début, 54h, registre, données…, fin. Lecture : début, 54h, registre, début répété, 55h, données… (NACK sur la dernière), fin. Le pointeur avance après chaque octet. Sans microcontrôleur, les valeurs par défaut s'appliquent. MODE est rangé ; il sera branché à la chaîne par les chantiers FEC, débit et DVB-S2. ENTREE 3 (mire) servira au chantier 3b ; la source est aujourd'hui la mire.

Fichiers : `jpeg2dvb_ip_libero.vhd` (blocs Libero, synthèse) et `jpeg2dvb_ip_sim.vhd` (modèles, GHDL) déclarent les mêmes entités `horloges` et `sortie_lvds` ; `jpeg2dvb_top.sdc` (contraintes).

### Dans Libero

1. Importer comme sources HDL `jpeg2dvb_fpga.vhd` et `jpeg2dvb_ip_libero.vhd` (pas `jpeg2dvb_ip_sim.vhd` ni `jpeg2dvb_fpga_tb.vhd`).
2. Catalogue ▸ Clock & Management ▸ PF_CCC, nom `PF_CCC_SYS` : un PLL, référence 50 MHz ; sortie 0 : 80 MHz vers le réseau global ; sortie 1 : 320 MHz en HS_IO_CLK.
3. PF_CCC, nom `PF_CCC_TVP` : un PLL, référence 50 MHz ; sortie 0 : 14,318182 MHz.
4. Catalogue ▸ I/O ▸ PF_IOD_GENERIC_TX, nom `PF_IOD_TX_SD` : interface TX_DDRX_B_G_FA (8 bits par cycle), 2 voies de données, sans horloge transmise, norme LVDS.
5. Comparer les ports des composants générés (`component/work/<nom>/<nom>.vhd`) à ceux de `jpeg2dvb_ip_libero.vhd` ; vérifier dans le guide PF_IOD l'ordre d'émission des bits de TX_DATA (le fichier suppose TX_DATA(0) en premier).
6. Design Hierarchy ▸ `jpeg2dvb_top` ▸ Set As Root.
7. Constraint Manager ▸ Timing : importer `jpeg2dvb_top.sdc`, puis Derive Constraints (horloges des PLL).
8. Brochage (I/O Editor) avec le PCB : sorties LVDS en banque GPIO (les banques HSIO ne font pas d'émission LVDS) ; `osc_50` et `tvp_sclk` sur des entrées d'horloge.

## Lancer les tests

```
sudo apt-get install ghdl        # GHDL 4.x
cd fpga_test
./run_tests.sh                   # tous les bancs + contrôle de synthèse
./run_tests.sh conv              # les bancs dont le nom contient « conv »
```

Chaque ligne affiche `OK …` (sortie identique à JPEG2DVB) ou `ECHEC …` (premiers écarts signalés).

## Références

Le dossier `fpga_test/` contient les outils de test (`run_tests.sh`, scripts Node) et des extraits des sorties de JPEG2DVB 2.x (1,3 Mo pour la vidéo, 1 Mo pour la chaîne arrière) :

- chaîne arrière : 64 paquets TS d'une seconde de flux (photo, 25 images, FEC 1/2, α = 0,35), et leurs sorties aux étapes 09 à 14 ; `node refs.js DOSSIER` les extrait et réécrit le paquetage `srrc_coef_pkg` de `jpeg2dvb_fpga.vhd` ; les références des taux 2/3 à 7/8 viennent de la page 12 réglée sur ces taux ;
- côté vidéo : 3 images de `dur.png`, DCT entière, régulation TM5 ; `node refs_video.js DOSSIER` ; les codes 1 et 31 viennent de la page 03 ;
- `node gen_vlc.js` régénère les tables VLC depuis la page 05.

## Débit

- Horloge : 80 MHz = 8 × débit symbole (10 MS/s). Un créneau TS de 1 504 bits dure exactement 13 056 cycles.
- Le filtre SRRC sort un échantillon par cycle ; la chaîne arrière suit sans trou une fois le flux établi (1 136 cycles d'amorçage, dont la mise à zéro de l'entrelaceur).
- DCT : 192 cycles par bloc (26,7 millions de coefficients par seconde à 80 MHz, pour 15,6 millions nécessaires en 720 × 576 à 25 images/s).

## Reste à faire

1. ✔ Fait (2026-10-19) : régulation de débit TM5 en arithmétique entière, dans la page 03 de JPEG2DVB (point P7 du cahier des charges), puis en VHDL (`rate_ctrl`), au bit près.
2. Sortie sigma-delta (point P3) : ✔ modulateur 1 bit d'ordre 3 et interpolation (`sd_entree`, `sdm3`, `sigma_delta`, banc `sdm`) ; ✔ sérialiseurs LVDS (PF_IOD, entité de tête), à valider dans Libero.
3. Mise en mémoire LSRAM : lecture synchrone de la mémoire de l'entrelaceur (1 122 octets) ; découpage en étages des chemins longs (quantification, VLC) après la première synthèse Libero.
4. Entrée vidéo PAL 720 × 576 : ✔ 3a, pilotage du TVP5150AM1 et réception BT.656 (2026-11-04) ; 3b, passage vers l'horloge 80 MHz, réunion des deux trames, mise en macroblocs 4:2:0 ; mode 720 × 576 de la chaîne (45 macroblocs par slice) à 10 MS/s.
5. DVB-S2 QPSK 1/4, trames longues, pilotes, CCM, à côté de DVB-S, choix par interrupteur DIP.
6. ✔ Entité de tête de la carte (2026-11-10) ; reste : brochage avec le PCB, branchement du registre MODE (FEC, débit, DVB-S2 en marche).

Remarque sur la mire : pour que la chrominance 4:2:0 du FPGA soit exacte, les frontières de couleur de la mire 16 couleurs doivent tomber sur des coordonnées paires ; la chrominance de chaque bloc 2 × 2 est alors celle de la palette. Le carré mobile et le compteur respectent déjà cette règle.

## Historique

| Date | Évolution |
|---|---|
| 2026-10-19 | Chaîne arrière (09 à 14) et côté vidéo (02 à 08) au bit près, 19 bancs de test ; page 08 de JPEG2DVB en 2.4 (instants du multiplexage en entiers exacts) |
| 2026-10-19 | Mire animée (`mire.js` : PNG pour la page 01 et paquetage `mire_pkg`), tête de chaîne `video_enc` et émetteur complet `dvbs_tx` : de la mire aux échantillons I/Q, identiques à JPEG2DVB ; 22 bancs de test |
| 2026-10-19 | Régulation TM5 (`rate_ctrl`, références régénérées ; bancs à adapter). Sources fusionnées en `jpeg2dvb_fpga.vhd` et `jpeg2dvb_fpga_tb.vhd` ; références, scripts et `run_tests.sh` déplacés dans `fpga_test/` |
| 2026-10-19 | Fusion propre (2.0) : un cartouche par fichier, context VHDL-2008 commun `jpeg2dvb_ctx`, chaque fonction et process commenté ; `fpga_test/README.md` donne le rôle de chaque fichier de test |
| 2026-10-19 | Régulation TM5 au bit près en VHDL : bancs adaptés (codes par rangée, codes par slice, `slice_ok`), nouveau banc `tb_rc`, `run_tests.sh` 1.2 ; 23 bancs OK, 11 modules synthétisables sans verrou |
| 2026-11-04 | Entrée vidéo PAL, chantier 3a : `bt656_rx`, `i2c_maitre`, `tvp_ctrl` (TVP5150AM1 sans microcontrôleur) ; `bt656.js`, bancs `tb_bt656` et `tb_tvp` (modèle I²C `tb_tvp5150`, chronologie du mode standard) ; `run_tests.sh` 1.5 ; 28 bancs OK, 16 modules synthétisables sans verrou |
| 2026-11-10 | Libero : clauses `library` / `use` à la place du `context` VHDL-2008, pointeurs de l'entrelaceur sans valeur initiale (Synplify MF682) ; première synthèse de `dvbs_tx` sans erreur. Entité de tête (chantier 6) : `jpeg2dvb_top`, `dvbs_sd`, `regs_i2c` (esclave I²C 2Ah), entrée imposée dans `tvp_ctrl`, `jpeg2dvb_ip_libero.vhd` / `jpeg2dvb_ip_sim.vhd`, `jpeg2dvb_top.sdc` ; bancs `tvp_force` et `top` ; `run_tests.sh` 1.6 |

## Licence

CC BY-NC 4.0 — **Eric PERRET**
