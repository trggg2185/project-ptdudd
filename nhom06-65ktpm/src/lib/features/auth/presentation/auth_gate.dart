import 'package:flutter/material.dart';

import '../domain/auth_repository.dart';
import 'auth_feedback.dart';
import 'sign_in_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.auth,
    this.habitsPageBuilder,
    this.sleepPageBuilder,
    this.profilePageBuilder,
    this.activityPageBuilder,
  });

  final AuthRepository auth;
  final Widget Function(AuthSession)? habitsPageBuilder;
  final Widget Function(AuthSession)? sleepPageBuilder;
  final Widget Function(AuthSession)? profilePageBuilder;
  final Widget Function(AuthSession)? activityPageBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Stream<AuthSession?> _sessions = widget.auth.sessions;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthSession?>(
      stream: _sessions,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Không thể đọc phiên đăng nhập.'),
                    TextButton(
                      onPressed: () =>
                          setState(() => _sessions = widget.auth.sessions),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final session = snapshot.data;
        return session == null
            ? SignInPage(auth: widget.auth)
            : _SessionNavigator(
                key: ValueKey(session.uid),
                auth: widget.auth,
                session: session,
                habitsPageBuilder: widget.habitsPageBuilder,
                sleepPageBuilder: widget.sleepPageBuilder,
                profilePageBuilder: widget.profilePageBuilder,
                activityPageBuilder: widget.activityPageBuilder,
              );
      },
    );
  }
}

// Discard pages and their data when the Firebase user changes.
class _SessionNavigator extends StatefulWidget {
  const _SessionNavigator({
    super.key,
    required this.auth,
    required this.session,
    required this.habitsPageBuilder,
    required this.sleepPageBuilder,
    required this.profilePageBuilder,
    required this.activityPageBuilder,
  });

  final AuthRepository auth;
  final AuthSession session;
  final Widget Function(AuthSession)? habitsPageBuilder;
  final Widget Function(AuthSession)? sleepPageBuilder;
  final Widget Function(AuthSession)? profilePageBuilder;
  final Widget Function(AuthSession)? activityPageBuilder;

  @override
  State<_SessionNavigator> createState() => _SessionNavigatorState();
}

class _SessionNavigatorState extends State<_SessionNavigator> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (result) => _navigator.currentState?.maybePop(result),
      child: Navigator(
        key: _navigator,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (context) => _SessionPage(
            auth: widget.auth,
            session: widget.session,
            habitsPageBuilder: widget.habitsPageBuilder,
            sleepPageBuilder: widget.sleepPageBuilder,
            profilePageBuilder: widget.profilePageBuilder,
            activityPageBuilder: widget.activityPageBuilder,
          ),
        ),
      ),
    );
  }
}

class _SessionPage extends StatefulWidget {
  const _SessionPage({
    required this.auth,
    required this.session,
    required this.habitsPageBuilder,
    required this.sleepPageBuilder,
    required this.profilePageBuilder,
    required this.activityPageBuilder,
  });

  final AuthRepository auth;
  final AuthSession session;
  final Widget Function(AuthSession)? habitsPageBuilder;
  final Widget Function(AuthSession)? sleepPageBuilder;
  final Widget Function(AuthSession)? profilePageBuilder;
  final Widget Function(AuthSession)? activityPageBuilder;

  @override
  State<_SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<_SessionPage> {
  late Future<({bool allowed, String message})> _dataAccess = _checkAccess();
  bool _signingOut = false;
  String? _signOutError;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() {
      _signingOut = true;
      _signOutError = null;
    });
    try {
      await widget.auth.signOut();
    } catch (error) {
      if (mounted) setState(() => _signOutError = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<({bool allowed, String message})> _checkAccess() async {
    try {
      final allowed = await widget.auth.hasDataAccess(refresh: true);
      return (
        allowed: allowed,
        message: allowed ? 'Tài khoản đã được cấp quyền truy cập dữ liệu.' : 'Tài khoản đang chờ quyền truy cập dữ liệu. Liên hệ nhóm trưởng để cấp quyền, rồi kiểm tra lại.',
      );
    } catch (error) {
      return (allowed: false, message: authErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HealthyLife')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Phiên đăng nhập',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (widget.session.email case final email?) Text(email),
                  const SizedBox(height: 24),
                  FutureBuilder<({bool allowed, String message})>(
                    future: _dataAccess,
                    builder: (context, snapshot) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            snapshot.connectionState == ConnectionState.done
                                ? snapshot.requireData.message
                                : 'Đang kiểm tra quyền truy cập dữ liệu…',
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed:
                              snapshot.connectionState !=
                                      ConnectionState.done ||
                                  _signingOut
                              ? null
                              : () => setState(() {
                                  _dataAccess = _checkAccess();
                                }),
                          child: const Text('Kiểm tra lại quyền'),
                        ),
                        for (final entry in {
                          'Mở hồ sơ và lịch': widget.profilePageBuilder,
                          'Mở thói quen': widget.habitsPageBuilder,
                          'Mở nhật ký ngủ': widget.sleepPageBuilder,
                          'Nhật ký vận động': widget.activityPageBuilder,
                        }.entries)
                          if (entry.value case final buildPage?)
                            FilledButton(
                              onPressed:
                                  snapshot.connectionState ==
                                          ConnectionState.done &&
                                      snapshot.data?.allowed == true &&
                                      !_signingOut
                                  ? () => Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            buildPage(widget.session),
                                      ),
                                    )
                                  : null,
                              child: Text(entry.key),
                            ),
                      ],
                    ),
                  ),
                  if (_signOutError case final error?)
                    Semantics(liveRegion: true, child: Text(error)),
                  FilledButton(
                    onPressed: _signingOut ? null : _signOut,
                    child: Text(_signingOut ? 'Đang đăng xuất…' : 'Đăng xuất'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
