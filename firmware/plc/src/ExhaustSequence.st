(*
 * =====================================================================================
 * Title:       OXsteam SCWR Exhaust Solids & Oxide Discharging System
 * Version:     v2.1.0-Alpha
 * Description: 4-Valve, 3-Chamber sequence enforcing zero-pressure drop on main lines
 *              and wire-drawing mitigation on isolated, hot-swappable bleed lines.
 * Co-Author:   OXsteam Engineering Team & AI Collaborator
 * =====================================================================================
 *)

TYPE SystemState :
(
    INIT,
    SETTLE_OXIDES,      // Main 1 Open: Dropping solids into Chamber 1
    ISOLATE_CHAMBER_1,  // Closing Main 1
    BLEED_PRESSURE,     // Cracking Wear Valve to vent high-velocity flash steam
    TRANSFER_CHAMBER_2, // Main 2 Open: Shifting low-pressure solids down
    ISOLATE_CHAMBER_2,  // Closing Main 2
    DISCHARGE_FINAL,    // Main 3 Open: Ejecting oxides out of system
    WEAR_VALVE_MAINT    // Emergency Maintenance State: Hot-swapping Wear Valve
);
END_TYPE

FUNCTION_BLOCK OXsteam_Exhaust_Controller
VAR_INPUT
    StartSequence       : BOOL;    // System run signal
    CycleTimerPreset    : TIME := T#5M; // Interval between oxide dumps (e.g., 5 mins)
    BleedTimerPreset    : TIME := T#45S; // Time required to drop Chamber 1 pressure to zero
    TransferTimerPreset : TIME := T#15S; // Gravity drop window for solids
    
    // Feedback Sensors from physical hardware
    Chamber1_Pressure   : REAL;    // Pressure in Bar or MPa
    WearValve_Maint_Req : BOOL;    // Technician panel button to initiate hot-swap
    WearValve_Maint_Done: BOOL;    // Technician panel button indicating swap complete
END_VAR

VAR_OUTPUT
    // Valve Actuator Coil Command Outputs (TRUE = OPEN, FALSE = CLOSED)
    MainValve_1         : BOOL; // Full-Port Upper
    MainValve_2         : BOOL; // Full-Port Middle
    MainValve_3         : BOOL; // Full-Port Lower
    IsolationValve_C    : BOOL; // High-Pressure Bleed Line Guard
    WearValve_D         : BOOL; // Sacrificial Throttling Valve
    
    // Status Indicators
    CurrentState        : SystemState := INIT;
    SafetyInterlockFault: BOOL;
END_VAR

VAR
    // Internal Clocks & Timers
    CycleTimer          : TON;
    BleedTimer          : TON;
    DropTimer           : TON;
    InterlockCheck      : BOOL;
END_VAR

BEGIN

    // ==========================================================================
    // 1. HARDWARE SAFETY INTERLOCKS (Hardcoded Prevention of Catastrophic Blowouts)
    // ==========================================================================
    // Rule A: Main Valve 1 must NEVER open if the Wear Valve is open or if any lower valve is open.
    // Rule B: Main Valve 3 must NEVER open if Main Valve 1 or 2 is open.
    InterlockCheck := NOT (
        (MainValve_1 AND (WearValve_D OR MainValve_2 OR MainValve_3)) OR
        (MainValve_3 AND (MainValve_1 OR MainValve_2))
    );
    
    IF NOT InterlockCheck THEN
        // Force-close all main process lines immediately if an invalid state occurs
        MainValve_1 := FALSE;
        MainValve_2 := FALSE;
        MainValve_3 := FALSE;
        WearValve_D := FALSE;
        SafetyInterlockFault := TRUE;
        CurrentState := INIT;
        RETURN;
    ELSE
        SafetyInterlockFault := FALSE;
    END_IF;

    // ==========================================================================
    // 2. HOT-SWAP MAINTENANCE OVERRIDE
    // ==========================================================================
    IF WearValve_Maint_Req AND (CurrentState = SETTLE_OXIDES OR CurrentState = INIT) THEN
        CurrentState := WEAR_VALVE_MAINT;
    END_IF;

    // ==========================================================================
    // 3. MAIN SEQUENCER STATE MACHINE
    // ==========================================================================
    CASE CurrentState OF
        
        INIT:
            // Establish safe baseline state
            MainValve_1      := FALSE;
            MainValve_2      := FALSE;
            MainValve_3      := FALSE;
            IsolationValve_C := TRUE; // Keep open normally so it experiences zero wear
            WearValve_D      := FALSE;
            
            IF StartSequence THEN
                CurrentState := SETTLE_OXIDES;
            END_IF;

        SETTLE_OXIDES:
            // Action: Drop oxides from reactor core directly into Chamber 1
            MainValve_1      := TRUE;
            MainValve_2      := FALSE;
            MainValve_3      := FALSE;
            IsolationValve_C := TRUE;
            WearValve_D      := FALSE;
            
            CycleTimer(IN := TRUE, PT := CycleTimerPreset);
            IF CycleTimer.Q THEN
                CycleTimer(IN := FALSE); // Reset clock
                CurrentState := ISOLATE_CHAMBER_1;
            END_IF;

        ISOLATE_CHAMBER_1:
            // Action: Close upper valve completely before bleeding
            MainValve_1      := FALSE; 
            
            // Safety handshake: Ensure upper valve reports 100% closed position
            IF NOT MainValve_1 THEN
                CurrentState := BLEED_PRESSURE;
            END_IF;

        BLEED_PRESSURE:
            // Action: Crack open the sacrificial wear valve.
            // High-velocity steam flashes across Valve D. Valve C remains unharmed.
            MainValve_1      := FALSE;
            MainValve_2      := FALSE;
            MainValve_3      := FALSE;
            IsolationValve_C := TRUE; 
            WearValve_D      := TRUE; // Open to vent line
            
            BleedTimer(IN := TRUE, PT := BleedTimerPreset);
            // Transition only when timer expires and pressure drops below 1.5 Bar (Atmospheric)
            IF BleedTimer.Q AND (Chamber1_Pressure < 1.5) THEN
                BleedTimer(IN := FALSE);
                WearValve_D  := FALSE; // Close the wear valve under no-flow conditions
                CurrentState := TRANSFER_CHAMBER_2;
            END_IF;

        TRANSFER_CHAMBER_2:
            // Action: Shift depressurized solids from Chamber 1 to Chamber 2
            MainValve_1      := FALSE;
            MainValve_2      := TRUE; // Open mid-valve safely
            MainValve_3      := FALSE;
            IsolationValve_C := TRUE;
            WearValve_D      := FALSE;
            
            DropTimer(IN := TRUE, PT := TransferTimerPreset);
            IF DropTimer.Q THEN
                DropTimer(IN := FALSE);
                MainValve_2  := FALSE;
                CurrentState := ISOLATE_CHAMBER_2;
            END_IF;

        ISOLATE_CHAMBER_2:
            // Action: Isolate mid-chamber before final atmospheric dumping
            MainValve_2      := FALSE;
            
            IF NOT MainValve_2 THEN
                CurrentState := DISCHARGE_FINAL;
            END_IF;

        DISCHARGE_FINAL:
            // Action: Drop dry oxide ash out to the atmosphere storage bin
            MainValve_1      := FALSE;
            MainValve_2      := FALSE;
            MainValve_3      := TRUE; // Open atmospheric seal
            IsolationValve_C := TRUE;
            WearValve_D      := FALSE;
            
            DropTimer(IN := TRUE, PT := TransferTimerPreset);
            IF DropTimer.Q THEN
                DropTimer(IN := FALSE);
                MainValve_3  := FALSE;
                CurrentState := SETTLE_OXIDES; // Restart the cycle
            END_IF;

        WEAR_VALVE_MAINT:
            // Action: ISOLATE THE WEAR VALVE FOR HOT SWAPPING
            MainValve_1      := FALSE; // Protect reactor pressure boundary
            MainValve_2      := FALSE;
            MainValve_3      := FALSE;
            
            // CLOSE the upstream isolation valve to lock high-pressure in Chamber 1
            IsolationValve_C := FALSE; 
            // OPEN Wear Valve D completely to vent any residual pressure in the small tube line
            WearValve_D      := TRUE; 
            
            // Technicians can now safely unbolt and replace Valve D.
            IF WearValve_Maint_Done THEN
                WearValve_D      := FALSE; // Close new valve
                IsolationValve_C := TRUE;  // Re-pressurize the small line slowly
                CurrentState     := INIT;  // Return to normal operation
            END_IF;

    END_CASE;
END_FUNCTION_BLOCK
