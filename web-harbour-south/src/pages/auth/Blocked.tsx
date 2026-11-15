import { Smartphone, UserX } from "lucide-react";

import { Button } from "@/components/ui/button";
import { useSession } from "@/lib/session";
import { AuthLayout } from "./AuthLayout";

const COPY = {
  fieldWorker: {
    icon: Smartphone,
    title: "Use the iPhone app",
    body: "The web app is for the office team. Your jobs, photos, signatures and timesheets are all in the Harbour South app on your iPhone.",
  },
  noMembership: {
    icon: UserX,
    title: "No company found",
    body: "This login isn't part of a company yet. Ask your company owner to invite you, or create your company in the iPhone app.",
  },
  inactive: {
    icon: UserX,
    title: "Your access is paused",
    body: "Your company has deactivated this login. Ask the owner or an admin to reactivate you.",
  },
  error: {
    icon: UserX,
    title: "Couldn't load your workspace",
    body: "Check your connection and try again.",
  },
};

export default function Blocked({ kind }: { kind: keyof typeof COPY }) {
  const { signOut, reload } = useSession();
  const c = COPY[kind];
  return (
    <AuthLayout>
      <div className="mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-tint text-primary">
        <c.icon className="h-6 w-6" />
      </div>
      <h2 className="text-[28px] font-bold tracking-tight">{c.title}</h2>
      <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">{c.body}</p>
      <div className="mt-8 flex gap-2">
        {kind === "error" && <Button onClick={reload}>Try again</Button>}
        <Button variant="outline" onClick={() => void signOut()}>
          Sign out
        </Button>
      </div>
    </AuthLayout>
  );
}
