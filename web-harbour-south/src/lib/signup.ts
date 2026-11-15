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

/** Where the company works; sets the currency used on its quotes and invoices. */
export const COUNTRY_OPTIONS: { code: string; label: string; currency: string }[] = [
  { code: "US", label: "United States", currency: "USD" },
  { code: "CA", label: "Canada", currency: "CAD" },
  { code: "GB", label: "United Kingdom", currency: "GBP" },
  { code: "IE", label: "Ireland", currency: "EUR" },
  { code: "AU", label: "Australia", currency: "AUD" },
  { code: "NZ", label: "New Zealand", currency: "NZD" },
];

export const localTimeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone || "America/New_York";
