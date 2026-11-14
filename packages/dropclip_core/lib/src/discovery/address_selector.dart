import 'dart:async';
import 'dart:io';

/// Async IPv4 DNS/mDNS lookup hook used when Bonsoir only surfaces IPv6 or a
/// `.local` hostname.
typedef HostIpv4Lookup = Future<List<InternetAddress>> Function(String host);

/// Strips IPv6 zone ids (e.g. `fe80::1%en0`) and optional brackets before
/// calling [InternetAddress.tryParse].
String stripIpZone(String address) {
  var clean = address.trim();
  if (clean.startsWith('[') && clean.endsWith(']') && clean.length > 2) {
    clean = clean.substring(1, clean.length - 1);
  }
  final zone = clean.indexOf('%');
  return zone == -1 ? clean : clean.substring(0, zone);
}

/// Ranks a dial candidate address (lower is preferred):
/// - `0`: private LAN IPv4 (`10/8`, `172.16-31/12`, `192.168/16`)
/// - `1`: other non-loopback, non-link-local IPv4 (e.g. `100.64/10`)
/// - `2`: IPv4 loopback (`127/8`) or link-local (`169.254/16`)
/// - `3`: non-link-local IPv6 (e.g. ULA `fd00::` or global `2405:...`)
/// - `4`: link-local IPv6 (`fe80::`) or `::1`
/// - `5`: unparsed hostname or blank string
int peerAddressRank(String address) {
  final clean = stripIpZone(address);
  if (clean.isEmpty) return 5;
  final parsed = InternetAddress.tryParse(clean);
  if (parsed == null) return 5;
  if (parsed.type == InternetAddressType.IPv4) {
    if (!parsed.isLoopback && !parsed.isLinkLocal) {
      final b = parsed.rawAddress;
      final isPrivate = b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168);
      return isPrivate ? 0 : 1;
    }
    return 2;
  }
  if (parsed.isLinkLocal || parsed.isLoopback) return 4;
  return 3;
}

/// Chooses the best address among Bonsoir's [hostAddresses], [hostAddress],
/// and [hostname], preserving discovery order within equal rank tiers.
String? selectBestPeerAddress({
  Iterable<String> hostAddresses = const [],
  String? hostAddress,
  String? hostname,
}) {
  final candidates = <String>[];
  final seen = <String>{};
  void addCandidate(String? raw) {
    if (raw == null) return;
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty && seen.add(trimmed)) candidates.add(trimmed);
  }

  for (final a in hostAddresses) {
    addCandidate(a);
  }
  addCandidate(hostAddress);
  addCandidate(hostname);
  if (candidates.isEmpty) return null;

  var best = candidates.first;
  var bestRank = peerAddressRank(best);
  for (final c in candidates.skip(1)) {
    final rank = peerAddressRank(c);
    if (rank < bestRank) {
      best = c;
      bestRank = rank;
    }
  }
  return best;
}

/// Resolves the best address for a discovered Bonsoir service, performing a
/// bounded IPv4 [InternetAddress.lookup] of [hostname] only when the service
/// event did not yet carry a usable IPv4 address.
Future<String?> resolveMdnsPeerAddress({
  Iterable<String> hostAddresses = const [],
  String? hostAddress,
  String? hostname,
  HostIpv4Lookup? lookupIpv4,
  Duration lookupTimeout = const Duration(milliseconds: 500),
}) async {
  final initial = selectBestPeerAddress(
    hostAddresses: hostAddresses,
    hostAddress: hostAddress,
    hostname: hostname,
  );
  if (initial != null && peerAddressRank(initial) <= 1) return initial;

  var host = (hostname ?? '').trim();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host.isEmpty || InternetAddress.tryParse(stripIpZone(host)) != null) {
    return initial;
  }

  try {
    final fn = lookupIpv4 ??
        (h) => InternetAddress.lookup(h, type: InternetAddressType.IPv4);
    final resolved = await fn(host).timeout(lookupTimeout);
    return selectBestPeerAddress(
      hostAddresses: [...hostAddresses, for (final a in resolved) a.address],
      hostAddress: hostAddress,
      hostname: hostname,
    );
  } on Object {
    return initial;
  }
}
