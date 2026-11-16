<!--
  Name       : README.md
  Project    : JPEG2DVB, 23 cm DVB-S/DVB-S2 transmitter
  Purpose    : azs-cad schematic of what enters and leaves the FPGA
  Author     : Eric PERRET
  Date       : 2026-11-16
  Version    : 1.0
  License    : CC BY-NC 4.0
  History    : 1.0  2026-11-16  creation
-->

# carte — schematic of the FPGA inputs and outputs

🇫🇷 [Version française : LISEZMOI.md](LISEZMOI.md)

Schematic in [azs-cad](https://github.com/ericperret/pcb-cad) format of what enters and leaves the FPGA (MPF050T or MPF100T, FCVG484 package, 0.8 mm pitch). The supplies, the video decoder and the RF stage are other schematics.

| File | Version | Role |
|---|---|---|
| `jpeg2dvb_fpga.lib` | 1.3 | library: 484-ball FPGA (round pads, `ROND` keyword, azs-cad 1.56.0 or later), DSC1001DL5-050.0000T oscillator, 10-pin FlashPro header |
| `jpeg2dvb_fpga.sch.dxf` | 1.2 | schematic: 76 components, 296 connections |
| `jpeg2dvb_fpga_broches.csv` | 1.1 | the 484 balls: Microchip function, bank, net, standard, Libero wiring instruction (pin report of the placed and routed design) |

In azs-cad: open the library, then the schematic (or both files together as a project).

## Schematic content

The FPGA is drawn as its package, ball A1 top left; the arrangement follows the board layout.

| Side | Content |
|---|---|
| Top | rails and decoupling, 50 MHz MEMS oscillator (STANDBY# to +3V3, 100 nF) |
| Left | 14 TVP5150AM1 signals on pads P1 to P14; 4.7 kΩ I²C pull-ups to +3V3 |
| Right | LVDS33 I/Q pairs on pads P15 to P18; unused rails to ground through 10 kΩ |
| Bottom | three LEDs (330 Ω each), FlashPro header J1 (VJTAG to +3V3), pull resistors of the dedicated balls as instructed by Libero |

The 22 signals are on the balls of [`../vhdl/jpeg2dvb_top.pdc`](../vhdl/jpeg2dvb_top.pdc); the match is checked by program (balls, nets, instructions).

## Rails

| Rail | FPGA balls | Decoupling (PolarFire board design guide, FCVG484 0.8 mm table) |
|---|---|---|
| +3V3 | VDDI2, VDDI4, VDDAUX2, VDDAUX4, VDDI3 (32 balls) | 8 × 100 nF, 4 × 47 µF |
| +1V0 | VDD (14 balls) | 4 × 100 nF, 1 × 1 µF, 2 × 330 µF tantalum |
| +1V8 | VDD18 (5 balls) | 2 × 100 nF, 2 × 47 µF |
| +2V5 | VDD25 (5 balls) | 5 × 100 nF, 1 × 10 µF |

VDDI0, VDDI1 (unused HSIO banks), VDDA, VDDA25, VDD_XCVR_CLK and XCVR_VREF (unused transceivers) each go to ground through 10 kΩ (`RPD_…` nets).

On the board: +3V3 and +1V0 as planes; +1V8 and +2V5, with 5 balls each, are routed like signals. A 6-layer test board (automatic placement) was fully routed by azs-cad 1.56.0.

## To do

Schematics of the supplies, the video decoder and the RF stage; board placement and routing.
