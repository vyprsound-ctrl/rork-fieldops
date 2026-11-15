import { format, isToday, isTomorrow, isYesterday } from "date-fns";

export const time = (iso: string | Date) => format(new Date(iso), "HH:mm");

export const timeRange = (start: string | null, end: string | null) => {
  if (!start) return "Unscheduled";
  return end ? `${time(start)}–${time(end)}` : time(start);
};

export const dayTitle = (d: Date) => {
  if (isToday(d)) return "Today";
  if (isTomorrow(d)) return "Tomorrow";
  if (isYesterday(d)) return "Yesterday";
  return format(d, "EEE d MMM");
};

export const dayAndTime = (iso: string | null) => (iso ? `${dayTitle(new Date(iso))} · ${time(iso)}` : "Unscheduled");

export const shortDate = (iso: string | Date) => format(new Date(iso), "d MMM yyyy");

export const relativeAgo = (iso: string) => {
  const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} h ago`;
  return shortDate(iso);
};

export const money = (value: number, currency: string) => {
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency, maximumFractionDigits: 0 }).format(value);
  } catch {
    return `${currency} ${Math.round(value).toLocaleString()}`;
  }
};

/** Exact amounts for quotes, invoices and payments. */
export const money2 = (value: number, currency: string) => {
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency, minimumFractionDigits: 2 }).format(value);
  } catch {
    return `${currency} ${value.toFixed(2)}`;
  }
};

/** A YYYY-MM-DD date shown without timezone drift. */
export const dateOnly = (ymd: string | null) => (ymd ? format(new Date(`${ymd.slice(0, 10)}T12:00:00`), "d MMM yyyy") : "—");

export const todayYmd = () => format(new Date(), "yyyy-MM-dd");

/** For a datetime-local input. */
export const toLocalInput = (iso: string | null) => (iso ? format(new Date(iso), "yyyy-MM-dd'T'HH:mm") : "");

export const fromLocalInput = (value: string) => (value ? new Date(value).toISOString() : null);
