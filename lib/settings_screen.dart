import 'package:flutter/material.dart';

import 'main.dart';
import 'turso_service.dart';

class SettingsScreen extends StatefulWidget {
  final String initialUrl;
  final String initialToken;

  const SettingsScreen({
    super.key,
    required this.initialUrl,
    required this.initialToken,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _tokenCtrl;
  bool _mostrarToken = false;
  bool _testando = false;
  bool? _testeOk;
  String? _testeMsg;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialUrl);
    _tokenCtrl = TextEditingController(text: widget.initialToken);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _testar() async {
    setState(() {
      _testando = true;
      _testeOk = null;
      _testeMsg = null;
    });
    final service =
        TursoService(url: _urlCtrl.text, token: _tokenCtrl.text.trim());
    // testConnection devolve a mensagem REAL do erro (DNS, 401, timeout, SQL…)
    final (ok, msg) = await service.testConnection();
    if (!mounted) return;
    setState(() {
      _testando = false;
      _testeOk = ok;
      _testeMsg = msg;
    });
  }

  void _salvar() {
    final url = _urlCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (url.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha a URL e o token.')),
      );
      return;
    }
    Navigator.of(context).pop({'url': url, 'token': token});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações do banco')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Use o mesmo banco Turso do dashboard CAMDA Estoque '
            '(TURSO_DATABASE_URL e TURSO_AUTH_TOKEN).',
            style: TextStyle(color: kMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'URL do banco',
              hintText: 'libsql://seu-banco-usuario.turso.io',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtrl,
            obscureText: !_mostrarToken,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Auth token',
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              suffixIcon: IconButton(
                icon: Icon(_mostrarToken ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _mostrarToken = !_mostrarToken),
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _testando ? null : _testar,
            icon: _testando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: Text(_testando ? 'Testando…' : 'Testar conexão'),
          ),
          if (_testeMsg != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _testeOk == true ? kGreen : kRed),
              ),
              child: Text(
                '${_testeOk == true ? '✅' : '❌'} $_testeMsg',
                style: TextStyle(
                  color: _testeOk == true ? kGreen : kRed,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _salvar,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
