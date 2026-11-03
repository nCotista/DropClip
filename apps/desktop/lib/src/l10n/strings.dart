import 'package:flutter/widgets.dart';

import '../settings/config.dart';

/// UI text in Thai and English (NFR-L01). Thai wording follows the QA UI
/// design. Read with `Strings.of(context)`; without a [StringsScope]
/// (e.g. in widget tests) the English text is used.
abstract class Strings {
  const Strings();

  static Strings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StringsScope>()?.strings ??
      const EnStrings();

  static Strings forLanguage(AppLanguage language) =>
      language == AppLanguage.th ? const ThStrings() : const EnStrings();

  // Shell
  String get clipboard;
  String get transfers;
  String get devices;
  String get settings;
  String get workspace;
  String get thisDevice;
  String devicesVerified(int n);
  String notAvailable(String feature, String ticket);
  String get sendClipboard;
  String get pairing;
  String get dropzone;

  // Settings (FR-12)
  String get application;
  String get languageSub;
  String get startAtLogin;
  String get startAtLoginSub;
  String get syncAuto;
  String get syncAutoSub;
  String get typesToSync;
  String get typesToSyncSub;
  String get text;
  String get links;
  String get images;
  String get ttlTitle;
  String get ttlSub;
  String get receivingFiles;
  String get autoAccept;
  String get autoAcceptSub;
  String get destination;
  String get destinationSub;
  String get autoStartFailed;
  String ttl(int? seconds);

  // Firewall onboarding (§3.1)
  String get firewallTitle;
  String get firewallBody;
  String get firewallPublic;
  String get gotIt;
}

class EnStrings extends Strings {
  const EnStrings();

  @override
  String get clipboard => 'Clipboard';
  @override
  String get transfers => 'Transfers';
  @override
  String get devices => 'Devices';
  @override
  String get settings => 'Settings';
  @override
  String get workspace => 'WORKSPACE';
  @override
  String get thisDevice => 'THIS DEVICE';
  @override
  String devicesVerified(int n) => '$n devices verified (SAS)';
  @override
  String notAvailable(String feature, String ticket) =>
      '$feature is not available yet ($ticket)';
  @override
  String get sendClipboard => 'Send clipboard';
  @override
  String get pairing => 'Pairing';
  @override
  String get dropzone => 'Dropzone';

  @override
  String get application => 'Application';
  @override
  String get languageSub => 'Changes every screen right away';
  @override
  String get startAtLogin => 'Start at login';
  @override
  String get startAtLoginSub =>
      'Stays hidden in the menubar / system tray, no window';
  @override
  String get syncAuto => 'Sync clipboard automatically';
  @override
  String get syncAutoSub => 'Sends what you copy to paired devices right away';
  @override
  String get typesToSync => 'Types to sync';
  @override
  String get typesToSyncSub => 'Password-manager content is never sent';
  @override
  String get text => 'Text';
  @override
  String get links => 'Links';
  @override
  String get images => 'Images';
  @override
  String get ttlTitle => 'Clear clipboard automatically (TTL)';
  @override
  String get ttlSub =>
      'Clears received data after this time unless something newer was copied';
  @override
  String get receivingFiles => 'Receiving files';
  @override
  String get autoAccept => 'Accept files automatically';
  @override
  String get autoAcceptSub => 'From paired devices, without asking. Off by '
      'default for safety (T-E03).';
  @override
  String get destination => 'Destination folder';
  @override
  String get destinationSub => 'Files are SHA-256 checked before moving here '
      'and are never opened automatically';
  @override
  String get autoStartFailed =>
      'Could not change "Start at login" on this system';
  @override
  String ttl(int? seconds) => switch (seconds) {
        null => 'Never',
        < 60 => '$seconds seconds',
        60 => '1 minute',
        _ => '${seconds ~/ 60} minutes',
      };

  @override
  String get firewallTitle => 'Allow DropClip on your network';
  @override
  String get firewallBody => 'Windows Defender Firewall will ask once. Choose '
      '"Allow access" for Private networks (home or work). DropClip only '
      'talks to your devices on this Wi-Fi — no cloud, no account.';
  @override
  String get firewallPublic => 'On a public network (café, airport), leave it '
      'blocked; pair with IP + PIN later if you need to.';
  @override
  String get gotIt => 'Got it';
}

class ThStrings extends Strings {
  const ThStrings();

  @override
  String get clipboard => 'คลิปบอร์ด';
  @override
  String get transfers => 'การส่งไฟล์';
  @override
  String get devices => 'อุปกรณ์';
  @override
  String get settings => 'การตั้งค่า';
  @override
  String get workspace => 'พื้นที่ทำงาน';
  @override
  String get thisDevice => 'เครื่องนี้';
  @override
  String devicesVerified(int n) => 'ยืนยันตัวตนแล้ว $n เครื่อง (SAS)';
  @override
  String notAvailable(String feature, String ticket) =>
      '$feature ยังใช้งานไม่ได้ ($ticket)';
  @override
  String get sendClipboard => 'ส่งคลิปบอร์ด';
  @override
  String get pairing => 'การจับคู่อุปกรณ์';
  @override
  String get dropzone => 'Dropzone';

  @override
  String get application => 'แอปพลิเคชัน';
  @override
  String get languageSub => 'เปลี่ยนภาษาของหน้าจอทั้งหมดทันที';
  @override
  String get startAtLogin => 'เปิดพร้อมระบบปฏิบัติการ';
  @override
  String get startAtLoginSub =>
      'ซ่อนอยู่ในแถบเมนูหรือ System Tray โดยไม่เปิดหน้าต่าง';
  @override
  String get syncAuto => 'ซิงก์คลิปบอร์ดอัตโนมัติ';
  @override
  String get syncAutoSub => 'ส่งสิ่งที่คัดลอกไปยังอุปกรณ์ที่จับคู่ไว้ทันที';
  @override
  String get typesToSync => 'ชนิดข้อมูลที่ซิงก์';
  @override
  String get typesToSyncSub => 'ข้อมูลจากโปรแกรมจัดการรหัสผ่านจะไม่ถูกส่งเสมอ';
  @override
  String get text => 'ข้อความ';
  @override
  String get links => 'ลิงก์';
  @override
  String get images => 'รูปภาพ';
  @override
  String get ttlTitle => 'ล้างคลิปบอร์ดอัตโนมัติ (TTL)';
  @override
  String get ttlSub =>
      'ล้างข้อมูลที่รับมาหลังเวลาที่กำหนด หากยังไม่ถูกคัดลอกทับ';
  @override
  String get receivingFiles => 'การรับไฟล์';
  @override
  String get autoAccept => 'รับไฟล์อัตโนมัติ';
  @override
  String get autoAcceptSub =>
      'รับไฟล์จากอุปกรณ์ที่จับคู่แล้วโดยไม่ต้องกดยืนยัน '
      'ปิดไว้เป็นค่าเริ่มต้นเพื่อความปลอดภัย (T-E03)';
  @override
  String get destination => 'โฟลเดอร์ปลายทาง';
  @override
  String get destinationSub => 'ไฟล์จะถูกตรวจ SHA-256 ก่อนย้ายเข้าโฟลเดอร์นี้ '
      'และจะไม่ถูกเปิดอัตโนมัติ';
  @override
  String get autoStartFailed =>
      'เปลี่ยน "เปิดพร้อมระบบปฏิบัติการ" บนเครื่องนี้ไม่ได้';
  @override
  String ttl(int? seconds) => switch (seconds) {
        null => 'ไม่ล้าง',
        < 60 => '$seconds วินาที',
        _ => '${seconds ~/ 60} นาที',
      };

  @override
  String get firewallTitle => 'อนุญาตให้ DropClip ใช้เครือข่าย';
  @override
  String get firewallBody =>
      'Windows Defender Firewall จะถามหนึ่งครั้ง ให้เลือก '
      '"Allow access" สำหรับเครือข่ายส่วนตัว (Private: บ้านหรือที่ทำงาน) '
      'DropClip คุยเฉพาะกับอุปกรณ์ของคุณใน Wi-Fi นี้ ไม่ผ่าน Cloud '
      'และไม่ต้องมีบัญชี';
  @override
  String get firewallPublic => 'บนเครือข่ายสาธารณะ (ร้านกาแฟ, สนามบิน) '
      'ให้ปล่อยบล็อกไว้ แล้วจับคู่ด้วย IP + PIN ภายหลังถ้าจำเป็น';
  @override
  String get gotIt => 'เข้าใจแล้ว';
}

/// Provides the [Strings] for the chosen language to the widget tree.
class StringsScope extends InheritedWidget {
  final Strings strings;

  const StringsScope({super.key, required this.strings, required super.child});

  @override
  bool updateShouldNotify(StringsScope old) =>
      old.strings.runtimeType != strings.runtimeType;
}
