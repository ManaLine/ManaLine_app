import 'package:web/web.dart' as web;

Future<void> write(String key, String? value) async {
  if (value == null) {
    web.window.sessionStorage.removeItem(key);
    return;
  }
  web.window.sessionStorage.setItem(key, value);
}

Future<String?> read(String key) async =>
    web.window.sessionStorage.getItem(key);

Future<void> delete(String key) async =>
    web.window.sessionStorage.removeItem(key);
