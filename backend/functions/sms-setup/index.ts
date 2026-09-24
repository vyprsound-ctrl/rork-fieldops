import { AuthError, corsHeaders, createAdminClient, jsonResponse, requireAuth } from "../_shared/auth.ts";
import { firstRow } from "../_shared/sms.ts";
import { friendlyTwilioError, masterConfig, searchLocalNumbers } from "../_shared/twilio.ts";
import { advanceProvisioning, type BusinessDetails, defaultSampleMessages, detailsProblem } from "../_shared/provisioning.ts";

/// Owner-only SMS setup. The company is ALWAYS the caller's own
/// (`current_company_id()`); no request field names a company, account,
/// service, number SID or Twilio SID.
///
/// actions:
///   status        friendly setup status (any SMS-capable role may read)
///   search        available local numbers by area code / contains
///   start         submit business details + chosen number, begin provisioning
///   choose_number pick a replacement when the chosen number was taken
///   retry         resume provisioning after a fixable failure
///   refresh       re-check carrier registration progress now
///   release       owner confirms turning SMS off and releasing the number

interface SetupRequest {
  action?: string;
  areaCode?: string;
  contains?: string;
  phoneNumber?: string;
  details?: Partial<BusinessDetails>;
  acceptedTerms?: boolean;
}

const E164 = /^\+1[2-9]\d{9}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const { userId, supabase } = await requireAuth(req);
    const request = (await req.json().catch(() => ({}))) as SetupRequest;
    const action = request.action ?? "status";

    const { data: companyId } = await supabase.rpc("current_company_id");
    if (!companyId) return jsonResponse({ error: "No company for this user." }, 403);

    const readStatus = async () => {
      const { data, error } = await supabase.rpc("sms_messaging_status");
      if (error) return null;
      return firstRow<Record<string, unknown>>(data);
    };

    if (action === "status") {
      const status = await readStatus();
      if (!status) return jsonResponse({ error: "You don't have access to SMS settings." }, 403);
      return jsonResponse({ status, providerAvailable: masterConfig() !== null });
    }

    // Everything below is owner-only.
    const { data: role } = await supabase.rpc("current_app_role");
    if (role !== "owner") return jsonResponse({ error: "Only the company owner can manage SMS setup." }, 403);

    const admin = createAdminClient();
    const config = masterConfig();

    if (action === "search") {
      if (!config) return jsonResponse({ error: "SMS isn't available yet. Harbour South is finishing its setup.", numbers: [] }, 503);
      const areaCode = (request.areaCode ?? "").replace(/[^0-9]/g, "");
      const contains = (request.contains ?? "").replace(/[^0-9]/g, "");
      if (areaCode && !/^[2-9]\d{2}$/.test(areaCode)) return jsonResponse({ error: "Enter a 3-digit US area code.", numbers: [] }, 422);
      try {
        const numbers = await searchLocalNumbers(config.master, {
          areaCode: areaCode || undefined, contains: contains.length >= 2 ? contains : undefined, limit: 20,
        });
        return jsonResponse({ numbers });
      } catch (err) {
        return jsonResponse({ error: friendlyTwilioError(err), numbers: [] }, 502);
      }
    }

    const { data: existing } = await admin.from("company_messaging_accounts").select("*").eq("company_id", companyId).maybeSingle();
    const { data: company } = await admin.from("companies").select("name, closed_at").eq("id", companyId).maybeSingle();
    if (!company || company.closed_at) return jsonResponse({ error: "This workspace is closed." }, 409);

    if (action === "start") {
      if (!config) return jsonResponse({ error: "SMS isn't available yet. Harbour South is finishing its setup." }, 503);
      if (request.acceptedTerms !== true) {
        return jsonResponse({ error: "Please confirm you've read the SMS & Messaging Terms." }, 422);
      }
      const { data: entitled } = await admin.rpc("sms_company_entitled", { p_company: companyId });
      if (entitled !== true) return jsonResponse({ error: "SMS needs an active Harbour South subscription." }, 402);
      if (existing && !["not_started", "failed"].includes(existing.status)) {
        return jsonResponse({ error: "SMS setup is already under way.", status: await readStatus() }, 409);
      }
      const problem = detailsProblem(request.details ?? {});
      if (problem) return jsonResponse({ error: problem }, 422);
      if (!request.phoneNumber || !E164.test(request.phoneNumber)) return jsonResponse({ error: "Choose a number first." }, 422);

      const setupFee = await admin.rpc("sms_setting_int", { p_key: "sms_setup_fee_cents", p_default: 0 });
      if (Number(setupFee.data ?? 0) > 0) {
        // Setup fees are not charged in this release; refuse rather than silently skip.
        return jsonResponse({ error: "SMS setup isn't available right now. Contact Harbour South support." }, 409);
      }

      const d = request.details as BusinessDetails;
      const cleaned: BusinessDetails = {
        ...d,
        legal_name: d.legal_name.trim(),
        state: d.state.trim().toUpperCase(),
        sample_messages: (d.sample_messages ?? []).filter((m) => m?.trim()).slice(0, 5).length >= 2
          ? d.sample_messages : defaultSampleMessages(company.name),
      };
      const row = {
        company_id: companyId, status: "provisioning", registration_route: cleaned.route,
        business_details: cleaned, requested_number: request.phoneNumber,
        requested_area_code: request.phoneNumber.slice(2, 5), provisioning_step: existing?.provisioning_step && existing.status === "failed"
          ? existing.provisioning_step : "subaccount",
        last_error: null, retry_count: 0, next_attempt_at: null, created_by_user_id: userId,
        registration_status: existing?.registration_status === "rejected" ? "not_submitted" : existing?.registration_status ?? "not_submitted",
        updated_at: new Date().toISOString(),
      };
      let accountId = existing?.id as string | undefined;
      if (existing) {
        // A rejected registration is resubmitted with the corrected details:
        // clear the rejected bundle references so new ones are created.
        const reset = existing.registration_status === "rejected"
          ? { customer_profile_sid: null, trust_product_sid: null, brand_sid: null, campaign_sid: null, brand_status: null,
              campaign_status: null, registration_error: null }
          : {};
        await admin.from("company_messaging_accounts").update({ ...row, ...reset }).eq("id", existing.id);
      } else {
        const { data: inserted, error } = await admin.from("company_messaging_accounts").insert(row).select("id").single();
        if (error || !inserted) return jsonResponse({ error: "SMS setup couldn't be started. Try again." }, 500);
        accountId = inserted.id;
      }
      const outcome = await advanceProvisioning(admin, accountId!);
      return jsonResponse({ status: await readStatus(), error: outcome.error ?? null, numberUnavailable: outcome.numberUnavailable ?? false });
    }

    if (!existing) return jsonResponse({ error: "SMS isn't set up yet." }, 404);

    if (action === "choose_number") {
      if (!request.phoneNumber || !E164.test(request.phoneNumber)) return jsonResponse({ error: "Choose a number first." }, 422);
      if (existing.provisioning_step !== "number_unavailable") return jsonResponse({ error: "Your number is already chosen." }, 409);
      await admin.from("company_messaging_accounts").update({
        requested_number: request.phoneNumber, provisioning_step: "number", last_error: null, updated_at: new Date().toISOString(),
      }).eq("id", existing.id);
      const outcome = await advanceProvisioning(admin, existing.id);
      return jsonResponse({ status: await readStatus(), error: outcome.error ?? null, numberUnavailable: outcome.numberUnavailable ?? false });
    }

    if (action === "retry" || action === "refresh") {
      if (existing.status === "failed" && existing.registration_status !== "rejected") {
        await admin.from("company_messaging_accounts").update({ status: existing.brand_sid ? "awaiting_registration" : "provisioning",
          next_attempt_at: null, updated_at: new Date().toISOString() }).eq("id", existing.id);
      }
      if (existing.registration_status === "rejected") {
        return jsonResponse({ status: await readStatus(), error: "Update your business details and submit again." }, 409);
      }
      const outcome = await advanceProvisioning(admin, existing.id);
      return jsonResponse({ status: await readStatus(), error: outcome.error ?? null, numberUnavailable: outcome.numberUnavailable ?? false });
    }

    if (action === "release") {
      const { error } = await supabase.rpc("confirm_sms_number_release");
      if (error) return jsonResponse({ error: "The number couldn't be released. Try again." }, 409);
      return jsonResponse({ status: await readStatus(), released: true });
    }

    return jsonResponse({ error: "Unknown action." }, 400);
  } catch (err) {
    if (err instanceof AuthError) return jsonResponse({ error: "Unauthorized" }, 401);
    console.error("[sms-setup] unexpected failure", err instanceof Error ? err.message : "unknown");
    return jsonResponse({ error: "Something went wrong with SMS setup. Try again shortly." }, 500);
  }
});
