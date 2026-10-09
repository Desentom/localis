import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:google_sign_in/google_sign_in.dart';

/// Кто сейчас пользуется приложением.
sealed class AccountState {
  const AccountState();
}

/// Гостевой режим. Приложение полностью работоспособно: все вычисления
/// идут на устройстве, аккаунт для них не нужен.
class GuestAccount extends AccountState {
  const GuestAccount();
}

class SignedInAccount extends AccountState {
  const SignedInAccount({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoUrl,
  });

  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  String get shortName {
    final n = displayName?.trim();
    if (n != null && n.isNotEmpty) return n.split(' ').first;
    if (email != null && email!.contains('@')) return email!.split('@').first;
    return 'Вы';
  }
}

class AuthFailure extends AccountState {
  const AuthFailure(this.message);
  final String message;
}

/// Вход через Google поверх Firebase Auth.
///
/// Ключевая мысль: вход НЕ обязателен. Модель считается на устройстве,
/// сервер не нужен, поэтому заставлять человека логиниться перед первым
/// вопросом — потеря половины установок. Google-вход разблокирует облачную
/// синхронизацию истории, когда она появится.
class AuthService {
  AuthService();

  fa.FirebaseAuth? _auth;
  final _controller = StreamController<AccountState>.broadcast();

  AccountState _state = const GuestAccount();
  AccountState get state => _state;

  /// Firebase недоступен (нет google-services.json, нет сети при первом
  /// запуске). Приложение продолжает работать как гостевое.
  bool get firebaseAvailable => _auth != null;

  Stream<AccountState> get stream => _controller.stream;

  /// Инициализация. Никогда не бросает: любая ошибка Firebase означает
  /// «работаем как гости», а не «не запускаемся».
  Future<void> initialize() async {
    try {
      _auth = fa.FirebaseAuth.instance;
      _auth!.authStateChanges().listen(
        (user) => _emit(_map(user)),
        // Ошибка потока не должна ронять приложение.
        onError: (Object _) {},
      );
      _emit(_map(_auth!.currentUser));
    } on Object {
      _auth = null;
      _emit(const GuestAccount());
    }
  }

  void _emit(AccountState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Future<AccountState> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) {
      const msg = 'Вход пока недоступен. Приложением можно пользоваться и так.';
      _emit(const AuthFailure(msg));
      return _state;
    }
    try {
      final signIn = GoogleSignIn.instance;
      await signIn.initialize(
        clientId: _webClientId.isEmpty ? null : _webClientId,
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );

      // Лёгкая попытка: если человек уже входил раньше, не мучим его
      // выбором аккаунта. В google_sign_in 7.x отдельного currentUser нет —
      // результат возвращает сам метод.
      final existing = await signIn.attemptLightweightAuthentication();
      final google = existing ?? await signIn.authenticate();

      final idToken = google.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google не вернул idToken');
      }

      // В google_sign_in 7.x у GoogleSignInAuthentication есть только idToken:
      // accessToken убрали вместе с currentUser. Для Firebase этого хватает —
      // именно idToken подписывает учётную запись.
      final credential = fa.GoogleAuthProvider.credential(idToken: idToken);
      final userCred = await auth.signInWithCredential(credential);
      _emit(_map(userCred.user));
    } on Object {
      _emit(const AuthFailure('Не удалось войти. Попробуйте ещё раз.'));
    }
    return _state;
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } on Object {
      // Выйти из Google не вышло — это не мешает выйти из Firebase.
    }
    try {
      await _auth?.signOut();
    } on Object {
      // ignore
    }
    _emit(const GuestAccount());
  }

  AccountState _map(fa.User? user) {
    if (user == null) return const GuestAccount();
    return SignedInAccount(
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
      photoUrl: user.photoURL,
    );
  }

  /// Значения из Firebase Console → Project settings. Дублируются в
  /// android/app/google-services.json.
  static const _webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );
}
