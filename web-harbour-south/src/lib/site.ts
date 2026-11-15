/**
 * Which face of the site to show. harboursouth.us (and www) is the public
 * marketing site; every other host (app.harboursouth.us, field-ops.rork.app,
 * previews) is the office web app.
 */
const MARKETING_HOSTS = new Set(["harboursouth.us", "www.harboursouth.us"]);

export const isMarketingHost = (): boolean =>
  typeof window !== "undefined" && MARKETING_HOSTS.has(window.location.hostname);

/** Where the office web app lives. Switch to https://app.harboursouth.us once its DNS record is live. */
export const OFFICE_APP_URL = "https://field-ops.rork.app";

export const APP_STORE_URL = "https://apps.apple.com/app/id6809271972";

/** Mirrors HarbourSouthLegalContactEmail in the iPhone app's Info.plist. */
export const LEGAL_CONTACT_EMAIL = "noreply@harboursouth.us";

export const LEGAL_LAST_UPDATED = "September 24, 2026";

export const LEGAL_PATHS = {
  privacy: "/privacy-policy",
  terms: "/terms-of-service",
  sms: "/sms-messaging-terms",
  deletion: "/account-data-deletion",
} as const;
