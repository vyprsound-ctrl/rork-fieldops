import { createAdminClient } from "../_shared/auth.ts";

/// Resolves a customer-facing invoice share token into the invoice data the
/// customer is allowed to see.
///
/// This is the data half of the public invoice page; the page itself is
/// rendered by the project's Cloudflare Worker, because Supabase's edge gateway
/// forces every function response to `text/plain` with a sandbox CSP and would
/// therefore show the customer raw markup.
///
/// The token is the whole address: no company id, customer id, invoice id or
/// credential appears in it, and nothing here is enumerable. There is no caller
/// to authenticate, so the admin client is used and every read is then scoped by
/// hand to the single invoice the token resolves to.
///
/// The response deliberately carries only customer-appropriate fields. Internal
/// notes, the person who recorded a payment, simulation flags and every internal
/// identifier stay behind.

const TOKEN_PATTERN = /^[a-f0-9]{64}$/;

/// Same rule the database constraint enforces, applied again before the link is
/// handed on to be rendered: https only, real host, no embedded credentials.
const PAYMENT_LINK_PATTERN =
  /^https:\/\/[A-Za-z0-9][A-Za-z0-9._~-]*(\.[A-Za-z0-9._~-]+)+(:[0-9]{1,5})?(\/[^\s]*)?$/;

const jsonHeaders = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store, no-cache, must-revalidate, private",
  "X-Robots-Tag": "noindex, nofollow, noarchive",
};

function notFound(): Response {
  return new Response(JSON.stringify({ ok: false }), { status: 404, headers: jsonHeaders });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: jsonHeaders });
  if (req.method !== "GET") {
    return new Response(JSON.stringify({ ok: false }), { status: 405, headers: jsonHeaders });
  }

  try {
    const token = new URL(req.url).searchParams.get("t") ?? "";
    if (!TOKEN_PATTERN.test(token)) return notFound();

    const admin = createAdminClient();

    const { data: share, error: shareError } = await admin
      .from("invoice_share_tokens")
      .select("id, company_id, invoice_id, revoked_at, view_count")
      .eq("token", token)
      .is("revoked_at", null)
      .maybeSingle();

    if (shareError) {
      console.error("[invoice-view] token lookup failed", shareError.message);
      return notFound();
    }
    if (!share) return notFound();

    const { data: invoice } = await admin
      .from("invoices")
      .select(
        "id, company_id, customer_id, number, title, scope_of_work, status, currency_code, payment_terms_label, issue_date, due_date, subtotal, tax, total, amount_paid, balance, viewed_at, voided_at",
      )
      .eq("id", share.invoice_id)
      .eq("company_id", share.company_id)
      .maybeSingle();

    if (!invoice) return notFound();

    const [{ data: company }, { data: customer }, { data: lines }, { data: payments }] =
      await Promise.all([
        admin
          .from("companies")
          .select("name, phone, address_line, city, state, postal_code, time_zone_identifier, online_payment_link_url")
          .eq("id", share.company_id)
          .maybeSingle(),
        admin
          .from("customers")
          .select("name")
          .eq("id", invoice.customer_id)
          .eq("company_id", share.company_id)
          .maybeSingle(),
        admin
          .from("invoice_line_items")
          .select("item_description, quantity, unit_price, line_total, sort_order")
          .eq("invoice_id", invoice.id)
          .eq("company_id", share.company_id)
          .order("sort_order", { ascending: true }),
        admin
          .from("payments")
          .select("amount, method, received_at, status")
          .eq("invoice_id", invoice.id)
          .eq("company_id", share.company_id)
          .eq("status", "succeeded")
          .order("received_at", { ascending: true }),
      ]);

    const balance = Number(invoice.balance ?? 0);
    const isVoid = invoice.status === "void" || invoice.voided_at !== null;
    const isPaid = !isVoid && balance <= 0;

    // A payment link is passed on only when the contractor configured one, the
    // invoice is live, and something is actually owed. Otherwise the page has
    // nothing to render — never a dead or disabled payment control.
    const rawLink = company?.online_payment_link_url ?? null;
    const paymentLink = rawLink && PAYMENT_LINK_PATTERN.test(rawLink) && !isVoid && !isPaid ? rawLink : null;

    // Recording that the customer opened it. This is the only write the page
    // makes: it never touches status, totals or payments, and viewing an
    // invoice can never settle it.
    const now = new Date().toISOString();
    await admin
      .from("invoice_share_tokens")
      .update({ last_viewed_at: now, view_count: (share.view_count ?? 0) + 1 })
      .eq("id", share.id);
    if (!invoice.viewed_at) {
      await admin.from("invoices").update({ viewed_at: now }).eq("id", invoice.id);
    }

    return new Response(
      JSON.stringify({
        ok: true,
        company: {
          name: company?.name ?? "",
          phone: company?.phone ?? "",
          address: [company?.address_line, company?.city, company?.state, company?.postal_code]
            .filter((part) => part && String(part).trim().length > 0)
            .join(", "),
          timeZone: company?.time_zone_identifier ?? "UTC",
        },
        customerName: customer?.name ?? "",
        invoice: {
          number: invoice.number,
          title: invoice.title,
          scopeOfWork: invoice.scope_of_work,
          currency: invoice.currency_code,
          paymentTerms: invoice.payment_terms_label,
          issueDate: invoice.issue_date,
          dueDate: invoice.due_date,
          subtotal: invoice.subtotal,
          tax: invoice.tax,
          total: invoice.total,
          amountPaid: invoice.amount_paid,
          balance: invoice.balance,
          isVoid,
          isPaid,
        },
        lines: (lines ?? []).map((line) => ({
          description: line.item_description,
          quantity: line.quantity,
          unitPrice: line.unit_price,
          lineTotal: line.line_total,
        })),
        payments: (payments ?? []).map((payment) => ({
          amount: payment.amount,
          method: payment.method,
          receivedAt: payment.received_at,
        })),
        paymentLink,
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (err) {
    console.error("[invoice-view] unexpected failure", err instanceof Error ? err.message : err);
    return notFound();
  }
});
