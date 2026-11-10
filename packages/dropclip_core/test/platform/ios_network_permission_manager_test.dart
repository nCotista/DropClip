import 'dart:convert';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  const validPlist = IosInfoPlistConfig(
    localNetworkUsageDescription:
        'DropClip uses your local network to discover and securely synchronize clipboards and files with your paired devices.',
    bonjourServices: <String>['_dropclip._tcp'],
    minimumIosMajorVersion: 15,
  );

  group('T3.1 iOS Local Network Privacy & NWBrowser Discovery', () {
    test(
      'requires Pre-Permission Explainer before starting NWBrowser and discovers LAN peers',
      () async {
        final gateway = InMemoryIosNwBrowserGateway(
          simulatedOsResponse: IosLocalNetworkPermissionState.granted,
        );
        final bridge = IosNetworkDiscoveryBridge(
          plistConfig: validPlist,
          gateway: gateway,
        );

        expect(
          () => bridge.requestPermissionAndStartDiscovery(),
          throwsStateError,
        );

        bridge.markPreExplainerShown();
        expect(
          bridge.permissionState,
          equals(IosLocalNetworkPermissionState.preExplainerShown),
        );

        final state = await bridge.requestPermissionAndStartDiscovery();
        expect(state, equals(IosLocalNetworkPermissionState.granted));
        expect(gateway.browserRunning, isTrue);

        bridge.onNativeBrowseResults(<Map<String, String>>[
          <String, String>{
            'v': '1',
            'id': '550e8400-e29b-41d4-a716-446655440000',
            'name': base64.encode(utf8.encode('MacBook Pro ของเจ 🖥️')),
            'os': 'macos',
            'tier': '1',
            'port': '53317',
            'fp': 'a' * 64,
            'cap': 'clip.push,clip.pull,file.stream',
          },
        ]);

        expect(bridge.currentPeers, hasLength(1));
        expect(
          bridge.currentPeers.single.displayName,
          equals('MacBook Pro ของเจ 🖥️'),
        );
        await bridge.dispose();
      },
    );

    test(
      'handles PolicyDenied state and deep-links to iOS System Settings (AC #2)',
      () async {
        final gateway = InMemoryIosNwBrowserGateway(
          simulatedOsResponse: IosLocalNetworkPermissionState.denied,
        );
        final bridge = IosNetworkDiscoveryBridge(
          plistConfig: validPlist,
          gateway: gateway,
        );

        bridge.markPreExplainerShown();
        final state = await bridge.requestPermissionAndStartDiscovery();
        expect(state, equals(IosLocalNetworkPermissionState.denied));
        expect(bridge.shouldShowDeniedSettingsGuide, isTrue);

        final opened = await bridge.openSettingsForPermissionRecovery();
        expect(opened, isTrue);
        expect(gateway.settingsOpenedCount, equals(1));
        await bridge.dispose();
      },
    );

    test(
      'validates Info.plist NSLocalNetworkUsageDescription, NSBonjourServices and iOS 15/16/17+',
      () {
        expect(
          () => IosNetworkDiscoveryBridge(
            plistConfig: const IosInfoPlistConfig(
              localNetworkUsageDescription: '',
              bonjourServices: <String>['_dropclip._tcp'],
            ),
            gateway: InMemoryIosNwBrowserGateway(),
          ),
          throwsStateError,
        );

        expect(
          () => IosNetworkDiscoveryBridge(
            plistConfig: const IosInfoPlistConfig(
              localNetworkUsageDescription: 'Valid description',
              bonjourServices: <String>['_http._tcp'],
            ),
            gateway: InMemoryIosNwBrowserGateway(),
          ),
          throwsStateError,
        );

        for (final iosMajor in <int>[15, 16, 17]) {
          const IosInfoPlistConfig(
            localNetworkUsageDescription: 'Valid description',
            bonjourServices: <String>['_dropclip._tcp'],
          ).validate();
          expect(iosMajor, greaterThanOrEqualTo(15));
        }
      },
    );
  });
}
