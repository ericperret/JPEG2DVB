/*
 * ══════════════════════════════════════════════════════════════
 *  Nom      : gpio_hw_interface.c
 *  Projet   : JPEG2DVB — chantier 2 : programmation du FPGA depuis l'ESP32 (M5Stack CoreS3)
 *  Objet    : portage JTAG-DirectC v2021.2 : accès aux broches JTAG par les registres
 *             GPIO de l'ESP32-S3 (TCK G8, TMS G9, TDI G17, TRSTB G1, TDO G18).
 *             Remplace JTAG/gpio_hw_interface.c d'origine (MSS GPIO).
 *             Sens des broches réglé par le firmware avant dp_top() et rendu ensuite.
 *  Auteur   : Eric PERRET
 *  Date     : 2026-11-21
 *  Version  : 1.0.0
 * ══════════════════════════════════════════════════════════════
 */
#include "dpuser.h"
#include "dpalg.h"
#include "dputil.h"
#include "jpeg2dvb_port.h"
#include "soc/soc.h"
#include "soc/gpio_reg.h"

#define M_TCK    (1UL << JPEG2DVB_GPIO_TCK)
#define M_TMS    (1UL << JPEG2DVB_GPIO_TMS)
#define M_TDI    (1UL << JPEG2DVB_GPIO_TDI)
#define M_TRST   (1UL << JPEG2DVB_GPIO_TRSTB)
#define M_TDO    (1UL << JPEG2DVB_GPIO_TDO)

/* état courant des broches JTAG, bits TCK/TDI/TMS/TRST de dpuser.h */
static DPUCHAR jtag_port_reg;

/* niveau de TDO : 0x80 si haut, 0 si bas */
DPUCHAR jtag_inp(void)
{
    (void)REG_READ(GPIO_IN_REG);            /* lecture de garde : TDO établi après le front */
    return ((REG_READ(GPIO_IN_REG) & M_TDO) != 0u) ? 0x80u : 0x00u;
}

/* positionne toutes les broches JTAG */
void jtag_outp(DPUCHAR outdata)
{
    uint32_t haut = 0u;
    uint32_t bas = 0u;
    if ((outdata & TCK) != 0u)  { haut |= M_TCK; }  else { bas |= M_TCK; }
    if ((outdata & TMS) != 0u)  { haut |= M_TMS; }  else { bas |= M_TMS; }
    if ((outdata & TDI) != 0u)  { haut |= M_TDI; }  else { bas |= M_TDI; }
    if ((outdata & TRST) != 0u) { haut |= M_TRST; } else { bas |= M_TRST; }
    REG_WRITE(GPIO_OUT_W1TS_REG, haut);
    REG_WRITE(GPIO_OUT_W1TC_REG, bas);
}

/* TCK et TRSTB à 1 */
void dp_jtag_init(void)
{
    jtag_port_reg = TCK | TRST;
    jtag_outp(jtag_port_reg);
}

/* TMS posé, impulsion sur TCK */
void dp_jtag_tms(DPUCHAR tms)
{
    jtag_port_reg &= (DPUCHAR)~(TMS | TCK);
    jtag_port_reg |= (tms ? TMS : 0u);
    jtag_outp(jtag_port_reg);
    jtag_port_reg |= TCK;
    jtag_outp(jtag_port_reg);
}

/* TMS et TDI posés, impulsion sur TCK */
void dp_jtag_tms_tdi(DPUCHAR tms, DPUCHAR tdi)
{
    jtag_port_reg &= (DPUCHAR)~(TMS | TCK | TDI);
    jtag_port_reg |= ((tms ? TMS : 0u) | (tdi ? TDI : 0u));
    jtag_outp(jtag_port_reg);
    jtag_port_reg |= TCK;
    jtag_outp(jtag_port_reg);
}

/* TMS et TDI posés, TDO lu TCK à 0, puis front montant */
DPUCHAR dp_jtag_tms_tdi_tdo(DPUCHAR tms, DPUCHAR tdi)
{
    DPUCHAR ret;
    jtag_port_reg &= (DPUCHAR)~(TMS | TCK | TDI);
    jtag_port_reg |= ((tms ? TMS : 0u) | (tdi ? TDI : 0u));
    jtag_outp(jtag_port_reg);
    ret = jtag_inp();
    jtag_port_reg |= TCK;
    jtag_outp(jtag_port_reg);
    return ret;
}
