<!--
  Nom      : LISEZMOI.md
  Objet    : portage FPGA de JPEG2DVB (émetteur DVB-S 23 cm), VHDL-2008
  Auteur   : Eric PERRET
  Date     : 2026-11-12
  Licence  : CC BY-NC 4.0
-->

# JPEG2DVB — portage FPGA en VHDL-2008

🇬🇧 [English version: README.md](README.md)

Modules VHDL de l'émetteur DVB-S 23 cm (FPGA Microchip PolarFire MPF100T, cahier des charges v0.4). Tous les modules sont dans un seul fichier, `jpeg2dvb_fpga.vhd` (synthèse), et tous les bancs dans `jpeg2dvb_fpga_tb.vhd` (simulation). Chaque module reproduit **au bit près** une étape de JPEG2DVB 2.x ; chaque banc de test GHDL lit les fichiers produits par JPEG2DVB (dossier [`fpga_test/`](../fpga_test/)) et compare la sortie du module octet par octet, ou échantillon par échantillon.

VHDL-2008 synthétisable, bibliothèque `ieee` seule, interfaces en flux `valid` / `ready` (contrôle de flux éprouvé par des trous aléatoires dans tous les bancs).

## Modules

| Module | Fonction | Étape JPEG2DVB | Banc | État |
|---|---|---|---|---|
| `dct8x8_int` | DCT 8 × 8 entière : 2 passes, 4 multiplieurs par passe (symétrie des coefficients), passe lignes pendant le chargement, résultats intermédiaires et sortie en mémoire | 02 (DCT entière) | `tb_bloc` | ✔ identique |
| `quant_intra` | Quantification intra, matrice par défaut, division exacte par inverses lus dans une mémoire morte synchrone (2 048 × 26 bits), trois étages ; code d'échelle lu avec chaque coefficient (un code par rangée) | 03 | `tb_bloc` | ✔ codes par rangée, codes 1 et 31 |
| `rate_ctrl` | Régulation de débit TM5 en entiers : un quantiser_scale_code par rangée de macroblocs, vanne de rangée entre la DCT et la quantification, comptage exact des bits VLC, division en 5 pas | 03 (TM5) | `tb_rc` | ✔ 54 codes, vanne contrôlée |
| `zigzag` | Balayage zigzag, deux bancs en alternance | 04 | `tb_bloc` | ✔ identique |
| `vlc_enc` + `vlc_tab_pkg` | VLC MPEG-2 : DC différentiel, B.14, échappement, fin de bloc | 05 | `tb_vlc` | ✔ bits et longueurs |
| `es_mux` + `bit_packer` | Flux élémentaire : en-têtes, GOP de 12, slices avec leur code d'échelle, fin de séquence | 06 | `tb_es` | ✔ 3 images |
| `ts_mux` | PES (PTS) et Transport Stream à débit constant : PAT/PMT 80 ms, PCR 30 ms, paquets nuls ; ordonnancement et PTS en cumul, sans multiplieur ; mode `G_MCPC` : deux programmes (PMT 0x0100 / 0x0200), `G_TRAMES1` : canal 1 en images de demi-trame | 07, 08 | `tb_octets` (`G_DUT` 6 = MCPC) | ✔ 976 paquets, MCPC 357 200 octets |
| `csa_enc` + `csa_tab_pkg` | Embrouillage DVB-CSA des paquets d'un PID, clé fixe (BISS-1) : chiffrement par blocs en chaîne depuis la fin du paquet, puis chiffrement de flux ; dans la chaîne de `dvbs_sd` entre `ts_mux` et la dispersion (PID 0x0101, actif quand `biss` = 1) | — (`fpga_test/csa.js`) | `tb_octets` (`csa`, `csa_biss`) | ✔ 177 paquets, cas limites, mot de contrôle du numéro 1234 |
| `prbs_disp` | Dispersion d'énergie | 09 | `tb_octets` | ✔ identique |
| `rs_enc` | RS(204,188) | 10 | `tb_octets` | ✔ identique |
| `interleaver` | Entrelaceur de Forney I = 12, M = 17, mémoire à lecture synchrone | 11 | `tb_octets` | ✔ identique |
| `conv_enc` | Codeur convolutif K = 7, 171/133, poinçonnage 1/2 à 7/8 | 12 | `tb_conv` | ✔ les 5 taux |
| `dvbs2_tx` + `dvbs2_pkg` + `mem_sdp` | DVB-S2 (EN 302 307-1) QPSK 1/4, trame normale de 16 200 bits, pilotes, CCM : en-tête de bande de base, BCH, LDPC (accumulation à lecture-écriture avec propagation), entrelacement, embrouillage de Gold, en-tête de trame physique | — (`fpga_test/dvbs2.js`, référence GNU Radio gr-dtv) | `tb_s2` | ✔ 3 trames, 99 846 symboles identiques |
| `choix_auto` + `tirage_biss` | Mode automatique d'après les entrées verrouillées, réévalué toutes les minutes ; numéro BISS de 4 chiffres tiré à la mise sous tension | carte | `tb_choix`, `tb_biss` | ✔ 4 scénarios et changement à la minute ; valeur, maintien, BCD |
| `qpsk_map` | QPSK, bit 0 → +1 | 13 | `tb_qpsk` | ✔ identique |
| `srrc_poly` + `srrc_coef_pkg` | SRRC α = 0,35, 8 phases × 13 coefficients 16 bits, sans multiplieur | 14 (`.cs16`) | `tb_srrc` | ✔ 160 000 échantillons |
| `tx_backend` | Chaîne arrière : TS → I/Q (09 à 14 assemblées) | 08 → 14 | `tb_backend` | ✔ 160 000 échantillons, un par cycle |
| `mire_gen` + `mire_pkg` | Mire animée 16 couleurs calculée depuis sa géométrie (sans mémoire d'image), carré mobile et compteur, macroblocs 4:2:0 | 01 (`fpga_test/mire.png`, option mobile) | `tb_mire` | ✔ 2 images |
| `video_enc` | Tête de chaîne : mire → DCT → régulation TM5 → quantification → zigzag → VLC → ES → TS | 01 → 08 | `tb_dvbs` | ✔ 791 paquets TS |
| `dvbs_tx` | Émetteur complet : mire → I/Q (`video_enc` + `tx_backend`) | 01 → 14 | `tb_dvbs` | ✔ 160 000 échantillons |
| `bt656_rx` | Récepteur BT.656 du décodeur TVP5150AM1 : codes SAV / EAV, trame, ligne, couples Cb Y Cr Y, horloge SCLK 27 MHz | entrée PAL | `tb_bt656` | ✔ 414 720 couples (4 trames, couleur et noir et blanc) |
| `i2c_maitre` + `tvp_ctrl` | Pilotage du TVP5150AM1 : démarrage, identification, PAL forcé, VBI coupé, choix automatique ou imposé AIP1A / AIP1B, garde et libération du bus I²C | entrée PAL | `tb_tvp` (modèle `tb_tvp5150`) | ✔ 4 scénarios |
| `dvbs_sd` | Émetteur jusqu'aux bits sigma-delta ; `G_MCPC` : programme 1 caméra (`cam_mb` → `codeur`, image noire sans caméra), programme 2 mire (numéro BISS affiché), `ts_mux` → `csa_enc` → DVB-S (`prbs_disp` … `conv_enc`) ou DVB-S2 (`dvbs2_tx`) selon `norme` → `sigma_delta` ; remise à zéro au changement de norme | 01 → 14 | blocs vérifiés par `video`, `mcpc`, `cam`, `csa`, `s2`, `chaine`, `sdm` | ✔ composé, blocs vérifiés ; chaîne complète trop lente en simulation |
| `codeur` | Codeur complet d'un programme : macroblocs de `mire_gen` ou `cam_mb` → DCT → régulation TM5 → quantification → zigzag → VLC → ES ; images 352 × 288 ou 720 × 576 en deux images de demi-trame (`G_TRAMES`) | 01 → 06 | `tb_codeur` | ✔ 720 × 576 : 4 demi-trames décodées par ffmpeg conformes à l'entrée |
| `cam_mb` | Voie caméra : paires BT.656 (27 MHz) → macroblocs 4:2:0 (80 MHz), moyenne arrondie des lignes de chrominance, passage entre horloges | entrée PAL | `tb_cam` | ✔ 1 244 160 octets (`cam_mb.bin`) |
| `horloges` + `sortie_lvds` | Enveloppes des cœurs Libero : PLL `PF_CCC_SYS` (80 / 320 MHz) et `PF_CCC_TVP` (14,318182 MHz), sérialiseur LVDS `PF_IOD_TX_SD` (2 voies, 640 Mbit/s) | carte | `tb_top` (modèles `jpeg2dvb_ip_sim.vhd`) | à valider dans Libero |
| `jpeg2dvb_top` | Entité de tête : PLL, remise à zéro, LVDS, décodeur, choix automatique, LED | carte | `tb_top` (modèles `jpeg2dvb_ip_sim.vhd`) | ✔ LED, décodeur absent, 45 247 groupes LVDS |

Tous les modules passent `ghdl --synth` sans verrou (contrôle de synthétisabilité ; la synthèse réelle se fait dans Libero SoC).

## Entrée vidéo PAL (TVP5150AM1)

Câblage imposé par `tvp_ctrl` :

- RESETB et PDN pilotées par le FPGA (`tvp_resetb`, `tvp_pdn`), pas de réseau RC : le reset doit suivre l'horloge XTAL1, produite par la PLL du FPGA (14,31818 MHz) ;
- SCL et SDA vers deux broches du FPGA (drain ouvert : `scl_oe`, `sda_oe`), rappels de 4,7 kΩ au 3,3 V ;
- YOUT7/I2CSEL : rappel de 10 kΩ à la masse (adresse B8h) ; INTREQ/GPCL/VBLK : 10 kΩ à la masse ;
- SCLK (27 MHz) : horloge de `bt656_rx` ; YOUT[7:0] : son entrée `d` ;
- AIP1A et AIP1B : deux entrées composites PAL (couleur ou noir et blanc), la première verrouillée est retenue.

`video_ok` signale un décodeur verrouillé en lignes et en trames ; sinon le programme 1 émet une image noire (voir la chaîne MCPC ci-dessous).

## Chaîne MCPC (`dvbs_sd`, `G_MCPC`)

Deux programmes dans un seul Transport Stream (DVB-S, FEC 1/2, 5 MS/s) :

| | Programme 1 | Programme 2 |
|---|---|---|
| Source | caméra (TVP5150AM1 → `bt656_rx` → `cam_mb`) ; image noire (Y 16, Cb = Cr = 128, 25 images par seconde) quand la caméra est absente, retour à la caméra sur un début d'image | mire animée (`mire_gen`), 352 × 288 |
| Codeur | `codeur` 720 × 576 : chaque trame (720 × 288, 45 × 18 macroblocs) codée en image MPEG-2 de demi-trame, haute puis basse (`G_TRAMES`) | `codeur` 352 × 288 |
| PMT / PID vidéo | 0x0100 / 0x0101 (porte aussi le PCR) | 0x0200 / 0x0201 |
| Part du débit | 47 % | 47 % |

La PAT liste les deux programmes. `ts_mux` (`G_MCPC`, `G_TRAMES1`) ordonnance les paquets par écarts tenus en cumul (PAT / PMT, PCR, canal 1, canal 2) ; une image du canal 1 est faite des deux demi-trames codées ; PTS = 3 600 · (n + 1) + 9 000 sur chaque canal. La chrominance des macroblocs de la caméra est la moyenne arrondie des deux lignes de chaque paire, (a + b + 1) >> 1. Le budget par image vient de `budget_image` avec 47 % du débit (50 demi-trames par seconde sur le canal 1, 25 images par seconde sur le canal 2).

Vérification : `ts_mux` en mode MCPC est identique au bit près à `mcpc.js` (banc `mcpc` ; `ffprobe` voit deux programmes, `ffmpeg` décode les deux) ; `cam_mb` est identique au bit près à `cam_mb.bin` (banc `cam`). `codeur` 720 × 576 en demi-trames : les 4 demi-trames de `cam_mb.bin` codées puis décodées par ffmpeg sont conformes à l’entrée. La chaîne complète est trop lente en simulation GHDL : elle se vérifie par blocs, puis sur carte.

## Entité de tête de la carte (`jpeg2dvb_top`)

Horloges : oscillateur MEMS 50 MHz (DSC1001) → PLL `PF_CCC_SYS` (80 MHz, 320 MHz des sérialiseurs) et PLL `PF_CCC_TVP` (14,318182 MHz exacts : VCO 1 575 MHz / 110) vers XTAL1 du décodeur. Remise à zéro tenue tant que les deux PLL ne sont pas verrouillés. Sorties LVDS I et Q à 640 Mbit/s (sérialiseurs 8:1). LED actives à 1 : PLL verrouillés, décodeur présent, vidéo verrouillée.

Aucun microcontrôleur ni registre : réglages fixes, 5 MS/s, FEC 1/2. `choix_auto` sonde les deux entrées vidéo (AIP1A puis AIP1B, 600 ms chacune) dès que le décodeur est identifié, puis toutes les minutes ; le mode précédent est tenu pendant le sondage :

| Entrées verrouillées | Mode | Programme 1 | Programme 2 |
|---|---|---|---|
| AIP1A seule | DVB-S | caméra A | mire |
| AIP1B seule | DVB-S2 QPSK 1/4 | caméra B | mire |
| A et B | DVB-S, BISS-1 | caméra A embrouillée | mire en clair, numéro affiché |
| aucune | DVB-S | image noire | mire |

BISS : le numéro de 4 chiffres (0000 à 9999) est tiré à la mise sous tension (`tirage_biss`, compteur figé à l'identification du décodeur) ; la clé de session est ce numéro répété trois fois, le mot de contrôle `S0 S1 S2 (S0+S1+S2) S3 S4 S5 (S3+S4+S5)`. Le numéro s'affiche sur la mire du programme 2 uniquement en mode BISS. LED actives à 1 : PLL verrouillés, décodeur présent, vidéo verrouillée.

Fichier source unique : `jpeg2dvb_fpga.vhd` contient toutes les unités, dont `horloges` et `sortie_lvds`. Seuls les trois cœurs du catalogue ci-dessous et les contraintes se créent à la main dans Libero. `jpeg2dvb_ip_sim.vhd` (modèles GHDL des trois cœurs) ne sert qu'en simulation ; `jpeg2dvb_top.sdc` contient les contraintes de l'étape 7.

### Dans Libero

1. Nouveau projet, composant MPF100T, boîtier FCG484 (même brochage que le MPF050T), VHDL-2008.
2. File ▸ Import ▸ HDL Source Files : `jpeg2dvb_fpga.vhd` seul.
3. Catalogue (View ▸ Windows ▸ Catalog) ▸ `PF_CCC`, nom `PF_CCC_SYS` : entrée 0 = 50 MHz ; rétroaction Post-VCO, bande passante High ; sortie 0 : activée, 80 MHz, Global Clock ; sortie 1 : activée, 320 MHz en HS_IO_CLK (option à vérifier dans le configurateur) ; verrouillage du PLL exposé. Ports : `REF_CLK_0`, `OUT0_FABCLK_0`, `OUT1_HS_IO_CLK_0`, `PLL_LOCK_0`.
4. `PF_CCC`, nom `PF_CCC_TVP` : entrée 0 = 50 MHz ; sortie 0 : activée, 14,318182 MHz (VCO 1 575 MHz / 110), Global Clock ; pas d'autre sortie. Ports : `REF_CLK_0`, `OUT0_FABCLK_0`, `PLL_LOCK_0`.
5. `PF_IOD_GENERIC_TX`, nom `PF_IOD_TX_SD` : interface TX_DDRX_B_G (le fichier suppose TX_DDRX_B_G_FA), 8 bits par cycle, 640 Mbps par voie, 2 voies de données, sans horloge transmise, norme LVDS (LVDS25 en banque 2,5 V, LVDS18G en banque 1,8 V). Ports : `TX_CLK_G`, `HS_IO_CLK`, `ARST_N`, `HS_IO_CLK_PAUSE`, `TX_DATA_0`, `TX_DATA_1`, `TXD`, `TXD_N`.
6. Comparer les ports générés (`component/work/<nom>/<nom>.vhd`) aux déclarations de composants de `horloges` et `sortie_lvds` dans `jpeg2dvb_fpga.vhd` ; vérifier dans le guide PF_IOD l'ordre d'émission des bits de TX_DATA (le fichier suppose TX_DATA(0) en premier).
7. Design Hierarchy ▸ `jpeg2dvb_top` ▸ Set As Root. Constraint Manager ▸ Timing, contraintes à saisir (ou importer `jpeg2dvb_top.sdc`) : `create_clock -name osc_50 -period 20.000 [get_ports osc_50]`, `create_clock -name tvp_sclk -period 37.037 [get_ports tvp_sclk]`, `set_clock_groups -asynchronous -group [get_clocks tvp_sclk]` ; puis Derive Constraints (horloges des PLL 80, 320 et 14,318182 MHz).
8. Brochage (I/O Editor) avec le PCB : sorties LVDS en banque GPIO (les banques HSIO ne font pas d'émission LVDS) ; `osc_50` et `tvp_sclk` sur des entrées d'horloge.
9. Synthesize, Place and Route, Verify Timing ; le rapport de ressources est `synthesis/jpeg2dvb_top.srr`.

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

- Horloge : 80 MHz = 16 × débit symbole (5 MS/s ; 8 × à 10 MS/s dans les bancs). Un créneau TS de 1 504 bits dure 26 112 cycles à 5 MS/s (13 056 à 10 MS/s).
- Le filtre SRRC sort un échantillon par cycle ; la chaîne arrière suit sans trou une fois le flux établi (1 136 cycles d'amorçage, dont la mise à zéro de l'entrelaceur).
- DCT : environ 140 cycles par bloc (36,6 millions de coefficients par seconde à 80 MHz, pour 15,6 millions nécessaires en 720 × 576 à 25 images/s).

## Surface (mesures sur MPF050T, cible MPF100T)

Réductions du 2026-11-11, toutes identiques au bit près aux références :

| Module | Avant | Après |
|---|---|---|
| `sdm3`, `sd_entree` | comparateurs de 25 bits, registres et candidats de 24 bits | seuils et corrections multiples de FS : poids forts seuls (comparateurs de 15 bits, `Pk` et candidats de 14 bits), états de 17, 20 et 22 bits, apports de 16 bits |
| `quant_intra` | table d'inverses combinatoire (1 984 × 25 bits), produits 22 × 24 et 22 × 14 | mémoire morte synchrone, produits 17 × 14 et 13 × 13 |
| `dct8x8_int` | 16 multiplieurs, 1 664 bascules de données | 8 multiplieurs, 414 bascules, mémoires 64 × 18 et 64 × 12 |
| `ts_mux` | quatre produits par créneau, compteurs de 32 bits | écarts tenus en cumul ; plus de rebouclage du compteur de créneaux (8 jours) ni du PTS à 2²¹ images |
| `interleaver` | lecture asynchrone de la mémoire | lecture synchrone |
| `mire_gen` | image de 101 376 mots de 4 bits | couleur calculée par comparaisons |

À contrôler dans le rapport de ressources Libero : `quant_intra` 3 LSRAM (mémoire morte), `interleaver` 1 LSRAM, `dct8x8_int` mémoires en µSRAM. `quant_intra` suppose |F| ≤ 4 095 (la DCT donne |F| ≤ 2 040).

### Synthèse Libero de `jpeg2dvb_top` (2026-11-12)

Synplify Pro, `mpf050tfcvg484-1`, `jpeg2dvb_fpga.vhd` 2.17, avant la création des trois cœurs Libero (`horloges` et `sortie_lvds` en boîtes vides) et sans contrainte d'horloge (100 MHz supposés) :

| Ressource | Utilisé | Disponible (MPF050T) |
|---|---|---|
| LUT à 4 entrées (avec la logique d'interface des mémoires et des DSP) | 30 217 | environ 48 000 |
| Bascules (avec la logique d'interface) | 11 763 | environ 48 000 |
| LSRAM (RAM1K20) | 131 | 160 (81 %) |
| µSRAM (RAM64x12) | 11 | 450 |
| Blocs de calcul (DSP) | 55 | 150 |

Estimation de timing avant placement-routage : `clk_sys` 75,0 MHz (13,3 ns) pour 80 MHz exigés (12,5 ns) ; `tvp_sclk` 129 MHz pour 27 MHz. Chemins critiques : calcul de couleur de `mire_gen` (31 niveaux de logique) et `o_valid` / `m_code` de `vlc_enc`. Les valeurs du placement-routage remplaceront ces estimations.

## Reste à faire

1. ✔ Chaîne complète du .vhd (versions 2.19 à 2.24) : DVB-S, DVB-S2, BISS, choix automatique, MCPC, caméra ; suite de tests complète OK, synthèse GHDL OK.
2. Libero : créer les trois cœurs (`PF_CCC_SYS`, `PF_CCC_TVP`, `PF_IOD_TX_SD`), synthèse, placement-routage, rapport de ressources (LSRAM de `dvbs2_tx`) et de timing à 80 MHz sur MPF100T.
3. Brochage avec le PCB (azs-cad.html), contraintes `jpeg2dvb_top.sdc`.
4. Test final sur carte : lire le Transport Stream avec un décodeur standard (DVB-S, DVB-S2, BISS).
5. Simulation de la chaîne complète (caméra, MCPC, DVB-S2) trop lente en GHDL : vérifiée par blocs ; à contrôler sur carte. Référence LVDS du banc `top` à régénérer pour l'entité de tête MCPC.

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
| 2026-11-11 | Réduction de surface pour le MPF050T, sortie inchangée au bit près (`jpeg2dvb_fpga.vhd` 2.6 à 2.11) : `sdm3` et `sd_entree` sur les bits utiles, `quant_intra` en mémoire morte synchrone, `dct8x8_int` à 4 multiplieurs par passe et mémoires, `ts_mux` sans multiplieur, `interleaver` en lecture synchrone, mire calculée (`mire.js` 1.2, `fusion.js` 1.1) |
| 2026-11-11 | Embrouillage DVB-CSA à clé fixe (BISS-1) : `csa_enc`, `csa_tab_pkg`, référence `csa.js` (autotest sur deux vecteurs publics), banc `csa` ; `jpeg2dvb_fpga.vhd` 2.12, `jpeg2dvb_fpga_tb.vhd` 2.7, `run_tests.sh` 1.7 |
| 2026-11-11 | Chaîne MCPC et caméra (`jpeg2dvb_fpga.vhd` 2.13 à 2.17) : `ts_mux` à deux programmes (`mcpc.js`, banc `mcpc`), `cam_mb` (`bt656.js` 1.1 écrit `cam_mb.bin`, banc `cam`), `codeur` 720 × 576 en images de demi-trame (`tb_codeur`), `dvbs_sd` et `jpeg2dvb_top` en MCPC (caméra sur le programme 1, mire sur le programme 2, 47 % du débit chacun), image noire sans caméra ; `run_tests.sh` 1.9 |
| 2026-11-12 | Première synthèse Libero de `jpeg2dvb_top` sur le MPF050T (131 LSRAM sur 160, 55 DSP sur 150, 75 MHz estimés pour 80 MHz exigés). `jpeg2dvb_fpga.vhd` 2.18 : `horloges` et `sortie_lvds` dans le fichier unique, `jpeg2dvb_ip_libero.vhd` supprimé, `jpeg2dvb_ip_sim.vhd` 2.0 (modèles des trois cœurs Libero) ; documentation mise à jour |
| 2026-11-12 | Réglages fixes (5 MS/s, FEC 1/2) et choix automatique (`choix_auto`), `regs_i2c` supprimé (2.20) ; DVB-S2 QPSK 1/4 (`dvbs2_tx`, 2.21) ; BISS-1 dans la chaîne, `tirage_biss`, numéro sur la mire (2.22) ; trois corrections de `dvbs2_tx` (banc `tb_s2` identique à `dvbs2.js`, 2.23) ; `codeur` 720 × 576 : `vlc_enc` recevait 22 colonnes au lieu de 45, image caméra corrigée (2.24) ; timing : `mire_gen` et `vlc_enc` en étages (2.19) ; cible MPF100T ; `run_tests.sh` 2.0 |

## Licence

CC BY-NC 4.0 — **Eric PERRET**
