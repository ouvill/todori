interface CloudflareBindings {
  REALTIME_CHANNELS: DurableObjectNamespace;
  PUBLISH_KEY_CURRENT: string;
  PUBLISH_KEY_CURRENT_ID: string;
  PUBLISH_KEY_PREVIOUS: string;
  PUBLISH_KEY_PREVIOUS_ID: string;
  TICKET_KEY_CURRENT: string;
  TICKET_KEY_CURRENT_ID: string;
  TICKET_KEY_PREVIOUS: string;
  TICKET_KEY_PREVIOUS_ID: string;
  TEST_ONLY_UNRESTRICTED_NAMESPACE?: "enabled";
}

declare namespace Cloudflare {
  interface Env extends CloudflareBindings {}

  interface GlobalProps {
    durableNamespaces: "RealtimeChannel";
    mainModule: typeof import("./index");
  }
}
