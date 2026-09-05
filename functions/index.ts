/// TradeDesk — the customer-facing invoice page.
///
/// This Worker exists for one reason: it is the only place in the stack that
/// can serve real HTML. Supabase's edge gateway rewrites every function
/// response to `text/plain` with a sandbox CSP, which would show a customer raw
/// markup, so the data half of this page lives in the `invoice-view` Supabase
/// function (which holds the service-role key) and the rendering half lives
/// here. No database credential is present in this Worker.
///
/// The URL carries a random 32-byte token and nothing else — no company id,
/// customer id, invoice id, invoice number or credential — so the page cannot
/// be guessed, enumerated or walked. A token can be revoked or rotated from the
/// app at any time, which kills the link immediately.
///
/// The page shows the customer their invoice and, when the contractor has
/// configured one, a button through to the contractor's *own* payment page.
/// TradeDesk does not process, route, hold or reconcile that payment, and
/// opening this page never changes what the invoice says is owed.

interface Env {
  EXPO_PUBLIC_SUPABASE_URL?: string;
}

interface InvoicePayload {
  ok: boolean;
  company: { name: string; phone: string; address: string; timeZone: string };
  customerName: string;
  invoice: {
    number: string;
    title: string;
    scopeOfWork: string;
    currency: string;
    paymentTerms: string;
    issueDate: string;
    dueDate: string;
    subtotal: string;
    tax: string;
    total: string;
    amountPaid: string;
    balance: string;
    isVoid: boolean;
    isPaid: boolean;
  };
  lines: Array<{ description: string; quantity: string; unitPrice: string; lineTotal: string }>;
  payments: Array<{ amount: string; method: string; receivedAt: string }>;
  paymentLink: string | null;
}

const TOKEN_PATTERN = /^[a-f0-9]{64}$/;

/// The same rule the database constraint and the data function enforce, applied
/// once more immediately before a button is rendered.
const PAYMENT_LINK_PATTERN =
  /^https:\/\/[A-Za-z0-9][A-Za-z0-9._~-]*(\.[A-Za-z0-9._~-]+)+(:[0-9]{1,5})?(\/[^\s]*)?$/;

const pageHeaders: Record<string, string> = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "no-store, no-cache, must-revalidate, private",
  "X-Robots-Tag": "noindex, nofollow, noarchive",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

function escapeHtml(value: string): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function money(value: string | number | null, currency: string): string {
  const amount = Number(value ?? 0);
  try {
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: (currency || "USD").trim(),
    }).format(amount);
  } catch {
    return `${(currency || "").trim()} ${amount.toFixed(2)}`;
  }
}

function formatDate(value: string | null, timeZone: string): string {
  if (!value) return "—";
  try {
    const date = new Date(String(value).length <= 10 ? `${value}T12:00:00Z` : value);
    return new Intl.DateTimeFormat("en-US", {
      day: "numeric",
      month: "short",
      year: "numeric",
      timeZone: timeZone || "UTC",
    }).format(date);
  } catch {
    return String(value);
  }
}

function notFoundPage(): Response {
  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Invoice unavailable</title>
<style>
  :root { color-scheme: light; }
  body { margin:0; min-height:100vh; display:grid; place-items:center; background:#f3f4f7; padding:24px;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; color:#15161a; }
  .card { background:#fff; border-radius:18px; padding:32px 26px; max-width:420px; text-align:center;
          box-shadow:0 1px 3px rgba(16,18,27,.08),0 12px 32px rgba(16,18,27,.06); }
  h1 { font-size:19px; margin:0 0 10px; letter-spacing:-.01em; }
  p { margin:0; font-size:15px; line-height:1.55; color:#606374; }
</style></head>
<body><div class="card">
  <h1>This invoice link isn't available</h1>
  <p>The link may have expired, been replaced with a newer one, or been withdrawn. Please contact the company that sent it for an up-to-date link.</p>
</div></body></html>`;
  return new Response(html, { status: 404, headers: pageHeaders });
}

function renderInvoice(data: InvoicePayload): Response {
  const { company, invoice, customerName } = data;
  const timeZone = company.timeZone;
  const currency = invoice.currency;
  const balance = Number(invoice.balance ?? 0);

  const isVoid = invoice.isVoid;
  const isPaid = invoice.isPaid;
  const isOverdue = !isVoid && !isPaid && new Date(`${invoice.dueDate}T23:59:59Z`) < new Date();

  const statusLabel = isVoid ? "Cancelled" : isPaid ? "Paid in full" : isOverdue ? "Past due" : "Due";
  const statusTone = isVoid ? "void" : isPaid ? "paid" : isOverdue ? "overdue" : "open";

  const paymentLink =
    data.paymentLink && PAYMENT_LINK_PATTERN.test(data.paymentLink) ? data.paymentLink : null;

  const lineRows = data.lines
    .map(
      (line) => `<tr>
        <td>
          <span class="desc">${escapeHtml(line.description)}</span>
          <span class="qty">${Number(line.quantity ?? 0)} × ${money(line.unitPrice, currency)}</span>
        </td>
        <td class="num">${money(line.lineTotal, currency)}</td>
      </tr>`,
    )
    .join("");

  const paymentRows = data.payments
    .map(
      (payment) => `<li>
          <span>${formatDate(payment.receivedAt, timeZone)} · ${escapeHtml(payment.method)}</span>
          <span class="num">−${money(payment.amount, currency)}</span>
        </li>`,
    )
    .join("");

  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Invoice ${escapeHtml(invoice.number)} · ${escapeHtml(company.name)}</title>
<style>
  :root { color-scheme: light; --ink:#15161a; --muted:#6b6f7d; --line:#e7e8ee; --bg:#f3f4f7;
          --accent:#0f5c4a; --danger:#b3261e; --ok:#1c7a4a; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--ink); padding:20px 16px 56px;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",sans-serif;
         -webkit-font-smoothing:antialiased; }
  .wrap { max-width:560px; margin:0 auto; }
  .card { background:#fff; border-radius:18px; padding:22px; margin-bottom:14px;
          box-shadow:0 1px 2px rgba(16,18,27,.06),0 10px 28px rgba(16,18,27,.05); }
  .top { display:flex; justify-content:space-between; align-items:flex-start; gap:14px; margin-bottom:20px; }
  .company { font-size:17px; font-weight:700; letter-spacing:-.01em; }
  .company small { display:block; font-weight:400; font-size:13px; color:var(--muted); margin-top:4px; line-height:1.5; }
  .pill { font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:.06em;
          padding:6px 11px; border-radius:999px; white-space:nowrap; }
  .pill.open { background:#eef2ff; color:#31408f; }
  .pill.overdue { background:#fdecea; color:var(--danger); }
  .pill.paid { background:#e7f5ec; color:var(--ok); }
  .pill.void { background:#eeeff3; color:var(--muted); }
  .hero { text-align:center; padding:6px 0 4px; }
  .hero .cap { font-size:12px; text-transform:uppercase; letter-spacing:.08em; color:var(--muted); font-weight:600; }
  .hero .amt { font-size:40px; font-weight:750; letter-spacing:-.03em; margin:8px 0 6px; font-variant-numeric:tabular-nums; }
  .hero .sub { font-size:14px; color:var(--muted); }
  .pay { display:block; margin:18px 0 6px; background:var(--accent); color:#fff;
         text-decoration:none; text-align:center; font-size:16px; font-weight:650;
         padding:16px 20px; border-radius:13px; }
  .pay:active { opacity:.85; }
  .payhint { font-size:12px; color:var(--muted); text-align:center; line-height:1.5; margin:10px 4px 0; }
  h2 { font-size:12px; text-transform:uppercase; letter-spacing:.07em; color:var(--muted);
       margin:0 0 12px; font-weight:650; }
  .meta { display:flex; flex-wrap:wrap; gap:16px 26px; }
  .meta div { min-width:96px; }
  .meta span { display:block; font-size:11px; text-transform:uppercase; letter-spacing:.05em; color:var(--muted); font-weight:600; }
  .meta strong { display:block; font-size:14px; font-weight:600; margin-top:3px; }
  table { width:100%; border-collapse:collapse; }
  td { padding:12px 0; border-bottom:1px solid var(--line); vertical-align:top; font-size:14px; }
  tr:last-child td { border-bottom:0; }
  .desc { display:block; }
  .qty { display:block; font-size:12px; color:var(--muted); margin-top:3px; font-variant-numeric:tabular-nums; }
  .num { text-align:right; white-space:nowrap; font-variant-numeric:tabular-nums; }
  .totals { display:flex; justify-content:space-between; font-size:14px; padding:7px 0; color:var(--muted); }
  .totals.grand { font-size:17px; font-weight:700; color:var(--ink); border-top:1px solid var(--line);
                  margin-top:8px; padding-top:14px; }
  ul { list-style:none; margin:0; padding:0; }
  ul li { display:flex; justify-content:space-between; font-size:14px; padding:8px 0; border-bottom:1px solid var(--line); }
  ul li:last-child { border-bottom:0; }
  .scope { font-size:14px; line-height:1.6; color:#3b3e4a; white-space:pre-wrap; margin:0; }
  footer { text-align:center; font-size:12px; color:var(--muted); line-height:1.6; padding:0 8px; }
</style></head>
<body><div class="wrap">

  <div class="card">
    <div class="top">
      <div class="company">${escapeHtml(company.name)}
        <small>${escapeHtml(company.address)}${company.phone ? `<br>${escapeHtml(company.phone)}` : ""}</small>
      </div>
      <div class="pill ${statusTone}">${statusLabel}</div>
    </div>

    <div class="hero">
      <div class="cap">${isVoid ? "Invoice cancelled" : isPaid ? "Paid in full" : "Amount due"}</div>
      <div class="amt">${money(isVoid ? invoice.total : balance, currency)}</div>
      <div class="sub">Invoice ${escapeHtml(invoice.number)} · ${
    isVoid ? "no payment is required" : isPaid ? "thank you" : `due ${formatDate(invoice.dueDate, timeZone)}`
  }</div>
    </div>

    ${
    paymentLink
      ? `<a class="pay" href="${escapeHtml(paymentLink)}" target="_blank" rel="noopener noreferrer nofollow">Pay online</a>
       <p class="payhint">You'll be taken to ${escapeHtml(company.name)}'s own payment page to pay them directly. Your payment is handled there, not on this page.</p>`
      : ""
  }
  </div>

  <div class="card">
    <h2>Details</h2>
    <div class="meta">
      <div><span>Billed to</span><strong>${escapeHtml(customerName || "—")}</strong></div>
      <div><span>Issued</span><strong>${formatDate(invoice.issueDate, timeZone)}</strong></div>
      <div><span>Due</span><strong>${formatDate(invoice.dueDate, timeZone)}</strong></div>
      ${
    invoice.paymentTerms
      ? `<div><span>Terms</span><strong>${escapeHtml(invoice.paymentTerms)}</strong></div>`
      : ""
  }
    </div>
  </div>

  ${
    invoice.scopeOfWork && invoice.scopeOfWork.trim().length > 0
      ? `<div class="card"><h2>Work carried out</h2><p class="scope">${escapeHtml(invoice.scopeOfWork)}</p></div>`
      : ""
  }

  <div class="card">
    <h2>${escapeHtml(invoice.title || "Invoice")}</h2>
    <table><tbody>${lineRows || `<tr><td colspan="2">No line items.</td></tr>`}</tbody></table>
    <div class="totals"><span>Subtotal</span><span class="num">${money(invoice.subtotal, currency)}</span></div>
    <div class="totals"><span>Tax</span><span class="num">${money(invoice.tax, currency)}</span></div>
    <div class="totals grand"><span>Total</span><span class="num">${money(invoice.total, currency)}</span></div>
  </div>

  ${
    paymentRows
      ? `<div class="card"><h2>Payments received</h2><ul>${paymentRows}</ul>
       <div class="totals grand"><span>${isPaid ? "Balance" : "Still due"}</span><span class="num">${
        money(balance, currency)
      }</span></div></div>`
      : ""
  }

  <footer>
    Questions about this invoice? Contact ${escapeHtml(company.name)}${
    company.phone ? ` on ${escapeHtml(company.phone)}` : ""
  }.<br>
    This page is private to you. Please don't share the link.
  </footer>
</div></body></html>`;

  return new Response(html, { status: 200, headers: pageHeaders });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/i") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method not allowed", { status: 405, headers: pageHeaders });
      }

      const token = url.searchParams.get("t") ?? "";
      if (!TOKEN_PATTERN.test(token)) return notFoundPage();

      const base = (env.EXPO_PUBLIC_SUPABASE_URL ?? "").replace(/\/+$/, "");
      if (!base) {
        console.error("[invoice] EXPO_PUBLIC_SUPABASE_URL is not configured for the Worker");
        return notFoundPage();
      }

      try {
        const response = await fetch(`${base}/functions/v1/invoice-view?t=${token}`, {
          headers: { Accept: "application/json" },
        });
        if (!response.ok) return notFoundPage();

        const data = (await response.json()) as InvoicePayload;
        if (!data?.ok) return notFoundPage();

        return renderInvoice(data);
      } catch (err) {
        console.error("[invoice] could not resolve the invoice", err instanceof Error ? err.message : err);
        return notFoundPage();
      }
    }

    return Response.json({ ok: true, service: "tradedesk" });
  },
};
