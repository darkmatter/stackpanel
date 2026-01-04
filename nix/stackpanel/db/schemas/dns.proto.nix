# ==============================================================================
# dns.proto.nix
#
# Protobuf schema for DNS configuration.
# Defines DNS records and domain configuration for the project.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "dns.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  enums = {
    RecordType = proto.mkEnum {
      name = "RecordType";
      description = "DNS record types";
      values = [
        "RECORD_TYPE_UNSPECIFIED"
        "RECORD_TYPE_A"
        "RECORD_TYPE_AAAA"
        "RECORD_TYPE_CNAME"
        "RECORD_TYPE_TXT"
        "RECORD_TYPE_MX"
        "RECORD_TYPE_NS"
        "RECORD_TYPE_SRV"
        "RECORD_TYPE_CAA"
      ];
    };

    DnsProvider = proto.mkEnum {
      name = "DnsProvider";
      description = "DNS provider";
      values = [
        "DNS_PROVIDER_UNSPECIFIED"
        "DNS_PROVIDER_CLOUDFLARE"
        "DNS_PROVIDER_ROUTE53"
        "DNS_PROVIDER_NAMECHEAP"
        "DNS_PROVIDER_DIGITALOCEAN"
        "DNS_PROVIDER_MANUAL"
      ];
    };
  };

  messages = {
    # Root DNS configuration
    Dns = proto.mkMessage {
      name = "Dns";
      description = "DNS records and domain configuration";
      fields = {
        default_ttl = proto.int32 1 "Default TTL for records (seconds)";
        zones = proto.map "string" "Zone" 2 "DNS zones/domains configuration";
      };
    };

    # Zone/Domain configuration
    Zone = proto.mkMessage {
      name = "Zone";
      description = "DNS zone configuration";
      fields = {
        domain = proto.string 1 "Domain name (e.g., 'example.com')";
        provider = proto.message "DnsProvider" 2 "DNS provider";
        zone_id = proto.optional (proto.string 3 "Provider-specific zone ID (if required)");
        records = proto.repeated (proto.message "Record" 4 "List of DNS records for this zone");
        managed = proto.bool 5 "Whether stackpanel manages this zone";
      };
    };

    # DNS Record configuration
    Record = proto.mkMessage {
      name = "Record";
      description = "DNS record configuration";
      fields = {
        type = proto.message "RecordType" 1 "DNS record type";
        name = proto.string 2 "Record name (subdomain or @ for root)";
        value = proto.string 3 "Record value (IP, hostname, or text content)";
        ttl = proto.int32 4 "Time to live in seconds";
        priority = proto.optional (proto.int32 5 "Priority for MX/SRV records");
        proxied = proto.bool 6 "Whether to proxy through CDN (Cloudflare-specific)";
        comment = proto.optional (proto.string 7 "Optional comment describing this record");
      };
    };
  };
}
