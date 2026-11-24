<!--
  Nom      : LISEZMOI.md
  Objet    : portage FPGA de JPEG2DVB (émetteur DVB-S 23 cm), VHDL-2008
  Auteur   : Eric PERRET
  Date     : 2026-11-24
  Licence  : CC BY-NC 4.0
-->

# JPEG2DVB — portage FPGA en VHDL-2008

🇬🇧 [English version: README.md](README.md)

Modules VHDL de l'émetteur DVB-S / DVB-S2 23 cm (FPGA Microchip PolarFire MPF050T ou MPF100T, boîtier FCVG484, même carte ; cahier des charges v0.4). Tous les modules sont dans un seul fichier, `jpeg2dvb_fpga.vhd` (synthèse), et tous les bancs dans `jpeg2dvb_fpga_tb.vhd` (simulation). Chaque module reproduit **au bit près** une étape de JPEG2DVB 2.x ; chaque banc de test GHDL lit les fichiers produits par JPEG2DVB (dossier [`fpga_test/`](../fpga_test/)) et compare la sortie du module octet par octet, ou échantillon par échantillon.

VHDL-2008 synthétisable, bibliothèque `ieee` seule, interfaces en flux `valid` / `ready` (contrôle de flux éprouvé par des trous aléatoires dans tous les bancs).

Fichiers de programmation prêts : [`jpeg2dvb_MPF050T.dat`](jpeg2dvb_MPF050T.dat) et [`jpeg2dvb_MPF100T.dat`](jpeg2dvb_MPF100T.dat) (VHDL 2.27), chargés dans le FPGA par l'ESP32 de programmation ([`esp32/`](esp32/LISEZMOI.md)) ou par un FlashPro sur J4. La carte est décrite plus bas (« La carte »).

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
| `horloges` + `sortie_lvds` | Enveloppes des quatre cœurs Libero : PLL `PF_CCC_SYS` (80 MHz) et `PF_CCC_TVP` (14,318 MHz), horloges des sérialiseurs `PF_IOD_TX_CCC_IOD` (320 MHz, 80 MHz), sérialiseur LVDS `PF_IOD_TX_SD` (2 voies, 640 Mbit/s, bits I et Q entrelacés sur `TXD_DATA`) | carte | `tb_top` (modèles `jpeg2dvb_ip_sim.vhd`) | ✔ placé et routé dans Libero ; ordre des bits de chaque voie à vérifier sur carte |
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

Horloges : oscillateur MEMS 50 MHz IC2 (DSC1001) → PLL `PF_CCC_SYS` (80 MHz) → `PF_IOD_TX_CCC_IOD` (× 4 : 320 MHz pour les sérialiseurs, et 80 MHz `TX_CLK_G` sur lequel tourne toute la logique). Second PLL `PF_CCC_TVP` : 50 MHz → 14,318 MHz vers XTAL1 du décodeur (14,318182 MHz demandés ; le configurateur n'accepte que trois décimales, écart de 12,7 ppm). Remise à zéro tenue tant que les trois PLL ne sont pas verrouillés. Sorties LVDS I et Q à 640 Mbit/s (sérialiseurs 8:1) : les bits des deux voies sont entrelacés sur le bus `TXD_DATA` du cœur (bit k de la voie n sur `TXD_DATA(2k + n)`, voie I = 0, voie Q = 1).

Aucun registre dans la version 2.27 : réglages fixes, 5 MS/s, FEC 1/2 (la liaison I²C du PIC vers le FPGA existe sur la carte, billes E18 et E19, mais le VHDL ne l'utilise pas encore). `choix_auto` sonde les deux entrées vidéo (AIP1A puis AIP1B, 600 ms chacune) dès que le décodeur est identifié, puis toutes les minutes ; le mode précédent est tenu pendant le sondage :

| Entrées verrouillées | Mode | Programme 1 | Programme 2 |
|---|---|---|---|
| AIP1A seule | DVB-S | caméra A | mire |
| AIP1B seule | DVB-S2 QPSK 1/4 | caméra B | mire |
| A et B | DVB-S, BISS-1 | caméra A embrouillée | mire en clair, numéro affiché |
| aucune | DVB-S | image noire | mire |

BISS : le numéro de 4 chiffres (0000 à 9999) est tiré à la mise sous tension (`tirage_biss`, compteur figé à l'identification du décodeur) ; la clé de session est ce numéro répété trois fois, le mot de contrôle `S0 S1 S2 (S0+S1+S2) S3 S4 S5 (S3+S4+S5)`. Le numéro s'affiche sur la mire du programme 2 uniquement en mode BISS. LED actives à 1 : PLL verrouillés, décodeur présent, vidéo verrouillée.

### Composant, boîtier, tensions

- Une seule carte pour deux composants : MPF050T ou MPF100T, boîtier **FCVG484** (484 billes, pas de 0,8 mm, 19 × 19 mm), gamme industrielle (−40 à 100 °C), vitesse STD. Le boîtier FCG484 (pas de 1,0 mm) n'existe pas pour le MPF050T : il est abandonné.
- Toutes les entrées-sorties sont en 3,3 V : LVCMOS33 pour les signaux, LVDS33 pour les sorties I/Q. Banques 2 et 4 (GPIO) à 3,3 V ; banques 0 et 1 (HSIO, 1,8 V au plus) et émetteurs-récepteurs inutilisés.
- Rails du FPGA : VDD 1,0 V, VDD18 1,8 V, VDD25 2,5 V ; VDDI2, VDDI4, VDDAUX2, VDDAUX4 et VDDI3 (JTAG) à 3,3 V ; les rails des banques et fonctions inutilisées (VDDI0, VDDI1, VDDA, VDDA25, VDD_XCVR_CLK, XCVR_VREF) vont à la masse par 10 kΩ.

### Brochage (`jpeg2dvb_top.pdc` 1.0)

Rangé par quadrant, boîtier vu de dessus, bille A1 en haut à gauche. Disposition de la carte : vidéo à gauche, FPGA au centre, I/Q et chaîne HF à droite, alimentations en haut, LED et programmation en bas.

| Fonction | Billes | Banque | Norme |
|---|---|---|---|
| `osc_50` | A10 | 2 | LVCMOS33 |
| `tvp_sclk` | G4 | 4 | LVCMOS33 |
| `tvp_d[0]` à `tvp_d[7]` | H2, J2, J1, J4, K1, L1, L2, M4 | 4 | LVCMOS33 |
| `tvp_xtal1`, `tvp_resetb`, `tvp_pdn` | F3, E3, F5 | 4 | LVCMOS33 |
| `tvp_scl`, `tvp_sda` | G3, G2 | 4 | LVCMOS33 |
| `led_pll`, `led_tvp`, `led_video` | R3, R4, T1 | 4 | LVCMOS33 |
| `sd_i_p` / `sd_i_n` | B19 / B20 | 2 | LVDS33 |
| `sd_q_p` / `sd_q_n` | A20 / A21 | 2 | LVDS33 |
| I²C du PIC : SCL / SDA (câblé, absent du `.pdc` 1.0) | E18 / E19 | 2 | LVCMOS33 |

Écarts imposés par le boîtier : seules les billes du haut et du côté gauche acceptent le 3,3 V ; les sorties I/Q sont donc en haut à droite, les LED en bas du côté gauche, et le JTAG reste sur ses billes fixes (F6 à H10). Libero accepte ce brochage sans erreur ni avertissement sur les deux composants.

Le schéma de ce qui arrive au FPGA et de ce qui en sort (format azs-cad, 2026-11-16) est dans [`captures/`](../captures/LISEZMOI.md), avec la table des 484 billes ; le projet azs-cad de la carte complète n'est pas dans le dépôt.

### Chaîne Libero sans intervention (`jpeg2dvb_libero.tcl` 1.3)

Le lot est un dossier du PC Libero (`~/dvb_lot`) qui reçoit `jpeg2dvb_libero.tcl`, `jpeg2dvb_fpga.vhd` (fichier source unique, `horloges` et `sortie_lvds` compris), `jpeg2dvb_top.sdc`, `jpeg2dvb_top.pdc` et `sonde.vhd`, tous pris dans `vhdl/`. Le projet Libero de référence (`~/dvb`, variable `REF` du script) n'est que lu. Le script (Libero SoC 2026.1, mode script, fenêtre Libero fermée) écrit tous les réglages, sans réglage par défaut :

1. cœurs : `coeurs/*.tcl` du lot ; s'ils manquent, ils sont exportés du projet de référence ;
2. table des broches du boîtier, obtenue de Libero par le design `sonde.vhd` ;
3. brochage : `jpeg2dvb_top.pdc` du lot, sinon brochage calculé ;
4. pour le MPF050T puis le MPF100T : projet neuf, VHDL-2008, mode bloc désactivé, cœurs, contraintes (`jpeg2dvb_top.sdc` et horloges des PLL par `derive_constraints_sdc`), synthèse, placement-routage, timing ; si le timing passe : données de programmation, initialisation des mémoires et fichier DAT (fabric et sNVM, sinon fabric seule) `jpeg2dvb_MPF050T.dat` ou `jpeg2dvb_MPF100T.dat` à la racine du lot ;
5. `resultats/bilan.txt`, `resultats/journal.txt` et l'archive `jpeg2dvb_resultats.tgz`.

Dans le dépôt, tout est à plat dans `vhdl/` : les deux `.dat` et leurs `.digest`, `resultats-bilan.txt`, `resultats-journal.txt`, `jpeg2dvb_resultats.tgz` et `jpeg2dvb_libero.log`.

| Fichier | Octets | Composant |
|---|---|---|
| `jpeg2dvb_MPF050T.dat` | 1 631 762 | MPF050T-FCVG484 |
| `jpeg2dvb_MPF100T.dat` | 3 528 818 | MPF100T-FCVG484 |

Lancement, dans le dossier du lot, une seule fois et au premier plan (deux lancements simultanés dans le même dossier se détruisent) :

```
libero SCRIPT:jpeg2dvb_libero.tcl LOGFILE:jpeg2dvb_libero.log
```

Environ 20 minutes par composant sur un PC à 4 Go de mémoire ; le mode script est environ dix fois plus rapide que l'interface graphique.

Les quatre cœurs :

| Cœur | Catalogue | Réglages |
|---|---|---|
| `PF_CCC_SYS` | `PF_CCC` | 50 MHz → 80 MHz, rétroaction Post-VCO |
| `PF_CCC_TVP` | `PF_CCC` | 50 MHz → 14,318 MHz |
| `PF_IOD_TX_CCC_IOD` | `PF_IOD_TX_CCC` | référence 80 MHz, × 4, 640 Mbit/s, rapport 8, alignement des horloges exposé |
| `PF_IOD_TX_SD` | `PF_IOD_GENERIC_TX` | `TX_DDRX_B`, 640 Mbit/s, 8 bits par cycle, 2 voies différentielles, sans horloge transmise |

Pièges rencontrés :

- le catalogue de cœurs doit être téléchargé (dépôts par défaut de Libero) avant toute création de cœur ;
- « Enable block creation » (Project Settings, Design flow) doit être décoché, sinon la synthèse n'insère pas les tampons d'entrée-sortie ;
- les sorties d'un sérialiseur `PF_IOD_GENERIC_TX` doivent être placées et verrouillées avant le placement-routage ;
- à 640 Mbit/s, ce sérialiseur exige le cœur d'horloges `PF_IOD_TX_CCC`, dont la référence vaut 320 MHz divisé par un entier (80 MHz ici) : un oscillateur de 50 MHz ne peut pas l'alimenter directement ;
- sans contraintes d'horloge, le rapport de timing affiche « N/A » et « aucune violation » ne prouve rien.

`jpeg2dvb_ip_sim.vhd` 2.2 (modèles GHDL des quatre cœurs) ne sert qu'en simulation.

## La carte

Circuit imprimé dessiné sous [azs-cad](https://github.com/ericperret/pcb-cad), en commande (novembre 2026) ; aucun essai sur carte à ce jour. Disposition : vidéo à gauche, FPGA au centre, I/Q et HF à droite, alimentations en haut, LED et programmation en bas.

| Bloc | Composants |
|---|---|
| Alimentation | J5 : 5 V ; quatre convertisseurs TLV62569 (U11 à U14) : +3V3, puis +2V5, +1V8 et +1V0 tirés du +3V3 ; U5 (ADM7150) : empreinte gardée, **non monté**, avec C62, C63 et C64 |
| Vidéo | J2, J3 (RCA) → U1 TVP5150AM1 → FPGA (BT.656, I²C du décodeur) |
| FPGA | IC1 MPF050T ou MPF100T (FCVG484), IC2 oscillateur DSC1001 50 MHz |
| I/Q | sorties sigma-delta LVDS → filtre de Butterworth d'ordre 5, 400 Ω différentiel, plat jusqu'à 5 MHz |
| HF | U2 ADL5375 (modulateur I/Q, OL 400 MHz à 6 GHz) → U4 ADL5611 → FL1 → J6 (SMA) |
| Oscillateur local | U3 ADF4351, référence IC3 DSC1001 50 MHz (par R45), R = 2, PFD 25 MHz, MOD 25, sorties ÷2 et ÷4 |
| PIC | U6 PIC16F18323 (ou modèle broche à broche compatible, F ou LF) : programme l'ADF4351 à chaque démarrage avec la fréquence gardée dans son EEPROM ; liaison I²C vers le FPGA (RC4 → E18 SCL, RC5 → E19 SDA, rappels R64 et R65 de 4,7 kΩ au +3V3) |
| Programmation | J7 (11 points) : ESP32 M5Stack CoreS3 qui programme le PIC (ICSP) et le FPGA (JTAG-DirectC) par une page web en Wi-Fi, voir [`esp32/`](esp32/LISEZMOI.md) ; J4 : FlashPro, en secours |

Filtre de sortie FL1 : un seul filtre Mini-Circuits LFCN (boîtier FV1206), changé au fer à souder selon la bande, place libre autour et sérigraphie sur la carte :

| Bande | FL1 |
|---|---|
| 950 à 2 150 MHz (23 cm, bande satellite) | LFCN-2250 (monté d'origine) |
| 70 cm | LFCN-490 |

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

## Surface et timing

Réductions du 2026-11-11, toutes identiques au bit près aux références :

| Module | Avant | Après |
|---|---|---|
| `sdm3`, `sd_entree` | comparateurs de 25 bits, registres et candidats de 24 bits | seuils et corrections multiples de FS : poids forts seuls (comparateurs de 15 bits, `Pk` et candidats de 14 bits), états de 17, 20 et 22 bits, apports de 16 bits |
| `quant_intra` | table d'inverses combinatoire (1 984 × 25 bits), produits 22 × 24 et 22 × 14 | mémoire morte synchrone, produits 17 × 14 et 13 × 13 |
| `dct8x8_int` | 16 multiplieurs, 1 664 bascules de données | 8 multiplieurs, 414 bascules, mémoires 64 × 18 et 64 × 12 |
| `ts_mux` | quatre produits par créneau, compteurs de 32 bits | écarts tenus en cumul ; plus de rebouclage du compteur de créneaux (8 jours) ni du PTS à 2²¹ images |
| `interleaver` | lecture asynchrone de la mémoire | lecture synchrone |
| `mire_gen` | image de 101 376 mots de 4 bits | couleur calculée par comparaisons |

Dans le rapport de ressources Libero : `quant_intra` 3 LSRAM (mémoire morte), `interleaver` 1 LSRAM, `dct8x8_int` mémoires en µSRAM. `quant_intra` suppose |F| ≤ 4 095 (la DCT donne |F| ≤ 2 040).

### Placement-routage de `jpeg2dvb_top` (2026-11-16)

Libero SoC 2026.1, `jpeg2dvb_fpga.vhd` 2.26, brochage `jpeg2dvb_top.pdc` 1.0, boîtier FCVG484, gamme industrielle, vitesse STD ; analyse de timing sur tous les coins :

| | MPF050T | MPF100T |
|---|---|---|
| LUT à 4 entrées | 35 287 / 48 144 (73 %) | 35 287 / 108 600 (32 %) |
| Bascules | 13 859 (29 %) | 13 859 (13 %) |
| LSRAM | 143 / 160 (89 %) | 143 / 352 (41 %) |
| µSRAM | 13 / 450 | 13 / 1 008 |
| Multiplieurs | 56 / 150 (37 %) | 56 / 336 (17 %) |
| PLL | 3 / 8 | 3 / 8 |
| Marge à 80 MHz, pire cas | +0,507 ns | +0,346 ns |
| Marge de maintien, pire cas | +0,072 ns | +0,067 ns |
| Violations | aucune | aucune |

**Le MPF050T est possible**, avec le même brochage que le MPF100T (fichiers de brochage identiques). Deux réserves : le MPF050T est presque plein en mémoire (17 blocs LSRAM libres), et la marge de timing est mince sur les deux composants : elle se revérifie à chaque version du VHDL. Chiffres complets : `resultats-bilan.txt` et `resultats-journal.txt`.

La première synthèse (2026-11-12, version 2.17, avant les cœurs et sans contrainte d'horloge) donnait 30 217 LUT, 131 LSRAM, 55 multiplieurs et 75 MHz estimés ; `mire_gen` et `vlc_enc` ont été découpés en étages depuis (2.19).

## Reste à faire

1. ✔ Chaîne complète du .vhd (versions 2.19 à 2.27) : DVB-S, DVB-S2, BISS, choix automatique, MCPC, caméra ; suite de tests complète et synthèse GHDL OK sur la 2.24 ; les versions 2.25 à 2.27 ne touchent que `horloges`, `sortie_lvds`, `jpeg2dvb_top` et des commentaires.
2. ✔ Libero (2026-11-16) : quatre cœurs, chaîne en mode script, placement-routage et timing à 80 MHz sur MPF050T et MPF100T, sans violation.
3. ✔ Brochage par quadrant (`jpeg2dvb_top.pdc` 1.0) et schéma des entrées-sorties du FPGA ([`captures/`](../captures/LISEZMOI.md)).
4. Délais d'entrée de la vidéo : le temps d'arrivée de `tvp_d[7:0]` par rapport à `tvp_sclk` (27 MHz) n'est pas déclaré dans `jpeg2dvb_top.sdc` ; à ajouter d'après la fiche du TVP5150AM1, puis relancer la chaîne Libero.
5. Ordre des bits dans chaque voie LVDS (bit 0 émis en premier) : hypothèse à vérifier sur carte.
6. Simulation de la chaîne complète (caméra, MCPC, DVB-S2) trop lente en GHDL : vérifiée par blocs ; à contrôler sur carte. Référence LVDS du banc `top` à régénérer pour l'entité de tête MCPC.
7. ✔ Carte : alimentations, étage HF, PIC, programmation par l'ESP32, circuit imprimé (en commande). ✔ Fichiers `.dat` des deux composants (2026-11-23). Reste l'essai sur carte : lire le Transport Stream avec un décodeur standard (DVB-S, DVB-S2, BISS).
8. Modes GMSK, DVB-C et DVB-T sur le MPF100T (le MPF050T est plein à 89 % en LSRAM et garde la version actuelle), choisis par le PIC sur la liaison I²C (E18, E19) et réglés depuis la page web de l'ESP32 ; bande ÷8 de l'ADF4351 pour 430 à 550 MHz.

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
| 2026-11-13 | Cœurs Libero tels que générés (2.25) : `PF_CCC_SYS` (80 MHz) alimente `PF_IOD_TX_CCC_IOD` (320 MHz, 80 MHz, alignement des horloges), bus `TXD_DATA` de 16 bits ; bits des voies I et Q entrelacés sur `TXD_DATA` (2.26) ; `jpeg2dvb_ip_sim.vhd` 2.2 (quatre cœurs) |
| 2026-11-16 | Chaîne Libero en mode script (`jpeg2dvb_libero.tcl` 1.2, `sonde.vhd`, `coeurs/`), `jpeg2dvb_top.sdc` 1.1, brochage par quadrant `jpeg2dvb_top.pdc` 1.0 ; boîtier FCVG484, tout en 3,3 V (LVCMOS33, LVDS33) ; placement-routage et timing sans violation sur MPF050T et MPF100T avec le même brochage ; schéma des entrées-sorties du FPGA dans `carte/` (aujourd'hui `captures/`) ; `jpeg2dvb_fpga.vhd` 2.27 (commentaires seuls) ; `jpeg2dvb_ip_libero.vhd` retiré ; documentation mise à jour |
| 2026-11-20 | Carte : alimentations par quatre TLV62569 (+3V3, +2V5, +1V8, +1V0), U5 (ADM7150) laissé en empreinte, non monté |
| 2026-11-23 | Programmation par l'ESP32 : J7 à 11 points (PIC et JTAG), firmware `esp32/` (`jpeg2dvb_prog.ino` 1.1.1, page web, détection du modèle de PIC, écriture de la fréquence) ; `jpeg2dvb_libero.tcl` 1.3 : export DAT ; `jpeg2dvb_MPF050T.dat` et `jpeg2dvb_MPF100T.dat` à la racine de `vhdl/` ; fichiers du dépôt à plat (`resultats-bilan.txt`, `resultats-journal.txt`) |
| 2026-11-23 | Carte, avant commande du circuit imprimé : liaison I²C du PIC vers le FPGA (RC4 → E18, RC5 → E19, R64 et R65 de 4,7 kΩ), filtre FL1 unique changé au fer selon la bande |
| 2026-11-24 | Documentation mise à jour (carte, deux oscillateurs, fichiers `.dat`, programmation) |

## Licence

CC BY-NC 4.0 — **Eric PERRET**
