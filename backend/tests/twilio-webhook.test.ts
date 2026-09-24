// Run: deno test backend/tests/twilio-webhook.test.ts
// Pure tests of the shared Twilio module: signature validation, form encoding,
// error mapping and price parsing. No network, no credentials.
import { assert, assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  computeTwilioSignature,
  encodeForm,
  friendlyTwilioError,
  priceToMicros,
  TwilioError,
  verifyTwilioSignature,
} from "../functions/_shared/twilio.ts";
import { withCompanyIdentification, variablesIn, normalisePhone } from "../functions/_shared/sms.ts";

// Twilio's own documented example (docs: "Webhooks security").
const DOC_URL = "https://mycompany.com/myapp.php?foo=1&bar=2";
const DOC_TOKEN = "12345";
const DOC_PARAMS = {
  CallSid: "CA1234567890ABCDE",
  Caller: "+12349013030",
  Digits: "1234",
  From: "+12349013030",
  To: "+18005551212",
};

Deno.test("signature matches Twilio's documented example", async () => {
  const sig = await computeTwilioSignature(DOC_URL, DOC_PARAMS, DOC_TOKEN);
  assertEquals(sig, "0/KCTR6DLpKmkAf8muzZqo1nDgQ=");
});

Deno.test("valid signature accepted with either company or master token", async () => {
  const sig = await computeTwilioSignature(DOC_URL, DOC_PARAMS, "subaccount-token");
  assert(await verifyTwilioSignature(DOC_URL, DOC_PARAMS, sig, ["subaccount-token", "master"]));
  assert(await verifyTwilioSignature(DOC_URL, DOC_PARAMS, sig, [null, "subaccount-token"]));
});

Deno.test("invalid, missing or wrong-company signatures are refused", async () => {
  const sig = await computeTwilioSignature(DOC_URL, DOC_PARAMS, "company-a-token");
  assertFalse(await verifyTwilioSignature(DOC_URL, DOC_PARAMS, sig, ["company-b-token", "master"]));
  assertFalse(await verifyTwilioSignature(DOC_URL, DOC_PARAMS, null, ["company-a-token"]));
  assertFalse(await verifyTwilioSignature(DOC_URL, DOC_PARAMS, "garbage", ["company-a-token"]));
  assertFalse(await verifyTwilioSignature(DOC_URL, DOC_PARAMS, sig, [null, undefined]));
});

Deno.test("signature is bound to the callback key in the URL", async () => {
  const a = "https://x.supabase.co/functions/v1/sms-status?k=" + "a".repeat(48);
  const b = "https://x.supabase.co/functions/v1/sms-status?k=" + "b".repeat(48);
  const sig = await computeTwilioSignature(a, DOC_PARAMS, "t");
  assertFalse(await verifyTwilioSignature(b, DOC_PARAMS, sig, ["t"]));
});

Deno.test("tampered parameters invalidate the signature", async () => {
  const sig = await computeTwilioSignature(DOC_URL, DOC_PARAMS, "t");
  assertFalse(await verifyTwilioSignature(DOC_URL, { ...DOC_PARAMS, AccountSid: "ACother" }, sig, ["t"]));
});

Deno.test("form encoding repeats array keys and drops nulls", () => {
  assertEquals(encodeForm({ A: "1", B: null, C: ["x", "y"], D: true }), "A=1&C=x&C=y&D=true");
});

Deno.test("transient vs permanent errors", () => {
  assert(new TwilioError("x", 503, null).isTransient);
  assert(new TwilioError("x", 429, "20429").isTransient);
  assert(new TwilioError("x", 0, null).isTransient);
  assertFalse(new TwilioError("x", 400, "21211").isTransient);
});

Deno.test("customer-facing errors never expose codes or SIDs", () => {
  for (const code of ["21422", "21610", "21211", "30034", "20003", "99999"]) {
    const text = friendlyTwilioError(new TwilioError("raw", 400, code));
    assertFalse(/\d{5}|AC[0-9a-f]|SM[0-9a-f]|HTTP/i.test(text), text);
  }
  assert(friendlyTwilioError(new TwilioError("raw", 400, "21610")).includes("STOP"));
});

Deno.test("provider price parsing", () => {
  assertEquals(priceToMicros("-0.00830"), 8300);
  assertEquals(priceToMicros(null), null);
});

Deno.test("company identification and variable parsing", () => {
  assertEquals(withCompanyIdentification("See you at 9", "Gulf Coast Air"), "Gulf Coast Air: See you at 9");
  assertEquals(withCompanyIdentification("Gulf Coast Air: hi", "Gulf Coast Air"), "Gulf Coast Air: hi");
  assertEquals(variablesIn("Hi {{customer_first_name}} {{ job_number }}"), ["customer_first_name", "job_number"]);
  assertEquals(normalisePhone("(813) 555-0101"), "+18135550101");
  assertEquals(normalisePhone("12"), null);
});
