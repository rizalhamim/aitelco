import { useSyncExternalStore } from "react";

const subscribe = () => () => {};

/** False during server render and hydration, true afterwards — for reading browser-only state. */
export function useMounted(): boolean {
  return useSyncExternalStore(subscribe, () => true, () => false);
}
