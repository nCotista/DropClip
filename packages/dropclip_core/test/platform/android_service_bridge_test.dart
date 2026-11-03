import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  group('T2.1 AndroidServiceBridge & Lifecycle Manager', () {
    test(
      'starts connectedDevice foreground service and manages MulticastLock',
      () async {
        final gateway = InMemoryAndroidNativeGateway();
        final bridge = AndroidServiceBridge(gateway: gateway);

        expect(await bridge.isRunning(), isFalse);
        final started = await bridge.startService();
        expect(started, isTrue);
        expect(await bridge.isRunning(), isTrue);
        expect(gateway.activeServiceType, equals('connectedDevice'));
        expect(bridge.isMulticastLockHeld, isTrue);

        await bridge.stopService();
        expect(await bridge.isRunning(), isFalse);
        expect(bridge.isMulticastLockHeld, isFalse);
        expect(gateway.isMulticastLockHeld, isFalse);
        await bridge.dispose();
      },
    );

    test(
      'recovers from Doze mode by releasing lock on sleep and re-acquiring on wake',
      () async {
        final gateway = InMemoryAndroidNativeGateway();
        var reconnectTriggered = 0;
        final bridge = AndroidServiceBridge(
          gateway: gateway,
          onReconnectAfterDoze: () async {
            reconnectTriggered++;
          },
        );

        await bridge.startService();
        expect(bridge.isMulticastLockHeld, isTrue);

        // Entering Doze releases MulticastLock to preserve <3%/24h battery (NFR-R03A).
        await bridge.onDozeStateChanged(inDozeMode: true);
        expect(bridge.isMulticastLockHeld, isFalse);

        // Exiting Doze restores MulticastLock and triggers control-plane reconnect.
        await bridge.onDozeStateChanged(inDozeMode: false);
        expect(bridge.isMulticastLockHeld, isTrue);
        expect(bridge.dozeRecoveryCount, equals(1));
        expect(reconnectTriggered, equals(1));
        await bridge.dispose();
      },
    );

    test(
      'suppresses 100% of EXTRA_IS_SENSITIVE clips from Quick Settings Tile (NFR-S04)',
      () async {
        final gateway = InMemoryAndroidNativeGateway();
        final bridge = AndroidServiceBridge(gateway: gateway);
        final emitted = <AndroidBridgeEvent>[];
        final sub = bridge.outboundEvents.listen(emitted.add);

        final blocked = bridge.handleNativeEvent(
          const AndroidBridgeEvent(
            action: 'send_clipboard',
            isSensitive: true,
            text: 'super-secret-password',
            timestampMs: 1757280000000,
          ),
        );
        expect(blocked, isFalse);
        expect(bridge.suppressedSensitiveCount, equals(1));

        final allowed = bridge.handleNativeEvent(
          const AndroidBridgeEvent(
            action: 'send_clipboard',
            isSensitive: false,
            text: 'hello desktop',
            timestampMs: 1757280000100,
          ),
        );
        expect(allowed, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(emitted, hasLength(1));
        expect(emitted.single.text, equals('hello desktop'));

        await sub.cancel();
        await bridge.dispose();
      },
    );

    test(
      'handles BOOT_COMPLETED auto-start, battery exemption and inbound clip write',
      () async {
        final gateway = InMemoryAndroidNativeGateway();
        final bridge = AndroidServiceBridge(gateway: gateway);

        expect(await bridge.onBootCompleted(autoStartEnabled: false), isFalse);
        expect(await bridge.isRunning(), isFalse);

        expect(await bridge.onBootCompleted(autoStartEnabled: true), isTrue);
        expect(await bridge.isRunning(), isTrue);

        expect(await bridge.requestBatteryExemption(), isTrue);
        expect(gateway.isBatteryExempted, isTrue);

        await bridge.writeInboundClipboard('Clipboard from Mac');
        expect(gateway.primaryClip, equals('Clipboard from Mac'));

        expect(
          () => gateway.startForegroundService(serviceType: 'dataSync'),
          throwsArgumentError,
        );
        await bridge.dispose();
      },
    );
  });
}
