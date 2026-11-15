import { supabase } from "./supabase";
import { AppError, rows, translate } from "./api";

export interface Vehicle {
  id: string;
  customer_id: string;
  registration: string;
  vin: string;
  make: string;
  model: string;
  created_at: string;
}

export async function vehicles(): Promise<Vehicle[]> {
  const list = await rows<Vehicle>(
    supabase.from("vehicles").select("id,customer_id,registration,vin,make,model,created_at"),
  );
  return list.sort((a, b) => b.created_at.localeCompare(a.created_at));
}

export async function vehicleJobCounts(): Promise<Map<string, number>> {
  const list = await rows<{ vehicle_id: string | null }>(
    supabase.from("jobs").select("vehicle_id").not("vehicle_id", "is", null),
  ).catch(() => [] as { vehicle_id: string | null }[]);
  const map = new Map<string, number>();
  for (const j of list) if (j.vehicle_id) map.set(j.vehicle_id, (map.get(j.vehicle_id) ?? 0) + 1);
  return map;
}

export interface VehicleDraft {
  id: string | null;
  customerId: string;
  registration: string;
  vin: string;
  make: string;
  model: string;
}

export const vehicleTitle = (v: Pick<Vehicle, "make" | "model" | "registration">) =>
  [v.make, v.model].filter((s) => s.trim()).join(" ") || v.registration || "Vehicle";

export async function saveVehicle(companyId: string, userId: string, d: VehicleDraft): Promise<string> {
  if (!d.customerId) throw new AppError("Choose a customer.");
  const registration = d.registration.trim().toUpperCase();
  const vin = d.vin.trim().toUpperCase();
  if (!registration && !vin) throw new AppError("Enter a plate or a VIN.");
  if (vin && !/^[A-HJ-NPR-Z0-9]{11,17}$/.test(vin)) throw new AppError("A VIN is 11–17 letters and numbers (no I, O or Q).");
  const payload = {
    customer_id: d.customerId,
    registration,
    vin,
    make: d.make.trim(),
    model: d.model.trim(),
    updated_at: new Date().toISOString(),
  };
  if (d.id) {
    const { error } = await supabase.from("vehicles").update(payload).eq("id", d.id);
    if (error) throw translate(error);
    return d.id;
  }
  const { data, error } = await supabase
    .from("vehicles")
    .insert({ ...payload, company_id: companyId, created_by_user_id: userId })
    .select("id")
    .single();
  if (error) throw translate(error);
  return (data as { id: string }).id;
}
