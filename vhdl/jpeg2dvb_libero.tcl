#===============================================================================
#  Nom        : jpeg2dvb_libero.tcl
#  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
#  Objet      : chaîne Libero SoC complète et sans intervention, tous réglages
#               écrits ici (aucun réglage par défaut) : projet neuf, cœurs,
#               contraintes, brochage, synthèse, placement-routage, timing,
#               fichier de programmation DAT (DirectC), sur MPF050T puis MPF100T
#               en boîtier FCVG484 (même carte) ; les rapports sont regroupés
#               dans jpeg2dvb_resultats.tgz
#  Auteur     : Eric PERRET
#  Date       : 2026-11-23
#  Version    : 1.3
#  Plateforme : Libero SoC 2026.1, mode script ; Libero (fenêtre) fermé
#  Lancement  : dans le dossier du lot :
#                 libero SCRIPT:jpeg2dvb_libero.tcl LOGFILE:jpeg2dvb_libero.log
#  Licence    : CC BY-NC 4.0
#  Entrées    : jpeg2dvb_fpga.vhd, jpeg2dvb_top.sdc, sonde.vhd, jpeg2dvb_top.pdc
#               (brochage imposé, facultatif) dans le même dossier ;
#               projet de référence /home/eperret/dvb (lecture seule) pour les
#               paramètres exacts des quatre cœurs
#  Sorties    : jpeg2dvb_MPF050T.dat et jpeg2dvb_MPF100T.dat dans le dossier
#               du lot (programmation par l'ESP32, JTAG-DirectC), coeurs/*.tcl,
#               travail/ (projets), resultats/ (rapports, journal.txt,
#               bilan.txt), jpeg2dvb_resultats.tgz
#  Étapes     : 1 cœurs du projet de référence exportés en Tcl
#               2 table des broches du MPF050T-FCVG484 (design sonde)
#               3 brochage provisoire calculé (une banque GPIO à 3,3 V)
#               4 chaîne complète MPF050T, puis MPF100T avec le même brochage ;
#                 si le timing passe : données de programmation, initialisation
#                 des mémoires, fichier de programmation, export DAT
#               5 bilan et archive
#  Historique : 1.0  2026-11-16  création
#               1.1  2026-11-16  brochage : les broches à fonction secondaire (DQS,
#                                CCC, CLKIN) servent aussi aux signaux (le MPF050T
#                                n'a pas assez de paires simples en banque 2)
#               1.2  2026-11-16  brochage imposé si jpeg2dvb_top.pdc est dans le lot
#                                (sinon brochage calculé, comme avant)
#               1.3  2026-11-23  export DAT (fabric + sNVM) de chaque composant
#                                dont le timing passe, à la racine du lot
#===============================================================================

set LOT      [file dirname [file normalize [info script]]]
set REF      /home/eperret/dvb
set RES      $LOT/resultats
set TRAVAIL  $LOT/travail
set COEURS   {PF_CCC_SYS PF_CCC_TVP PF_IOD_TX_CCC_IOD PF_IOD_TX_SD}
set RACINE   jpeg2dvb_top
set BOITIER  FCVG484
set VITESSE  STD
set GAMME    IND
file mkdir $RES $TRAVAIL $LOT/coeurs

#-------------------------------------------------------------------------------
# journal : E : texte → T : horodatage → S : écran et resultats/journal.txt
#-------------------------------------------------------------------------------
proc journal {texte} {
    global RES
    set ligne "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]  $texte"
    puts $ligne
    set f [open $RES/journal.txt a]
    puts $f $ligne
    close $f
}

#-------------------------------------------------------------------------------
# etape : E : nom, commande Tcl → T : exécution protégée → S : 1 si réussie
#-------------------------------------------------------------------------------
proc etape {nom commande} {
    journal "DEBUT  $nom"
    if {[catch {uplevel #0 $commande} erreur]} {
        journal "ECHEC  $nom : $erreur"
        return 0
    }
    journal "OK     $nom"
    return 1
}

#-------------------------------------------------------------------------------
# abandon : E : motif → T : bilan et archive de ce qui existe → S : fin du script
#-------------------------------------------------------------------------------
proc abandon {motif} {
    journal "ABANDON : $motif"
    catch {close_project}
    archive
    exit 1
}

#-------------------------------------------------------------------------------
# projet_neuf : E : nom, composant → T : new_project et project_settings avec
#   tous les réglages → S : projet ouvert dans travail/<nom>
#-------------------------------------------------------------------------------
proc projet_neuf {nom die} {
    global TRAVAIL BOITIER VITESSE GAMME
    file delete -force $TRAVAIL/$nom
    set ok [etape "projet $nom ($die-$BOITIER, $VITESSE, $GAMME)" [list new_project \
        -location $TRAVAIL/$nom -name $nom -project_description {} \
        -block_mode 0 -standalone_peripheral_initialization 0 \
        -instantiate_in_smartdesign 1 -ondemand_build_dh 1 \
        -use_relative_path 0 -linked_files_root_dir_env {} \
        -hdl {VHDL} -family {PolarFire} -die $die -package $BOITIER \
        -speed $VITESSE -die_voltage {1.0} -part_range $GAMME \
        -adv_options {IO_DEFT_STD:LVCMOS 1.8V} \
        -adv_options {RESTRICTPROBEPINS:1} \
        -adv_options {RESTRICTSPIPINS:0} \
        -adv_options {SYSTEM_CONTROLLER_SUSPEND_MODE:0} \
        -adv_options "TEMPR:$GAMME" \
        -adv_options "VCCI_1.2_VOLTR:$GAMME" \
        -adv_options "VCCI_1.5_VOLTR:$GAMME" \
        -adv_options "VCCI_1.8_VOLTR:$GAMME" \
        -adv_options "VCCI_2.5_VOLTR:$GAMME" \
        -adv_options "VCCI_3.3_VOLTR:$GAMME" \
        -adv_options "VOLTR:$GAMME"]]
    if {!$ok} { abandon "création du projet $nom" }
    set ok [etape "réglages du projet (VHDL-2008, pas de mode bloc)" {project_settings \
        -hdl {VHDL} -verilog_mode {SYSTEM_VERILOG} -vhdl_mode {VHDL_2008} \
        -standalone_peripheral_initialization 0 -instantiate_in_smartdesign 1 \
        -ondemand_build_dh 1 -display_fanout_limit {10} \
        -abort_flow_on_sdc_errors 1 -abort_flow_on_pdc_errors 1 -block_mode 0}]
    if {!$ok} {
        set ok [etape "réglages du projet, forme réduite" {project_settings \
            -vhdl_mode {VHDL_2008} -verilog_mode {SYSTEM_VERILOG} -block_mode 0}]
    }
    if {!$ok} { abandon "réglages du projet $nom (VHDL-2008)" }
}

#-------------------------------------------------------------------------------
# lire_table : E : rapport de broches (CSV) → T : lignes Pin,Port,Function,Bank
#   → S : liste de {broche fonction banque}
#-------------------------------------------------------------------------------
proc lire_table {fichier} {
    set f [open $fichier r]
    set table {}
    set dans 0
    while {[gets $f ligne] >= 0} {
        if {[string match "Pin,Port,Function,Bank,*" $ligne]} { set dans 1; continue }
        if {!$dans} { continue }
        set c [split $ligne ,]
        if {[llength $c] < 4} { continue }
        lappend table [list [lindex $c 0] [lindex $c 2] [lindex $c 3]]
    }
    close $f
    return $table
}

#-------------------------------------------------------------------------------
# paires_gpio : E : table, banque → T : broches GPIO<n>P/N de la banque
#   → S : liste triée par n de {n brocheP fonctionP brocheN fonctionN}
#-------------------------------------------------------------------------------
proc paires_gpio {table banque} {
    array set p {}
    array set n {}
    foreach l $table {
        lassign $l broche fonction bq
        if {$bq ne $banque} { continue }
        if {[regexp {^GPIO(\d+)([PN])B\d} $fonction -> num pol]} {
            if {$pol eq "P"} { set p($num) [list $broche $fonction] } else { set n($num) [list $broche $fonction] }
        }
    }
    set paires {}
    foreach num [lsort -integer [array names p]] {
        if {[info exists n($num)]} {
            lappend paires [list $num [lindex $p($num) 0] [lindex $p($num) 1] [lindex $n($num) 0] [lindex $n($num) 1]]
        }
    }
    return $paires
}

#-------------------------------------------------------------------------------
# banques_gpio : E : table → T : comptage → S : banques GPIO, la plus fournie
#   d'abord
#-------------------------------------------------------------------------------
proc banques_gpio {table} {
    array set nb {}
    foreach l $table {
        lassign $l broche fonction bq
        if {[regexp {^GPIO\d+[PN]B\d} $fonction]} {
            if {![info exists nb($bq)]} { set nb($bq) 0 }
            incr nb($bq)
        }
    }
    set tri {}
    foreach bq [array names nb] { lappend tri [list $bq $nb($bq)] }
    set tri [lsort -integer -decreasing -index 1 [lsort -index 0 $tri]]
    set res {}
    foreach t $tri { lappend res [lindex $t 0] }
    return $res
}

#-------------------------------------------------------------------------------
# ecrire_pdc : E : table des broches, numéro d'essai (0 à 3), fichier → T :
#   brochage provisoire : signaux en LVCMOS33 dans la banque GPIO la plus
#   fournie, horloges sur des broches CLKIN, sorties I/Q sur deux paires
#   simples ; essais 0 et 1 : LVDS33 dans la même banque (paires 0-1 puis
#   4-5) ; essais 2 et 3 : LVDS25 dans l'autre banque GPIO → S : fichier PDC,
#   texte décrivant l'essai (vide si l'essai est impossible)
#-------------------------------------------------------------------------------
proc ecrire_pdc {table essai fichier} {
    set banques [banques_gpio $table]
    if {[llength $banques] == 0} { return "" }
    set b_sig [lindex $banques 0]
    if {$essai < 2} {
        set b_lvds $b_sig
        set norme LVDS33
    } else {
        if {[llength $banques] < 2} { return "" }
        set b_lvds [lindex $banques 1]
        set norme LVDS25
    }
    set rang [expr {($essai % 2) * 4}]
    # paires simples (sans fonction secondaire) de la banque des sorties I/Q
    set simples {}
    foreach pr [paires_gpio $table $b_lvds] {
        lassign $pr num bp fp bn fn
        if {[string first / $fp] < 0 && [string first / $fn] < 0} { lappend simples $pr }
    }
    if {[llength $simples] < $rang + 2} { return "" }
    set pi [lindex $simples $rang]
    set pq [lindex $simples [expr {$rang + 1}]]
    array set pris {}
    foreach pr [list $pi $pq] { set pris([lindex $pr 1]) 1; set pris([lindex $pr 3]) 1 }
    # horloges : broches P portant une fonction CLKIN dans la banque des signaux
    #   signaux : broches simples d'abord, puis broches à fonction secondaire
    #   (DQS, CCC, CLKIN : utilisables en entrée-sortie ordinaire), sauf LPRB
    set horloges {}
    set libres {}
    set autres {}
    foreach pr [paires_gpio $table $b_sig] {
        lassign $pr num bp fp bn fn
        if {[info exists pris($bp)] || [info exists pris($bn)]} { continue }
        if {[string first LPRB $fp] >= 0 || [string first LPRB $fn] >= 0} { continue }
        if {[string first CLKIN $fp] >= 0 && [llength $horloges] < 2} {
            lappend horloges $bp
            if {[string first / $fn] < 0} { lappend libres $bn } else { lappend autres $bn }
            continue
        }
        foreach {b fct} [list $bp $fp $bn $fn] {
            if {[string first / $fct] < 0} { lappend libres $b } else { lappend autres $b }
        }
    }
    set libres [concat $libres $autres]
    while {[llength $horloges] < 2} {
        if {[llength $libres] == 0} { return "" }
        lappend horloges [lindex $libres 0]
        set libres [lrange $libres 1 end]
    }
    set signaux {
        {tvp_d[0] INPUT} {tvp_d[1] INPUT} {tvp_d[2] INPUT} {tvp_d[3] INPUT}
        {tvp_d[4] INPUT} {tvp_d[5] INPUT} {tvp_d[6] INPUT} {tvp_d[7] INPUT}
        {tvp_xtal1 OUTPUT} {tvp_resetb OUTPUT} {tvp_pdn OUTPUT}
        {tvp_scl INOUT} {tvp_sda INOUT}
        {led_pll OUTPUT} {led_tvp OUTPUT} {led_video OUTPUT}
    }
    if {[llength $libres] < [llength $signaux]} { return "" }
    set f [open $fichier w]
    puts $f "# =============================================================================="
    puts $f "#  Nom        : [file tail $fichier]"
    puts $f "#  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)"
    puts $f "#  Objet      : brochage provisoire de jpeg2dvb_top, boîtier FCVG484, commun au"
    puts $f "#               MPF050T et au MPF100T ; écrit par jpeg2dvb_libero.tcl d'après la"
    puts $f "#               table des broches du MPF050T (essai $essai)"
    puts $f "#  Auteur     : Eric PERRET"
    puts $f "#  Date       : [clock format [clock seconds] -format %Y-%m-%d]"
    puts $f "#  Version    : 1.0"
    puts $f "#  Licence    : CC BY-NC 4.0"
    puts $f "#  Contenu    : signaux LVCMOS33 en $b_sig ; sorties I/Q $norme en $b_lvds"
    puts $f "# =============================================================================="
    puts $f ""
    puts $f "set_io -port_name osc_50   -pin_name [lindex $horloges 0] -fixed true -io_std LVCMOS33 -DIRECTION INPUT"
    puts $f "set_io -port_name tvp_sclk -pin_name [lindex $horloges 1] -fixed true -io_std LVCMOS33 -DIRECTION INPUT"
    set k 0
    foreach s $signaux {
        lassign $s port sens
        puts $f "set_io -port_name {$port} -pin_name [lindex $libres $k] -fixed true -io_std LVCMOS33 -DIRECTION $sens"
        incr k
    }
    puts $f "set_io -port_name sd_i_p -pin_name [lindex $pi 1] -fixed true -io_std $norme -DIRECTION OUTPUT"
    puts $f "set_io -port_name sd_i_n -pin_name [lindex $pi 3] -fixed true -io_std $norme -DIRECTION OUTPUT"
    puts $f "set_io -port_name sd_q_p -pin_name [lindex $pq 1] -fixed true -io_std $norme -DIRECTION OUTPUT"
    puts $f "set_io -port_name sd_q_n -pin_name [lindex $pq 3] -fixed true -io_std $norme -DIRECTION OUTPUT"
    close $f
    return "essai $essai : signaux LVCMOS33 en $b_sig, I/Q $norme en $b_lvds (paires GPIO[lindex $pi 0] et GPIO[lindex $pq 0])"
}

#-------------------------------------------------------------------------------
# sans_balises : E : fichier XML → T : balises retirées → S : lignes non vides
#-------------------------------------------------------------------------------
proc sans_balises {fichier} {
    set f [open $fichier r]
    set texte [read $f]
    close $f
    regsub -all {<[^>]*>} $texte "\n" texte
    set lignes {}
    foreach l [split $texte "\n"] {
        set l [string trim $l]
        if {$l ne ""} { lappend lignes $l }
    }
    return $lignes
}

#-------------------------------------------------------------------------------
# bilan : E : composant, dossier des rapports copiés → T : extraction des
#   tableaux de ressources, du résumé de timing et des violations → S : texte
#   ajouté à resultats/bilan.txt
#-------------------------------------------------------------------------------
proc bilan {die dossier} {
    global RES RACINE
    set f [open $RES/bilan.txt a]
    puts $f "================ $die ================"
    set r $dossier/${RACINE}_compile_netlist_resources.rpt
    if {[file exists $r]} {
        set g [open $r r]
        set dans 0
        while {[gets $g l] >= 0} {
            if {[string match "Resource Usage*" $l]} { set dans 1 }
            if {[string match "Detailed Logic*" $l]} { break }
            if {$dans} { puts $f $l }
        }
        close $g
    } else {
        puts $f "ressources : rapport absent"
    }
    foreach {titre nom} [list "TIMING MAX (setup)" ${RACINE}_max_timing_multi_corner.xml "TIMING MIN (hold)" ${RACINE}_min_timing_multi_corner.xml] {
        puts $f "--- $titre : domaine, période (ns), fréquence (MHz), marge (ns), coin"
        if {[file exists $dossier/$nom]} {
            set l [sans_balises $dossier/$nom]
            set a [lsearch -exact $l Summary]
            set b [lsearch -exact $l "Input to Output"]
            if {$a >= 0 && $b > $a} { puts $f [join [lrange $l [expr {$a + 6}] [expr {$b - 3}]] "  |  "] }
        } else {
            puts $f "rapport absent"
        }
    }
    foreach {titre nom} [list "VIOLATIONS MAX" ${RACINE}_max_timing_violations_multi_corner.xml "VIOLATIONS MIN" ${RACINE}_min_timing_violations_multi_corner.xml] {
        if {[file exists $dossier/$nom]} {
            set l [sans_balises $dossier/$nom]
            set a [lsearch -glob $l "slow_lv_lt*"]
            puts $f "--- $titre : [join [lrange $l [expr {$a + 1}] [expr {$a + 12}]] {  |  }]"
        } else {
            puts $f "--- $titre : rapport absent"
        }
    }
    puts $f ""
    close $f
}

#-------------------------------------------------------------------------------
# collecte : E : projet, composant → T : copie des rapports → S : resultats/<die>
#-------------------------------------------------------------------------------
proc collecte {projet die} {
    global RES RACINE
    set d $RES/$die
    file mkdir $d
    foreach motif [list synthesis/*.srr synthesis/*_rpt.txt synthesis/*.areasrr synthesis/*_cdc.csv synthesis/*.prj \
                        designer/$RACINE/*.rpt designer/$RACINE/*.csv designer/$RACINE/*.log \
                        designer/$RACINE/*multi_corner.xml designer/$RACINE/*coverage*.xml designer/$RACINE/*.sdc \
                        constraint/*.sdc constraint/*.log constraint/io/*.pdc *.prjx] {
        foreach fichier [glob -nocomplain $projet/$motif] { catch {file copy -force $fichier $d} }
    }
    bilan $die $d
}

#-------------------------------------------------------------------------------
# archive : E : — → T : tar de resultats/ et coeurs/ → S : jpeg2dvb_resultats.tgz
#-------------------------------------------------------------------------------
proc archive {} {
    global LOT
    catch {exec tar czf $LOT/jpeg2dvb_resultats.tgz -C $LOT resultats coeurs}
    journal "archive : $LOT/jpeg2dvb_resultats.tgz"
}

#-------------------------------------------------------------------------------
# exporter_dat : E : composant (projet ouvert, placé-routé, timing fait) → T :
#   données de programmation, données d'initialisation des mémoires, fichier de
#   programmation, export DAT fabric + sNVM (fabric seule si le sNVM est refusé)
#   → S : jpeg2dvb_<composant>.dat dans le dossier du lot, 1 si exporté
#-------------------------------------------------------------------------------
proc exporter_dat {die} {
    global LOT
    set dat $LOT/jpeg2dvb_${die}.dat
    catch {file delete -force $dat}
    if {![etape "réglages du fichier de programmation $die" {configure_tool -name {GENERATEPROGRAMMINGFILE} \
        -params {program_fabric:true} -params {program_security:false} \
        -params {sanitize_snvm:false}}]} { return 0 }
    if {![etape "DONNEES DE PROGRAMMATION $die" {run_tool -name {GENERATEPROGRAMMINGDATA}}]} { return 0 }
    if {![etape "initialisation des mémoires $die" {generate_design_initialization_data}]} { return 0 }
    if {![etape "FICHIER DE PROGRAMMATION $die" {run_tool -name {GENERATEPROGRAMMINGFILE}}]} { return 0 }
    set commun [list -file_name jpeg2dvb_${die} -export_dir $LOT -format {DAT} \
        -limit_SVF_file_size 0 -limit_SVF_file_by_max_filesize_or_vectors {SIZE} \
        -svf_max_filesize {1024} -svf_max_vectors {1000} \
        -trusted_facility_file 1 \
        -zeroization_likenew_action 0 -zeroization_unrecoverable_action 0]
    if {![etape "EXPORT DAT $die (fabric + sNVM)" [list export_bitstream_file {*}$commun -trusted_facility_file_components {FABRIC SNVM}]]} {
        if {![etape "EXPORT DAT $die (fabric seule)" [list export_bitstream_file {*}$commun -trusted_facility_file_components {FABRIC}]]} { return 0 }
    }
    if {![file exists $dat]} {
        journal "ECHEC  export DAT $die : $dat absent (DAT présents : [join [glob -nocomplain -directory $LOT -tails *.dat] {, }])"
        return 0
    }
    journal "DAT    [file tail $dat] : [file size $dat] octets"
    return 1
}

#-------------------------------------------------------------------------------
# chaine : E : composant, table des broches, premier essai de brochage → T :
#   projet neuf, cœurs, contraintes, synthèse, placement-routage (brochage
#   suivant si refus dans les 5 premières minutes), timing, collecte → S :
#   numéro de l'essai de brochage retenu, -1 si le placement-routage échoue
#-------------------------------------------------------------------------------
proc chaine {die table essai} {
    global LOT TRAVAIL RES COEURS RACINE
    set nom [string tolower $die]
    set projet $TRAVAIL/$nom
    projet_neuf $nom $die
    if {![etape "import du VHDL" [list import_files -convert_EDN_to_HDL 0 -library {work} -hdl_source $LOT/jpeg2dvb_fpga.vhd]]} { abandon "import du VHDL" }
    foreach c $COEURS {
        if {![etape "cœur $c" [list source $LOT/coeurs/$c.tcl]]} { abandon "création du cœur $c sur $die" }
    }
    if {![etape "hiérarchie" {build_design_hierarchy}]} { abandon "hiérarchie" }
    if {![etape "racine $RACINE" [list set_root -module ${RACINE}::work]]} { abandon "racine" }
    if {![etape "import du SDC" [list import_files -convert_EDN_to_HDL 0 -sdc $LOT/jpeg2dvb_top.sdc]]} { abandon "import du SDC" }
    if {![etape "horloges des PLL (derive_constraints_sdc)" {derive_constraints_sdc}]} { abandon "derive_constraints_sdc" }
    set sdc_u $projet/constraint/jpeg2dvb_top.sdc
    set sdc_d $projet/constraint/${RACINE}_derived_constraints.sdc
    set pdc   $projet/constraint/io/jpeg2dvb_top.pdc
    # brochage : fichier jpeg2dvb_top.pdc du lot s'il existe, sinon calculé
    set fixe [file exists $LOT/jpeg2dvb_top.pdc]
    if {$fixe} {
        file copy -force $LOT/jpeg2dvb_top.pdc $RES/jpeg2dvb_top.pdc
        set essai 0
        journal "brochage imposé : $LOT/jpeg2dvb_top.pdc"
    } else {
        set desc [ecrire_pdc $table $essai $RES/jpeg2dvb_top.pdc]
        if {$desc eq ""} { abandon "aucun brochage possible (essai $essai)" }
        journal "brochage $desc"
    }
    if {![etape "import du PDC" [list import_files -convert_EDN_to_HDL 0 -io_pdc $RES/jpeg2dvb_top.pdc]]} { abandon "import du PDC" }
    set ok 1
    set ok [expr {$ok && [etape "contraintes de la synthèse" [list organize_tool_files -tool {SYNTHESIZE} -file $sdc_u -file $sdc_d -module ${RACINE}::work -input_type {constraint}]]}]
    set ok [expr {$ok && [etape "contraintes du placement-routage" [list organize_tool_files -tool {PLACEROUTE} -file $pdc -file $sdc_u -file $sdc_d -module ${RACINE}::work -input_type {constraint}]]}]
    set ok [expr {$ok && [etape "contraintes du timing" [list organize_tool_files -tool {VERIFYTIMING} -file $sdc_u -file $sdc_d -module ${RACINE}::work -input_type {constraint}]]}]
    if {!$ok} { abandon "association des contraintes" }
    # réglages des outils : valeurs du projet de référence (run du 2026-11-16)
    etape "réglages de la synthèse" {configure_tool -name {SYNTHESIZE} \
        -params {AUTO_COMPILE_POINT:true} -params {BLOCK_MODE:false} \
        -params {CDC_MIN_NUM_SYNC_REGS:2} -params {CDC_REPORT:true} \
        -params {CLOCK_ASYNC:800} -params {CLOCK_DATA:5000} \
        -params {CLOCK_GATE_ENABLE:false} -params {CLOCK_GLOBAL:2} \
        -params {RAM_OPTIMIZED_FOR_POWER:false} -params {RETIMING:false} \
        -params {ROM_TO_LOGIC:true} -params {SEQSHIFT_TO_URAM:1}}
    etape "réglages du placement-routage" {configure_tool -name {PLACEROUTE} \
        -params {DELAY_ANALYSIS:MAX} -params {EFFORT_LEVEL:false} \
        -params {GB_DEMOTION:true} -params {INCRPLACEANDROUTE:false} \
        -params {IOREG_COMBINING:false} -params {MULTI_PASS_LAYOUT:false} \
        -params {PDPR:false} -params {RANDOM_SEED:0} \
        -params {REPAIR_MIN_DELAY:false} -params {REPLICATION:false} \
        -params {TDPR:true} -params {USE_RAM_MATH_INTERFACE_LOGIC:true}}
    etape "réglages du timing" {configure_tool -name {VERIFYTIMING} \
        -params {CONSTRAINTS_COVERAGE:true} -params {FORMAT:XML} \
        -params {MAX_TIMING_MULTI_CORNER:true} -params {MAX_TIMING_VIOLATIONS_MULTI_CORNER:true} \
        -params {MIN_TIMING_MULTI_CORNER:true} -params {MIN_TIMING_VIOLATIONS_MULTI_CORNER:true} \
        -params {MAX_PATHS_TIMING:5} -params {MAX_PATHS_VIOLATION:20} \
        -params {SLACK_THRESHOLD_VIOLATION:0.0}}
    catch {save_project}
    if {![etape "SYNTHESE $die" {run_tool -name {SYNTHESIZE}}]} {
        collecte $projet $die
        catch {close_project}
        return -1
    }
    set retenu -1
    while {$essai < 4} {
        set t0 [clock seconds]
        if {[etape "PLACEMENT-ROUTAGE $die (brochage essai $essai)" {run_tool -name {PLACEROUTE}}]} {
            set retenu $essai
            break
        }
        if {$fixe} {
            journal "placement-routage refusé avec le brochage imposé"
            break
        }
        if {[clock seconds] - $t0 > 300} {
            journal "placement-routage refusé après plus de 5 minutes : pas un problème de brochage"
            break
        }
        incr essai
        set desc ""
        while {$essai < 4 && $desc eq ""} {
            set desc [ecrire_pdc $table $essai $RES/jpeg2dvb_top.pdc]
            if {$desc eq ""} { incr essai }
        }
        if {$desc eq ""} { break }
        journal "brochage $desc"
        file copy -force $RES/jpeg2dvb_top.pdc $pdc
    }
    if {$retenu >= 0} {
        set timing [etape "TIMING $die" {run_tool -name {VERIFYTIMING}}]
        catch {file copy -force $pdc $RES/jpeg2dvb_top_${nom}.pdc}
        if {$timing} { exporter_dat $die } else { journal "pas de DAT pour $die : timing en échec" }
    }
    catch {save_project}
    collecte $projet $die
    catch {close_project}
    return $retenu
}

#===============================================================================
# 1. cœurs du projet de référence exportés en Tcl (paramètres exacts)
#===============================================================================
journal "===== jpeg2dvb_libero.tcl 1.3 ====="
set manque 0
foreach c $COEURS { if {![file exists $LOT/coeurs/$c.tcl]} { set manque 1 } }
if {$manque} {
    if {![etape "ouverture du projet de référence" [list open_project -file $REF/dvb.prjx]]} { abandon "projet de référence $REF/dvb.prjx illisible (Libero ouvert ?)" }
    foreach c $COEURS {
        if {![etape "export du cœur $c" [list export_component_to_tcl -component $c -library {work} -package {} -file $LOT/coeurs/$c.tcl]]} { abandon "export du cœur $c" }
    }
    catch {close_project}
}

#===============================================================================
# 2. table des broches du MPF050T-FCVG484 (design sonde)
#===============================================================================
set csv $RES/broches_mpf050t_${BOITIER}.csv
if {![file exists $csv]} {
    projet_neuf sonde MPF050T
    if {![etape "import de sonde.vhd" [list import_files -convert_EDN_to_HDL 0 -library {work} -hdl_source $LOT/sonde.vhd]]} { abandon "import de sonde.vhd" }
    if {![etape "hiérarchie de sonde" {build_design_hierarchy}]} { abandon "hiérarchie de sonde" }
    if {![etape "racine sonde" {set_root -module {sonde::work}}]} { abandon "racine sonde" }
    if {![etape "synthèse de sonde" {run_tool -name {SYNTHESIZE}}]} { abandon "synthèse de sonde" }
    if {![etape "placement-routage de sonde" {run_tool -name {PLACEROUTE}}]} { abandon "placement-routage de sonde" }
    set source_csv $TRAVAIL/sonde/designer/sonde/sonde_pinrpt_boardlayout.csv
    if {![file exists $source_csv]} {
        catch {export_pin_reports -export_dir $TRAVAIL/sonde/designer/sonde -pin_report_by_name 1 -pin_report_by_pkg_pin 1 -bank_report 1 -io_report 1}
    }
    if {![file exists $source_csv]} { abandon "rapport de broches absent : $source_csv" }
    file copy -force $source_csv $csv
    catch {close_project}
}
set table [lire_table $csv]
journal "table des broches : [llength $table] broches, banques GPIO : [banques_gpio $table]"
if {[llength $table] < 100} { abandon "table des broches illisible" }

#===============================================================================
# 3 et 4. chaîne complète : MPF050T, puis MPF100T avec le même brochage
#===============================================================================
set essai_050 [chaine MPF050T $table 0]
journal "MPF050T : [expr {$essai_050 >= 0 ? "placé-routé (brochage essai $essai_050)" : "ECHEC, voir le journal et resultats/MPF050T"}]"
set essai_100 [chaine MPF100T $table [expr {$essai_050 >= 0 ? $essai_050 : 0}]]
journal "MPF100T : [expr {$essai_100 >= 0 ? "placé-routé (brochage essai $essai_100)" : "ECHEC, voir le journal et resultats/MPF100T"}]"
if {$essai_050 >= 0 && $essai_100 >= 0} {
    journal "même brochage sur les deux composants : [expr {$essai_050 == $essai_100 ? {OUI} : {NON}}]"
}

foreach die {MPF050T MPF100T} {
    set f $LOT/jpeg2dvb_${die}.dat
    if {[file exists $f]} { journal "[file tail $f] : [file size $f] octets" } else { journal "[file tail $f] : absent" }
}

#===============================================================================
# 5. archive
#===============================================================================
archive
journal "===== fin ====="
