import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

const fixtureKeyCurrent =
  "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8";
const fixtureKeyPrevious =
  "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8";

export default defineConfig({
  plugins: [
    cloudflareTest({
      miniflare: {
        bindings: {
          PUBLISH_KEY_CURRENT: fixtureKeyCurrent,
          PUBLISH_KEY_CURRENT_ID: "publish-current",
          PUBLISH_KEY_PREVIOUS: fixtureKeyPrevious,
          PUBLISH_KEY_PREVIOUS_ID: "publish-previous",
          TICKET_KEY_CURRENT: fixtureKeyCurrent,
          TICKET_KEY_CURRENT_ID: "ticket-current",
          TICKET_KEY_PREVIOUS: fixtureKeyPrevious,
          TICKET_KEY_PREVIOUS_ID: "ticket-previous",
          TEST_ONLY_UNRESTRICTED_NAMESPACE: "enabled",
        },
      },
      wrangler: { configPath: "./wrangler.jsonc" },
    }),
  ],
  test: {
    include: ["test/**/*.test.ts"],
  },
});
