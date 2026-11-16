<!--
  Nom        : LISEZMOI.md
  Projet     : JPEG2DVB, émetteur DVB-S/DVB-S2 23 cm
  Objet      : schéma azs-cad de ce qui arrive au FPGA et de ce qui en sort
  Auteur     : Eric PERRET
  Date       : 2026-11-16
  Version    : 1.0
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-16  création
-->

# carte — schéma des entrées-sorties du FPGA

🇬🇧 [English version: README.md](README.md)

Schéma au format [azs-cad](https://github.com/ericperret/pcb-cad) de ce qui arrive au FPGA (MPF050T ou MPF100T, boîtier FCVG484, pas de 0,8 mm) et de ce qui en sort. Les alimentations, le décodeur vidéo et l'étage HF sont d'autres schémas.

| Fichier | Version | Rôle |
|---|---|---|
| `jpeg2dvb_fpga.lib` | 1.3 | bibliothèque : FPGA 484 billes (pastilles rondes, mot `ROND`, azs-cad 1.56.0 ou plus), oscillateur DSC1001DL5-050.0000T, connecteur FlashPro 10 points |
| `jpeg2dvb_fpga.sch.dxf` | 1.2 | schéma : 76 composants, 296 liaisons |
| `jpeg2dvb_fpga_broches.csv` | 1.1 | les 484 billes : fonction Microchip, banque, réseau, norme, consigne de câblage de Libero (rapport de broches du design placé et routé) |

Dans azs-cad : ouvrir la bibliothèque, puis le schéma (ou les deux fichiers ensemble comme projet).

## Contenu du schéma

Le FPGA est dessiné comme son boîtier, bille A1 en haut à gauche ; la disposition suit celle de la carte.

| Côté | Contenu |
|---|---|
| Haut | rails et découplages, oscillateur MEMS 50 MHz (STANDBY# au +3V3, 100 nF) |
| Gauche | 14 signaux du TVP5150AM1 sur les pastilles P1 à P14 ; rappels I²C de 4,7 kΩ au +3V3 |
| Droite | paires I/Q LVDS33 sur les pastilles P15 à P18 ; rails inutilisés à la masse par 10 kΩ |
| Bas | trois LED (330 Ω chacune), connecteur FlashPro J1 (VJTAG au +3V3), rappels des billes dédiées selon la consigne de Libero |

Les 22 signaux sont sur les billes de [`../vhdl/jpeg2dvb_top.pdc`](../vhdl/jpeg2dvb_top.pdc) ; la correspondance est vérifiée par programme (billes, réseaux, consignes).

## Rails

| Rail | Billes du FPGA | Découplage (guide de carte PolarFire, tableau FCVG484 0,8 mm) |
|---|---|---|
| +3V3 | VDDI2, VDDI4, VDDAUX2, VDDAUX4, VDDI3 (32 billes) | 8 × 100 nF, 4 × 47 µF |
| +1V0 | VDD (14 billes) | 4 × 100 nF, 1 × 1 µF, 2 × 330 µF tantale |
| +1V8 | VDD18 (5 billes) | 2 × 100 nF, 2 × 47 µF |
| +2V5 | VDD25 (5 billes) | 5 × 100 nF, 1 × 10 µF |

VDDI0, VDDI1 (banques HSIO inutilisées), VDDA, VDDA25, VDD_XCVR_CLK et XCVR_VREF (émetteurs-récepteurs inutilisés) vont chacun à la masse par 10 kΩ (réseaux `RPD_…`).

Sur le circuit : +3V3 et +1V0 en plans ; +1V8 et +2V5, qui n'ont que 5 billes chacun, se routent comme des signaux. Un circuit d'essai à 6 couches (placement automatique) a été routé en entier par azs-cad 1.56.0.

## Reste à faire

Schémas des alimentations, du décodeur vidéo et de l'étage HF ; placement et routage de la carte.
