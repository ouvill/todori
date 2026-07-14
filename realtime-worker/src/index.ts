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
import { observeRealtimeWorker } from "./observability";
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
  if (request.method !== "GET") return connectFailure(methodNotAllowed("GET"));
  if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
    return connectFailure(new Response("websocket upgrade required", { status: 426 }));
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return connectFailure(unauthorized());
  const token = authorization.slice("Bearer ".length);
  if (!token || token.includes(" ")) return connectFailure(unauthorized());

  const nowSeconds = Math.floor(Date.now() / 1000);
  const keys = ticketKeys(env);
  if (!isValidSigningKeySet(keys)) return connectFailure(unavailable());
  const ticket = await verifyTicket(token, keys, nowSeconds);
  if (!ticket) return connectFailure(unauthorized());

  const namespace = channelNamespace(env);
  const stub = namespace.getByName(ticket.channel);
  const headers = new Headers({ Upgrade: "websocket" });
  headers.set(HEADER_CHANNEL, ticket.channel);
  headers.set(HEADER_DEVICE, ticket.device);
  headers.set(HEADER_EXPIRES_AT, String(ticket.exp));
  try {
    const response = await stub.fetch("https://realtime.internal/connect", { headers });
    if (response.status === 101) {
      observeRealtimeWorker("realtime_connect_succeeded");
      return response;
    }
    return connectFailure(response);
  } catch {
    return connectFailure(unavailable());
  }
}

async function handlePublish(
  request: Request,
  env: CloudflareBindings,
): Promise<Response> {
  if (request.method !== "POST") return publishFailure(methodNotAllowed("POST"));
  const nowSeconds = Math.floor(Date.now() / 1000);
  const keys = publishKeys(env);
  if (!isValidSigningKeySet(keys)) return publishFailure(unavailable());
  const verified = await verifyPublish(request, keys, nowSeconds);
  if (!verified) return publishFailure(unauthorized());

  const namespace = channelNamespace(env);
  const stub = namespace.getByName(verified.payload.channel);
  const headers = new Headers();
  headers.set(HEADER_SOURCE_DEVICE, verified.payload.source_device);
  try {
    const response = await stub.fetch("https://realtime.internal/publish", {
      body: verified.body,
      headers,
      method: "POST",
    });
    if (response.ok) {
      observeRealtimeWorker("realtime_publish_succeeded");
      return response;
    }
    return publishFailure(response);
  } catch {
    return publishFailure(unavailable());
  }
}

function connectFailure(response: Response): Response {
  observeRealtimeWorker("realtime_connect_failed");
  return response;
}

function publishFailure(response: Response): Response {
  observeRealtimeWorker("realtime_publish_failed");
  return response;
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
