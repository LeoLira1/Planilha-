import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'divergencias_tab.dart';
import 'models.dart';
import 'produtos_cache.dart';
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

  /// Assinatura do estoque correspondente aos produtos que estão em memória.
  String _assinaturaProdutos = '';
  DateTime? _produtosSalvoEm;
  DateTime? _atualizadoEm;

  /// Validade máxima do cache de produtos. A assinatura já pega qualquer
  /// mudança real; isso é só rede de segurança para o caso raro de uma
  /// alteração que não mexa nem na contagem nem nas somas (trocar as
  /// quantidades de dois produtos entre si, por exemplo).
  static const _validadeCache = Duration(hours: 24);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('turso_url') ?? '';
    final token = prefs.getString('turso_token') ?? '';
    _senhaSalva = prefs.getString('senha_edicao') ?? '';
    _senhaOk = _senhaSalva == kSenhaEdicao;
    // Cache antes da rede: a lista de produtos aparece na hora, mesmo offline.
    await _lerCache();
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

  Future<void> _lerCache() async {
    final cache = await ProdutosCache.ler();
    if (cache == null || !mounted) return;
    setState(() {
      _produtos = cache.produtos;
      _assinaturaProdutos = cache.assinatura;
      _produtosSalvoEm = cache.salvoEm;
    });
  }

  /// Recarrega em duas etapas em vez de baixar tudo:
  ///   1. um único request traz as divergências (payload pequeno) e a
  ///      assinatura do estoque — a aba Ativas já atualiza aqui;
  ///   2. os ~800 e poucos produtos só descem se a assinatura mudou, se
  ///      ainda não temos nada, ou se o cache passou de [_validadeCache].
  /// No caso comum (estoque em dia) o refresh inteiro é um request de alguns
  /// bytes, numa conexão que já está aberta.
  Future<void> _carregar({bool manual = false}) async {
    final service = _service;
    // O botão já fica desabilitado durante o load, mas o pull-to-refresh não:
    // sem esta guarda, puxar a lista várias vezes empilha recargas.
    if (service == null || _loading) return;
    setState(() {
      _loading = true;
      _erro = null;
    });
    final cronometro = Stopwatch()..start();
    try {
      final r = await service.fetchDivergenciasEAssinatura();
      if (!mounted) return;
      setState(() => _divergencias = r.divergencias);

      final cacheVencido = _produtosSalvoEm == null ||
          DateTime.now().difference(_produtosSalvoEm!) > _validadeCache;
      final baixarProdutos = _produtos == null ||
          cacheVencido ||
          r.assinatura != _assinaturaProdutos;

      if (baixarProdutos) {
        final produtos = await service.fetchProdutos();
        await ProdutosCache.gravar(produtos, r.assinatura);
        if (!mounted) return;
        setState(() {
          _produtos = produtos;
          _assinaturaProdutos = r.assinatura;
          _produtosSalvoEm = DateTime.now();
        });
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _atualizadoEm = DateTime.now();
      });
      if (kDebugMode) {
        debugPrint('[carregar] ${cronometro.elapsedMilliseconds} ms — produtos '
            '${baixarProdutos ? 'baixados' : 'do cache'}');
      }
      if (manual) {
        _avisar(baixarProdutos
            ? '✅ Atualizado — ${_produtos?.length ?? 0} produtos'
            : '✅ Atualizado — estoque já estava em dia');
      }
    } on TursoException catch (e) {
      // Falha de rede: diz por que falhou (URL errada × DNS do aparelho ×
      // sem internet) em vez de deixar o usuário adivinhando. O diagnóstico
      // leva alguns segundos, então só roda quando o erro vai mesmo tomar a
      // tela — com produtos em cache ele viraria só espera inútil.
      final semDados = _produtos == null;
      final detalhe = (semDados && e.problemaDeRede)
          ? '\n\n${(await service.diagnosticar()).texto}'
          : '';
      if (!mounted) return;
      setState(() {
        _erro = '${e.message}$detalhe';
        _loading = false;
      });
      // Com dados em cache a tela continua utilizável: o erro vira aviso.
      if (!semDados) _avisar('❌ ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro inesperado: $e';
        _loading = false;
      });
      if (_produtos != null) _avisar('❌ Erro inesperado: $e');
    }
  }

  void _avisar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
    _service?.dispose();
    _service = TursoService(url: result['url']!, token: result['token']!);
    // Outro banco, outro estoque_mestre: o cache guardado não vale mais.
    await ProdutosCache.limpar();
    if (!mounted) return;
    setState(() {
      _produtos = null;
      _assinaturaProdutos = '';
      _produtosSalvoEm = null;
      // Um refresh do banco antigo pode estar no ar; o serviço dele já foi
      // fechado, então o resultado é lixo. Zerar aqui evita que a guarda de
      // _loading engula a recarga do banco novo.
      _loading = false;
    });
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
              tooltip: _atualizadoEm == null
                  ? 'Recarregar'
                  : 'Recarregar (última: ${_hhmm(_atualizadoEm!)})',
              // Enquanto atualiza, o próprio botão vira o indicador: os dados
              // em cache continuam na tela em vez de sumirem num spinner.
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kAmber),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _loading ? null : () => _carregar(manual: true),
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
        action: FilledButton(
            onPressed: () => _carregar(manual: true),
            child: const Text('Tentar novamente')),
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
          onRefresh: () => _carregar(manual: true),
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
