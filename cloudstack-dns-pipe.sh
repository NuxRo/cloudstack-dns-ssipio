#!/usr/bin/env bash
  #
  # Originally written by Sam Stephenson for xip.io
  set -e
  shopt -s nocasematch
  # Configuration
  #
  # Increment this timestamp when the contents of the file change.
  XIP_TIMESTAMP="2018092000"
  # The top-level domain for which the name server is authoritative.
  # CHANGEME: change "sslip.io" to your domain
  XIP_DOMAIN="sslip.io"
  # How long responses should be cached, in seconds.
  XIP_TTL=300
  # SOA record
  XIP_SOA="briancunnie.gmail.com ns-he.nono.io $XIP_TIMESTAMP $XIP_TTL $XIP_TTL $XIP_TTL $XIP_TTL"
  # The public IP addresses (e.g. for the web site) of the top-level domain.
  # `A` queries for the top-level domain will return this list of addresses.
  # CHANGEME: change this to your domain's webserver's address
  #XIP_ROOT_ADDRESSES=( "78.46.204.247" )
  #XIP_ROOT_ADDRESSES_AAAA=( "2a01:4f8:c17:b8f::2" )
  # The public IP addresses on which this xip-pdns server will run.
  # `NS` queries for the top-level domain will return this list of servers.
  # Note: [change from xip.io] The NS servers are in a different domain
  # (i.e. nono.io) so the addresses don't need to be included.
#  XIP_NS=(           "ns-aws.nono.io" "ns-azure.nono.io" "ns-gce.nono.io" )
  # These are the MX records for your domain.  IF YOU'RE NOT SURE,
  # don't set it at at all (comment it out)--it defaults to no
  # MX records.
  # XIP_MX_RECORDS=(
  #   "10"  "mx.zoho.com"
  #   "20"  "mx2.zoho.com"
  # )
 # XIP_MX_RECORDS=(
 #   "10"	"mail.protonmail.ch"
 # )
  # These are the TXT records for your domain.  IF YOU'RE NOT SURE,
  # don't set it at at all (comment it out)--it defaults to no
 # XIP_TXT_RECORDS=(
 #   "protonmail-verification=ce0ca3f5010aa7a2cf8bcc693778338ffde73e26"
 # )
  # These are the domains which we should not reply with any records
  # at all. Normally this can be emtpy. The only purpose this variable
  # serves is in the case of multiple PowerDNS backends, in this case
  # the BIND backend. It shouldn't return any records for these domains,
  # otherwise it can break CNAME/wildcard records for which the BIND
  # backend is authoritative.
 # XIP_EXCLUDED_DOMAINS=(
 #   "nono.io"
 #   "nono.com"
 # )
  if [ -a "$1" ]; then
    source "$1"
  fi
  #
  # Protocol helpers
  #
  read_cmd() {
    local IFS=$'\t'
    local i=0
    local arg
    read -ra CMD
    for arg; do
      eval "$arg=\"\${CMD[$i]}\""
      let i=i+1
    done
  }
  send_cmd() {
    local IFS=$'\t'
    printf "%s\n" "$*"
  }
  fail() {
    send_cmd "FAIL"
    log "Exiting"
    exit 1
  }
  read_helo() {
    read_cmd HELO VERSION
    [ "$HELO" = "HELO" ] && [ "$VERSION" = "1" ]
  }
  read_query() {
    read_cmd TYPE QNAME QCLASS QTYPE ID IP
  }
  send_answer() {
    local type="$1"
    shift
    send_cmd "DATA" "$QNAME" "$QCLASS" "$type" "$XIP_TTL" "$ID" "$@"
  }
  log() {
    printf "[xip-pdns:$$] %s\n" "$@" >&2
  }
  #
  # xip.io domain helpers
  #
  IP_PATTERN="(^|\.)(x{0}(x{0}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))($|\.)"
  DASHED_IP_PATTERN="(^|-|\.)(x{0}(x{0}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)-){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))($|-|\.)"
  # https://stackoverflow.com/questions/53497/regular-expression-that-matches-valid-ipv6-addresses
  # We don't use "dotted" IPv6 because DNS doesn't allow two dots next to each other
  #   e.g. "::1" -> "1..sslip.io" isn't allowed (dig error: `is not a legal name (empty label)`)
  DASHED_IPV6_PATTERN="(^|\.)(x{0}([0-9a-fA-F]{1,4}-){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}-){1,7}-|([0-9a-fA-F]{1,4}-){1,6}-[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}-){1,5}(-[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}-){1,4}(-[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}-){1,3}(-[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}-){1,2}(-[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}-(x{0}(-[0-9a-fA-F]{1,4}){1,6})|-(x{0}(-[0-9a-fA-F]{1,4}){1,7}|-))(\.|$)"
  qtype_is() {
    [ "$QTYPE" = "$1" ] || [ "$QTYPE" = "ANY" ]
  }
  qname_is_root_domain() {
    [ "$QNAME" = "$XIP_DOMAIN" ]
  }
  subdomain_is_ip() {
    [[ "$QNAME" =~ $IP_PATTERN ]]
  }
  subdomain_is_dashed_ip() {
    [[ "$QNAME" =~ $DASHED_IP_PATTERN ]]
  }
  subdomain_is_dashed_ipv6() {
    [[ "$QNAME" =~ $DASHED_IPV6_PATTERN ]]
  }
  resolve_ip_subdomain() {
    [[ "$QNAME" =~ $IP_PATTERN ]] || true
    echo "${BASH_REMATCH[2]}"
  }
  resolve_dashed_ip_subdomain() {
    [[ "$QNAME" =~ $DASHED_IP_PATTERN ]] || true
    echo "${BASH_REMATCH[2]//-/.}"
  }
  resolve_dashed_ipv6_subdomain() {
    [[ "$QNAME" =~ $DASHED_IPV6_PATTERN ]] || true
    echo "${BASH_REMATCH[2]//-/:}"
  }
  answer_soa_query() {
    send_answer "SOA" "$XIP_SOA"
  }
  answer_ns_query() {
    local i=1
    local ns_address
    for ns in "${XIP_NS[@]}"; do
      send_answer "NS" "$ns"
    done
  }
  answer_root_a_query() {
    local address
    for address in "${XIP_ROOT_ADDRESSES[@]}"; do
      send_answer "A" "$address"
    done
  }
  answer_root_aaaa_query() {
    local address
    for address in "${XIP_ROOT_ADDRESSES_AAAA[@]}"; do
      send_answer "AAAA" "$address"
    done
  }
  answer_localhost_a_query() {
    send_answer "A" "127.0.0.1"
  }
  answer_localhost_aaaa_query() {
    send_answer "AAAA" "::1"
  }
  answer_mx_query() {
    set -- "${XIP_MX_RECORDS[@]}"
    while [ $# -gt 1 ]; do
      send_answer "MX" "$1	$2"
    shift 2
    done
  }
  answer_txt_query() {
    local address
    for text in "${XIP_TXT_RECORDS[@]}"; do
      send_answer "TXT" "$text"
    done
  }
  answer_subdomain_a_query_for() {
    local type="$1"
    local address="$(resolve_${type}_subdomain)"
    if [ -n "$address" ] && $(echo "$address" | grepcidr -f /etc/pdns/ips.txt >/dev/null); then
      send_answer "A" "$address"
    fi
  }
  answer_subdomain_aaaa_query_for() {
    local type="$1"
    local address="$(resolve_${type}_subdomain)"
    if [ -n "$address" ] && $(echo "$address" | grepcidr -f /etc/pdns/ips.txt >/dev/null); then
      send_answer "AAAA" "$address"
    fi
  }
  #
  # PowerDNS pipe backend implementation
  #
  trap fail err
  read_helo
  send_cmd "OK" "xip.io PowerDNS pipe backend (protocol version 1)"
  while read_query; do
    log "Query: type=$TYPE qname=$QNAME qclass=$QCLASS qtype=$QTYPE id=$ID ip=$IP"
    for excluded_domain in "${XIP_EXCLUDED_DOMAINS[@]}"; do
      if [[ $QNAME =~ $excluded_domain$ ]]; then
        log "'$QNAME' matched '$excluded_domain'"
        send_cmd "END"
        continue 2
      fi
    done
    if qtype_is "SOA"; then
      answer_soa_query
    fi
    if qtype_is "NS"; then
      answer_ns_query
    fi
    if qtype_is "TXT"; then
      answer_txt_query
    fi
    if qtype_is "MX"; then
      answer_mx_query
    fi
    if qtype_is "A"; then
      LC_QNAME=$(echo $QNAME | tr 'A-Z' 'a-z')
      if [ $LC_QNAME == $XIP_DOMAIN ]; then
        answer_root_a_query
      else
        if [ $LC_QNAME == "localhost.$XIP_DOMAIN" ]; then
          answer_localhost_a_query
        elif subdomain_is_dashed_ip; then
          answer_subdomain_a_query_for dashed_ip
        elif subdomain_is_ip; then
          answer_subdomain_a_query_for ip
        fi
      fi
    fi
    if qtype_is "AAAA"; then
      LC_QNAME=$(echo $QNAME | tr 'A-Z' 'a-z')
      if [ $LC_QNAME == $XIP_DOMAIN ]; then
        answer_root_aaaa_query
      elif [ $LC_QNAME == "localhost.$XIP_DOMAIN" ]; then
          answer_localhost_aaaa_query
      elif subdomain_is_dashed_ipv6; then
          answer_subdomain_aaaa_query_for dashed_ipv6
      fi
    fi
    send_cmd "END"
  done
