/**
 * The Harbour South domain, mirrored from the iPhone app's models so both apps
 * use the same words, the same workflow and the same role rules.
 * Source of truth for the rules is the database; this file keeps the UI honest.
 */

export type Role = "owner" | "admin" | "dispatcher" | "fieldWorker" | "accounts";

export const OFFICE_ROLES: Role[] = ["owner", "admin", "dispatcher", "accounts"];

export const ROLE_TITLE: Record<Role, string> = {
  owner: "Owner",
  admin: "Admin",
  dispatcher: "Dispatcher",
  fieldWorker: "Field worker",
  accounts: "Accounts",
};

export type Permission =
  | "companyProfileRead"
  | "companyProfileManage"
  | "companyDelete"
  | "usersRead"
  | "usersManage"
  | "saasBillingRead"
  | "saasBillingManage"
  | "customersReadAll"
  | "customersManage"
  | "customerBillingDetailsRead"
  | "jobsReadAll"
  | "jobsManage"
  | "jobStatusHistoryReadAll"
  | "calendarReadAll"
  | "assignmentsManage"
  | "jobNotesRead"
  | "jobNotesCreate"
  | "jobPhotosRead"
  | "jobPhotosCreate"
  | "equipmentRead"
  | "equipmentManage"
  | "fieldWorkerLocationReadAll"
  | "quotesRead"
  | "quotesManage"
  | "quoteFinancialsRead"
  | "invoicesRead"
  | "invoicesManage"
  | "paymentsRead"
  | "paymentsManage"
  | "smsLedgerRead"
  | "smsCreditsConsume"
  | "smsCreditsPurchase"
  | "reportsOperational"
  | "reportsFinancial";

/** Copied exactly from the database's role_permissions table (office roles). */
const MATRIX: Record<Role, Permission[]> = {
  owner: [
    "companyProfileRead", "companyProfileManage", "companyDelete", "usersRead", "usersManage", "saasBillingRead",
    "saasBillingManage", "customersReadAll", "customersManage", "customerBillingDetailsRead", "jobsReadAll", "jobsManage",
    "jobStatusHistoryReadAll", "calendarReadAll", "assignmentsManage", "jobNotesRead", "jobNotesCreate", "jobPhotosRead",
    "jobPhotosCreate", "equipmentRead", "equipmentManage", "fieldWorkerLocationReadAll", "quotesRead", "quotesManage",
    "quoteFinancialsRead", "invoicesRead", "invoicesManage", "paymentsRead", "paymentsManage", "smsLedgerRead",
    "smsCreditsConsume", "smsCreditsPurchase", "reportsOperational", "reportsFinancial",
  ],
  admin: [
    "companyProfileRead", "usersRead", "usersManage", "customersReadAll", "customersManage", "customerBillingDetailsRead",
    "jobsReadAll", "jobsManage", "jobStatusHistoryReadAll", "calendarReadAll", "assignmentsManage", "jobNotesRead",
    "jobNotesCreate", "jobPhotosRead", "jobPhotosCreate", "equipmentRead", "equipmentManage", "fieldWorkerLocationReadAll",
    "quotesRead", "quotesManage", "quoteFinancialsRead", "invoicesRead", "invoicesManage", "paymentsRead", "paymentsManage",
    "smsLedgerRead", "smsCreditsConsume", "reportsOperational", "reportsFinancial",
  ],
  dispatcher: [
    "companyProfileRead", "usersRead", "customersReadAll", "customersManage", "jobsReadAll", "jobsManage",
    "jobStatusHistoryReadAll", "calendarReadAll", "assignmentsManage", "jobNotesRead", "jobNotesCreate", "jobPhotosRead",
    "jobPhotosCreate", "equipmentRead", "fieldWorkerLocationReadAll", "quotesRead", "smsCreditsConsume", "reportsOperational",
  ],
  fieldWorker: [],
  accounts: [
    "companyProfileRead", "usersRead", "customersReadAll", "customerBillingDetailsRead", "jobsReadAll", "quotesRead",
    "quoteFinancialsRead", "invoicesRead", "invoicesManage", "paymentsRead", "paymentsManage", "smsLedgerRead",
    "reportsFinancial",
  ],
};

/** What a role keeps while the company has no active subscription. */
const READ_ONLY_KEEP: Permission[] = [
  "companyProfileRead", "companyDelete", "saasBillingRead", "saasBillingManage", "usersRead",
  "jobsReadAll", "jobStatusHistoryReadAll", "calendarReadAll", "customersReadAll", "customerBillingDetailsRead",
  "jobNotesRead", "jobPhotosRead", "fieldWorkerLocationReadAll", "quotesRead", "quoteFinancialsRead", "invoicesRead",
  "paymentsRead", "equipmentRead", "smsLedgerRead", "reportsOperational", "reportsFinancial",
];

export function permissionsFor(role: Role, readOnly: boolean): Set<Permission> {
  const granted = MATRIX[role] ?? [];
  return new Set(readOnly ? granted.filter((p) => READ_ONLY_KEEP.includes(p)) : granted);
}

// ---------------------------------------------------------------------------
// Trades and terminology
// ---------------------------------------------------------------------------

export type Trade =
  | "hvac" | "plumbing" | "electrical" | "roofing" | "applianceRepair" | "locksmith"
  | "generalMaintenance" | "pestControl" | "other" | "propertyServices" | "automotive";

export interface Terminology {
  worker: string;
  workerPlural: string;
  Worker: string;
  WorkerPlural: string;
}

const cap = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);

export function terminology(trade: Trade | string | null | undefined): Terminology {
  const map: Record<string, [string, string]> = {
    hvac: ["field worker", "field workers"],
    plumbing: ["plumber", "plumbers"],
    electrical: ["electrician", "electricians"],
    roofing: ["roofer", "roofers"],
    locksmith: ["locksmith", "locksmiths"],
  };
  const [worker, workerPlural] = map[trade ?? ""] ?? ["technician", "technicians"];
  return { worker, workerPlural, Worker: cap(worker), WorkerPlural: cap(workerPlural) };
}

// ---------------------------------------------------------------------------
// Jobs
// ---------------------------------------------------------------------------

export type JobStatus =
  | "scheduled" | "workerAssigned" | "travelling" | "arrived" | "inProgress"
  | "completed" | "invoiced" | "paid" | "cancelled";

export type JobKind = "callOut" | "install" | "maintenance" | "warranty";
export type JobPriority = "standard" | "urgent";

export const JOB_STATUSES: JobStatus[] = [
  "scheduled", "workerAssigned", "travelling", "arrived", "inProgress", "completed", "invoiced", "paid", "cancelled",
];

export const PIPELINE: JobStatus[] = [
  "scheduled", "workerAssigned", "travelling", "arrived", "inProgress", "completed", "invoiced", "paid",
];

export function statusTitle(status: JobStatus, terms: Terminology): string {
  switch (status) {
    case "scheduled": return "Scheduled";
    case "workerAssigned": return `${terms.Worker} assigned`;
    case "travelling": return "Travelling";
    case "arrived": return "Arrived";
    case "inProgress": return "In progress";
    case "completed": return "Completed";
    case "invoiced": return "Invoiced";
    case "paid": return "Paid";
    case "cancelled": return "Cancelled";
  }
}

export type Tone = "info" | "warning" | "success" | "neutral" | "danger";

export function statusTone(status: JobStatus): Tone {
  switch (status) {
    case "scheduled":
    case "workerAssigned": return "info";
    case "travelling":
    case "arrived":
    case "inProgress": return "warning";
    case "completed":
    case "invoiced":
    case "paid": return "success";
    case "cancelled": return "neutral";
  }
}

export const isOpen = (s: JobStatus) => !["completed", "invoiced", "paid", "cancelled"].includes(s);
export const isFieldActive = (s: JobStatus) => ["travelling", "arrived", "inProgress"].includes(s);

export const KIND_TITLE: Record<JobKind, string> = {
  callOut: "Call-out",
  install: "Installation",
  maintenance: "Maintenance",
  warranty: "Warranty",
};

interface Transition {
  from: JobStatus;
  to: JobStatus;
  action: string;
  needs: Permission | "fieldWork";
  destructive?: boolean;
}

/** The iPhone app's JobWorkflow table. Field steps are done on the phone. */
export const WORKFLOW: Transition[] = [
  { from: "scheduled", to: "workerAssigned", action: "Assign {worker}", needs: "assignmentsManage" },
  { from: "workerAssigned", to: "travelling", action: "Start travel", needs: "fieldWork" },
  { from: "travelling", to: "arrived", action: "Arrived on site", needs: "fieldWork" },
  { from: "arrived", to: "inProgress", action: "Start work", needs: "fieldWork" },
  { from: "inProgress", to: "completed", action: "Complete job", needs: "fieldWork" },
  { from: "completed", to: "invoiced", action: "Mark invoiced", needs: "invoicesManage" },
  { from: "invoiced", to: "paid", action: "Mark paid", needs: "paymentsManage" },
  { from: "workerAssigned", to: "scheduled", action: "Unassign {worker}", needs: "assignmentsManage" },
  { from: "travelling", to: "workerAssigned", action: "Send back to assigned", needs: "jobsManage" },
  { from: "scheduled", to: "cancelled", action: "Cancel job", needs: "jobsManage", destructive: true },
  { from: "workerAssigned", to: "cancelled", action: "Cancel job", needs: "jobsManage", destructive: true },
  { from: "travelling", to: "cancelled", action: "Cancel job", needs: "jobsManage", destructive: true },
  { from: "arrived", to: "cancelled", action: "Cancel job", needs: "jobsManage", destructive: true },
];

/**
 * Status moves the office can make from the web. Assign/unassign are left out:
 * they go through the assignment control so the clash rule always runs.
 */
export function officeTransitions(status: JobStatus, perms: Set<Permission>, terms: Terminology) {
  return WORKFLOW.filter(
    (t) =>
      t.from === status &&
      t.needs !== "fieldWork" &&
      t.needs !== "assignmentsManage" &&
      perms.has(t.needs),
  ).map((t) => ({ ...t, action: t.action.replace("{worker}", terms.worker) }));
}

export type NoteVisibility = "internalOnly" | "customerVisible";

export const PHOTO_KIND_TITLE: Record<string, string> = {
  before: "Before",
  during: "During",
  after: "After",
  equipment: "Equipment",
  damage: "Damage",
  property_condition: "Property",
  part: "Part",
  proof: "Proof",
  signature: "Signature",
  other: "Other",
};

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

export interface JobRow {
  id: string;
  customer_id: string;
  address_id: string;
  equipment_id: string | null;
  quote_id: string | null;
  number: string;
  title: string;
  job_description: string | null;
  kind: JobKind;
  priority: JobPriority;
  status: JobStatus;
  scheduled_start: string | null;
  scheduled_end: string | null;
  actual_start: string | null;
  actual_end: string | null;
  created_at: string;
}

export const JOB_COLUMNS =
  "id,customer_id,address_id,equipment_id,quote_id,number,title,job_description,kind,priority,status,scheduled_start,scheduled_end,actual_start,actual_end,created_at";

export interface Customer {
  id: string;
  name: string;
  type: string;
}

export interface Address {
  id: string;
  customer_id: string;
  line1: string;
  city: string;
  state: string;
  postal_code: string;
  latitude: number | null;
  longitude: number | null;
  access_notes: string | null;
}

export interface AppUser {
  id: string;
  name: string;
  phone: string | null;
  role: Role;
  status: string;
}

/** A job with everything a row on screen needs. */
export interface JobView extends JobRow {
  customer?: Customer;
  address?: Address;
  workerId?: string;
  worker?: AppUser;
}

export const addressLine = (a?: Address) =>
  a ? [a.line1, a.city, a.postal_code].filter(Boolean).join(", ") : "";

export const shortAddress = (a?: Address) => (a ? [a.line1, a.city].filter(Boolean).join(", ") : "");

export const initials = (name: string) =>
  name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0])
    .join("")
    .toUpperCase();

/** A job's booked slot; a start without an end is treated as one hour. */
export function slot(job: Pick<JobRow, "scheduled_start" | "scheduled_end">): [number, number] | null {
  if (!job.scheduled_start) return null;
  const start = new Date(job.scheduled_start).getTime();
  const end = job.scheduled_end ? new Date(job.scheduled_end).getTime() : start + 3600_000;
  return [start, Math.max(start, end)];
}

export interface Clash {
  jobId: string;
  number: string;
  title: string;
  range: string;
}
