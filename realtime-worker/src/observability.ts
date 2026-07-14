export const REALTIME_WORKER_EVENTS = [
  "realtime_connect_succeeded",
  "realtime_connect_failed",
  "realtime_publish_succeeded",
  "realtime_publish_failed",
] as const;

export type RealtimeWorkerEvent = (typeof REALTIME_WORKER_EVENTS)[number];

export interface RealtimeWorkerObservation {
  event: RealtimeWorkerEvent;
}

export function realtimeWorkerObservation(
  event: RealtimeWorkerEvent,
): RealtimeWorkerObservation {
  return { event };
}

export function observeRealtimeWorker(event: RealtimeWorkerEvent): void {
  console.info(JSON.stringify(realtimeWorkerObservation(event)));
}
