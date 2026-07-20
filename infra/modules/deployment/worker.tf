resource "cloudflare_workers_custom_domain" "realtime" {
  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  hostname   = local.realtime_domain
  service    = local.realtime_service
}
