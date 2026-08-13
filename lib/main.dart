import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'divergencias_tab.dart';
import 'models.dart';
import 'registrar_tab.dart';
import 'settings_screen.dart';
import 'turso_service.dart';

/// Mesma senha do expander "Registrar divergência de contagem" do dashboard.
const kSenhaEdicao = 'camda@edit';

// Paleta do dashboard CAMDA Estoque
const kBg = Color(0xFF0B1220);
const kCard = Color(0xFF111827);
const kBorder = Color(0xFF1E293B);
const kAmber = Color(0xFFF59E0B);
const kGreen = Color(0xFF22C55E);
const kRed = Color(0xFFF87171);
const kText = Color(0xFFE0E6ED);
const kMuted = Color(0xFF94A3B8);

void main() {
  runApp(const CamdaApp());
}

class CamdaApp extends StatelessWidget {
  const CamdaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CAMDA Divergências',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAmber,
          brightness: Brightness.dark,
          surface: kCard,
        ),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: kCard,
          foregroundColor: kText,
        ),
        cardTheme: CardThemeData(
          color: kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: kBorder),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kBorder),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TursoService? _service;
  String _senhaSalva = '';
  bool _senhaOk = false;

  List<Produto>? _produtos;
  List<Divergencia>? _divergencias;
  bool _loading = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('turso_url') ?? '';
    final token = prefs.getString('turso_token') ?? '';
    _senhaSalva = prefs.getString('senha_edicao') ?? '';
    _senhaOk = _senhaSalva == kSenhaEdicao;
    if (url.isEmpty || token.isEmpty) {
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => _abrirConfiguracoes());
      }
      return;
    }
    _service = TursoService(url: url, token: token);
    await _carregar();
  }

  Future<void> _carregar() async {
    final service = _service;
    if (service == null) return;
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final results = await Future.wait([
        service.fetchProdutos(),
        service.fetchDivergencias(),
      ]);
      if (!mounted) return;
      setState(() {
        _produtos = results[0] as List<Produto>;
        _divergencias = results[1] as List<Divergencia>;
        _loading = false;
      });
    } on TursoException catch (e) {
      // Falha de rede: diz por que falhou (URL errada × DNS do aparelho ×
      // sem internet) em vez de deixar o usuário adivinhando.
      final detalhe =
          e.problemaDeRede ? '\n\n${(await service.diagnosticar()).texto}' : '';
      if (!mounted) return;
      setState(() {
        _erro = '${e.message}$detalhe';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro inesperado: $e';
        _loading = false;
      });
    }
  }

  Future<void> _recarregarDivergencias() async {
    final service = _service;
    if (service == null) return;
    try {
      final divs = await service.fetchDivergencias();
      if (mounted) setState(() => _divergencias = divs);
    } on TursoException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('❌ ${e.message}')));
      }
    }
  }

  Future<void> _abrirConfiguracoes() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initialUrl: prefs.getString('turso_url') ?? '',
          initialToken: prefs.getString('turso_token') ?? '',
        ),
      ),
    );
    if (result == null) return;
    await prefs.setString('turso_url', result['url']!);
    await prefs.setString('turso_token', result['token']!);
    _service = TursoService(url: result['url']!, token: result['token']!);
    await _carregar();
  }

  Future<void> _onSenhaChanged(String senha) async {
    final ok = senha == kSenhaEdicao;
    if (ok != _senhaOk) setState(() => _senhaOk = ok);
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('senha_edicao', senha);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nDivs = _divergencias?.length ?? 0;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('⚠️ CAMDA Divergências',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Recarregar',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _carregar,
            ),
            IconButton(
              tooltip: 'Configurações',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _abrirConfiguracoes,
            ),
          ],
          bottom: TabBar(
            indicatorColor: kAmber,
            labelColor: kAmber,
            unselectedLabelColor: kMuted,
            tabs: [
              const Tab(text: 'REGISTRAR'),
              Tab(text: 'ATIVAS${nDivs > 0 ? ' ($nDivs)' : ''}'),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_service == null) {
      return _centerMessage(
        icon: Icons.settings_outlined,
        text: 'Configure a URL e o token do banco Turso para começar.',
        action: FilledButton(
          onPressed: _abrirConfiguracoes,
          child: const Text('Abrir configurações'),
        ),
      );
    }
    if (_loading && _produtos == null) {
      return const Center(child: CircularProgressIndicator(color: kAmber));
    }
    if (_erro != null && _produtos == null) {
      return _centerMessage(
        icon: Icons.cloud_off,
        text: _erro!,
        action: FilledButton(onPressed: _carregar, child: const Text('Tentar novamente')),
      );
    }
    return TabBarView(
      children: [
        RegistrarTab(
          service: _service!,
          produtos: _produtos ?? const [],
          divergencias: _divergencias ?? const [],
          senhaInicial: _senhaSalva,
          senhaOk: _senhaOk,
          onSenhaChanged: _onSenhaChanged,
          onRegistrado: _recarregarDivergencias,
        ),
        DivergenciasTab(
          service: _service!,
          divergencias: _divergencias ?? const [],
          senhaOk: _senhaOk,
          onChanged: _recarregarDivergencias,
          onRefresh: _carregar,
        ),
      ],
    );
  }

  Widget _centerMessage({
    required IconData icon,
    required String text,
    Widget? action,
  }) {
    return Center(
      child: SingleChildScrollView(
        // O diagnóstico de rede é longo: sem rolagem ele estoura a tela.
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: kMuted),
            const SizedBox(height: 16),
            SelectableText(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kText, height: 1.35),
            ),
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );
  }
}
