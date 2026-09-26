export type Screen = {
  id: string;
  route: string;
  group: string;
  title: string;
  description: string;
  kind: string;
  metrics: string[];
  columns: string[];
  rows: string[][];
  panels: { title: string; body: string }[];
  note: string;
  parent: string | null;
  form: string[];
  action: string;
  contract: string;
  children: string[];
  persona: string;
  document: string;
};
export type Metric = {
  label: string;
  value: string;
  hint: string;
  formula: string;
  scope: string;
  status: string;
  cents?: number;
};
export type ReviewState =
  | "ready"
  | "loading"
  | "empty"
  | "partial"
  | "stale"
  | "error"
  | "denied"
  | "provisional"
  | "final";
export type Scope = "all" | "production";
