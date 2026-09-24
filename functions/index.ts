/// Harbour South FieldOps — the customer-facing invoice page and the
/// team-invitation dispatcher.
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
/// The page shows the customer their invoice and, when payment is possible, a
/// way to settle it. There are two mutually exclusive routes, and the page
/// chooses at runtime:
///
///   1. CARD, via Stripe. Offered only when the trade business has connected a
///      Stripe account that Stripe itself says can take charges. The card
///      fields are Stripe's own hosted Payment Element, so no card number ever
///      touches this Worker, this page's JavaScript, or Harbour South. The
///      PaymentIntent is created by the `invoice-payment` Supabase function ON
///      BEHALF OF the connected account, so the money moves to the trade
///      business and Harbour South never holds customer funds.
///   2. The contractor's OWN payment page, when they configured a manual link
///      and have not connected Stripe. Harbour South does not process, route,
///      hold or reconcile that one at all.
///
/// Paying here never marks the invoice paid by itself. This page can only ask
/// Stripe for money; the invoice moves when the signature-verified
/// `payment_intent.succeeded` webhook is processed server-side.
///
/// This Worker also serves the two Stripe Connect onboarding landing pages
/// (`/stripe/return`, `/stripe/refresh`) so an Express onboarding session that
/// is finished or abandoned lands somewhere real instead of a dead URL.

interface Env {
  EXPO_PUBLIC_SUPABASE_URL?: string;
  /// The anon key is a PUBLIC key by design. It is forwarded only so the
  /// Supabase gateway accepts the browser's call to `invoice-payment`; that
  /// function's real authorisation is the invoice share token.
  EXPO_PUBLIC_SUPABASE_ANON_KEY?: string;
  /// Email transport for team invitations. Server-side only — no email
  /// credential is ever present in the iOS app.
  RESEND_API_KEY?: string;
  RESEND_FROM_EMAIL?: string;
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

/// Everything the payment half of the page needs, resolved server-side.
interface PayContext {
  supabaseBase: string;
  anonKey: string | null;
  token: string;
  returnUrl: string;
  /// Set when Stripe has just redirected the customer back here.
  redirectStatus: string | null;
}

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

/// Safe embedding of a server value inside an inline <script>. JSON.stringify
/// alone is not enough: a literal `</script>` inside a string would close the
/// element, so the angle bracket is escaped as well.
function jsonForScript(value: unknown): string {
  return JSON.stringify(value ?? null)
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029");
}

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

// =============================================================================
// Customer-facing quote page (linked from "Send Quote by SMS").
//
// The token is the only key. The data comes from `quote_public_view`, a
// SECURITY DEFINER function granted to anon that returns ONLY what a customer
// should see: the business's name and contact details, the quote number,
// title, scope, lines and totals. No internal ids, staff, cost or margin data.
// =============================================================================

interface QuoteView {
  ok: boolean;
  company?: { name: string; phone: string | null; email: string | null; address: string | null };
  quote?: {
    number: string; title: string; scope: string; status: string; valid_until: string | null;
    subtotal: number; tax: number; total: number; currency: string; customer: string | null;
  };
  lines?: Array<{ description: string; quantity: number; unit_price: number; line_total: number }>;
}

async function quotePage(token: string, env: Env): Promise<Response> {
  const base = (env.EXPO_PUBLIC_SUPABASE_URL ?? "").replace(/\/+$/, "");
  const anonKey = (env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? "").trim();
  if (!base || !anonKey) return notFoundPage();
  let data: QuoteView;
  try {
    const response = await fetch(`${base}/rest/v1/rpc/quote_public_view`, {
      method: "POST",
      headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_token: token }),
    });
    if (!response.ok) return notFoundPage();
    data = (await response.json()) as QuoteView;
  } catch (err) {
    console.error("[quote] could not resolve the quote", err instanceof Error ? err.message : err);
    return notFoundPage();
  }
  if (!data?.ok || !data.quote || !data.company) return notFoundPage();

  const q = data.quote;
  const c = data.company;
  const statusLabel: Record<string, string> = {
    viewed: "Awaiting your decision", accepted: "Accepted", declined: "Declined", expired: "Expired",
  };
  const rows = (data.lines ?? []).map((l) =>
    `<tr><td>${escapeHtml(l.description)}<div class="qty">${escapeHtml(String(Number(l.quantity)))} × ${
      escapeHtml(money(l.unit_price, q.currency))}</div></td><td class="amt">${escapeHtml(money(l.line_total, q.currency))}</td></tr>`
  ).join("");
  const contact = [c.phone ? `Call ${c.phone}` : null, c.email].filter(Boolean).join(" · ");
  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Quote ${escapeHtml(q.number)} from ${escapeHtml(c.name)}</title>
<style>
  :root { color-scheme: light; }
  body { margin:0; background:#f3f4f7; padding:20px 14px 40px; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; color:#15161a; }
  .wrap { max-width:560px; margin:0 auto; }
  .card { background:#fff; border-radius:18px; padding:22px 20px; margin-bottom:14px; box-shadow:0 1px 3px rgba(16,18,27,.08),0 12px 32px rgba(16,18,27,.05); }
  .biz { display:flex; gap:12px; align-items:center; }
  .mark { width:44px; height:44px; border-radius:11px; background:#14367A; color:#fff; font-weight:700; font-size:20px; display:grid; place-items:center; }
  h1 { font-size:17px; margin:0; } .sub { color:#606374; font-size:13px; margin-top:2px; }
  .num { color:#606374; font-size:14px; margin:0 0 4px; } .title { font-size:20px; font-weight:700; margin:0 0 10px; }
  .pill { display:inline-block; background:#FDF1E7; color:#A4480C; border-radius:999px; padding:4px 10px; font-size:12px; font-weight:600; }
  .scope { white-space:pre-wrap; color:#33364a; font-size:15px; line-height:1.55; margin:14px 0 0; }
  table { width:100%; border-collapse:collapse; font-size:15px; } td { padding:10px 0; border-bottom:1px solid #eceef3; vertical-align:top; }
  .qty { color:#8a8d9b; font-size:13px; margin-top:2px; } .amt { text-align:right; white-space:nowrap; padding-left:12px; }
  .tot td { border:0; padding:4px 0; color:#606374; } .grand td { font-size:20px; font-weight:700; color:#15161a; padding-top:10px; }
  .foot { color:#8a8d9b; font-size:12px; text-align:center; margin-top:18px; line-height:1.5; }
</style></head>
<body><div class="wrap">
<div class="card"><div class="biz"><div class="mark">${escapeHtml((c.name.trim()[0] ?? "·").toUpperCase())}</div>
<div><h1>${escapeHtml(c.name)}</h1>${c.address ? `<div class="sub">${escapeHtml(c.address)}</div>` : ""}</div></div></div>
<div class="card">
<p class="num">Quote ${escapeHtml(q.number)}${q.customer ? ` · for ${escapeHtml(q.customer)}` : ""}</p>
<p class="title">${escapeHtml(q.title || "Your quote")}</p>
<span class="pill">${escapeHtml(statusLabel[q.status] ?? "Quote")}</span>
${q.valid_until ? `<span class="sub" style="margin-left:8px">Valid until ${escapeHtml(formatDate(q.valid_until, "UTC"))}</span>` : ""}
${q.scope ? `<p class="scope">${escapeHtml(q.scope)}</p>` : ""}
</div>
<div class="card"><table>${rows}
<tr class="tot"><td>Subtotal</td><td class="amt">${escapeHtml(money(q.subtotal, q.currency))}</td></tr>
<tr class="tot"><td>Tax</td><td class="amt">${escapeHtml(money(q.tax, q.currency))}</td></tr>
<tr class="grand"><td>Total</td><td class="amt">${escapeHtml(money(q.total, q.currency))}</td></tr></table></div>
<div class="card" style="text-align:center"><p style="margin:0 0 4px;font-weight:600">Ready to go ahead, or have a question?</p>
<p class="sub" style="margin:0">Reply to the text message you received${contact ? `, or ${escapeHtml(contact)}` : ""}.</p></div>
<p class="foot">This quote was sent by ${escapeHtml(c.name)} using Harbour South FieldOps.</p>
</div></body></html>`;
  return new Response(html, { status: 200, headers: pageHeaders });
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

function renderInvoice(data: InvoicePayload, pay: PayContext): Response {
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

  // Stripe has just sent the customer back here. The webhook is what actually
  // settles the invoice, so this says what is true right now — money taken,
  // invoice catching up — rather than claiming the invoice is already paid.
  let banner = "";
  if (pay.redirectStatus === "succeeded") {
    banner =
      `<div class="banner ok"><strong>Payment received.</strong> Thank you. This invoice updates automatically once the payment settles, usually within a minute.</div>`;
  } else if (pay.redirectStatus === "processing") {
    banner =
      `<div class="banner warn"><strong>Payment processing.</strong> Your bank has not finished confirming it yet. You do not need to pay again.</div>`;
  } else if (pay.redirectStatus) {
    banner =
      `<div class="banner bad"><strong>That payment was not completed.</strong> Nothing has been charged. You can try again below.</div>`;
  }

  // No card control on an invoice that cannot take one, and none immediately
  // after a successful payment — offering to pay again there would be a trap.
  const offerCard = !isVoid && !isPaid && balance > 0 && pay.redirectStatus !== "succeeded";

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
  /* Harbour South palette, sampled from the mark: royal blue for brand and
     structure, orange for the one action on the page. Semantic colours are
     unchanged — green still means paid, red still means a problem. */
  :root { color-scheme: light; --ink:#0F1B2A; --muted:#5B6675; --line:#E1E6EF; --bg:#F6F8FB;
          --brand:#1B3FA8; --accent:#E1691A; --danger:#C7311F; --ok:#0F8F49; }
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
  .pill.open { background:#EAF0FC; color:var(--brand); }
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
  .pay[disabled] { opacity:.55; }
  button.pay { width:100%; border:0; cursor:pointer; font-family:inherit; }
  .payhint { font-size:12px; color:var(--muted); text-align:center; line-height:1.5; margin:10px 4px 0; }
  .banner { border-radius:13px; padding:14px 16px; margin:0 0 14px; font-size:14px; line-height:1.5; }
  .banner.ok { background:#e7f5ec; color:#14603a; }
  .banner.warn { background:#fff5e6; color:#7a4b00; }
  .banner.bad { background:#fdecea; color:var(--danger); }
  .payel { margin-top:16px; }
  .paynote { font-size:13px; line-height:1.5; margin:12px 0 0; }
  .paynote.bad { color:var(--danger); }
  .paynote.muted { color:var(--muted); }
  .spin { display:inline-block; width:15px; height:15px; border:2px solid rgba(255,255,255,.45);
          border-top-color:#fff; border-radius:50%; animation:spin .7s linear infinite; vertical-align:-2px; }
  @keyframes spin { to { transform:rotate(360deg); } }
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

    ${banner}

    <!-- Stripe card payment. Filled in by the script at the foot of the page,
         and only after the server has confirmed this business can genuinely
         take a card, so no dead control is ever rendered. -->
    <div id="pay-region"></div>

    ${
    paymentLink
      ? `<div id="manual-pay">
         <a class="pay" href="${escapeHtml(paymentLink)}" target="_blank" rel="noopener noreferrer nofollow">Pay online</a>
         <p class="payhint">You'll be taken to ${escapeHtml(company.name)}'s own payment page to pay them directly. Your payment is handled there, not on this page.</p>
       </div>`
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
</div>
${offerCard ? cardPaymentScript(pay) : ""}
</body></html>`;

  return new Response(html, { status: 200, headers: pageHeaders });
}

/// The browser half of the card flow.
///
/// Kept as a plain constant with a single `__PAY_CONFIG__` placeholder rather
/// than an interpolated template, so no server value can ever be spliced into
/// executable positions in this script — only into one JSON literal.
const CARD_CLIENT = `
(function () {
  var cfg = __PAY_CONFIG__;
  var region = document.getElementById('pay-region');
  var manual = document.getElementById('manual-pay');
  if (!region || !cfg || !cfg.supabaseBase) return;

  function node(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text) n.textContent = text;
    return n;
  }

  function note(message, tone) {
    var p = node('p', 'paynote ' + (tone || 'muted'), message);
    region.appendChild(p);
    return p;
  }

  function amountLabel(cents, currency) {
    try {
      return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: (currency || 'usd').toUpperCase()
      }).format(cents / 100);
    } catch (e) {
      return (cents / 100).toFixed(2);
    }
  }

  function call(action) {
    var headers = { 'Content-Type': 'application/json', 'Accept': 'application/json' };
    if (cfg.anonKey) {
      headers['apikey'] = cfg.anonKey;
      headers['Authorization'] = 'Bearer ' + cfg.anonKey;
    }
    return fetch(cfg.supabaseBase + '/functions/v1/invoice-payment', {
      method: 'POST',
      headers: headers,
      body: JSON.stringify({ token: cfg.token, action: action })
    }).then(function (response) {
      return response.json().catch(function () { return {}; }).then(function (body) {
        return { ok: response.ok, body: body || {} };
      });
    });
  }

  function showElement(data, start, hint) {
    start.style.display = 'none';
    if (hint) hint.style.display = 'none';

    var stripe = Stripe(data.publishableKey, { stripeAccount: data.stripeAccount });
    var elements = stripe.elements({
      clientSecret: data.clientSecret,
      appearance: { theme: 'stripe', variables: { colorPrimary: '#1B3FA8', borderRadius: '10px' } }
    });

    var holder = node('div', 'payel');
    region.appendChild(holder);
    elements.create('payment', { layout: 'tabs' }).mount(holder);

    var submit = node('button', 'pay', 'Pay ' + amountLabel(data.amountCents, data.currency));
    submit.type = 'button';
    region.appendChild(submit);

    var problem = node('p', 'paynote bad');
    region.appendChild(problem);
    note('Your card details go straight to Stripe. This page never sees or stores them.', 'muted');

    submit.addEventListener('click', function () {
      var label = submit.textContent;
      submit.disabled = true;
      problem.textContent = '';
      submit.textContent = '';
      submit.appendChild(node('span', 'spin'));

      function recover(message) {
        submit.disabled = false;
        submit.textContent = label;
        problem.textContent = message;
      }

      stripe.confirmPayment({
        elements: elements,
        confirmParams: { return_url: cfg.returnUrl }
      }).then(function (outcome) {
        recover((outcome && outcome.error && outcome.error.message)
          ? outcome.error.message
          : 'That payment could not be completed. Please check the details and try again.');
      }).catch(function () {
        recover('That payment could not be completed. Please try again.');
      });
    });
  }

  call('quote').then(function (result) {
    var quote = result.body;
    if (!result.ok || !quote.payable || !quote.cardsAvailable) return;
    if (!(quote.balanceCents > 0)) return;

    if (manual) manual.style.display = 'none';

    var start = node('button', 'pay', 'Pay ' + amountLabel(quote.balanceCents, quote.currency) + ' by card');
    start.type = 'button';
    region.appendChild(start);
    var hint = note('Paid securely to ' + (quote.companyName || 'this business') +
      ' through Stripe. Your card details are handled by Stripe and never reach this page.', 'muted');

    start.addEventListener('click', function () {
      start.disabled = true;
      start.textContent = '';
      start.appendChild(node('span', 'spin'));

      call('intent').then(function (created) {
        var data = created.body;

        if (!created.ok || !data.clientSecret) {
          start.style.display = 'none';
          note(data.error || 'Card payment could not be started. Please contact the business that sent this invoice.', 'bad');
          if (manual) manual.style.display = '';
          return;
        }

        if (!data.publishableKey || typeof Stripe !== 'function') {
          start.style.display = 'none';
          note('Card payment is not fully set up for this business yet. Please contact them to arrange payment.', 'bad');
          if (manual) manual.style.display = '';
          return;
        }

        showElement(data, start, hint);
      }).catch(function () {
        start.style.display = 'none';
        note('Card payment could not be started. Please try again shortly.', 'bad');
        if (manual) manual.style.display = '';
      });
    });
  }).catch(function () {
    // Silent by design: the contractor's manual link, when there is one, is
    // already on the page and remains the honest fallback.
  });
})();
`;

/// The card-payment client.
///
/// Deliberately written without JavaScript template literals: this string is
/// itself inside one, and a stray dollar-brace would be interpolated by the
/// Worker instead of reaching the browser.
///
/// WHAT THIS CODE CANNOT DO, BY CONSTRUCTION:
///   * see a card number — the fields are an iframe served by Stripe;
///   * choose the amount — the server reads it from the invoice balance;
///   * choose the platform fee — the server reads it from `platform_settings`;
///   * mark anything paid — only the signature-verified webhook does that.
function cardPaymentScript(pay: PayContext): string {
  return `<script src="https://js.stripe.com/v3/"></script>\n<script>\n${CARD_CLIENT.replace("__PAY_CONFIG__", jsonForScript(pay))}\n</script>`;
}

/// Where an Express onboarding session lands when it finishes or expires.
///
/// Stripe requires both a return_url and a refresh_url, and an onboarding link
/// is single-use: without real pages here the owner is dropped on a URL that
/// does not resolve, which is exactly the dead end this fixes.
///
/// These pages are deliberately dumb. They hold no credential, take no
/// parameter, and assert nothing about whether onboarding actually succeeded —
/// only Stripe knows that, and the app re-reads it from Stripe on next open.
/// There is no deep link back into the app because the app's URL scheme is
/// reserved for Supabase auth callbacks, and a Stripe redirect through it would
/// be misread as a sign-in attempt.
function stripeLandingPage(kind: "return" | "refresh"): Response {
  const finished = kind === "return";
  const title = finished ? "Setup submitted" : "This setup link has expired";
  const body = finished
    ? "Thanks \u2014 your details have gone to Stripe. You can close this page and switch back to Harbour South FieldOps. Stripe usually confirms within a minute, and the app shows your live status on the Subscription screen."
    : "Stripe setup links can only be opened once. Nothing has been lost. Switch back to Harbour South FieldOps, open the Subscription screen and tap Continue setup to carry on where you left off.";

  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${escapeHtml(title)}</title>
<style>
  :root { color-scheme: light; }
  body { margin:0; min-height:100vh; display:grid; place-items:center; background:#f3f4f7; padding:24px;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; color:#15161a; }
  .card { background:#fff; border-radius:18px; padding:32px 26px; max-width:440px; text-align:center;
          box-shadow:0 1px 3px rgba(16,18,27,.08),0 12px 32px rgba(16,18,27,.06); }
  .mark { width:46px; height:46px; border-radius:50%; margin:0 auto 16px; display:grid; place-items:center;
          background:${finished ? "#e7f5ec" : "#fff5e6"}; color:${finished ? "#14603a" : "#7a4b00"};
          font-size:22px; font-weight:700; }
  h1 { font-size:19px; margin:0 0 10px; letter-spacing:-.01em; }
  p { margin:0; font-size:15px; line-height:1.6; color:#606374; }
</style></head>
<body><div class="card">
  <div class="mark">${finished ? "\u2713" : "!"}</div>
  <h1>${escapeHtml(title)}</h1>
  <p>${escapeHtml(body)}</p>
</div></body></html>`;

  return new Response(html, { status: 200, headers: pageHeaders });
}

// =============================================================================
// Team invitations
//
// An owner or admin invites somebody by email. The invitation ROW is created by
// the database (`create_invitation`), which takes the company from the caller's
// own session and stamps the role — this Worker cannot create, alter or
// re-target an invitation, and holds no database credential that would let it.
//
// What this Worker adds is the part that was missing entirely: actually
// delivering the invitation. Before this, the code was displayed to the owner
// and had to be relayed by hand, so an invited engineer never received anything.
//
// AUTHORISATION is the caller's own JWT, twice over:
//   1. The token is verified against Supabase Auth before anything is read.
//   2. The invitation row is then read WITH THAT SAME TOKEN, so Row Level
//      Security is what proves the invitation belongs to the caller's company
//      and that their role may see it at all. A caller who points this at
//      another company's invitation gets nothing back and a 404.
//
// The recipient address is taken from the row the database returned, never from
// the request body, so this cannot be used to mail an invitation somewhere it
// was not addressed.
// =============================================================================

/// Matches the invitation codes `create_invitation` issues, and nothing that
/// could be smuggled into a URL or an email header.
const INVITE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{6,128}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const jsonHeaders: Record<string, string> = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface InvitationRow {
  id: string;
  email: string;
  role: string;
  company_id: string;
  expires_at: string;
  accepted_at: string | null;
  revoked_at: string | null;
}

const ROLE_TITLES: Record<string, string> = {
  owner: "Owner",
  admin: "Admin",
  dispatcher: "Dispatcher",
  fieldWorker: "Engineer",
  accounts: "Accounts",
};

function roleTitle(role: string): string {
  return ROLE_TITLES[role] ?? role;
}

function inviteEmailHtml(
  companyName: string,
  personName: string,
  role: string,
  joinUrl: string,
  token: string,
  expiresLabel: string,
): string {
  const greeting = personName ? `Hi ${escapeHtml(personName)},` : "Hello,";
  return `<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:#15161a;line-height:1.6;max-width:520px">` +
    `<p style="font-size:16px;margin:0 0 14px">${greeting}</p>` +
    `<p style="margin:0 0 16px"><strong>${escapeHtml(companyName)}</strong> has invited you to join them on ` +
    `<strong>Harbour South FieldOps</strong> as <strong>${escapeHtml(roleTitle(role))}</strong>.</p>` +
    `<p style="margin:0 0 24px"><a href="${escapeHtml(joinUrl)}" style="background:#E1691A;color:#fff;` +
    `text-decoration:none;padding:13px 22px;border-radius:11px;font-weight:600;display:inline-block">Set up your account</a></p>` +
    `<p style="margin:0 0 6px;color:#606374;font-size:14px">If the button doesn't work, open Harbour South FieldOps, ` +
    `choose <strong>Join</strong> on the sign-in screen and enter this code:</p>` +
    `<p style="margin:0 0 18px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:15px;` +
    `background:#f3f4f7;border-radius:9px;padding:12px 14px;word-break:break-all">${escapeHtml(token)}</p>` +
    `<p style="margin:0;color:#8a8d9b;font-size:13px">${escapeHtml(expiresLabel)} ` +
    `You choose your own password when you set up your account — nobody at ${escapeHtml(companyName)} can see it.</p>` +
    `</div>`;
}

async function dispatchInvitation(request: Request, env: Env, origin: string): Promise<Response> {
  const base = (env.EXPO_PUBLIC_SUPABASE_URL ?? "").replace(/\/+$/, "");
  const anonKey = (env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? "").trim();
  if (!base || !anonKey) {
    console.error("[invite] Supabase coordinates are not configured for the Worker");
    return Response.json({ error: "unavailable" }, { status: 503, headers: jsonHeaders });
  }

  const authorization = request.headers.get("Authorization") ?? "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) {
    return Response.json({ error: "unauthorized" }, { status: 401, headers: jsonHeaders });
  }

  const body = (await request.json().catch(() => ({}))) as {
    invitationId?: string;
    token?: string;
    name?: string;
  };

  const invitationId = (body.invitationId ?? "").trim();
  const token = (body.token ?? "").trim();
  const personName = (body.name ?? "").trim().slice(0, 80);

  if (!UUID_PATTERN.test(invitationId) || !INVITE_TOKEN_PATTERN.test(token)) {
    return Response.json({ error: "invalidRequest" }, { status: 400, headers: jsonHeaders });
  }

  const callerHeaders = { apikey: anonKey, Authorization: authorization, Accept: "application/json" };

  // 1. Is this a real, live identity? A dropped or forged token stops here.
  const identity = await fetch(`${base}/auth/v1/user`, { headers: callerHeaders });
  if (!identity.ok) {
    return Response.json({ error: "unauthorized" }, { status: 401, headers: jsonHeaders });
  }

  // 2. Read the invitation AS THE CALLER. RLS on `invitations` is the whole
  //    boundary: it returns the row only for a caller in the same company whose
  //    role may manage users. Nothing here re-implements that rule.
  const lookup = await fetch(
    `${base}/rest/v1/invitations?id=eq.${encodeURIComponent(invitationId)}` +
      `&select=id,email,role,company_id,expires_at,accepted_at,revoked_at&limit=1`,
    { headers: callerHeaders },
  );

  if (!lookup.ok) {
    console.error("[invite] invitation lookup failed", lookup.status);
    return Response.json({ error: "notFound" }, { status: 404, headers: jsonHeaders });
  }

  const rows = (await lookup.json().catch(() => [])) as InvitationRow[];
  const invitation = Array.isArray(rows) ? rows[0] : undefined;
  if (!invitation) {
    return Response.json({ error: "notFound" }, { status: 404, headers: jsonHeaders });
  }
  if (invitation.accepted_at || invitation.revoked_at) {
    return Response.json({ error: "notUsable" }, { status: 409, headers: jsonHeaders });
  }

  // The company name, again through the caller's own token.
  let companyName = "Your company";
  try {
    const companyLookup = await fetch(
      `${base}/rest/v1/companies?id=eq.${encodeURIComponent(invitation.company_id)}&select=name&limit=1`,
      { headers: callerHeaders },
    );
    if (companyLookup.ok) {
      const companies = (await companyLookup.json()) as Array<{ name?: string }>;
      companyName = companies?.[0]?.name?.trim() || companyName;
    }
  } catch (err) {
    console.error("[invite] company lookup failed", err instanceof Error ? err.message : err);
  }

  const apiKey = (env.RESEND_API_KEY ?? "").trim();
  const from = (env.RESEND_FROM_EMAIL ?? "").trim();

  const joinUrl = `${origin}/join?t=${encodeURIComponent(token)}` +
    (personName ? `&n=${encodeURIComponent(personName)}` : "");

  if (!apiKey || !from) {
    // NOT a success. The invitation exists and the code is valid, but nothing
    // was delivered, and the app is told exactly that so it can fall back to
    // handing the code over in person.
    console.warn("[invite] email provider not configured — nothing was delivered");
    return Response.json(
      {
        delivered: false,
        configured: false,
        recipient: invitation.email,
        joinUrl,
        detail: "Email provider not configured, so nothing was sent.",
      },
      { status: 200, headers: jsonHeaders },
    );
  }

  const expiresLabel = (() => {
    try {
      const when = new Intl.DateTimeFormat("en-US", { day: "numeric", month: "short", year: "numeric" })
        .format(new Date(invitation.expires_at));
      return `This invitation expires on ${when}.`;
    } catch {
      return "This invitation expires.";
    }
  })();

  const subject = `${companyName} invited you to Harbour South FieldOps`;
  const text = `${personName ? `Hi ${personName},\n\n` : ""}${companyName} has invited you to join them on ` +
    `Harbour South FieldOps as ${roleTitle(invitation.role)}.\n\n` +
    `Set up your account:\n${joinUrl}\n\n` +
    `Or open the app, choose "Join" on the sign-in screen and enter this code:\n${token}\n\n` +
    `${expiresLabel} You choose your own password.\n`;

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from,
        to: [invitation.email],
        subject,
        html: inviteEmailHtml(companyName, personName, invitation.role, joinUrl, token, expiresLabel),
        text,
      }),
    });

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      console.error("[invite] email provider refused the message", response.status, detail.slice(0, 300));
      return Response.json(
        {
          delivered: false,
          configured: true,
          recipient: invitation.email,
          joinUrl,
          detail: `The email provider refused the message (${response.status}).`,
        },
        { status: 200, headers: jsonHeaders },
      );
    }

    return Response.json(
      { delivered: true, configured: true, recipient: invitation.email, joinUrl, detail: "Invitation sent." },
      { status: 200, headers: jsonHeaders },
    );
  } catch (err) {
    console.error("[invite] email transport failed", err instanceof Error ? err.message : err);
    return Response.json(
      {
        delivered: false,
        configured: true,
        recipient: invitation.email,
        joinUrl,
        detail: "Couldn't reach the email provider.",
      },
      { status: 200, headers: jsonHeaders },
    );
  }
}

/// The page an invited person lands on from their email.
///
/// It carries no credential of its own and reveals nothing about the company —
/// only the code that was already in the email that brought them here. Its job
/// is to hand the code to the app on a phone, and to still be useful on a
/// laptop where the app cannot be opened at all.
function joinLandingPage(token: string, name: string): Response {
  const deepLink = `com.harboursouth.fieldservice://join?token=${encodeURIComponent(token)}` +
    (name ? `&name=${encodeURIComponent(name)}` : "");

  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Join Harbour South FieldOps</title>
<style>
  :root { color-scheme: light; }
  body { margin:0; min-height:100vh; display:grid; place-items:center; background:#f3f4f7; padding:24px;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; color:#15161a; }
  .card { background:#fff; border-radius:20px; padding:32px 26px; max-width:460px; width:100%;
          box-shadow:0 1px 3px rgba(16,18,27,.08),0 12px 32px rgba(16,18,27,.06); }
  h1 { font-size:21px; margin:0 0 10px; letter-spacing:-.015em; }
  p { margin:0 0 16px; font-size:15px; line-height:1.6; color:#606374; }
  .cta { display:block; text-align:center; background:#E1691A; color:#fff; text-decoration:none;
         padding:15px 22px; border-radius:12px; font-weight:600; font-size:16px; margin:0 0 20px; }
  .code { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:14px; background:#f3f4f7;
          border-radius:10px; padding:13px 15px; word-break:break-all; color:#15161a; user-select:all; }
  .label { font-size:12px; text-transform:uppercase; letter-spacing:.08em; color:#8a8d9b;
           font-weight:700; margin:0 0 7px; }
</style></head>
<body><div class="card">
  <h1>Set up your account</h1>
  <p>You've been invited to Harbour South FieldOps. Open the app on your phone to choose a password and get going.</p>
  <a class="cta" href="${escapeHtml(deepLink)}">Open Harbour South FieldOps</a>
  <p class="label">Or enter this join code</p>
  <div class="code">${escapeHtml(token)}</div>
  <p style="margin:16px 0 0;font-size:13px;color:#8a8d9b">On your phone, open Harbour South FieldOps, tap
  <strong>Join</strong> on the sign-in screen, then enter your email, a password of your own choosing, your name
  and this code.</p>
</div></body></html>`;

  return new Response(html, { status: 200, headers: pageHeaders });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/invite") {
      if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: jsonHeaders });
      if (request.method !== "POST") {
        return Response.json({ error: "methodNotAllowed" }, { status: 405, headers: jsonHeaders });
      }
      return dispatchInvitation(request, env, url.origin);
    }

    if (url.pathname === "/join") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method not allowed", { status: 405, headers: pageHeaders });
      }
      const token = (url.searchParams.get("t") ?? "").trim();
      if (!INVITE_TOKEN_PATTERN.test(token)) return notFoundPage();
      return joinLandingPage(token, (url.searchParams.get("n") ?? "").trim().slice(0, 80));
    }

    if (url.pathname === "/stripe/return" || url.pathname === "/stripe/refresh") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method not allowed", { status: 405, headers: pageHeaders });
      }
      return stripeLandingPage(url.pathname.endsWith("refresh") ? "refresh" : "return");
    }

    if (url.pathname === "/q") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method not allowed", { status: 405, headers: pageHeaders });
      }
      const token = url.searchParams.get("t") ?? "";
      if (!TOKEN_PATTERN.test(token)) return notFoundPage();
      return quotePage(token, env);
    }

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

        // Stripe appends redirect_status when it sends the customer back. Only
        // the three values Stripe documents are honoured; anything else is
        // treated as a failure rather than quietly shown as success.
        const rawStatus = url.searchParams.get("redirect_status");
        const redirectStatus = url.searchParams.get("paid") === "1"
          ? (rawStatus === "succeeded" || rawStatus === "processing" ? rawStatus : "failed")
          : null;

        return renderInvoice(data, {
          supabaseBase: base,
          anonKey: (env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? "").trim() || null,
          token,
          returnUrl: `${url.origin}/i?t=${token}&paid=1`,
          redirectStatus,
        });
      } catch (err) {
        console.error("[invoice] could not resolve the invoice", err instanceof Error ? err.message : err);
        return notFoundPage();
      }
    }

    // Readiness only: booleans, never the values themselves. This is what makes
    // it possible to confirm from outside that the email credential actually
    // reached the deployment, instead of discovering it from a failed invite.
    return Response.json({
      ok: true,
      service: "harbour-south-fieldops",
      email: {
        configured: Boolean((env.RESEND_API_KEY ?? "").trim() && (env.RESEND_FROM_EMAIL ?? "").trim()),
      },
    });
  },
};
