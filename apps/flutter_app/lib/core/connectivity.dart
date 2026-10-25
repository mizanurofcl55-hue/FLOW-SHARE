enum RouteKind {
  localNetwork,
  temporaryHotspot,
  nearby,
  applePeer,
  wifiAware,
  wifiDirect,
  remote,
}

class RouteCapability {
  final RouteKind kind;
  final bool implemented;
  final String explanationKey;
  const RouteCapability(this.kind, this.implemented, this.explanationKey);
}

/// Only linked adapters are advertised; hardware support alone is insufficient.
class ConnectionPlanner {
  static List<RouteCapability> capabilities({required bool android}) => [
    const RouteCapability(RouteKind.localNetwork, true, 'lanHelp'),
    RouteCapability(
      RouteKind.temporaryHotspot,
      true,
      android ? 'androidHotspotHelp' : 'hotspotHelp',
    ),
    const RouteCapability(RouteKind.nearby, false, 'directUnavailable'),
    const RouteCapability(RouteKind.applePeer, false, 'directUnavailable'),
    const RouteCapability(RouteKind.wifiAware, false, 'directUnavailable'),
    const RouteCapability(RouteKind.wifiDirect, false, 'directUnavailable'),
    const RouteCapability(RouteKind.remote, false, 'remoteUnavailable'),
  ];
}
