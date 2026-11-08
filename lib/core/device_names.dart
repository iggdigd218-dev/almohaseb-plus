// ثوابت أسماء الأجهزة الافتراضية — **مصدر حقيقة واحد**.
//
// (توحيد الثوابت) كانت القائمة نفسها مكرّرة نصًّا في `repository.dart`
// و`apply_remote.dart` و`cloud_join.dart` و`profile_dialog.dart`، وأي
// اختلاف حرف واحد يُبطل الحماية صامتًا.
//
// القاعدة: كل ما في هذه القائمة اسم «مكان شاغر» يجوز الكتابة فوقه
// بالاسم الحقيقي القادم من الروستر أو من جهاز المدير.
library;

/// الأسماء الافتراضية التي لا تُعدّ اسمًا مخصّصًا.
const Set<String> kPlaceholderDeviceNames = <String>{
  'المدير',
  'عضو',
  'جهاز',
  'جهاز المحاسب',
  'جهاز مدير الحسابات',
  'جهاز عضو',
  'مستخدم جديد',
  'غير معيّن',
};

/// الاسم الافتراضي المستخدم عند غياب أي اسم.
const String kDefaultMemberDeviceName = 'مستخدم جديد';
const String kDefaultOwnerDeviceName = 'المدير';

/// هل النص اسم مكان شاغر (فارغ أو ضمن القائمة)؟
bool isPlaceholderDeviceName(String? raw) {
  final name = (raw ?? '').trim();
  if (name.isEmpty) return true;
  return kPlaceholderDeviceNames.contains(name);
}

/// هل النص اسم مخصّص حقيقي (غير مكان شاغر)؟
bool isCustomDeviceName(String? raw) => !isPlaceholderDeviceName(raw);

/// توحيد اسم العضو من سجل الجهاز والمستخدم المرتبط به دون إظهار أسماء افتراضية مثل «جهاز» أو «جهاز عضو».
String resolveMemberUnifiedName({
  String? deviceName,
  String? userName,
  bool isOwner = false,
  String? fallback,
}) {
  final dev = (deviceName ?? '').trim();
  final usr = (userName ?? '').trim();
  if (isCustomDeviceName(dev)) return dev;
  if (isCustomDeviceName(usr)) return usr;
  if (fallback != null) return fallback;
  return isOwner ? 'المدير' : 'مستخدم جديد';
}
