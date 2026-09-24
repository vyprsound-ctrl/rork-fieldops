import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  attachNumberToService,
  ensureMessagingService,
  ensureSubaccount,
  fetchBrand,
  fetchCampaign,
  friendlyTwilioError,
  listIncomingNumbers,
  masterConfig,
  MESSAGING,
  POLICY,
  purchaseNumber,
  TRUST_HUB,
  trustHubAssign,
  trustHubCreate,
  trustHubEvaluateAndSubmit,
  TWILIO_API,
  twilioRequest,
  TwilioError,
  type TwilioCredentials,
} from "./twilio.ts";

/// Resumable, idempotent provisioning of ONE company's messaging stack.
///
/// Each step checks what already exists (on Twilio and in the database)
/// before creating anything, and records itself in
/// `messaging_provisioning_events`. A crash, timeout or transient Twilio
/// error leaves the account on the step it reached; the next run (owner
/// "Retry" or the maintenance tick) continues from there. Permanent 4xx
/// errors stop and are shown to the owner in plain words — never retried
/// automatically.
///
/// Steps: subaccount -> messaging_service -> number -> registration
///        (customer profile, trust product, brand) -> campaign -> active.
/// SMS only becomes sendable when Twilio reports the campaign VERIFIED.

export interface BusinessDetails {
  route: "standard" | "low_volume" | "sole_proprietor";
  legal_name: string;
  business_type?: string;
  ein?: string;
  website?: string;
  industry?: string;
  street: string;
  street2?: string;
  city: string;
  state: string;
  postal_code: string;
  rep_first_name: string;
  rep_last_name: string;
  rep_title?: string;
  rep_position?: string;
  rep_email: string;
  rep_phone: string;
  contact_name?: string;
  contact_phone?: string;
  contact_email?: string;
  use_case_description?: string;
  opt_in_description: string;
  sample_messages?: string[];
  mobile_phone?: string;
}

// deno-lint-ignore no-explicit-any
type Account = Record<string, any>;

async function logEvent(
  admin: SupabaseClient,
  account: Account,
  operation: string,
  stage: string,
  outcome: "started" | "succeeded" | "failed" | "skipped",
  extra: { reference?: string | null; code?: string | null; message?: string | null; key?: string | null } = {},
): Promise<void> {
  await admin.from("messaging_provisioning_events").upsert({
    company_id: account.company_id,
    messaging_account_id: account.id,
    operation,
    stage,
    outcome,
    provider_reference: extra.reference ?? null,
    error_code: extra.code ?? null,
    error_message: extra.message ? extra.message.slice(0, 500) : null,
    idempotency_key: extra.key ?? null,
  }, { onConflict: "idempotency_key", ignoreDuplicates: true });
}

async function update(admin: SupabaseClient, accountId: string, patch: Record<string, unknown>): Promise<void> {
  await admin.from("company_messaging_accounts").update({ ...patch, updated_at: new Date().toISOString() }).eq("id", accountId);
}

async function subaccountCredentials(admin: SupabaseClient, account: Account): Promise<TwilioCredentials | null> {
  if (!account.twilio_subaccount_sid) return null;
  const { data } = await admin.rpc("messaging_subaccount_token", { p_account: account.id });
  return typeof data === "string" && data ? { accountSid: account.twilio_subaccount_sid, authToken: data } : null;
}

const INDUSTRY: Record<string, string> = {
  hvac: "CONSTRUCTION", plumbing: "CONSTRUCTION", electrical: "CONSTRUCTION", roofing: "CONSTRUCTION",
  applianceRepair: "PROFESSIONAL_SERVICES", locksmith: "PROFESSIONAL_SERVICES",
  generalMaintenance: "PROFESSIONAL_SERVICES", pestControl: "PROFESSIONAL_SERVICES", other: "PROFESSIONAL_SERVICES",
};

export function defaultSampleMessages(companyName: string): string[] {
  return [
    `${companyName}: Hi Jane, your appointment is confirmed for Tue, Oct 6 at 9:00 AM (job J-1047). Reply STOP to opt out.`,
    `${companyName}: Mike is on the way to you now.`,
    `${companyName}: Invoice INV-2041 for $240.00 is ready. View and pay: https://example.com/i Reply STOP to opt out.`,
  ];
}

/// Validates owner-supplied details. Returns the first problem, or null.
/// Nothing is invented: every required field must come from the owner.
export function detailsProblem(d: Partial<BusinessDetails>): string | null {
  const req = (v: unknown) => typeof v === "string" && v.trim().length > 0;
  if (!d.route || !["standard", "low_volume", "sole_proprietor"].includes(d.route)) return "Choose your business type.";
  if (!req(d.legal_name)) return "Enter your legal business name.";
  if (!req(d.street) || !req(d.city) || !req(d.state) || !req(d.postal_code)) return "Enter your full business address.";
  if (!/^[A-Za-z]{2}$/.test(String(d.state ?? "").trim())) return "Use the two-letter state code, like FL.";
  if (!/^\d{5}(-\d{4})?$/.test(String(d.postal_code ?? "").trim())) return "Enter a valid ZIP code.";
  if (!req(d.rep_first_name) || !req(d.rep_last_name)) return "Enter the authorized representative's name.";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(d.rep_email ?? ""))) return "Enter a valid email for the representative.";
  if (!/^\+?[0-9()\s.-]{10,20}$/.test(String(d.rep_phone ?? ""))) return "Enter a valid phone number for the representative.";
  if (!req(d.opt_in_description) || String(d.opt_in_description).trim().length < 40) {
    return "Describe how customers agree to receive texts (at least a sentence).";
  }
  if (d.route === "sole_proprietor") {
    if (!/^\+?[0-9()\s.-]{10,20}$/.test(String(d.mobile_phone ?? ""))) {
      return "Enter the owner's own mobile number — it receives a one-time verification text.";
    }
  } else {
    if (!req(d.business_type)) return "Choose your company structure.";
    if (!/^\d{2}-?\d{7}$/.test(String(d.ein ?? "").trim())) return "Enter your 9-digit EIN, like 12-3456789.";
    if (!/^https?:\/\/[^\s.]+\.[^\s]{2,}/i.test(String(d.website ?? "").trim())) {
      return "Enter your business website (carriers review it).";
    }
  }
  return null;
}

function e164(raw: string): string {
  const digits = raw.replace(/[^0-9]/g, "");
  return raw.trim().startsWith("+") ? `+${digits}` : digits.length === 10 ? `+1${digits}` : `+${digits}`;
}

export interface StepOutcome {
  account: Account;
  done: boolean;
  error?: string;
  numberUnavailable?: boolean;
}

/// Runs provisioning forward as far as it can in one invocation.
export async function advanceProvisioning(admin: SupabaseClient, accountId: string): Promise<StepOutcome> {
  const config = masterConfig();
  let { data: account } = await admin.from("company_messaging_accounts").select("*").eq("id", accountId).maybeSingle();
  if (!account) return { account: {}, done: false, error: "Unknown messaging account." };
  if (!["provisioning", "awaiting_registration"].includes(account.status)) return { account, done: true };
  if (!config) {
    await update(admin, account.id, { last_error: "SMS isn't available yet. Harbour South is finishing its setup.", last_error_at: new Date().toISOString() });
    return { account, done: false, error: "SMS isn't available yet." };
  }

  const { data: company } = await admin.from("companies").select("id, name, trade, closed_at").eq("id", account.company_id).maybeSingle();
  if (!company || company.closed_at) return { account, done: true };
  const details = account.business_details as BusinessDetails;

  const step = async (name: string, fn: () => Promise<void>) => {
    await logEvent(admin, account!, "provision", name, "started");
    await fn();
    await logEvent(admin, account!, "provision", name, "succeeded", { key: `${account!.id}:${name}:ok` });
  };

  try {
    // 1. Subaccount (deterministic name -> never duplicated)
    if (!account.twilio_subaccount_sid) {
      await step("subaccount", async () => {
        const sub = await ensureSubaccount(config.master, company.id);
        await admin.rpc("messaging_store_subaccount_token", { p_account: account!.id, p_token: sub.auth_token });
        await update(admin, account!.id, { twilio_subaccount_sid: sub.sid, provisioning_step: "messaging_service" });
        account!.twilio_subaccount_sid = sub.sid;
      });
    }
    const sub = await subaccountCredentials(admin, account);
    if (!sub) throw new Error("subaccount token missing");

    // 2. Messaging Service (per company, callbacks carry the company key)
    if (!account.messaging_service_sid) {
      await step("messaging_service", async () => {
        const service = await ensureMessagingService(sub, company.id, account!.callback_key);
        await update(admin, account!.id, { messaging_service_sid: service.sid, provisioning_step: "number" });
        account!.messaging_service_sid = service.sid;
      });
    }

    // 3. Number (credits never charged for a number that wasn't bought)
    const { data: existingNumber } = await admin.from("company_phone_numbers").select("id, phone_number_sid, e164")
      .eq("company_id", company.id).neq("status", "released").maybeSingle();
    if (!existingNumber) {
      if (!account.requested_number) {
        await update(admin, account.id, { provisioning_step: "number_unavailable" });
        return { account, done: false, numberUnavailable: true, error: "Choose a number to continue." };
      }
      await logEvent(admin, account, "provision", "number", "started", { reference: account.requested_number });
      const owned = (await listIncomingNumbers(sub)).find((n) => n.phone_number === account!.requested_number);
      let bought = owned ?? null;
      if (!bought) {
        try {
          bought = await purchaseNumber(sub, account.requested_number, company.id);
        } catch (err) {
          if (err instanceof TwilioError && (err.code === "21422" || err.code === "21452")) {
            await update(admin, account.id, { provisioning_step: "number_unavailable", requested_number: null,
              last_error: "That number was just taken by someone else. Choose another number.",
              last_error_at: new Date().toISOString() });
            await logEvent(admin, account, "provision", "number", "failed", { code: err.code, message: err.message });
            return { account, done: false, numberUnavailable: true, error: "That number was just taken. Choose another number." };
          }
          throw err;
        }
      }
      const digits = bought.phone_number.replace(/[^0-9]/g, "");
      await admin.rpc("sms_record_number_purchase", {
        p_account: account.id, p_sid: bought.sid, p_e164: bought.phone_number,
        p_area: digits.length === 11 ? digits.slice(1, 4) : null, p_locality: null, p_region: null,
      });
      await attachNumberToService(sub, account.messaging_service_sid, bought.sid);
      await logEvent(admin, account, "provision", "number", "succeeded", { reference: bought.sid, key: `${account.id}:number:${bought.sid}` });
      await update(admin, account.id, { provisioning_step: "registration", last_error: null });
    } else if (existingNumber.phone_number_sid) {
      await attachNumberToService(sub, account.messaging_service_sid, existingNumber.phone_number_sid);
    }

    // 4. Registration: the COMPANY'S identity, submitted by the owner.
    const soleProp = details.route === "sole_proprietor";
    const email = config.notificationEmail ?? details.rep_email;
    const statusCallback = `${config.callbackBase}/sms-maintenance?event=trusthub`;

    if (!account.customer_profile_sid) {
      await step("customer_profile", async () => {
        const profile = await trustHubCreate(sub, "CustomerProfiles", {
          FriendlyName: `${company.name}`.slice(0, 64), Email: email,
          PolicySid: soleProp ? POLICY.starterCustomerProfile : POLICY.secondaryCustomerProfile,
          StatusCallback: statusCallback,
        });
        const bundle = `CustomerProfiles/${profile.sid}`;
        let endUser: { sid: string };
        let rep: { sid: string } | null = null;
        if (soleProp) {
          endUser = await trustHubCreate(sub, "EndUsers", {
            Type: "starter_customer_profile_information", FriendlyName: `${company.name} owner`.slice(0, 64),
            Attributes: JSON.stringify({ first_name: details.rep_first_name, last_name: details.rep_last_name,
              email: details.rep_email, phone_number: e164(details.rep_phone) }),
          });
        } else {
          endUser = await trustHubCreate(sub, "EndUsers", {
            Type: "customer_profile_business_information", FriendlyName: `${company.name} business`.slice(0, 64),
            Attributes: JSON.stringify({
              business_name: details.legal_name, business_type: details.business_type,
              business_industry: details.industry || INDUSTRY[company.trade] || "PROFESSIONAL_SERVICES",
              business_registration_identifier: "EIN",
              business_registration_number: String(details.ein).replace(/^(\d{2})-?(\d{7})$/, "$1-$2"),
              business_identity: "direct_customer", business_regions_of_operation: "USA_AND_CANADA",
              website_url: details.website,
            }),
          });
          rep = await trustHubCreate(sub, "EndUsers", {
            Type: "authorized_representative_1", FriendlyName: `${details.rep_first_name} ${details.rep_last_name}`.slice(0, 64),
            Attributes: JSON.stringify({ first_name: details.rep_first_name, last_name: details.rep_last_name,
              email: details.rep_email, phone_number: e164(details.rep_phone),
              business_title: details.rep_title || "Owner", job_position: details.rep_position || "CEO" }),
          });
        }
        const address = await twilioRequest<{ sid: string }>(sub, `${TWILIO_API}/Accounts/${sub.accountSid}/Addresses.json`, {
          params: { CustomerName: details.legal_name, Street: details.street, StreetSecondary: details.street2 || undefined,
            City: details.city, Region: details.state.toUpperCase(), PostalCode: details.postal_code, IsoCountry: "US" },
        });
        const document = await trustHubCreate(sub, "SupportingDocuments", {
          Type: "customer_profile_address", FriendlyName: `${company.name} address`.slice(0, 64),
          Attributes: JSON.stringify({ address_sids: address.sid }),
        });
        await trustHubAssign(sub, bundle, endUser.sid);
        if (rep) await trustHubAssign(sub, bundle, rep.sid);
        await trustHubAssign(sub, bundle, document.sid);
        if (config.primaryCustomerProfileSid) await trustHubAssign(sub, bundle, config.primaryCustomerProfileSid);
        const evaluation = await trustHubEvaluateAndSubmit(sub, bundle,
          soleProp ? POLICY.starterCustomerProfile : POLICY.secondaryCustomerProfile);
        await update(admin, account!.id, {
          customer_profile_sid: profile.sid, business_end_user_sid: endUser.sid, representative_end_user_sid: rep?.sid ?? null,
          address_sid: address.sid, supporting_document_sid: document.sid, registration_status: "submitted",
          registration_error: evaluation.compliant ? null : evaluation.detail,
        });
        account!.customer_profile_sid = profile.sid;
        if (!evaluation.compliant) throw new TwilioError(evaluation.detail ?? "profile incomplete", 400, "profileIncomplete");
      });
    }

    if (!account.trust_product_sid) {
      await step("trust_product", async () => {
        const product = await trustHubCreate(sub, "TrustProducts", {
          FriendlyName: `${company.name} A2P`.slice(0, 64), Email: email,
          PolicySid: soleProp ? POLICY.soleProprietorTrustProduct : POLICY.a2pMessagingProfile, StatusCallback: statusCallback,
        });
        const endUser = soleProp
          ? await trustHubCreate(sub, "EndUsers", {
            Type: "sole_proprietor_information", FriendlyName: `${company.name} brand`.slice(0, 64),
            Attributes: JSON.stringify({ brand_name: details.legal_name.slice(0, 255), mobile_phone_number: e164(details.mobile_phone ?? "") }),
          })
          : await trustHubCreate(sub, "EndUsers", {
            Type: "us_a2p_messaging_profile_information", FriendlyName: `${company.name} messaging`.slice(0, 64),
            Attributes: JSON.stringify({ company_type: "private" }),
          });
        const bundle = `TrustProducts/${product.sid}`;
        await trustHubAssign(sub, bundle, endUser.sid);
        await trustHubAssign(sub, bundle, account!.customer_profile_sid);
        const evaluation = await trustHubEvaluateAndSubmit(sub, bundle,
          soleProp ? POLICY.soleProprietorTrustProduct : POLICY.a2pMessagingProfile);
        await update(admin, account!.id, { trust_product_sid: product.sid, trust_end_user_sid: endUser.sid,
          registration_error: evaluation.compliant ? null : evaluation.detail });
        account!.trust_product_sid = product.sid;
        if (!evaluation.compliant) throw new TwilioError(evaluation.detail ?? "trust product incomplete", 400, "profileIncomplete");
      });
    }

    if (!account.brand_sid) {
      await step("brand", async () => {
        // deno-lint-ignore no-explicit-any
        const brand = await twilioRequest<any>(sub, `${MESSAGING}/a2p/BrandRegistrations`, {
          params: {
            CustomerProfileBundleSid: account!.customer_profile_sid, A2PProfileBundleSid: account!.trust_product_sid,
            BrandType: soleProp ? "SOLE_PROPRIETOR" : "STANDARD",
            SkipAutomaticSecVet: details.route === "low_volume" ? true : undefined,
          },
        });
        await update(admin, account!.id, { brand_sid: brand.sid, brand_status: brand.status ?? "PENDING",
          registration_status: "brand_pending", status: "awaiting_registration", provisioning_step: "brand_review" });
        account!.brand_sid = brand.sid;
        account!.status = "awaiting_registration";
      });
    }

    // 5. Brand review -> campaign -> active
    const brand = await fetchBrand(sub, account.brand_sid);
    const brandStatus = String(brand.status ?? "PENDING");
    const identity = String(brand.identity_status ?? "");
    await update(admin, account.id, { brand_status: brandStatus, brand_identity_status: identity || null });
    if (brandStatus === "FAILED" || brandStatus === "SUSPENDED") {
      const reason = Array.isArray(brand.errors) && brand.errors[0]?.description
        ? String(brand.errors[0].description) : "Carriers didn't approve your business registration.";
      await update(admin, account.id, { registration_status: "rejected", status: "failed", registration_error: reason,
        last_error: `Registration wasn't approved: ${reason} Update your details and resubmit.`, last_error_at: new Date().toISOString() });
      await logEvent(admin, account, "registration", "brand", "failed", { reference: account.brand_sid, message: reason });
      return { account, done: false, error: reason };
    }
    if (brandStatus !== "APPROVED") {
      await update(admin, account.id, { next_attempt_at: new Date(Date.now() + 30 * 60_000).toISOString() });
      return { account, done: false };
    }
    if (soleProp && identity !== "VERIFIED" && identity !== "VETTED_VERIFIED") {
      await update(admin, account.id, { registration_status: "needs_verification",
        next_attempt_at: new Date(Date.now() + 15 * 60_000).toISOString() });
      return { account, done: false };
    }

    if (!account.campaign_sid) {
      await step("campaign", async () => {
        const samples = (details.sample_messages ?? []).filter((m) => m && m.trim().length >= 20).slice(0, 5);
        const messageSamples = samples.length >= 2 ? samples : defaultSampleMessages(company.name);
        // deno-lint-ignore no-explicit-any
        const campaign = await twilioRequest<any>(sub, `${MESSAGING}/Services/${account!.messaging_service_sid}/Compliance/Usa2p`, {
          params: {
            BrandRegistrationSid: account!.brand_sid,
            Description: (details.use_case_description?.trim() ||
              `${details.legal_name} is a field service business. It sends its own customers operational text messages: appointment confirmations and reminders, technician on-the-way and arrival updates, job updates, quotes, invoices and payment reminders. No marketing.`).slice(0, 4096),
            MessageFlow: details.opt_in_description.trim().slice(0, 2048),
            MessageSamples: messageSamples.map((m) => m.slice(0, 1024)),
            UsAppToPersonUsecase: soleProp ? "SOLE_PROPRIETOR" : details.route === "low_volume" ? "LOW_VOLUME" : "CUSTOMER_CARE",
            HasEmbeddedLinks: true,
            HasEmbeddedPhone: false,
          },
        });
        await update(admin, account!.id, { campaign_sid: campaign.sid, campaign_status: campaign.campaign_status ?? "PENDING",
          registration_status: "campaign_pending", provisioning_step: "campaign_review" });
        account!.campaign_sid = campaign.sid;
      });
    }

    const campaign = await fetchCampaign(sub, account.messaging_service_sid, account.campaign_sid);
    const campaignStatus = String(campaign.campaign_status ?? "PENDING");
    await update(admin, account.id, { campaign_status: campaignStatus });
    if (campaignStatus === "VERIFIED") {
      await update(admin, account.id, { status: "active", registration_status: "approved", provisioning_step: "complete",
        last_error: null, next_attempt_at: null });
      await logEvent(admin, account, "registration", "campaign", "succeeded", { reference: account.campaign_sid, key: `${account.id}:active` });
      const { data: owner } = await admin.from("app_users").select("id").eq("company_id", account.company_id)
        .eq("role", "owner").eq("status", "active").limit(1).maybeSingle();
      if (owner) {
        await admin.rpc("enqueue_push", { p_company: account.company_id, p_user: owner.id, p_event: "sms.ready",
          p_title: "SMS is ready", p_body: "Your business number is approved. You can now text customers from Harbour South.",
          p_job: null, p_customer: null });
      }
      return { account: { ...account, status: "active" }, done: true };
    }
    if (campaignStatus === "FAILED" || campaignStatus === "SUSPENDED") {
      const reason = Array.isArray(campaign.errors) && campaign.errors[0]?.description
        ? String(campaign.errors[0].description) : "Carriers didn't approve your messaging use.";
      await update(admin, account.id, { registration_status: "rejected", status: "failed", registration_error: reason,
        last_error: `Registration wasn't approved: ${reason}`, last_error_at: new Date().toISOString() });
      return { account, done: false, error: reason };
    }
    await update(admin, account.id, { next_attempt_at: new Date(Date.now() + 60 * 60_000).toISOString() });
    return { account, done: false };
  } catch (err) {
    const friendly = friendlyTwilioError(err);
    const transient = err instanceof TwilioError ? err.isTransient : true;
    const code = err instanceof TwilioError ? err.code : null;
    await logEvent(admin, account, "provision", account.provisioning_step ?? "unknown", "failed", {
      code, message: err instanceof Error ? err.message : "unknown",
    });
    const retries = (account.retry_count ?? 0) + 1;
    await update(admin, account.id, {
      last_error: code === "profileIncomplete" ? (err as Error).message : friendly,
      last_error_at: new Date().toISOString(),
      retry_count: retries,
      // Transient: back off and let maintenance retry. Permanent: stop and wait for the owner.
      next_attempt_at: transient ? new Date(Date.now() + Math.min(60, 2 ** retries) * 60_000).toISOString() : null,
      status: transient ? account.status : "failed",
    });
    return { account, done: false, error: friendly };
  }
}

export { TRUST_HUB };
