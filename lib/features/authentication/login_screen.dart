import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

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
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      await ref.read(authControllerProvider.notifier).login(
            email: _emailController.text,
            password: _passwordController.text,
          );
      // Navigation is the router's job — it redirects on auth state change.
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final environment = ref.watch(environmentProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.xl,
              vertical: Space.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Brand(),
                    const SizedBox(height: 70),
                    Text('Sign in', style: theme.textTheme.titleLarge),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Use your Scenario employee account.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: Space.xl),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      // Lets Keychain / Google Password Manager fill these,
                      // which is what makes a long unique password practical
                      // on a phone. `enableSuggestions: false` on the password
                      // field keeps it out of the keyboard's learned-word
                      // dictionary, which is shared across apps.
                      autofillHints: const [AutofillHints.username],
                      enabled: !_submitting,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@company.com',
                        prefixIcon: Icon(Icons.alternate_email, size: 20),
                      ),
                      validator: (value) =>
                          (value == null || !value.contains('@'))
                              ? 'Enter your email address.'
                              : null,
                    ),
                    const SizedBox(height: Space.md),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.password],
                      enabled: !_submitting,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Enter your password.'
                          : null,
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: Space.lg),
                      InlineError(message: _error),
                    ],
                    const SizedBox(height: Space.xl),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign in',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                            ),
                          ),
                    ),
                    // Development builds only. `showsDeveloperAffordances`
                    // rather than `isDevelopment`: the environment defaults to
                    // development, so the latter printed the backend host on
                    // the login screen of any release build made without
                    // --dart-define.
                    if (environment.showsDeveloperAffordances) ...[
                      const SizedBox(height: Space.lg),
                      Text(
                        environment.apiBaseUrl,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: ScenarioColors.primary,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: const Icon(
            Icons.forum_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: Space.md),
        Text(
          'Scenario',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
        ),
      ],
    );
  }
}
