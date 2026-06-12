import time

class OXsteamMassBalanceTracker:
    def __init__(self):
        # Target System Metrics (kg/hour) based on 1000 kg/hr wet slurry baseline
        self.target_intake_mass_rate = 1000.0  
        self.target_oxide_mass_rate = 50.0     
        self.target_gas_mass_rate = 150.0      
        self.target_water_mass_rate = 800.0    
        
        # System Tolerance Bounds (Allow 3% deviation for sensor noise)
        self.allowable_error_margin = 0.03 

    def calculate_mass_deviation(self, active_intake, active_gas, active_water, active_oxide_batch_weight, cycles_per_hour):
        """
        Computes real-time mass balance: Input Mass must equal Output Mass.
        Outputs are measured continuously except oxides, which are calculated via batch dumps.
        """
        # Convert periodic oxide batch dumps to an hourly mass rate
        calculated_oxide_hourly_rate = active_oxide_batch_weight * cycles_per_hour
        
        total_input_rate = active_intake
        total_output_rate = active_gas + active_water + calculated_oxide_hourly_rate
        
        # Compute absolute mass differential
        mass_differential = total_input_rate - total_output_rate
        percent_error = abs(mass_differential) / total_input_rate if total_input_rate > 0 else 0.0
        
        # Check system safety parameters
        system_alert = False
        alert_message = "SYSTEM BALANCED: Steady state maintained."
        
        if percent_error > self.allowable_error_margin:
            system_alert = True
            if mass_differential > 0:
                alert_message = f"CRITICAL FAULT: Mass Loss Detected ({mass_differential:.2f} kg/hr). Potential system leak or internal scaling clog."
            else:
                alert_message = f"CRITICAL FAULT: Mass Surplus Detected ({abs(mass_differential):.2f} kg/hr). Check flow sensor calibration thresholds."
                
        return {
            "Total_Input_kg_hr": total_input_rate,
            "Total_Output_kg_hr": total_output_rate,
            "Mass_Differential": mass_differential,
            "Deviation_Percent": percent_error * 100,
            "Alert_Triggered": system_alert,
            "Status_Message": alert_message
        }

# --- Quick Unit Test Execution ---
if __name__ == "__main__":
    tracker = OXsteamMassBalanceTracker()
    
    # Test Case 1: Healthy running state (25 kg per dump, 2 dumps per hour = 50 kg/hr)
    print("--- Running Test 1: Normal Equilibrium Operations ---")
    metrics = tracker.calculate_mass_deviation(
        active_intake=1000.0, 
        active_gas=151.0, 
        active_water=798.0, 
        active_oxide_batch_weight=25.0, 
        cycles_per_hour=2
    )
    print(f"Status: {metrics['Status_Message']} (Deviation: {metrics['Deviation_Percent']:.2f}%)")

    # Test Case 2: Simulating an active leak or a core pressure drop
    print("\n--- Running Test 2: Simulating Low Gas Extraction (Leak/Clog) ---")
    fault_metrics = tracker.calculate_mass_deviation(
        active_intake=1000.0, 
        active_gas=90.0, # Dangerous drop in gas flow
        active_water=800.0, 
        active_oxide_batch_weight=25.0, 
        cycles_per_hour=2
    )
    print(f"Status: {fault_metrics['Status_Message']}")
