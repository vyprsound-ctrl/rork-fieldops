/**
 * harboursouth.us serves both faces of Harbour South from one site:
 *  - the public website (landing, pricing, contact, legal) at the root, and
 *  - the office web app under /app.
 */
export const APP_BASE = "/app";

export const isAppPath = (pathname: string): boolean => pathname === APP_BASE || pathname.startsWith(`${APP_BASE}/`);

/** Where "Log in" goes: the office app on this same domain. */
export const OFFICE_APP_URL = APP_BASE;

export const APP_STORE_URL = "https://apps.apple.com/app/id6809271972";

/** Public support and legal contact. */
export const CONTACT_EMAIL = "help@harboursouth.us";
export const LEGAL_CONTACT_EMAIL = CONTACT_EMAIL;

export const LEGAL_LAST_UPDATED = "September 24, 2026";

export const LEGAL_PATHS = {
  privacy: "/privacy-policy",
  terms: "/terms-of-service",
  sms: "/sms-messaging-terms",
  deletion: "/account-data-deletion",
} as const;

export const CONTACT_PATH = "/contact";
