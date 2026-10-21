import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import 'auth_controller.dart';

/// What the sign-in form shows for a failed attempt.
///
/// Known backend codes get their own localized wording, chosen by
/// [ApiException.code] rather than the server's English message, so the text
/// follows the app's language. Anything else shows [ApiException.message],
/// which `fromResponse` has already stripped of server-side object dumps —
/// falling back to plain wording when that is all the server sent.
String loginErrorMessage(AppLocalizations l10n, ApiException error) =>
    switch (error.code) {
      'invalid_credentials' => l10n.loginInvalidCredentialsError,
      _ => error.message,
    };

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  /// The brand mark, also bundled as the launcher icon's source.
  static const logoAsset = 'assets/launcher/app_icon.png';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _submitting = false;
  bool _obscure = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // Pre-fill the last signed-in address. Agents share devices between shifts
    // far less often than they re-open the app, so this saves typing.
    ref.read(secureStoreProvider).readLastEmail().then((email) {
      if (email != null && mounted) _emailController.text = email;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // One sign-in at a time: the button stays tappable (and readable) while
    // the request runs, so further taps and Enter presses land here.
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(
            email: _emailController.text,
            password: _passwordController.text,
          );
      // Navigation is the router's job — it redirects on auth state change.
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = loginErrorMessage(context.l10n, error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final environment = ref.watch(environmentProvider);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            // Short screens (or the keyboard taking half of one) get a
            // smaller mark and tighter gaps, never an overflow: the whole
            // page scrolls once it no longer fits.
            final compact = viewport.maxHeight < 640;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.xl,
                vertical: Space.xl,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0, viewport.maxHeight - Space.xl * 2),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Brand(compact: compact),
                        SizedBox(height: compact ? Space.xl : Space.xxl),
                        _FormPanel(
                          child: AutofillGroup(
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    l10n.signInTitle,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    l10n.signInSubtitle,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: Space.xl),
                                  _emailField(l10n),
                                  const SizedBox(height: Space.lg),
                                  _passwordField(l10n),
                                  if (_error.isNotEmpty) ...[
                                    const SizedBox(height: Space.lg),
                                    InlineError(message: _error),
                                  ],
                                  const SizedBox(height: Space.xl),
                                  _SignInButton(
                                    label: l10n.signInButton,
                                    loading: _submitting,
                                    onPressed: _submit,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Development builds only. `showsDeveloperAffordances`
                        // rather than `isDevelopment`: the environment
                        // defaults to development, so the latter printed the
                        // backend host on the login screen of any release
                        // build made without --dart-define.
                        if (environment.showsDeveloperAffordances) ...[
                          const SizedBox(height: Space.lg),
                          Text(
                            environment.apiBaseUrl,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _emailField(AppLocalizations l10n) => TextFormField(
    key: const Key('loginEmailField'),
    controller: _emailController,
    keyboardType: TextInputType.emailAddress,
    textInputAction: TextInputAction.next,
    // An address reads left to right in either language; the label and
    // icon still follow the app's direction.
    textDirection: TextDirection.ltr,
    autocorrect: false,
    enableSuggestions: false,
    // Lets Keychain / Google Password Manager fill these, which is what
    // makes a long unique password practical on a phone.
    autofillHints: const [AutofillHints.username, AutofillHints.email],
    readOnly: _submitting,
    onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
    decoration: InputDecoration(
      labelText: l10n.emailLabel,
      hintText: l10n.emailHint,
      hintTextDirection: TextDirection.ltr,
      prefixIcon: const Icon(Icons.alternate_email, size: 20),
    ),
    validator: (value) => (value == null || !value.contains('@'))
        ? l10n.emailValidationError
        : null,
  );

  Widget _passwordField(AppLocalizations l10n) => TextFormField(
    key: const Key('loginPasswordField'),
    controller: _passwordController,
    focusNode: _passwordFocus,
    obscureText: _obscure,
    textInputAction: TextInputAction.done,
    textDirection: TextDirection.ltr,
    autocorrect: false,
    // Keeps the password out of the keyboard's learned-word dictionary,
    // which is shared across apps.
    enableSuggestions: false,
    autofillHints: const [AutofillHints.password],
    readOnly: _submitting,
    onFieldSubmitted: (_) => _submit(),
    decoration: InputDecoration(
      labelText: l10n.passwordLabel,
      prefixIcon: const Icon(Icons.lock_outline, size: 20),
      suffixIcon: IconButton(
        key: const Key('loginPasswordVisibility'),
        tooltip: _obscure ? l10n.showPasswordTooltip : l10n.hidePasswordTooltip,
        icon: Icon(
          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
        ),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
    validator: (value) =>
        (value == null || value.isEmpty) ? l10n.passwordValidationError : null,
  );
}

/// The logo, the product name and what it is for.
class _Brand extends StatelessWidget {
  const _Brand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final logoSize = compact ? 68.0 : 88.0;

    return Column(
      children: [
        // The launcher icon's artwork: a square tile, shown at a fixed
        // square size so it can never stretch, and rounded like the icon
        // it is on the home screen.
        DecoratedBox(
          key: const Key('loginLogo'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(logoSize * 0.24),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(logoSize * 0.24),
            child: Image.asset(
              LoginScreen.logoAsset,
              width: logoSize,
              height: logoSize,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              // The product name follows; the mark adds nothing to read out.
              excludeFromSemantics: true,
            ),
          ),
        ),
        SizedBox(height: compact ? Space.md : Space.lg),
        Text(
          l10n.appProductName,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: compact ? 22 : 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          l10n.loginTagline,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }
}

/// The form's own surface: set apart from the page by the theme's card
/// colour and border, without boxing in the whole screen.
class _FormPanel extends StatelessWidget {
  const _FormPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// The primary action. While [loading] it keeps its colour and shows a
/// spinner — a greyed-out button would read as "not allowed" — and the
/// caller ignores further taps.
class _SignInButton extends StatelessWidget {
  const _SignInButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: loading,
      child: FilledButton(
        key: const Key('loginSubmitButton'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: onPressed,
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: scheme.onPrimary,
                  semanticsLabel: label,
                ),
              )
            : Text(
                label,
                // From the text theme, so it is set in the app's font (the
                // button theme's own style names none).
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
