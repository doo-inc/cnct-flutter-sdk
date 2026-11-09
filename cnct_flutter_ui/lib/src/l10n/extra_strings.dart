/// The few words a native app needs that the hosted widget's table has no key for, because a web
/// page gets them from the browser: the three sources of the attach menu, what a screen reader
/// says for a message, the offline banner and a refused file type.
///
/// Kept out of `strings.g.dart` on purpose, so that file stays exactly the shared table. Overridable
/// through `strings:` like any other key. They belong in `docs/chat-ui/strings.json` for every SDK;
/// until they are there, they live here, in both languages, and `strings_test.dart` holds them to
/// the same rules as the shared table.
const Map<String, Map<String, String>> cnctExtraStrings = {
  'en': {
    'photos': 'Photos',
    'camera': 'Camera',
    'files': 'Files',
    'youSaid': 'You said: {text}',
    'theySaid': '{name} said: {text}',
    'offline': 'You’re offline. Reconnecting…',
    'teamTyping': 'The team is typing',
    'notAccepted': '{name} is a kind of file that cannot be sent.',
  },
  'ar': {
    'photos': 'الصور',
    'camera': 'الكاميرا',
    'files': 'الملفات',
    'youSaid': 'أنت: {text}',
    'theySaid': '{name}: {text}',
    'offline': 'لا يوجد اتصال. جارٍ إعادة الاتصال…',
    'teamTyping': 'الفريق يكتب الآن',
    'notAccepted': 'لا يمكن إرسال هذا النوع من الملفات: {name}',
  },
};
