import { env } from "cloudflare:workers";
import { evictDurableObject, runInDurableObject, SELF } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { CHANGE_FRAME, MAX_CONNECTIONS, type ConnectionAttachment } from "../src/contracts";
import { verifyPublish, verifyTicket } from "../src/crypto";
import fixture from "./fixtures/realtime-hmac-v1.json";
import {
  CHANNEL,
  closeEvent,
  connect,
  DEVICE_A,
  DEVICE_B,
  issueTicket,
  message,
  opaqueTag,
  publish,
} from "./helpers";

const openSockets: WebSocket[] = [];

afterEach(() => {
  for (const socket of openSockets.splice(0)) {
    try {
      socket.close(1000, "test complete");
    } catch {
      // Already closed by the Worker.
    }
  }
});

describe("ticket authentication", () => {
  it("matches the shared HMAC v1 fixture", async () => {
    const payload = JSON.parse(fixture.ticket.payload);
    expect(await verifyTicket(fixture.ticket.token, {
      current: { id: payload.kid, encodedKey: fixture.ticket.key_base64url },
      previous: { id: "unused", encodedKey: env.TICKET_KEY_PREVIOUS },
    }, payload.iat)).toEqual(payload);

    const request = new Request("https://example.com/v1/publish", {
      body: fixture.publish.body,
      headers: {
        "X-Todori-Realtime-Key-Id": fixture.publish.key_id,
        "X-Todori-Realtime-Signature": fixture.publish.signature,
        "X-Todori-Realtime-Timestamp": String(fixture.publish.timestamp),
      },
      method: "POST",
    });
    const verified = await verifyPublish(request, {
      current: {
        id: fixture.publish.key_id,
        encodedKey: fixture.publish.key_base64url,
      },
      previous: { id: "unused", encodedKey: env.PUBLISH_KEY_PREVIOUS },
    }, fixture.publish.timestamp);
    expect(new TextDecoder().decode(verified?.body)).toBe(fixture.publish.body);
  });

  it("verifies the fixed ticket byte contract directly", async () => {
    const now = Math.floor(Date.now() / 1000);
    const payload = {
      kid: env.TICKET_KEY_CURRENT_ID,
      aud: "todori-realtime" as const,
      channel: CHANNEL,
      device: DEVICE_A,
      iat: now,
      exp: now + 300,
    };
    const token = await issueTicket(payload, env.TICKET_KEY_CURRENT);
    expect(await verifyTicket(token, {
      current: {
        id: env.TICKET_KEY_CURRENT_ID,
        encodedKey: env.TICKET_KEY_CURRENT,
      },
      previous: {
        id: env.TICKET_KEY_PREVIOUS_ID,
        encodedKey: env.TICKET_KEY_PREVIOUS,
      },
    }, now)).toEqual(payload);
  });

  it("accepts the current and previous key and rejects unknown or tampered tickets", async () => {
    const current = await connect(DEVICE_A);
    expect(current.status).toBe(101);
    accept(current);

    const previous = await connect(DEVICE_B, {
      key: env.TICKET_KEY_PREVIOUS,
      kid: env.TICKET_KEY_PREVIOUS_ID,
    });
    expect(previous.status).toBe(101);
    accept(previous);

    const unknown = await connect("D".repeat(43), { kid: "unknown-key" });
    expect(unknown.status).toBe(401);

    const now = Math.floor(Date.now() / 1000);
    const token = await issueTicket({
      aud: "todori-realtime",
      channel: CHANNEL,
      device: "E".repeat(43),
      exp: now + 300,
      iat: now,
      kid: env.TICKET_KEY_CURRENT_ID,
    }, env.TICKET_KEY_CURRENT);
    const tampered = `${token.slice(0, -1)}${token.endsWith("A") ? "B" : "A"}`;
    const response = await SELF.fetch("https://example.com/v1/connect", {
      headers: { Authorization: `Bearer ${tampered}`, Upgrade: "websocket" },
    });
    expect(response.status).toBe(401);
  });

  it("rejects expired, wrong-audience, reordered, and extra-field payloads", async () => {
    const now = Math.floor(Date.now() / 1000);
    expect((await connect(DEVICE_A, { expiresAt: now - 1 })).status).toBe(401);

    const base = {
      kid: env.TICKET_KEY_CURRENT_ID,
      aud: "wrong-audience",
      channel: CHANNEL,
      device: DEVICE_A,
      iat: now,
      exp: now + 300,
    };
    const wrongAudience = await signedRawTicket(base);
    expect((await connectWithToken(wrongAudience)).status).toBe(401);

    const reordered = await signedRawTicket({ aud: "todori-realtime", kid: base.kid,
      channel: CHANNEL, device: DEVICE_A, iat: now, exp: now + 300 });
    expect((await connectWithToken(reordered)).status).toBe(401);

    const extra = await signedRawTicket({ ...base, aud: "todori-realtime", extra: true });
    expect((await connectWithToken(extra)).status).toBe(401);
  });
});

describe("publish authentication and fan-out", () => {
  it("fans out only to remote devices and duplicate publish remains a duplicate hint", async () => {
    const source = accept(await connect(DEVICE_A));
    const remote = accept(await connect(DEVICE_B));
    let sourceMessages = 0;
    source.addEventListener("message", () => sourceMessages++);

    const firstMessage = message(remote);
    expect((await publishPayload(DEVICE_A)).status).toBe(204);
    expect(await firstMessage).toBe(CHANGE_FRAME);
    expect(sourceMessages).toBe(0);

    const duplicateMessage = message(remote);
    expect((await publishPayload(DEVICE_A)).status).toBe(204);
    expect(await duplicateMessage).toBe(CHANGE_FRAME);
    expect(sourceMessages).toBe(0);
  });

  it("accepts previous key and rejects stale, unknown, tampered, noncanonical, and oversized publish", async () => {
    const remote = accept(await connect(DEVICE_B));
    const previousMessage = message(remote);
    const previous = await publishPayload(DEVICE_A, {
      key: env.PUBLISH_KEY_PREVIOUS,
      kid: env.PUBLISH_KEY_PREVIOUS_ID,
    });
    expect(previous.status).toBe(204);
    expect(await previousMessage).toBe(CHANGE_FRAME);

    const now = Math.floor(Date.now() / 1000);
    expect((await publishPayload(DEVICE_A, { timestamp: now - 31 })).status).toBe(401);
    expect((await publishPayload(DEVICE_A, { kid: "unknown-key" })).status).toBe(401);

    const canonical = new TextEncoder().encode(JSON.stringify({
      v: 1,
      channel: CHANNEL,
      source_device: DEVICE_A,
    }));
    const tampered = canonical.slice();
    tampered[tampered.length - 2] = "Z".charCodeAt(0);
    expect((await publishPayload(DEVICE_A, { body: tampered })).status).toBe(401);

    const noncanonical = new TextEncoder().encode(
      `{ "v": 1, "channel": "${CHANNEL}", "source_device": "${DEVICE_A}" }`,
    );
    expect((await publishPayload(DEVICE_A, { body: noncanonical })).status).toBe(401);
    expect((await publishPayload(DEVICE_A, { body: new Uint8Array(513) })).status).toBe(401);
  });
});

describe("connection lifecycle", () => {
  it("replaces the previous socket for the same device", async () => {
    const first = accept(await connect(DEVICE_A));
    const closed = closeEvent(first);
    const second = accept(await connect(DEVICE_A));
    expect(second.readyState).toBe(WebSocket.OPEN);
    expect((await closed).code).toBe(4001);
  });

  it("rejects the 129th active connection", async () => {
    const capacityChannel = opaqueTag(9);
    for (let index = 0; index < MAX_CONNECTIONS; index++) {
      const device = opaqueTag(index + 10);
      const response = await connect(device, { channel: capacityChannel });
      expect(response.status).toBe(101);
      accept(response);
    }
    const overflow = await connect(opaqueTag(200), { channel: capacityChannel });
    expect(overflow.status).toBe(429);
  });

  it("restores attachment metadata across eviction and closes expired sockets on publish", async () => {
    const source = accept(await connect(DEVICE_A));
    const remote = accept(await connect(DEVICE_B));
    const expiredClosed = closeEvent(remote);
    const stub = env.REALTIME_CHANNELS.getByName(CHANNEL);
    await runInDurableObject(stub, (_instance, state) => {
      const socket = state.getWebSockets().find((candidate) => {
        const attachment = candidate.deserializeAttachment() as ConnectionAttachment;
        return attachment.device === DEVICE_B;
      });
      if (!socket) throw new Error("remote socket missing");
      socket.serializeAttachment({
        device: DEVICE_B,
        expiresAt: Math.floor(Date.now() / 1000) - 1,
      } satisfies ConnectionAttachment);
    });
    await evictDurableObject(stub);
    expect((await publishPayload(DEVICE_A)).status).toBe(204);
    expect((await expiredClosed).code).toBe(4003);
    expect(source.readyState).toBe(WebSocket.OPEN);
  });

  it("rejects client application messages", async () => {
    const socket = accept(await connect(DEVICE_A));
    const closed = closeEvent(socket);
    socket.send("not allowed");
    expect((await closed).code).toBe(1008);
  });
});

function accept(response: Response): WebSocket {
  expect(response.status).toBe(101);
  const socket = response.webSocket;
  if (!socket) throw new Error("expected websocket response");
  socket.accept();
  openSockets.push(socket);
  return socket;
}

function publishPayload(
  sourceDevice: string,
  options: Parameters<typeof publish>[1] = {},
): Promise<Response> {
  return publish({ v: 1, channel: CHANNEL, source_device: sourceDevice }, options);
}

async function signedRawTicket(payload: object): Promise<string> {
  return issueTicket(payload as never, env.TICKET_KEY_CURRENT);
}

function connectWithToken(token: string): Promise<Response> {
  return SELF.fetch("https://example.com/v1/connect", {
    headers: { Authorization: `Bearer ${token}`, Upgrade: "websocket" },
  });
}
