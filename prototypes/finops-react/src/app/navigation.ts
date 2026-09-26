import { useSyncExternalStore } from "react";
import type { ReviewState, Scope } from "../types";
const subscribe = (fn: () => void) => {
  window.addEventListener("hashchange", fn);
  return () => window.removeEventListener("hashchange", fn);
};
export function useRoute() {
  const hash = useSyncExternalStore(
    subscribe,
    () => window.location.hash,
    () => "#/home",
  );
  const [path, query] = hash.replace(/^#\/?/, "").split("?");
  const params = new URLSearchParams(query);
  return {
    id: path || "home",
    scope: (params.get("account") === "production"
      ? "production"
      : "all") as Scope,
    review: (params.get("state") || "ready") as ReviewState,
    params,
  };
}
export function navigate(id: string) {
  const q = window.location.hash.split("?")[1];
  window.location.hash = "/" + id + (q ? "?" + q : "");
  window.scrollTo({ top: 0 });
}
export function setParam(key: string, value: string) {
  const [path, query] = window.location.hash.replace(/^#/, "").split("?");
  const p = new URLSearchParams(query);
  p.set(key, value);
  window.location.hash = (path || "/home") + "?" + p.toString();
}
export function href(id: string) {
  const q = window.location.hash.split("?")[1];
  return "#/" + id + (q ? "?" + q : "");
}
