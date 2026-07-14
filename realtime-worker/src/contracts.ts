export const CHANGE_FRAME = '{"v":1,"type":"changed"}';
export const MAX_CONNECTIONS = 128;
export const MAX_PUBLISH_BODY_BYTES = 512;
export const MAX_PUBLISH_SKEW_SECONDS = 30;
export const MAX_TICKET_BYTES = 1024;
export const TICKET_AUDIENCE = "todori-realtime";
export const TICKET_TTL_SECONDS = 300;

export const HEADER_CHANNEL = "X-Todori-Realtime-Channel";
export const HEADER_DEVICE = "X-Todori-Realtime-Device";
export const HEADER_EXPIRES_AT = "X-Todori-Realtime-Expires-At";
export const HEADER_KEY_ID = "X-Todori-Realtime-Key-Id";
export const HEADER_SIGNATURE = "X-Todori-Realtime-Signature";
export const HEADER_SOURCE_DEVICE = "X-Todori-Realtime-Source-Device";
export const HEADER_TIMESTAMP = "X-Todori-Realtime-Timestamp";

export const KEY_ID_PATTERN = /^[A-Za-z0-9_-]{1,32}$/;
export const OPAQUE_TAG_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export interface TicketPayload {
  kid: string;
  aud: typeof TICKET_AUDIENCE;
  channel: string;
  device: string;
  iat: number;
  exp: number;
}

export interface PublishPayload {
  v: 1;
  channel: string;
  source_device: string;
}

export interface ConnectionAttachment {
  device: string;
  expiresAt: number;
}
