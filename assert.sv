/*module usb2_cdr_lock_fsm_assert (
    input wire       clk_sys,
    input wire       rstn,
    input wire       enable,
    input wire       ce,
    input wire       ted_valid,

    input wire [1:0] state,
    input wire [1:0] state_o,

    input wire       acc_reset,
    input wire       loop_reset,
    input wire       gain_sel,
    input wire       locked,

    input wire       se0_ok,
    input wire       idle_ok,
    input wire       lock_ev,
    input wire       timeout_ev,
    input wire       drop_ev,
    input wire [$clog2(TIMEOUT):0] to_cnt,
    input wire [1:0] good_cnt,
    input wire [1:0] bad_cnt,
    input wire [2:0] edge_cnt,
    input wire [7:0] se0_cnt,
    input wire [7:0] idle_cnt,
    input wire err_small,
    input wire err_large,
    input wire line_bad,
    input wire        idle
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_ACQ  = 2'd1;
    localparam [1:0] S_TRK  = 2'd2;
    localparam [1:0] S_LOSS = 2'd3;
    localparam TO_W = $clog2(TIMEOUT) + 1;
    parameter OS = 8;
    parameter TIMEOUT = 8*OS;
    reg [TO_W-1:0] to_cnt;
        parameter SE0_QUAL  = OS;
    parameter IDLE_QUAL = 4;


// LFSM_001: Reset forces FSM to IDLE.
property p_lfsm_001_reset_to_idle;
    @(posedge clk_sys)
    (!rstn) |=> (state == S_IDLE);
endproperty
a_lfsm_001_reset_to_idle: assert property (p_lfsm_001_reset_to_idle);

// LFSM_002: Disable forces FSM to IDLE.
property p_lfsm_002_disable_to_idle;
    @(posedge clk_sys) disable iff (!rstn)
    (!enable) |=> (state == S_IDLE);
endproperty
a_lfsm_002_disable_to_idle: assert property (p_lfsm_002_disable_to_idle);

// LFSM_003: State output must match the internal FSM state.
property p_lfsm_003_state_output_check;
    @(posedge clk_sys) disable iff (!rstn)
    (state_o == state);
endproperty
a_lfsm_003_state_output_check: 
assert property (p_lfsm_003_state_output_check);
  
// LFSM_004: IDLE state must assert loop_reset and acc_reset and deassert locked.
property p_lfsm_004_idle_output_check;
    @(posedge clk_sys) disable iff (!rstn)
    (state == S_IDLE) |->
 (loop_reset && acc_reset && !locked);
endproperty
a_lfsm_004_idle_output_check:
 assert property (p_lfsm_004_idle_output_check);

// LFSM_005: ACQUIRE state must select high gain and keep locked deasserted.
property p_lfsm_005_acquire_output_check;
    @(posedge clk_sys) disable iff (!rstn)
    (state == S_ACQ) |-> (gain_sel && !locked);
endproperty
a_lfsm_005_acquire_output_check: 
assert property (p_lfsm_005_acquire_output_check);


/// LFSM_006: TRACK state must select low gain and assert locked.
property p_lfsm_006_track_output_check;
    @(posedge clk_sys) disable iff (!rstn)
    (state == S_TRK) |-> (!gain_sel && locked);
endproperty
a_lfsm_006_track_output_check: assert property 
(p_lfsm_006_track_output_check);

// LFSM_007: LOSS state must deassert locked.
property p_lfsm_007_loss_output_check;
    @(posedge clk_sys) disable iff (!rstn)
    (state == S_LOSS) |-> (!locked);
endproperty
a_lfsm_007_loss_output_check:
 assert property (p_lfsm_007_loss_output_check);

// LFSM_008: FSM must transition from IDLE to ACQUIRE when ted_valid is asserted.
property p_lfsm_008_idle_to_acquire;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_IDLE && ted_valid)
    |=> (state == S_ACQ);
endproperty
a_lfsm_008_idle_to_acquire: 
assert property (p_lfsm_008_idle_to_acquire);

// LFSM_009: FSM must transition from ACQUIRE to TRACK when lock condition is satisfied.
property p_lfsm_009_acquire_to_track;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_ACQ && lock_ev && !se0_ok)
    |=> (state == S_TRK);
endproperty
a_lfsm_009_acquire_to_track:
 assert property (p_lfsm_009_acquire_to_track);

// LFSM_010: FSM must transition from ACQUIRE to LOSS when SE0 is qualified.
property p_lfsm_010_acquire_to_loss;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_ACQ && se0_ok)
    |=> (state == S_LOSS);
endproperty
a_lfsm_010_acquire_to_loss:
 assert property (p_lfsm_010_acquire_to_loss);


// LFSM_011: FSM must transition from ACQUIRE to IDLE when acquisition timeout occurs.
property p_lfsm_011_acquire_timeout_to_idle;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_ACQ && timeout_ev && !se0_ok && !lock_ev)
    |=> (state == S_IDLE);
endproperty
a_lfsm_011_acquire_timeout_to_idle: 
assert property (p_lfsm_011_acquire_timeout_to_idle); 

// LFSM_012: FSM must transition from TRACK to LOSS when SE0 is qualified.
property p_lfsm_012_track_to_loss;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_TRK && se0_ok)
    |=> (state == S_LOSS);
endproperty
a_lfsm_012_track_to_loss: 
assert property (p_lfsm_012_track_to_loss);

// LFSM_013: FSM must transition from TRACK to IDLE when timing error exceeds the allowed limit.
property p_lfsm_013_track_to_idle;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_TRK && drop_ev && !se0_ok)
    |=> (state == S_IDLE);
endproperty
a_lfsm_013_track_to_idle:
 assert property (p_lfsm_013_track_to_idle);

// LFSM_014: FSM must transition from LOSS to IDLE when line idle is qualified.
property p_lfsm_014_loss_to_idle;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_LOSS && idle_ok)
    |=> (state == S_IDLE);
endproperty
a_lfsm_014_loss_to_idle:
 assert property (p_lfsm_014_loss_to_idle);

// LFSM_015: FSM state must remain unchanged when clock enable is low.
property p_lfsm_015_state_hold_when_ce_low;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (!ce) |=> $stable(state);
endproperty
a_lfsm_015_state_hold_when_ce_low: 
assert property (p_lfsm_015_state_hold_when_ce_low); 

// LFSM_016: ACQUIRE returns to IDLE when line idle is qualified.
property p_lfsm_016_acquire_idle_return;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_ACQ && idle_ok &&
     !se0_ok && !lock_ev && !timeout_ev)
    |=> (state == S_IDLE);
endproperty
a_lfsm_016_acquire_idle_return:
 assert property (p_lfsm_016_acquire_idle_return);

// LFSM_017: FSM must remain in TRACK when no loss condition occurs.
property p_lfsm_017_track_state_hold;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_TRK && !se0_ok && !drop_ev)
    |=> (state == S_TRK);
endproperty
a_lfsm_017_track_state_hold:
 assert property (p_lfsm_017_track_state_hold);

// LFSM_018: Timeout counter must increment on every enabled clock in ACQUIRE.
property p_lfsm_018_timeout_counter_increment;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_ACQ)
    |=> (to_cnt == ($past(to_cnt) + 1'b1));
endproperty

a_lfsm_018_timeout_counter_increment: 
assert property (p_lfsm_018_timeout_counter_increment);

// LFSM_019: FSM must remain in LOSS until idle is qualified.
property p_lfsm_019_loss_state_hold;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_LOSS && !idle_ok)
    |=> (state == S_LOSS);
endproperty

a_lfsm_019_loss_state_hold:
 assert property (p_lfsm_019_loss_state_hold);

// LFSM_020: Timeout counter must hold its value when ce is low.
property p_lfsm_020_timeout_counter_hold;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (!ce)
    |=> $stable(to_cnt);
endproperty

a_lfsm_020_timeout_counter_hold: 
assert property (p_lfsm_020_timeout_counter_hold);


// LFSM_021: LOSS state must hold loop state, park accumulator, and deassert lock.
property p_lfsm_021_loss_output_control;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (state == S_LOSS)
    |-> (!loop_reset && acc_reset && !locked);
endproperty
a_lfsm_021_loss_output_control: assert property (p_lfsm_021_loss_output_control);


// LFSM_022: Good counter must reset when a large TED error occurs during ACQUIRE.
property p_lfsm_022_good_counter_reset;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_ACQ && ted_valid && !err_small)
    |=> (good_cnt == 0);
endproperty
a_lfsm_022_good_counter_reset: assert property (p_lfsm_022_good_counter_reset);


// LFSM_023: Good counter must remain saturated at 3.
property p_lfsm_023_good_counter_saturation;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_ACQ && ted_valid && err_small && good_cnt == 3)
    |=> (good_cnt == 3);
endproperty
a_lfsm_023_good_counter_saturation: assert property (p_lfsm_023_good_counter_saturation);


// LFSM_024: Bad counter must reset after a non-large TED error in TRACK.
property p_lfsm_024_bad_counter_reset;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_TRK && ted_valid && !err_large)
    |=> (bad_cnt == 0);
endproperty
a_lfsm_024_bad_counter_reset: assert property (p_lfsm_024_bad_counter_reset);


// LFSM_025: Edge counter must remain saturated at 7.
property p_lfsm_025_edge_counter_saturation;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_ACQ && ted_valid && edge_cnt == 7)
    |=> (edge_cnt == 7);
endproperty
a_lfsm_025_edge_counter_saturation: assert property (p_lfsm_025_edge_counter_saturation);


// LFSM_026: SE0 qualification counter must reset when line_bad is deasserted.
property p_lfsm_026_se0_counter_reset;
    @(posedge clk_sys) disable iff (!rstn)
    (ce && !line_bad)
    |=> (se0_cnt == 0);
endproperty
a_lfsm_026_se0_counter_reset: assert property (p_lfsm_026_se0_counter_reset);


// LFSM_027: SE0 qualification counter must not exceed SE0_QUAL.
property p_lfsm_027_se0_counter_saturation;
    @(posedge clk_sys) disable iff (!rstn)
    (ce && line_bad && se0_cnt >= SE0_QUAL)
    |=> (se0_cnt == SE0_QUAL);
endproperty
a_lfsm_027_se0_counter_saturation: assert property (p_lfsm_027_se0_counter_saturation);


// LFSM_028: Idle qualification counter must reset when idle is deasserted.
property p_lfsm_028_idle_counter_reset;
    @(posedge clk_sys) disable iff (!rstn)
    (ce && !idle)
    |=> (idle_cnt == 0);
endproperty
a_lfsm_028_idle_counter_reset: assert property (p_lfsm_028_idle_counter_reset);


// LFSM_029: Idle qualification counter must not exceed IDLE_QUAL.
property p_lfsm_029_idle_counter_saturation;
    @(posedge clk_sys) disable iff (!rstn)
    (ce && idle && idle_cnt >= IDLE_QUAL)
    |=> (idle_cnt == IDLE_QUAL);
endproperty
a_lfsm_029_idle_counter_saturation: assert property (p_lfsm_029_idle_counter_saturation);


// LFSM_030: Edge and good counters must hold when ted_valid is low in ACQUIRE.
property p_lfsm_030_acquire_counter_hold;
    @(posedge clk_sys) disable iff (!rstn || !enable)
    (ce && state == S_ACQ && !ted_valid)
    |=> ($stable(edge_cnt) && $stable(good_cnt));
endproperty
a_lfsm_030_acquire_counter_hold: assert property (p_lfsm_030_acquire_counter_hold);

endmodule
bind usb2_cdr_lock_fsm
    usb2_cdr_lock_fsm_assert #(
        .OS(OS),
        .TIMEOUT(TIMEOUT),
        .SE0_QUAL(SE0_QUAL),
        .IDLE_QUAL(IDLE_QUAL)
    ) u_usb2_cdr_lock_fsm_assert (.*);*/ 


////////////////phase accumlator///////////////////
/*module usb2_cdr_phase_acc_assert #(
    parameter W         = 24,
    parameter OS        = 8,
    parameter LOG2_OS   = 3,
    parameter LOOP_W    = 18,
    parameter [W-1:0] STEP_NOM    = 24'h200000,
    parameter [W-1:0] RESET_PHASE = 24'h900000
)(
    input wire clk_sys,
    input wire rstn,
    input wire ce,
    input wire acc_reset,
    input wire signed [LOOP_W-1:0] loop_delta,
    input wire [1:0] speed,
    input wire [W-1:0] phase,
    input wire [LOG2_OS-1:0] phase_idx,
    input wire phase_frac,
    input wire bit_strobe,
    input wire [W-1:0] step_eff
);

   wire [W:0] acc_next = {1'b0, phase} + {1'b0, step_eff};

// PA_001: Verify phase accumulator reset loads RESET_PHASE and clears bit_strobe.
property p_pa_001_reset;
    @(posedge clk_sys)
    !rstn |=> (phase == RESET_PHASE && !bit_strobe);
endproperty

a_pa_001_reset:
    assert property (p_pa_001_reset);

// PA_002: Verify acc_reset loads RESET_PHASE and clears bit_strobe.
property p_pa_002_acc_reset;
    @(posedge clk_sys) disable iff (!rstn)
    acc_reset |=> (phase == RESET_PHASE && !bit_strobe);
endproperty

a_pa_002_acc_reset:
    assert property (p_pa_002_acc_reset);

// PA_003: Verify phase increments by step_eff when ce is asserted.
property p_pa_003_phase_increment;
    @(posedge clk_sys) disable iff (!rstn)
    ce && !acc_reset
    |=> phase == ($past(phase) + $past(step_eff));
endproperty

a_pa_003_phase_increment:
    assert property (p_pa_003_phase_increment);

// PA_004: Verify bit_strobe is asserted when phase addition generates a carry-out.
property p_pa_004_carry_generation;
    @(posedge clk_sys) disable iff (!rstn)
    ce && !acc_reset
    |=> bit_strobe == $past(acc_next[W]);
endproperty

a_pa_004_carry_generation:
    assert property (p_pa_004_carry_generation);

// PA_005: Verify phase remains stable when clock enable is low.
property p_pa_005_phase_hold;
    @(posedge clk_sys) disable iff (!rstn)
    !ce && !acc_reset
    |=> $stable(phase);
endproperty

a_pa_005_phase_hold:
    assert property (p_pa_005_phase_hold);

// PA_006: Verify bit_strobe remains stable when clock enable is low.
property p_pa_006_strobe_hold;
    @(posedge clk_sys) disable iff (!rstn)
    !ce && !acc_reset
    |=> $stable(bit_strobe);
endproperty

a_pa_006_strobe_hold:
    assert property (p_pa_006_strobe_hold);

// PA_007: Verify phase_idx is extracted from the most significant phase bits.
property p_pa_007_phase_idx;
    @(posedge clk_sys) disable iff (!rstn)
    phase_idx == phase[W-1 -: LOG2_OS];
endproperty

a_pa_007_phase_idx:
    assert property (p_pa_007_phase_idx);

// PA_008: Verify phase_frac is extracted from the bit immediately below phase_idx.
property p_pa_008_phase_frac;
    @(posedge clk_sys) disable iff (!rstn)
    phase_frac == phase[W-LOG2_OS-1];
endproperty

a_pa_008_phase_frac:
    assert property (p_pa_008_phase_frac);

// PA_009: Verify phase wraps around when the accumulator generates a carry-out.
property p_pa_009_phase_wrap;
    @(posedge clk_sys) disable iff (!rstn)
    bit_strobe && $past(ce)
    |-> phase < $past(phase);
endproperty

a_pa_009_phase_wrap:
    assert property (p_pa_009_phase_wrap);

// PA_010: Verify bit_strobe is deasserted in the next enabled cycle after a strobe.
property p_pa_010_strobe_single_cycle;
    @(posedge clk_sys) disable iff (!rstn)
    bit_strobe && ce && !acc_reset
    |=> !bit_strobe;
endproperty
a_pa_010_strobe_single_cycle:
    assert property (p_pa_010_strobe_single_cycle);

// PA_011: Verify bit_strobe reflects the carry-out of phase accumulation.
property p_pa_011_strobe_carry;
    @(posedge clk_sys) disable iff (!rstn)
    ($past(rstn) && $past(ce) && !$past(acc_reset))
    |->
    (bit_strobe == ($past(step_eff) > ~$past(phase)));
endproperty

a_pa_011_strobe_carry:
    assert property (p_pa_011_strobe_carry);

// PA_012: Verify step_eff remains within the specified clamp limits.
property p_pa_012_step_clamp;
    @(posedge clk_sys) disable iff (!rstn)
    ((speed == 2'b00) &&
     (step_eff >= (STEP_NOM - ((STEP_NOM + 25) / 50))) &&
     (step_eff <= (STEP_NOM + ((STEP_NOM + 25) / 50)))
    )
    ||
    ((speed != 2'b00) &&
     (step_eff >= (STEP_NOM - ((STEP_NOM + 100) / 200))) &&
     (step_eff <= (STEP_NOM + ((STEP_NOM + 100) / 200)))
    );
endproperty

a_pa_012_step_clamp:
    assert property (p_pa_012_step_clamp);

// PA_013: Verify step_eff equals STEP_NOM when loop_delta is zero.
property p_pa_013_nominal_step;
    @(posedge clk_sys) disable iff (!rstn)
    (loop_delta == '0) |-> (step_eff == STEP_NOM);
endproperty

a_pa_013_nominal_step:
    assert property (p_pa_013_nominal_step);

// PA_014: Verify bit_strobe changes only when ce is asserted.
property p_pa_014_strobe_update;
    @(posedge clk_sys) disable iff (!rstn)
    !acc_reset && !ce
    |=> $stable(bit_strobe);
endproperty

a_pa_014_strobe_update:
    assert property (p_pa_014_strobe_update);

// PA_015: Verify bit_strobe is asserted whenever phase wraps around.
property p_pa_015_strobe_on_wrap;
    @(posedge clk_sys) disable iff (!rstn)
    ($past(ce) && !$past(acc_reset) &&
     $past(rstn) && (phase < $past(phase)))
    |-> bit_strobe;
endproperty

a_pa_015_strobe_on_wrap:
    assert property (p_pa_015_strobe_on_wrap);

// PA_016: Verify effective step increases or remains nominal for positive loop_delta.
property p_pa_016_positive_loop_delta;
    @(posedge clk_sys) disable iff (!rstn)
    (loop_delta > 0)
    |-> (step_eff >= STEP_NOM);
endproperty

a_pa_016_positive_loop_delta:
    assert property (p_pa_016_positive_loop_delta);

// PA_017: Verify effective step does not exceed nominal step for negative loop_delta.
property p_pa_017_negative_loop_delta;
    @(posedge clk_sys) disable iff (!rstn)
    (loop_delta < 0)
    |-> (step_eff <= STEP_NOM);
endproperty

a_pa_017_negative_loop_delta:
    assert property (p_pa_017_negative_loop_delta);

// PA_018: Verify accumulator reset is asserted in High-Speed mode.
property p_pa_018_hs_acc_reset;
    @(posedge clk_sys) disable iff (!rstn)
    (speed == 2'b10) |-> acc_reset;
endproperty

a_pa_018_hs_acc_reset:
    assert property (p_pa_018_hs_acc_reset);

// PA_019: Assume only supported speed encodings are applied.
property p_pa_019_valid_speed;
    @(posedge clk_sys) disable iff (!rstn)
    speed inside {2'b00, 2'b01, 2'b10};
endproperty

as_pa_019_valid_speed:
    assume property (p_pa_019_valid_speed);

// PA_020 :Verify effective step stays within the specified speed-dependent limits.
property p_pa_023_step_clamp;
    @(posedge clk_sys) disable iff (!rstn)
    (speed == 2'b00) |-> (step_eff inside {[24'd411041:24'd427819]}) &&
    (speed == 2'b01) |-> (step_eff inside {[24'd417333:24'd421527]});
endproperty

a_pa_023_step_clamp:
    assert property (p_pa_023_step_clamp);
endmodule

bind usb2_cdr_phase_acc usb2_cdr_phase_acc_assert
   #(.W(W), .OS(OS),
 .LOG2_OS(LOG2_OS), .LOOP_W(LOOP_W),
 .STEP_NOM(STEP_NOM), .RESET_PHASE(RESET_PHASE))
 u_usb2_cdr_phase_acc_assert (.*); */


/////////////////////sampler///////////////
/*module usb2_cdr_sampler_assert #(
    parameter OS       = 8,
    parameter LOG2_OS  = 3,
    parameter MAJORITY = 0
)(
    input wire               clk_sys,
    input wire               rstn,
    input wire               ce,
    input wire               d_p_sync,
    input wire               d_n_sync,

    input wire [OS-1:0]      sample_window,
    input wire [LOG2_OS-1:0] phase_idx,
    input wire               phase_frac,
    input wire               bit_strobe,
    input wire               acc_reset,

    input wire               sample_tap,
    input wire               recovered_bit_clk,
    input wire               dp_out,
    input wire               dm_out,
    input wire               recovered_data,
    input wire               rx_bit_valid
);

    // SA_001: Verify sample_tap selects the correct sample from sample_window.
property p_sa_001_tap_selection;
    @(posedge clk_sys) disable iff (!rstn)
    (MAJORITY == 0)
    |->
    (sample_tap == sample_window[
        (({1'b0, phase_idx} + {{LOG2_OS{1'b0}}, phase_frac}) > OS-1)
        ? OS-1
        : ({1'b0, phase_idx} + {{LOG2_OS{1'b0}}, phase_frac})
    ]);
endproperty

a_sa_001_tap_selection:
    assert property (p_sa_001_tap_selection);

// SA_002: Verify majority voting of three samples.
property p_sa_002_majority_voting;
    @(posedge clk_sys) disable iff (!rstn)
    (MAJORITY == 1 &&
     (phase_idx + phase_frac) > 0 &&
     (phase_idx + phase_frac) < OS-1)
    |->
    (sample_tap ==
     ($countones({
         sample_window[phase_idx + phase_frac - 1],
         sample_window[phase_idx + phase_frac],
         sample_window[phase_idx + phase_frac + 1]
     }) >= 2));
endproperty

a_sa_002_majority_voting:
    assert property (p_sa_002_majority_voting);

// SA_003: Verify recovered bit clock is asserted only when the bit strobe and clock enable are active.
property p_sa_003_recovered_bit_clock;
    @(posedge clk_sys) disable iff (!rstn)
    recovered_bit_clk == (bit_strobe && ce);
endproperty

a_sa_003_recovered_bit_clock:
    assert property (p_sa_003_recovered_bit_clock);

// SA_004: Verify DP/DM output capture after the strobe.
property p_sa_004_dp_dm_capture;
    @(posedge clk_sys) disable iff (!rstn)
    (bit_strobe && ce)
    |=> (dp_out == $past(d_p_sync) &&
         dm_out == $past(d_n_sync));
endproperty

a_sa_004_dp_dm_capture:
    assert property (p_sa_004_dp_dm_capture);

// SA_005: Verify output register holds its value between strobes.
property p_sa_005_output_hold;
    @(posedge clk_sys) disable iff (!rstn)
    !recovered_bit_clk
    |=> $stable({dp_out, dm_out});
endproperty

a_sa_005_output_hold:
    assert property (p_sa_005_output_hold);

// SA_006: Verify Sampler output reset values.
property p_sa_006_output_reset;
    @(posedge clk_sys)
    !rstn
    |=> (dp_out == 1'b1 && dm_out == 1'b0);
endproperty

a_sa_006_output_reset:
    assert property (p_sa_006_output_reset);

// SA_007: Verify recovered bit clock is one clk_sys cycle wide.
property p_sa_007_recovered_bit_clk_width;
    @(posedge clk_sys) disable iff (!rstn)
    recovered_bit_clk |=> !recovered_bit_clk;
endproperty

a_sa_007_recovered_bit_clk_width:
    assert property (p_sa_007_recovered_bit_clk_width);

// SA_008: Verify single-tap selection at window boundaries.
property p_sa_008_majority_boundary;
    @(posedge clk_sys) disable iff (!rstn)
    (MAJORITY == 1 &&
     (({1'b0, phase_idx} + phase_frac) == 0 ||
      ({1'b0, phase_idx} + phase_frac) == OS-1))
    |->
    (sample_tap == sample_window[
        ({1'b0, phase_idx} + phase_frac)
    ]);
endproperty

a_sa_008_majority_boundary:
    assert property (p_sa_008_majority_boundary);
endmodule

bind usb2_cdr_sampler
    usb2_cdr_sampler_assert #(
        .OS(OS),
        .LOG2_OS(LOG2_OS),
        .MAJORITY(MAJORITY)
    ) u_usb2_cdr_sampler_assert (.*);*/

/////////////////////////TOP Module/////////////

module usb2_cdr_top_sva #(
    parameter LS_DIV = 8
)(
    input logic       clk_sys,
    input logic       rstn,
    input logic [1:0] speed,
    input logic       ce,
    input logic recovered_bit_clk,
    input wire en_eff,
    input wire [1:0] fsm_state,
    input wire       locked,
    input wire gain_sel,
    input wire acc_reset,
    input wire loop_reset,
    input wire dp_out,
    input wire dm_out,
    input wire enable,
    input wire d_p_sync,
    input wire d_n_sync

);

    // TP_001: Verify clock enable is always high in FS mode.
    property p_tp_001_fs_ce;
        @(posedge clk_sys) disable iff (!rstn)
        (speed == 2'b01) |-> ce;
    endproperty

    a_tp_001_fs_ce:
        assert property (p_tp_001_fs_ce);

    // TP_002: Verify clock enable is generated once every 8 clocks in LS mode.
    property p_tp_002_ls_ce_period;
    @(posedge clk_sys)
    disable iff (!rstn || speed != 2'b00)

    ce |=> (!ce[*7] ##1 ce);
endproperty

a_tp_002_ls_ce_period:
    assert property (p_tp_002_ls_ce_period);
    
     // TP_003: Verify that the LS/FS CDR block remains idle in HS mode.
property p_tp_003_hs_idle;
    @(posedge clk_sys)
    disable iff (!rstn || speed != 2'b10)

    (speed == 2'b10)
    |=> (speed == 2'b10 && !locked && !recovered_bit_clk);
endproperty

a_tp_003_hs_idle:
    assert property (p_tp_003_hs_idle);


// TP_004: No recovered clock strobe in HS mode
property p_tp_004_hs_no_strobe;
    @(posedge clk_sys) disable iff (!rstn)
    (speed == 2'b10) |-> !recovered_bit_clk;
endproperty

a_tp_004_hs_no_strobe: assert property (p_tp_004_hs_no_strobe);

// TP_005: No recovered clock strobe when recovery is disabled
property p_tp_005_recovery_disabled;
    @(posedge clk_sys) disable iff (!rstn)
    (!en_eff && speed != 2'b10) |-> !recovered_bit_clk;
endproperty

a_tp_005_recovery_disabled:
    assert property (p_tp_005_recovery_disabled);

// TP_006: Reset clears lock status
property p_tp_006_reset_locked;
    @(posedge clk_sys)
    !rstn |-> !locked;
endproperty

a_tp_006_reset_locked:
    assert property (p_tp_006_reset_locked);

// TP_007: Lock must remain LOW during ACQUIRE
property p_tp_007_no_lock_during_acquire;
    @(posedge clk_sys) disable iff (!rstn)
    (fsm_state == 2'b01) |-> !locked;
endproperty

a_tp_007_no_lock_during_acquire:
    assert property (p_tp_007_no_lock_during_acquire);

// TP_008: Lock must be LOW during LOSS
property p_tp_008_no_lock_during_loss;
    @(posedge clk_sys) disable iff (!rstn)
    (fsm_state == 2'b11) |-> !locked;
endproperty

a_tp_008_no_lock_during_loss:
    assert property (p_tp_008_no_lock_during_loss);

// TP_009: Low gain must be selected during TRACK
property p_tp_009_track_low_gain;
    @(posedge clk_sys) disable iff (!rstn)
    (fsm_state == 2'b10) |-> (gain_sel == 1'b0);
endproperty

a_tp_009_track_low_gain:
    assert property (p_tp_009_track_low_gain);

// TP_010: Accumulator must be reset during LOSS
property p_tp_010_acc_reset_during_loss;
    @(posedge clk_sys) disable iff (!rstn)
    (fsm_state == 2'b11) |-> acc_reset;
endproperty

a_tp_010_acc_reset_during_loss:
    assert property (p_tp_010_acc_reset_during_loss);

// TP_011: Loop must not be reset during LOSS
property p_tp_011_loop_held_during_loss;
    @(posedge clk_sys) disable iff (!rstn)
    (fsm_state == 2'b11) |-> (loop_reset == 1'b0);
endproperty

a_tp_011_loop_held_during_loss:
    assert property (p_tp_011_loop_held_during_loss);

// TP_012: Loop reset must be asserted during IDLE
property p_tp_012_loop_reset_during_idle;
    @(posedge clk_sys) disable iff (!rstn)
    (fsm_state == 2'b00) |-> (loop_reset == 1'b1);
endproperty

a_tp_012_loop_reset_during_idle:
    assert property (p_tp_012_loop_reset_during_idle);

// TP_013: High gain must be selected during ACQUIRE
property p_tp_013_acquire_high_gain;
    @(posedge clk_sys) disable iff (!rstn)
    (fsm_state == 2'b01) |-> (gain_sel == 1'b1);
endproperty

a_tp_013_acquire_high_gain:
    assert property (p_tp_013_acquire_high_gain);

// TP_014: Lock must remain low during ACQUIRE
property p_tp_014_acquire_locked_low;
    @(posedge clk_sys) disable iff (!rstn)
    (fsm_state == 2'b01) |-> (locked == 1'b0);
endproperty

a_tp_014_acquire_locked_low:
    assert property (p_tp_014_acquire_locked_low);

// TP_015: DP/DM outputs must remain stable between strobes
property p_tp_015_dp_dm_hold;
    @(posedge clk_sys) disable iff (!rstn)
    !$past(recovered_bit_clk) |-> $stable({dp_out, dm_out});
endproperty

a_tp_015_dp_dm_hold:
    assert property (p_tp_015_dp_dm_hold);

// TP_016: DP/DM outputs must have specified reset values
property p_tp_016_dp_dm_reset;
    @(posedge clk_sys)
    (!rstn) |=> (dp_out == 1'b1 && dm_out == 1'b0);
endproperty

a_tp_016_dp_dm_reset:
    assert property (p_tp_016_dp_dm_reset);

// TP_017: Recovered bit clock must be one clk_sys cycle wide
property p_tp_017_recovered_clk_one_cycle;
    @(posedge clk_sys) disable iff (!rstn)
    recovered_bit_clk |=> !recovered_bit_clk;
endproperty

a_tp_017_recovered_clk_one_cycle:
    assert property (p_tp_017_recovered_clk_one_cycle);

// TP_018: Lock must be deasserted when recovery is disabled
property p_tp_018_lock_disabled;
    @(posedge clk_sys) disable iff (!rstn)
    (!enable) |=> (locked == 1'b0);
endproperty

a_tp_018_lock_disabled:
    assert property (p_tp_018_lock_disabled);

// TP_019: Lock must be LOW during reset
property p_tp_019_lock_reset;
    @(posedge clk_sys)
    !rstn |=> (locked == 1'b0);
endproperty

a_tp_019_lock_reset:
    assert property (p_tp_019_lock_reset);

// TP_020: DP/DM outputs must hold between strobes
property p_tp_020_dp_dm_hold;
    @(posedge clk_sys) disable iff (!rstn)
    (! $past(recovered_bit_clk)) |->
        ($stable(dp_out) && $stable(dm_out));
endproperty

a_tp_020_dp_dm_hold:
    assert property (p_tp_020_dp_dm_hold);

// TP_021: DP/DM outputs must have reset values
property p_tp_021_dp_dm_reset;
    @(posedge clk_sys)
    !rstn |=> (dp_out == 1'b1 && dm_out == 1'b0);
endproperty

a_tp_021_dp_dm_reset:
    assert property (p_tp_021_dp_dm_reset);

// TP_022: Lock must be asserted only in TRACK state
property p_tp_022_lock_only_track;
    @(posedge clk_sys) disable iff (!rstn)
    locked |-> (fsm_state == 2'd2);
endproperty

a_tp_022_lock_only_track:
    assert property (p_tp_022_lock_only_track);

// TP_023: Lock must be low when recovery is disabled
property p_tp_023_lock_disabled;
    @(posedge clk_sys) disable iff (!rstn)
    (!enable) |=> (!locked);
endproperty

a_tp_023_lock_disabled:
    assert property (p_tp_023_lock_disabled);

// TP_024: Recovered clock strobe must be one cycle wide
property p_tp_024_strobe_width;
    @(posedge clk_sys) disable iff (!rstn)
    ((speed == 2'b00 || speed == 2'b01) && recovered_bit_clk)
    |=> !recovered_bit_clk;
endproperty

a_tp_024_strobe_width:
    assert property (p_tp_024_strobe_width);

// TP_025: Lock must be low when recovery is disabled
property p_tp_025_lock_disabled;
    @(posedge clk_sys) disable iff (!rstn)
    (!enable) |=> !locked;
endproperty

a_tp_025_lock_disabled:
    assert property (p_tp_025_lock_disabled);

// TP_026: recovered_bit_clk must be a one-cycle pulse
property p_tp_026_recovered_clk_pulse;
    @(posedge clk_sys) disable iff (!rstn)
    recovered_bit_clk |=> !recovered_bit_clk;
endproperty

a_tp_026_recovered_clk_pulse:
    assert property (p_tp_026_recovered_clk_pulse);

// TP_027: Low gain and loop must remain active during LOCKED state
property p_tp_027_locked_control;
    @(posedge clk_sys) disable iff (!rstn)
    locked |-> (!gain_sel && !loop_reset);
endproperty

a_tp_027_locked_control:
    assert property (p_tp_027_locked_control);

// TP_028: Accumulator reset must not indicate lock
property p_tp_028_acc_reset_unlocked;
    @(posedge clk_sys) disable iff (!rstn)
    acc_reset |-> !locked;
endproperty

a_tp_028_acc_reset_unlocked:
    assert property (p_tp_028_acc_reset_unlocked);

// TP_029: DP/DM outputs capture synchronized line values after strobe
property p_tp_029_dp_dm_capture;
    @(posedge clk_sys) disable iff (!rstn)
    recovered_bit_clk |=> 
    (dp_out == $past(d_p_sync) &&
     dm_out == $past(d_n_sync));
endproperty

a_tp_029_dp_dm_capture:
    assert property (p_tp_029_dp_dm_capture);

// TP_030: IDLE control signals
property p_tp_030_idle_control;
    @(posedge clk_sys) disable iff (!rstn)
    loop_reset |-> (acc_reset && gain_sel && !locked);
endproperty

a_tp_030_idle_control:
    assert property (p_tp_030_idle_control);

// TP_030: IDLE control signals
property p_tp_030_idle_control;
    @(posedge clk_sys) disable iff (!rstn)
    loop_reset |-> (acc_reset && gain_sel && !locked);
endproperty

a_tp_030_idle_control:
    assert property (p_tp_030_idle_control);

// TP_031: High gain must be disabled during LOSS
property p_tp_031_loss_gain;
    @(posedge clk_sys) disable iff (!rstn)
    (acc_reset && !loop_reset) |-> (!gain_sel && !locked);
endproperty

a_tp_031_loss_gain:
    assert property (p_tp_031_loss_gain);
endmodule
bind usb2_cdr_top
usb2_cdr_top_sva #(
    .LS_DIV(LS_DIV)
) u_usb2_cdr_top_sva (.*);
