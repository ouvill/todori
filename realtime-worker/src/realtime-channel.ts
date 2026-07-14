import { DurableObject } from "cloudflare:workers";
import {
  CHANGE_FRAME,
  HEADER_CHANNEL,
  HEADER_DEVICE,
  HEADER_EXPIRES_AT,
  HEADER_SOURCE_DEVICE,
  MAX_CONNECTIONS,
  type ConnectionAttachment,
} from "./contracts";
import { isOpaqueTag } from "./crypto";

const CLOSE_REPLACED = 4001;
const CLOSE_EXPIRED = 4003;

export class RealtimeChannel extends DurableObject<CloudflareBindings> {
  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/connect") {
      return this.acceptConnection(request);
    }
    if (request.method === "POST" && url.pathname === "/publish") {
      return this.publish(request);
    }
    return new Response("not found", { status: 404 });
  }

  override webSocketMessage(socket: WebSocket): void {
    socket.close(1008, "client messages are not accepted");
  }

  override webSocketClose(
    socket: WebSocket,
    code: number,
    reason: string,
  ): void {
    socket.close(code, reason);
  }

  override webSocketError(socket: WebSocket): void {
    socket.close(1011, "websocket error");
  }

  private acceptConnection(request: Request): Response {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("websocket upgrade required", { status: 426 });
    }
    const channel = request.headers.get(HEADER_CHANNEL);
    const device = request.headers.get(HEADER_DEVICE);
    const expiresAtText = request.headers.get(HEADER_EXPIRES_AT);
    const expiresAt = expiresAtText ? Number(expiresAtText) : Number.NaN;
    if (
      !channel ||
      !device ||
      !isOpaqueTag(channel) ||
      !isOpaqueTag(device) ||
      !Number.isSafeInteger(expiresAt)
    ) {
      return new Response("invalid connection", { status: 400 });
    }

    const nowSeconds = Math.floor(Date.now() / 1000);
    const active: WebSocket[] = [];
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = readAttachment(socket);
      if (!attachment || attachment.expiresAt <= nowSeconds) {
        socket.close(CLOSE_EXPIRED, "ticket expired");
        continue;
      }
      if (attachment.device === device) {
        socket.close(CLOSE_REPLACED, "connection replaced");
        continue;
      }
      active.push(socket);
    }
    if (active.length >= MAX_CONNECTIONS) {
      return new Response("connection limit reached", { status: 429 });
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ device, expiresAt } satisfies ConnectionAttachment);
    return new Response(null, { status: 101, webSocket: client });
  }

  private publish(request: Request): Response {
    const sourceDevice = request.headers.get(HEADER_SOURCE_DEVICE);
    if (!sourceDevice || !isOpaqueTag(sourceDevice)) {
      return new Response("invalid publish", { status: 400 });
    }
    const nowSeconds = Math.floor(Date.now() / 1000);
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = readAttachment(socket);
      if (!attachment || attachment.expiresAt <= nowSeconds) {
        socket.close(CLOSE_EXPIRED, "ticket expired");
      } else if (attachment.device !== sourceDevice) {
        socket.send(CHANGE_FRAME);
      }
    }
    return new Response(null, { status: 204 });
  }
}

function readAttachment(socket: WebSocket): ConnectionAttachment | null {
  const value: unknown = socket.deserializeAttachment();
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const candidate = value as Record<string, unknown>;
  if (Object.keys(candidate).length !== 2) return null;
  return typeof candidate.device === "string" &&
    isOpaqueTag(candidate.device) &&
    Number.isSafeInteger(candidate.expiresAt)
    ? { device: candidate.device, expiresAt: candidate.expiresAt as number }
    : null;
}
