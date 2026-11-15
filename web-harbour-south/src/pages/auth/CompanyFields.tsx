import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { COUNTRY_OPTIONS, TRADE_OPTIONS } from "@/lib/signup";

export interface CompanyDraft {
  ownerName: string;
  companyName: string;
  trade: string;
  country: string;
}

export const EMPTY_COMPANY: CompanyDraft = { ownerName: "", companyName: "", trade: "hvac", country: "US" };

export function CompanyFields({ value, onChange }: { value: CompanyDraft; onChange: (next: CompanyDraft) => void }) {
  const set = (patch: Partial<CompanyDraft>) => onChange({ ...value, ...patch });
  return (
    <>
      <div className="space-y-2">
        <Label htmlFor="owner">Your name</Label>
        <Input
          id="owner"
          autoComplete="name"
          required
          value={value.ownerName}
          onChange={(e) => set({ ownerName: e.target.value })}
          className="h-12 bg-card text-[15px]"
        />
      </div>
      <div className="space-y-2">
        <Label htmlFor="company">Company name</Label>
        <Input
          id="company"
          autoComplete="organization"
          required
          value={value.companyName}
          onChange={(e) => set({ companyName: e.target.value })}
          className="h-12 bg-card text-[15px]"
        />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-2">
          <Label>Trade</Label>
          <Select value={value.trade} onValueChange={(trade) => set({ trade })}>
            <SelectTrigger className="h-12 bg-card text-[15px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {TRADE_OPTIONS.map((t) => (
                <SelectItem key={t.id} value={t.id}>
                  {t.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2">
          <Label>Country</Label>
          <Select value={value.country} onValueChange={(country) => set({ country })}>
            <SelectTrigger className="h-12 bg-card text-[15px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {COUNTRY_OPTIONS.map((c) => (
                <SelectItem key={c.code} value={c.code}>
                  {c.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>
    </>
  );
}

export function setupFrom(draft: CompanyDraft, timeZone: string) {
  const country = COUNTRY_OPTIONS.find((c) => c.code === draft.country) ?? COUNTRY_OPTIONS[0];
  return {
    company_name: draft.companyName.trim(),
    trade: draft.trade,
    country_code: country.code,
    currency_code: country.currency,
    time_zone_identifier: timeZone,
    owner_name: draft.ownerName.trim(),
  };
}
