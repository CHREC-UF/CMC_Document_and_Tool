# wave file for Questa
onerror {resume}

env /
add log -r *

set pairs [lsort [find instances -r hmc_bfm0/*/hmc_serdes]]
if {[llength $pairs] > 0} {
    add wave -divider "HMC BFM SERDES"
    foreach pair $pairs {
        set serdes [lindex $pair 0]
        add wave ${serdes}/link_train_sm_q
    }
}

add wave -divider "HMC BFM FLIT RX"
foreach pair [lsort [find instances -r hmc_flit_top/hmc_flit_bfm_rx*]] {
    set flit_bfm [lindex $pair 0]
    add wave -expand ${flit_bfm}/debug_req_head\[0\]
    #add wave  -expand ${flit_bfm}/debug_req_tail\[0\]
}

add wave -divider "HMC BFM FLIT TX"
foreach pair [lsort [find instances -r hmc_flit_top/hmc_flit_bfm_tx*]] {
    set flit_bfm [lindex $pair 0]
    add wave -expand ${flit_bfm}/debug_rsp_head\[0\]
    #add wave -expand ${flit_bfm}/debug_rsp_tail\[0\]
}

add wave -divider "HMC BFM RETRY"
foreach pair [lsort [find instances -r hmc_flit_top/hmc_retry*]] {
    set retry [lindex $pair 0]
    add wave ${retry}/error_abort*
    add wave ${retry}/start_retry*
}
