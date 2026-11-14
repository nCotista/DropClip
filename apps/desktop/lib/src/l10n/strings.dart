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
  String get webCompanion;
  String get webCompanionSub;

  // Connection (network adapter)
  String get connection;
  String get networkAdapter;
  String get networkAdapterSub;
  String get networkAutomatic;
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
  String get deviceName;
  String get deviceNameSub;
  String get destinationSub;
  String get autoStartFailed;
  String ttl(int? seconds);

  // Firewall onboarding (§3.1)
  String get firewallTitle;
  String get firewallBody;
  String get firewallPublic;
  String get gotIt;

  // Clipboard page
  String get copied;
  String liveSyncAcross(int n);
  String get autoSync;
  String get searchClips;
  String get all;
  String get recentHeader;
  String get noClipsMatch;
  String fromDevice(String device, String age);
  String get copyAgain;
  String get openFile;
  String get showInFolder;
  String get removeItem;
  String suppressed(int n);

  // Side panel
  String get nearbyDevices;
  String onlineCount(int n);
  String get noDevicesNearby;
  String get phoneOnScreenHint;
  String get pairNewDevice;

  // Pairing (T1.3, UI-03)
  String get pairedDevices;
  String get noPairedDevices;
  String get connected;
  String get offline;
  String get pair;
  String get remove;
  String get pinOnOtherDevice;
  String enterPinOf(String name);
  String get sasQuestion;
  String get sasMatch;
  String get sasNoMatch;
  String pairedWith(String name);
  String pairFailed(String code);
  String receiveFrom(String name);
  String get accept;
  String get decline;
  String revokedElsewhere(String name);
  String get keep;
  String get linkPhoneWeb;
  String get linkPhoneWebHint;
  String get linkedBrowsers;
  String sentToBrowser(String name);
  String get waitingForPeer;
  String get dropFiles;
  String get dropFilesSub;
  String get online;
  String get manual;
  String get syncLatency;
  String latencyTarget({required bool under});

  // Tray menu (UI-01)
  String connectedTo(String network);
  String get clipboardSync;
  String get onlineDevices;
  String get trayOpenDropzone;
  String get traySendClipboard;
  String get trayPair;
  String get trayTrusted;
  String get traySettings;
  String get trayQuit;

  // Dropzone (UI-02)
  String get dropHere;
  String get releaseToAdd;
  String get clickToChoose;
  String itemCount(int n);
  String get sendTo;
  String sendToDevice(String name);
  String get dropzoneKeys;

  // Debug console (T0.3)
  String debugConsole(int lines);
  String get noLogLines;
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
  String get webCompanion => 'Web companion (/web)';
  @override
  String get webCompanionSub =>
      'Allow a linked phone browser over local HTTPS (expires in 8 hours)';
  @override
  String get connection => 'Connection';
  @override
  String get networkAdapter => 'Network adapter';
  @override
  String get networkAdapterSub =>
      'Which connection other devices use to reach this PC. Automatic skips '
      'hypervisor switches, VPNs and Wi-Fi Direct.';
  @override
  String get networkAutomatic => 'Automatic';
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
  String get deviceName => 'Device name';
  @override
  String get deviceNameSub =>
      'What other devices see; paired ones update when they next connect';
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

  @override
  String get copied => 'Copied to clipboard';
  @override
  String liveSyncAcross(int n) =>
      'Live sync across $n devices · text, links, PNG/JPEG';
  @override
  String get autoSync => 'Auto-sync';
  @override
  String get searchClips => 'Search recent clips…';
  @override
  String get all => 'All';
  @override
  String get recentHeader => 'RECENT · UP TO 20 ITEMS · MEMORY ONLY';
  @override
  String get noClipsMatch => 'No clips match';
  @override
  String fromDevice(String device, String age) => 'From $device · $age';
  @override
  String get copyAgain => 'Copy again';
  @override
  String get openFile => 'Open file';
  @override
  String get showInFolder => 'Show in folder';
  @override
  String get removeItem => 'Remove';
  @override
  String suppressed(int n) =>
      '${n == 1 ? '1 item' : '$n items'} from a password manager not synced '
      '— password-manager content never leaves this device';

  @override
  String get nearbyDevices => 'Nearby devices';
  @override
  String onlineCount(int n) => '$n online';
  @override
  String get noDevicesNearby => 'No devices nearby';
  @override
  String get phoneOnScreenHint =>
      'Phones show up while DropClip is open on their screen.';
  @override
  String get pairNewDevice => 'Pair new device';
  @override
  String get pairedDevices => 'Paired devices';
  @override
  String get noPairedDevices => 'No paired devices yet';
  @override
  String get connected => 'Connected';
  @override
  String get offline => 'Offline';
  @override
  String get pair => 'Pair';
  @override
  String get remove => 'Remove';
  @override
  String get pinOnOtherDevice =>
      'On the other device, choose Pair and enter this PIN';
  @override
  String enterPinOf(String name) => 'Enter the PIN shown on $name';
  @override
  String get sasQuestion => 'Do both devices show this number?';
  @override
  String get sasMatch => 'They match';
  @override
  String get sasNoMatch => "They don't match";
  @override
  String pairedWith(String name) => 'Paired with $name';
  @override
  String pairFailed(String code) => 'Pairing failed ($code)';
  @override
  String receiveFrom(String name) => '$name wants to send you';
  @override
  String get accept => 'Accept';
  @override
  String get decline => 'Decline';
  @override
  String revokedElsewhere(String name) =>
      'Another device removed $name. Remove it here too?';
  @override
  String get keep => 'Keep';
  @override
  String get linkPhoneWeb => 'Link a phone via web';
  @override
  String get linkPhoneWebHint =>
      'Scan with the phone camera (same Wi-Fi). Safari warns once about the certificate: tap Show Details, then visit this website.';
  @override
  String get linkedBrowsers => 'Linked browsers';
  @override
  String sentToBrowser(String name) => 'Ready for $name to download';
  @override
  String get waitingForPeer => 'Waiting for the other device…';
  @override
  String get dropFiles => 'Drop files to send';
  @override
  String get dropFilesSub => 'Any size · Resumable · SHA-256 checked';
  @override
  String get online => 'Online';
  @override
  String get manual => 'Manual';
  @override
  String get syncLatency => 'Sync latency · p95';
  @override
  String latencyTarget({required bool under}) =>
      under ? 'Under 1,000 ms target' : 'Over 1,000 ms target';

  @override
  String connectedTo(String network) => 'Connected · $network';
  @override
  String get clipboardSync => 'Clipboard sync';
  @override
  String get onlineDevices => 'ONLINE DEVICES';
  @override
  String get trayOpenDropzone => 'Open Dropzone';
  @override
  String get traySendClipboard => 'Send clipboard to…';
  @override
  String get trayPair => 'Pair new device…';
  @override
  String get trayTrusted => 'Trusted devices…';
  @override
  String get traySettings => 'Settings…';
  @override
  String get trayQuit => 'Quit DropClip';
  @override
  String get dropHere => 'Drop files or folders here';
  @override
  String get releaseToAdd => 'Release to add';
  @override
  String get clickToChoose => 'or click to choose files';
  @override
  String itemCount(int n) => n == 1 ? '1 item' : '$n items';
  @override
  String get sendTo => 'SEND TO';
  @override
  String sendToDevice(String name) => 'Send to $name';
  @override
  String get dropzoneKeys => '↑↓ choose · Enter send · Esc close';
  @override
  String debugConsole(int lines) => 'Debug console · $lines lines';
  @override
  String get noLogLines => 'No log lines yet';
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
  String get webCompanion => 'เว็บคอมพาเนียน (/web)';
  @override
  String get webCompanionSub =>
      'เปิดให้เบราว์เซอร์มือถือเชื่อมต่อผ่าน HTTPS ในวง LAN (หมดอายุใน 8 ชม.)';
  @override
  String get connection => 'การเชื่อมต่อ';
  @override
  String get networkAdapter => 'อแดปเตอร์เครือข่าย';
  @override
  String get networkAdapterSub =>
      'เลือกการเชื่อมต่อที่อุปกรณ์อื่นใช้เข้าถึงเครื่องนี้ โหมดอัตโนมัติจะข้าม '
      'สวิตช์เสมือน VPN และ Wi-Fi Direct';
  @override
  String get networkAutomatic => 'อัตโนมัติ';
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
  String get deviceName => 'ชื่อเครื่อง';
  @override
  String get deviceNameSub =>
      'ชื่อที่เครื่องอื่นเห็น เครื่องที่จับคู่แล้วจะเห็นชื่อใหม่เมื่อเชื่อมต่อครั้งถัดไป';
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

  @override
  String get copied => 'คัดลอกแล้ว';
  @override
  String liveSyncAcross(int n) =>
      'ซิงก์สดกับ $n อุปกรณ์ · ข้อความ ลิงก์ PNG/JPEG';
  @override
  String get autoSync => 'ซิงก์อัตโนมัติ';
  @override
  String get searchClips => 'ค้นหาคลิปล่าสุด…';
  @override
  String get all => 'ทั้งหมด';
  @override
  String get recentHeader =>
      'ล่าสุด · สูงสุด 20 รายการ · เก็บในหน่วยความจำเท่านั้น';
  @override
  String get noClipsMatch => 'ไม่พบคลิปที่ตรงกัน';
  @override
  String fromDevice(String device, String age) => 'จาก $device · $age';
  @override
  String get copyAgain => 'คัดลอกอีกครั้ง';
  @override
  String get openFile => 'เปิดไฟล์';
  @override
  String get showInFolder => 'เปิดตำแหน่งไฟล์';
  @override
  String get removeItem => 'ลบออก';
  @override
  String suppressed(int n) => 'ไม่ได้ซิงก์ $n รายการจากโปรแกรมจัดการรหัสผ่าน '
      '— ข้อมูลจากโปรแกรมจัดการรหัสผ่านจะไม่ออกจากเครื่องนี้';

  @override
  String get nearbyDevices => 'อุปกรณ์ใกล้เคียง';
  @override
  String onlineCount(int n) => 'ออนไลน์ $n เครื่อง';
  @override
  String get noDevicesNearby => 'ไม่พบอุปกรณ์ใกล้เคียง';
  @override
  String get phoneOnScreenHint =>
      'มือถือจะขึ้นในรายการเมื่อเปิดแอป DropClip ค้างไว้บนหน้าจอ';
  @override
  String get pairNewDevice => 'จับคู่อุปกรณ์ใหม่';
  @override
  String get pairedDevices => 'อุปกรณ์ที่จับคู่แล้ว';
  @override
  String get noPairedDevices => 'ยังไม่มีอุปกรณ์ที่จับคู่';
  @override
  String get connected => 'เชื่อมต่ออยู่';
  @override
  String get offline => 'ออฟไลน์';
  @override
  String get pair => 'จับคู่';
  @override
  String get remove => 'ลบ';
  @override
  String get pinOnOtherDevice =>
      'ที่อุปกรณ์อีกเครื่อง กด "จับคู่" แล้วกรอก PIN นี้';
  @override
  String enterPinOf(String name) => 'กรอก PIN ที่แสดงบน $name';
  @override
  String get sasQuestion => 'ทั้งสองเครื่องแสดงตัวเลขนี้ตรงกันไหม';
  @override
  String get sasMatch => 'ตรงกัน';
  @override
  String get sasNoMatch => 'ไม่ตรงกัน';
  @override
  String pairedWith(String name) => 'จับคู่กับ $name แล้ว';
  @override
  String pairFailed(String code) => 'จับคู่ไม่สำเร็จ ($code)';
  @override
  String receiveFrom(String name) => '$name ต้องการส่งไฟล์ให้คุณ';
  @override
  String get accept => 'รับ';
  @override
  String get decline => 'ปฏิเสธ';
  @override
  String revokedElsewhere(String name) =>
      'อุปกรณ์อื่นลบ $name แล้ว จะลบที่เครื่องนี้ด้วยไหม';
  @override
  String get keep => 'เก็บไว้';
  @override
  String get linkPhoneWeb => 'เชื่อมมือถือผ่านเว็บ';
  @override
  String get linkPhoneWebHint =>
      'สแกนด้วยกล้องมือถือ (Wi-Fi เดียวกัน) ครั้งแรก Safari จะเตือนเรื่องใบรับรอง ให้กด แสดงรายละเอียด แล้วเลือก เข้าชมเว็บไซต์นี้';
  @override
  String get linkedBrowsers => 'เบราว์เซอร์ที่เชื่อมอยู่';
  @override
  String sentToBrowser(String name) => 'พร้อมให้ $name ดาวน์โหลดแล้ว';
  @override
  String get waitingForPeer => 'กำลังรออุปกรณ์อีกเครื่อง…';
  @override
  String get dropFiles => 'ลากไฟล์มาวางเพื่อส่ง';
  @override
  String get dropFilesSub =>
      'ไม่จำกัดขนาด · ส่งต่อจากจุดที่ค้างได้ · ตรวจ SHA-256';
  @override
  String get online => 'ออนไลน์';
  @override
  String get manual => 'ส่งเอง';
  @override
  String get syncLatency => 'ความหน่วงการซิงก์ · p95';
  @override
  String latencyTarget({required bool under}) =>
      under ? 'ต่ำกว่าเป้า 1,000 ms' : 'เกินเป้า 1,000 ms';

  @override
  String connectedTo(String network) => 'เชื่อมต่อแล้ว · $network';
  @override
  String get clipboardSync => 'ซิงก์คลิปบอร์ด';
  @override
  String get onlineDevices => 'อุปกรณ์ที่ออนไลน์';
  @override
  String get trayOpenDropzone => 'เปิด Dropzone';
  @override
  String get traySendClipboard => 'ส่งคลิปบอร์ดไปยัง…';
  @override
  String get trayPair => 'จับคู่อุปกรณ์ใหม่…';
  @override
  String get trayTrusted => 'อุปกรณ์ที่เชื่อถือ…';
  @override
  String get traySettings => 'การตั้งค่า…';
  @override
  String get trayQuit => 'ออกจาก DropClip';
  @override
  String get dropHere => 'ลากไฟล์หรือโฟลเดอร์มาวางที่นี่';
  @override
  String get releaseToAdd => 'ปล่อยเพื่อเพิ่ม';
  @override
  String get clickToChoose => 'หรือคลิกเพื่อเลือกไฟล์';
  @override
  String itemCount(int n) => '$n รายการ';
  @override
  String get sendTo => 'ส่งไปที่';
  @override
  String sendToDevice(String name) => 'ส่งไปที่ $name';
  @override
  String get dropzoneKeys => '↑↓ เลือก · Enter ส่ง · Esc ปิด';
  @override
  String debugConsole(int lines) => 'คอนโซลดีบัก · $lines บรรทัด';
  @override
  String get noLogLines => 'ยังไม่มีบันทึก';
}

/// Provides the [Strings] for the chosen language to the widget tree.
class StringsScope extends InheritedWidget {
  final Strings strings;

  const StringsScope({super.key, required this.strings, required super.child});

  @override
  bool updateShouldNotify(StringsScope old) =>
      old.strings.runtimeType != strings.runtimeType;
}
