import type { ReactNode } from "react";
import { CalendarDays, ClipboardList, MapPin } from "lucide-react";

export function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="grid min-h-full lg:grid-cols-[1.05fr_1fr]">
      <div className="relative hidden overflow-hidden bg-brand-navy p-12 text-white lg:flex lg:flex-col">
        {/* Harbour arch, echoing the logo */}
        <div className="pointer-events-none absolute -bottom-80 left-[62%] h-[640px] w-[640px] -translate-x-1/2 rounded-full border-[46px] border-brand-orange/90" />
        <div className="pointer-events-none absolute -bottom-64 left-[62%] h-[460px] w-[460px] -translate-x-1/2 rounded-full border border-white/10" />
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_20%_10%,hsl(225_72%_38%/0.55),transparent_55%)]" />

        <div className="relative flex items-center gap-3">
          <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-white">
            <img src="/brand-logo.png" alt="" className="h-10 w-10 object-contain" />
          </div>
          <div className="leading-tight">
            <p className="text-lg font-bold">Harbour South</p>
            <p className="text-xs font-semibold uppercase tracking-[0.16em] text-brand-orange">FieldOps · Office</p>
          </div>
        </div>

        <div className="relative mt-24 max-w-md">
          <h1 className="text-[44px] font-bold leading-[1.05] tracking-tight">Run the whole day from one screen.</h1>
          <p className="mt-4 text-lg text-white/70">
            The same jobs, people and schedule as the iPhone app — laid out for the office.
          </p>
          <ul className="mt-10 space-y-4 text-[15px] text-white/85">
            {[
              { icon: ClipboardList, text: "Drag jobs onto your team's day" },
              { icon: CalendarDays, text: "Day, week and month calendar" },
              { icon: MapPin, text: "See who's where, live" },
            ].map(({ icon: Icon, text }) => (
              <li key={text} className="flex items-center gap-3">
                <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/10">
                  <Icon className="h-[18px] w-[18px] text-brand-orange" />
                </span>
                {text}
              </li>
            ))}
          </ul>
        </div>
      </div>

      <div className="flex items-center justify-center bg-background px-6 py-12">
        <div className="w-full max-w-[400px]">
          <div className="mb-10 flex items-center gap-3 lg:hidden">
            <img src="/brand-logo.png" alt="" className="h-12 w-12 rounded-xl bg-white object-contain" />
            <p className="text-lg font-bold">Harbour South</p>
          </div>
          {children}
        </div>
      </div>
    </div>
  );
}
