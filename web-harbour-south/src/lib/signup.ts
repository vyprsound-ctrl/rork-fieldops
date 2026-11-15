/** Trades the server accepts (app_trade), labelled like the iPhone app. */
export const TRADE_OPTIONS: { id: string; label: string }[] = [
  { id: "hvac", label: "HVAC" },
  { id: "plumbing", label: "Plumbing" },
  { id: "electrical", label: "Electrical" },
  { id: "roofing", label: "Roofing" },
  { id: "applianceRepair", label: "Appliance repair" },
  { id: "locksmith", label: "Locksmith" },
  { id: "generalMaintenance", label: "General maintenance" },
  { id: "pestControl", label: "Pest control" },
  { id: "propertyServices", label: "Property services" },
  { id: "automotive", label: "Automotive" },
  { id: "other", label: "Other" },
];

/** Where the company works; sets the currency used on its quotes and invoices. US only for now. */
export const COUNTRY_OPTIONS: { code: string; label: string; currency: string }[] = [
  { code: "US", label: "United States", currency: "USD" },
];

/** The browser's time zone when it's a US one, otherwise US Eastern (the owner can change it later). */
export const localTimeZone = () => {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone ?? "";
  return /^(America|Pacific\/Honolulu|US\/)/.test(tz) ? tz : "America/New_York";
};
