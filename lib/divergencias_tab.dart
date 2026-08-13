import 'package:flutter/material.dart';

import 'main.dart';
import 'models.dart';
import 'turso_service.dart';

/// Tipo do filtro inteligente aplicado na lista de divergências ativas.
enum FiltroTipo { cooperado, produto, categoria }

extension FiltroTipoUi on FiltroTipo {
  IconData get icone {
    switch (this) {
      case FiltroTipo.cooperado:
        return Icons.person_outline;
      case FiltroTipo.produto:
        return Icons.inventory_2_outlined;
      case FiltroTipo.categoria:
        return Icons.category_outlined;
    }
  }

  String get rotulo {
    switch (this) {
      case FiltroTipo.cooperado:
        return 'Cooperado';
      case FiltroTipo.produto:
        return 'Produto';
      case FiltroTipo.categoria:
        return 'Categoria';
    }
  }
}

/// Sugestão exibida enquanto o usuário digita no campo de busca.
class _Sugestao {
  final FiltroTipo tipo;
  final String valor;
  final int quantidade;
  final int saldo;

  const _Sugestao({
    required this.tipo,
    required this.valor,
    required this.quantidade,
    required this.saldo,
  });
}

/// Normaliza texto para busca: minúsculas e sem acentos, para que "jose"
/// encontre "José" e "seringa" encontre "Seringa".
String _norm(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final buffer = StringBuffer();
  for (final c in s.toLowerCase().runes) {
    final ch = String.fromCharCode(c);
    final i = de.indexOf(ch);
    buffer.write(i >= 0 ? para[i] : ch);
  }
  return buffer.toString();
}

/// Lista das divergências ativas (tabela `divergencias`), igual à aba
/// Divergências do dashboard. Permite filtrar por cooperado/produto/categoria
/// e resolver (apagar) um registro com a mesma lógica do dashboard, exigindo
/// a senha de edição.
class DivergenciasTab extends StatefulWidget {
  final TursoService service;
  final List<Divergencia> divergencias;
  final bool senhaOk;
  final Future<void> Function() onChanged;
  final Future<void> Function() onRefresh;

  const DivergenciasTab({
    super.key,
    required this.service,
    required this.divergencias,
    required this.senhaOk,
    required this.onChanged,
    required this.onRefresh,
  });

  @override
  State<DivergenciasTab> createState() => _DivergenciasTabState();
}

class _DivergenciasTabState extends State<DivergenciasTab>
    with AutomaticKeepAliveClientMixin {
  final _buscaCtrl = TextEditingController();
  final _buscaFocus = FocusNode();

  FiltroTipo? _filtroTipo;
  String _filtroValor = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // O foco muda quais sugestões aparecem (atalho de cooperados com o
    // campo vazio), por isso o rebuild.
    _buscaFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    _buscaFocus.dispose();
    super.dispose();
  }

  bool get _temFiltro => _filtroTipo != null;

  String _campo(Divergencia d, FiltroTipo tipo) {
    switch (tipo) {
      case FiltroTipo.cooperado:
        return d.cooperado;
      case FiltroTipo.produto:
        return d.produto;
      case FiltroTipo.categoria:
        return d.categoria;
    }
  }

  /// Divergências exibidas: filtro selecionado tem prioridade; sem filtro,
  /// o texto digitado faz uma busca livre em todos os campos.
  List<Divergencia> get _filtradas {
    if (_temFiltro) {
      final alvo = _norm(_filtroValor);
      return widget.divergencias
          .where((d) => _norm(_campo(d, _filtroTipo!)) == alvo)
          .toList();
    }
    final q = _norm(_buscaCtrl.text.trim());
    if (q.isEmpty) return widget.divergencias;
    return widget.divergencias
        .where((d) =>
            _norm(d.cooperado).contains(q) ||
            _norm(d.produto).contains(q) ||
            _norm(d.codigo).contains(q) ||
            _norm(d.categoria).contains(q))
        .toList();
  }

  /// Agrupa as divergências por um campo e devolve as sugestões que casam
  /// com o texto digitado, das mais frequentes para as menos frequentes.
  List<_Sugestao> _sugestoesDe(FiltroTipo tipo, String q) {
    final qtd = <String, int>{};
    final saldo = <String, int>{};
    for (final d in widget.divergencias) {
      final valor = _campo(d, tipo).trim();
      if (valor.isEmpty) continue;
      if (q.isNotEmpty && !_norm(valor).contains(q)) continue;
      qtd[valor] = (qtd[valor] ?? 0) + 1;
      saldo[valor] = (saldo[valor] ?? 0) + d.delta;
    }
    final itens = qtd.keys
        .map((v) => _Sugestao(
              tipo: tipo,
              valor: v,
              quantidade: qtd[v]!,
              saldo: saldo[v]!,
            ))
        .toList();
    itens.sort((a, b) {
      final porQtd = b.quantidade.compareTo(a.quantidade);
      return porQtd != 0 ? porQtd : a.valor.compareTo(b.valor);
    });
    return itens;
  }

  /// Sugestões exibidas abaixo do campo: cooperados primeiro (é o uso mais
  /// comum), depois categorias e produtos. Com o campo vazio e em foco,
  /// mostra os cooperados com mais divergências como atalho.
  List<_Sugestao> get _sugestoes {
    final q = _norm(_buscaCtrl.text.trim());
    if (q.isEmpty) {
      if (!_buscaFocus.hasFocus) return const [];
      return _sugestoesDe(FiltroTipo.cooperado, '').take(6).toList();
    }
    return [
      ..._sugestoesDe(FiltroTipo.cooperado, q).take(6),
      ..._sugestoesDe(FiltroTipo.categoria, q).take(3),
      ..._sugestoesDe(FiltroTipo.produto, q).take(4),
    ];
  }

  void _aplicarFiltro(FiltroTipo tipo, String valor) {
    _buscaFocus.unfocus();
    setState(() {
      _filtroTipo = tipo;
      _filtroValor = valor;
      _buscaCtrl.clear();
    });
  }

  void _limparFiltro() {
    setState(() {
      _filtroTipo = null;
      _filtroValor = '';
      _buscaCtrl.clear();
    });
  }

  Future<void> _resolver(BuildContext context, Divergencia d) async {
    if (!widget.senhaOk) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🔑 Digite a senha de edição na aba Registrar para resolver.'),
      ));
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Resolver divergência?', style: TextStyle(fontSize: 16)),
        content: Text(
          '${d.produto} (${d.codigo})\n'
          '${d.status} de ${d.deltaFmt} un.'
          '${d.cooperado.isEmpty ? '' : ' · ${d.cooperado}'}\n\n'
          'O registro será removido da lista de divergências ativas '
          '(o histórico é mantido).',
          style: const TextStyle(color: kMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Resolver')),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;
    try {
      await widget.service.resolverDivergencia(d);
      await widget.onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Divergência de ${d.produto} resolvida.'),
          backgroundColor: const Color(0xFF14532D),
        ));
      }
    } on TursoException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ ${e.message}'),
          backgroundColor: const Color(0xFF7F1D1D),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lista = _filtradas;
    final sugestoes = _sugestoes;
    return Column(
      children: [
        _buildBusca(),
        if (sugestoes.isNotEmpty) _buildSugestoes(sugestoes),
        if (_temFiltro || _buscaCtrl.text.trim().isNotEmpty) _buildResumo(lista),
        Expanded(child: _buildLista(lista)),
      ],
    );
  }

  Widget _buildBusca() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _buscaCtrl,
            focusNode: _buscaFocus,
            textCapitalization: TextCapitalization.words,
            // Digitar de novo começa uma busca nova: o filtro anterior sai
            // de cena para não competir com o texto.
            onChanged: (v) => setState(() {
              if (v.trim().isNotEmpty) {
                _filtroTipo = null;
                _filtroValor = '';
              }
            }),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filtrar por cooperado, produto ou código…',
              hintStyle: const TextStyle(color: kMuted, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: kMuted),
              suffixIcon: _buscaCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, color: kMuted),
                      onPressed: () {
                        _buscaCtrl.clear();
                        setState(() {});
                      },
                    ),
            ),
            style: const TextStyle(color: kText, fontSize: 13.5),
          ),
          if (_temFiltro)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                children: [
                  Chip(
                    backgroundColor: kCard,
                    side: const BorderSide(color: kAmber),
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(_filtroTipo!.icone, size: 16, color: kAmber),
                    label: Text(_filtroValor,
                        style: const TextStyle(color: kAmber, fontSize: 12.5)),
                    deleteIcon: const Icon(Icons.close, size: 16, color: kAmber),
                    onDeleted: _limparFiltro,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSugestoes(List<_Sugestao> sugestoes) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: sugestoes.length,
        itemBuilder: (context, i) {
          final s = sugestoes[i];
          final sobra = s.saldo > 0;
          return ListTile(
            dense: true,
            leading: Icon(s.tipo.icone, size: 18, color: kAmber),
            title: Text(s.valor,
                style: const TextStyle(color: kText, fontSize: 13.5),
                overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${s.tipo.rotulo} · ${s.quantidade} divergência'
              '${s.quantidade == 1 ? '' : 's'}',
              style: const TextStyle(color: kMuted, fontSize: 11.5),
            ),
            trailing: Text(
              s.saldo == 0 ? '0' : '${sobra ? '+' : ''}${s.saldo}',
              style: TextStyle(
                color: s.saldo == 0 ? kMuted : (sobra ? kGreen : kRed),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            onTap: () => _aplicarFiltro(s.tipo, s.valor),
          );
        },
      ),
    );
  }

  Widget _buildResumo(List<Divergencia> lista) {
    final faltas = lista.where((d) => d.delta < 0).length;
    final sobras = lista.where((d) => d.delta > 0).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${lista.length} de ${widget.divergencias.length} · '
              '$faltas falta${faltas == 1 ? '' : 's'} · '
              '$sobras sobra${sobras == 1 ? '' : 's'}',
              style: const TextStyle(color: kMuted, fontSize: 12),
            ),
          ),
          if (_temFiltro || _buscaCtrl.text.isNotEmpty)
            InkWell(
              onTap: _limparFiltro,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('Limpar',
                    style: TextStyle(
                        color: kAmber,
                        fontSize: 12,
                        decoration: TextDecoration.underline)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLista(List<Divergencia> lista) {
    if (lista.isEmpty) {
      final filtrando = _temFiltro || _buscaCtrl.text.trim().isNotEmpty;
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        color: kAmber,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            Icon(filtrando ? Icons.search_off : Icons.check_circle_outline,
                size: 48, color: filtrando ? kMuted : kGreen),
            const SizedBox(height: 12),
            Center(
              child: Text(
                filtrando
                    ? 'Nenhuma divergência para esse filtro.'
                    : 'Nenhuma divergência ativa. 🎉',
                style: const TextStyle(color: kMuted),
              ),
            ),
            if (filtrando) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _limparFiltro,
                  child: const Text('Limpar filtro',
                      style: TextStyle(color: kAmber)),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: kAmber,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: lista.length,
        itemBuilder: (context, i) {
          final d = lista[i];
          final sobra = d.delta > 0;
          final temCooperado = d.cooperado.trim().isNotEmpty;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              title: Text(d.produto,
                  style: const TextStyle(
                      color: kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cod: ${d.codigo} · ${d.categoria}',
                        style: const TextStyle(color: kMuted, fontSize: 11.5)),
                    Row(
                      children: [
                        // Toque no nome filtra a lista por aquele cooperado.
                        InkWell(
                          onTap: temCooperado
                              ? () => _aplicarFiltro(
                                  FiltroTipo.cooperado, d.cooperado.trim())
                              : null,
                          child: Text(
                            temCooperado ? d.cooperado : 'sem cooperado',
                            style: TextStyle(
                              color: temCooperado ? kAmber : kMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(' · ${d.criadoEm}',
                              style:
                                  const TextStyle(color: kMuted, fontSize: 11.5),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${sobra ? 'SOBRA' : 'FALTA'} ${d.deltaFmt}',
                    style: TextStyle(
                      color: sobra ? kGreen : kRed,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  InkWell(
                    onTap: () => _resolver(context, d),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Resolver',
                          style: TextStyle(
                              color: kAmber,
                              fontSize: 11.5,
                              decoration: TextDecoration.underline)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
