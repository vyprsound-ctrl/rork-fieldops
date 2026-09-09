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
      appearance: { theme: 'stripe', variables: { colorPrimary: '#0f5c4a', borderRadius: '10px' } }
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

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/stripe/return" || url.pathname === "/stripe/refresh") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method not allowed", { status: 405, headers: pageHeaders });
      }
      return stripeLandingPage(url.pathname.endsWith("refresh") ? "refresh" : "return");
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

    return Response.json({ ok: true, service: "tradedesk" });
  },
};
