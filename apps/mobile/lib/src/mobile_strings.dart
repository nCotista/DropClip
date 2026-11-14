import 'package:flutter/widgets.dart';

/// The phone app's texts in English and Thai (NFR-L01).
class MobileStrings {
  final bool th;

  const MobileStrings(this.th);

  static MobileStrings of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MobileStringsScope>()
          ?.strings ??
      const MobileStrings(false);

  String _t(String en, String thai) => th ? thai : en;

  String get pairWithComputer => _t('Pair device', 'จับคู่อุปกรณ์');
  String get sendClipboard => _t('Send clipboard', 'ส่งคลิปบอร์ด');
  String get sendFile => _t('Send file', 'ส่งไฟล์');
  String get sent => _t('Sent', 'ส่งแล้ว');
  String get connected => _t('Connected', 'เชื่อมต่ออยู่');
  String get offline => _t('Offline', 'ออฟไลน์');
  String get remove => _t('Remove', 'ลบ');
  String removeQuestion(String name) => _t(
      'Remove $name? It will forget this phone too.',
      'ลบ $name ไหม? เครื่องนั้นจะลืมมือถือเครื่องนี้ด้วย');
  String get cancel => _t('Cancel', 'ยกเลิก');
  String get received => _t('Received', 'ที่ได้รับ');
  String get nothingYet => _t('Nothing received yet', 'ยังไม่ได้รับอะไร');
  String get clear => _t('Clear', 'ล้าง');
  String get copyAgain => _t('Copy again', 'คัดลอกอีกครั้ง');
  String get openFile => _t('Open', 'เปิด');
  String get copied => _t('Copied', 'คัดลอกแล้ว');
  String fromDevice(String name) => _t('From $name', 'จาก $name');
  String get noComputerOnline =>
      _t('No device is connected', 'ไม่มีอุปกรณ์ที่เชื่อมต่ออยู่');
  String get sendTo => _t('Send to', 'ส่งไปที่');
  String sending(String name, int percent) =>
      _t('Sending $name… $percent%', 'กำลังส่ง $name… $percent%');
  String sentFile(String name) => _t('Sent $name', 'ส่ง $name แล้ว');
  String sendFailed(String why) =>
      _t('Could not send: $why', 'ส่งไม่สำเร็จ: $why');
  String get settings => _t('Settings', 'ตั้งค่า');
  String get computers => _t('Devices', 'อุปกรณ์');
  String get statusNoPair =>
      _t('No paired device yet', 'ยังไม่มีอุปกรณ์ที่จับคู่');
  String get statusNoPairHint => _t(
      'Pair with a computer or another phone: scan, enter IP + PIN, or show a QR code.',
      'จับคู่กับคอมพิวเตอร์หรือมือถืออีกเครื่อง: สแกน กรอก IP + PIN หรือแสดงคิวอาร์โค้ด');
  String get statusOffline => _t('Not connected', 'ยังไม่ได้เชื่อมต่อ');
  String get statusOfflineHint => _t(
      'Open DropClip on the other device, on the same Wi-Fi.',
      'เปิด DropClip บนอีกเครื่อง และต่อ Wi-Fi วงเดียวกัน');
  String statusConnected(String name) =>
      _t('Connected to $name', 'เชื่อมต่อกับ $name');
  String get statusConnectedHint => _t(
      'Copied text arrives here; tap a clip to copy it again.',
      'ข้อความที่คัดลอกจะส่งมาที่นี่ แตะเพื่อคัดลอกอีกครั้ง');
  String get thisPhone => _t('This phone', 'มือถือเครื่องนี้');
  String get phoneName => _t('Phone name', 'ชื่อมือถือ');
  String get phoneNameHint => _t(
      'What other devices see; paired ones update when they next connect',
      'ชื่อที่เครื่องอื่นเห็น เครื่องที่จับคู่แล้วจะเห็นชื่อใหม่เมื่อเชื่อมต่อครั้งถัดไป');
  String get save => _t('Save', 'บันทึก');
  String get language => _t('Language', 'ภาษา');
  String get syncClipboard => _t('Sync clipboard', 'ซิงก์คลิปบอร์ด');
  String get syncHint =>
      _t('Off: nothing is sent or received', 'ปิด: จะไม่ส่งและไม่รับคลิปบอร์ด');
  String get syncOff => _t('Clipboard sync is off', 'ซิงก์คลิปบอร์ดปิดอยู่');
  String get computerIp => _t('Device IP', 'IP ของอุปกรณ์');
  String get port => _t('Port', 'พอร์ต');
  String get scanQr => _t('Scan QR', 'สแกน QR');
  String get joinMode => _t('Scan / PIN', 'สแกน / PIN');
  String get hostMode => _t('Show QR', 'แสดง QR');
  String get pinOnOtherDevice => _t(
      'Or enter this PIN on the other device', 'หรือกรอกรหัสนี้บนอีกเครื่อง');
  String get waitingForPeer => _t(
      'Waiting for confirmation on the other device…', 'รออีกเครื่องยืนยัน…');
  String get pair => _t('Pair', 'จับคู่');
  String get close => _t('Close', 'ปิด');
  String get sasQuestion => _t(
      'Does the other device show this number?', 'อีกเครื่องแสดงตัวเลขนี้ไหม?');
  String get match => _t('Match', 'ตรงกัน');
  String get noMatch => _t("Doesn't match", 'ไม่ตรงกัน');
  String pairedWith(String name) =>
      _t('Paired with $name', 'จับคู่กับ $name แล้ว');
  String pairFailed(String why) =>
      _t('Pairing failed: $why', 'จับคู่ไม่สำเร็จ: $why');
  String get scanTitle =>
      _t('Scan the pairing QR code', 'สแกนคิวอาร์โค้ดจับคู่');
}

class MobileStringsScope extends InheritedWidget {
  final MobileStrings strings;

  const MobileStringsScope(
      {super.key, required this.strings, required super.child});

  @override
  bool updateShouldNotify(MobileStringsScope old) =>
      old.strings.th != strings.th;
}
