import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';

/// Connexion / inscription — mêmes règles et endpoints que /login du site :
/// pseudo 3–30 caractères `[a-zA-Z0-9_-]`, mot de passe ≥ 12 caractères avec
/// au moins un symbole.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.register = false});
  final bool register;
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late bool _register = widget.register;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  final _pseudo = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pseudo.addListener(() => setState(() {}));
    _pass.addListener(() => setState(() {}));
    _pass2.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pseudo.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  bool get _pseudoOk => RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(_pseudo.text);
  bool get _pseudoLen => _pseudo.text.length >= 3 && _pseudo.text.length <= 30;
  bool get _lenOk => _pass.text.length >= 12;
  bool get _symOk => RegExp(r'''[!@#$%^&*()_+\-=\[\]{}|;':",.\\/<>?`~]''').hasMatch(_pass.text);
  bool get _matchOk => _pass2.text.isNotEmpty && _pass.text == _pass2.text;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _busy = true;
    });
    final acc = ref.read(accountRepositoryProvider);
    String? err;
    try {
      if (_register) {
        if (!_pseudoLen) {
          err = 'Le pseudo doit avoir entre 3 et 30 caractères.';
        } else if (!_pseudoOk) {
          err = 'Le pseudo ne peut contenir que des lettres, chiffres, - et _.';
        } else if (!_lenOk || !_symOk) {
          err = 'Le mot de passe doit faire 12 caractères minimum et contenir un symbole.';
        } else if (!_matchOk) {
          err = 'Les mots de passe ne correspondent pas.';
        } else {
          err = await acc.register(_pseudo.text.trim(), _pass.text);
        }
      } else {
        err = await acc.login(_pseudo.text.trim(), _pass.text);
      }
    } catch (e) {
      err = 'Erreur de connexion au serveur.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      await ref.read(sessionProvider.notifier).refresh();
      if (!mounted) return;
      showSnack(context, 'Connexion réussie ! Données synchronisées.');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(_register ? 'INSCRIPTION' : 'CONNEXION')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Center(child: Image.asset('assets/images/logo.png', width: 150)),
          const SizedBox(height: 20),
          TextField(
            controller: _pseudo,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Pseudo',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: _obscure,
            textInputAction: _register ? TextInputAction.next : TextInputAction.done,
            onSubmitted: (_) => _register ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_register) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _pass2,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Confirmer le mot de passe',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            _Req('Lettres, chiffres, - et _ uniquement', _pseudo.text.isNotEmpty && _pseudoOk),
            _Req('12 caractères minimum', _lenOk),
            _Req('Au moins un symbole', _symOk),
            _Req('Les mots de passe correspondent', _matchOk),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13))),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_register ? 'Créer mon compte' : 'Se connecter'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() {
              _register = !_register;
              _error = null;
            }),
            child: Text(_register
                ? 'Déjà un compte ? Se connecter'
                : 'Pas encore de compte ? S\'inscrire'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.sync_rounded, size: 18, color: AppColors.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'La connexion synchronise vos favoris, watchlist, historique et progression '
                  'avec votre compte anime-sama. Sans compte, tout reste enregistré sur cet appareil.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Req extends StatelessWidget {
  const _Req(this.text, this.ok);
  final String text;
  final bool ok;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 16, color: ok ? AppColors.success : AppColors.textDim),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                fontSize: 12.5, color: ok ? AppColors.text : AppColors.textDim)),
      ]),
    );
  }
}
