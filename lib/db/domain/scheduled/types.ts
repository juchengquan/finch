// lib/db/domain/scheduled/types.ts — public row + input/patch shapes for the
// scheduled (recurring transactions) domain. Keep this file free of SQL
// imports — it should be safe to import from any layer (UI components, route
// handlers, app_state) without pulling in the DB driver.

export interface ScheduledPatch {
  name?: string;
  description?: string | null;
  amount?: number | null;
  frequency?: string;
  dayOfMonth?: number;
  weekDay?: number;
  autoPost?: number;
  color?: string | null;
  type?: string;
  category?: string | null;
  endDate?: string | null;
  maxExecutions?: number | null;
  installmentTotal?: number | null;
}

export interface NewScheduled {
  id: string;
  ledgerId: string;
  name: string;
  description: string | null;
  type: string;
  amount: number | null;
  frequency: string;
  dayOfMonth: number;
  weekDay: number | null;
  accountId: string;
  fromAccountId: string | null;
  autoPost: number;
  color: string | null;
  category: string | null;
  startDate: string;
  endDate: string | null;
  maxExecutions: number | null;
  installmentTotal: number | null;
}
