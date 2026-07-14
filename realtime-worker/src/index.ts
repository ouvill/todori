import {
  HEADER_CHANNEL,
  HEADER_DEVICE,
  HEADER_EXPIRES_AT,
  HEADER_SOURCE_DEVICE,
} from "./contracts";
import {
  isValidSigningKeySet,
  verifyPublish,
  verifyTicket,
  type SigningKeySet,
} from "./crypto";
export { RealtimeChannel } from "./realtime-channel";

export default {
  async fetch(request: Request, env: CloudflareBindings): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/v1/connect") {
      return handleConnect(request, env);
    }
    if (url.pathname === "/v1/publish") {
      return handlePublish(request, env);
    }
    return new Response("not found", { status: 404 });
  },
} satisfies ExportedHandler<CloudflareBindings>;

async function handleConnect(
  request: Request,
  env: CloudflareBindings,
): Promise<Response> {
  if (request.method !== "GET") return methodNotAllowed("GET");
  if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
    return new Response("websocket upgrade required", { status: 426 });
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return unauthorized();
  const token = authorization.slice("Bearer ".length);
  if (!token || token.includes(" ")) return unauthorized();

  const nowSeconds = Math.floor(Date.now() / 1000);
  const keys = ticketKeys(env);
  if (!isValidSigningKeySet(keys)) return unavailable();
  const ticket = await verifyTicket(token, keys, nowSeconds);
  if (!ticket) return unauthorized();

  const namespace = channelNamespace(env);
  const stub = namespace.getByName(ticket.channel);
  const headers = new Headers({ Upgrade: "websocket" });
  headers.set(HEADER_CHANNEL, ticket.channel);
  headers.set(HEADER_DEVICE, ticket.device);
  headers.set(HEADER_EXPIRES_AT, String(ticket.exp));
  return stub.fetch("https://realtime.internal/connect", { headers });
}

async function handlePublish(
  request: Request,
  env: CloudflareBindings,
): Promise<Response> {
  if (request.method !== "POST") return methodNotAllowed("POST");
  const nowSeconds = Math.floor(Date.now() / 1000);
  const keys = publishKeys(env);
  if (!isValidSigningKeySet(keys)) return unavailable();
  const verified = await verifyPublish(request, keys, nowSeconds);
  if (!verified) return unauthorized();

  const namespace = channelNamespace(env);
  const stub = namespace.getByName(verified.payload.channel);
  const headers = new Headers();
  headers.set(HEADER_SOURCE_DEVICE, verified.payload.source_device);
  return stub.fetch("https://realtime.internal/publish", {
    body: verified.body,
    headers,
    method: "POST",
  });
}

function ticketKeys(env: CloudflareBindings): SigningKeySet {
  return {
    current: { id: env.TICKET_KEY_CURRENT_ID, encodedKey: env.TICKET_KEY_CURRENT },
    previous: { id: env.TICKET_KEY_PREVIOUS_ID, encodedKey: env.TICKET_KEY_PREVIOUS },
  };
}

function publishKeys(env: CloudflareBindings): SigningKeySet {
  return {
    current: { id: env.PUBLISH_KEY_CURRENT_ID, encodedKey: env.PUBLISH_KEY_CURRENT },
    previous: { id: env.PUBLISH_KEY_PREVIOUS_ID, encodedKey: env.PUBLISH_KEY_PREVIOUS },
  };
}

function channelNamespace(env: CloudflareBindings): DurableObjectNamespace {
  if (env.TEST_ONLY_UNRESTRICTED_NAMESPACE === "enabled") {
    return env.REALTIME_CHANNELS;
  }
  return env.REALTIME_CHANNELS.jurisdiction("eu");
}

function methodNotAllowed(allowed: string): Response {
  return new Response("method not allowed", {
    headers: { Allow: allowed },
    status: 405,
  });
}

function unauthorized(): Response {
  return new Response("unauthorized", { status: 401 });
}

function unavailable(): Response {
  return new Response("realtime unavailable", { status: 503 });
}
