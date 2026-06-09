import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';
import 'models.dart';
import 'turso_service.dart';

/// Réplica do expander "⚠️ Registrar divergência de contagem" do dashboard
/// (seção Repor Loja): senha de edição, produto, diferença (+sobrando /
/// −faltando) e nome do cooperado. O valor do sistema NÃO é alterado.
class RegistrarTab extends StatefulWidget {
  final TursoService service;
  final List<Produto> produtos;
  final List<Divergencia> divergencias;
  final String senhaInicial;
  final bool senhaOk;
  final ValueChanged<String> onSenhaChanged;
  final Future<void> Function() onRegistrado;

  const RegistrarTab({
    super.key,
    required this.service,
    required this.produtos,
    required this.divergencias,
    required this.senhaInicial,
    required this.senhaOk,
    required this.onSenhaChanged,
    required this.onRegistrado,
  });

  @override
  State<RegistrarTab> createState() => _RegistrarTabState();
}

class _RegistrarTabState extends State<RegistrarTab>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _senhaCtrl;
  final _buscaCtrl = TextEditingController();
  final _buscaFocus = FocusNode();
  final _deltaCtrl = TextEditingController(text: '0');
  final _coopCtrl = TextEditingController();

  bool _mostrarSenha = false;
  Produto? _selecionado;
  bool _salvando = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _senhaCtrl = TextEditingController(text: widget.senhaInicial);
  }

  @override
  void dispose() {
    _senhaCtrl.dispose();
    _buscaCtrl.dispose();
    _buscaFocus.dispose();
    _deltaCtrl.dispose();
    _coopCtrl.dispose();
    super.dispose();
  }

  int get _delta => int.tryParse(_deltaCtrl.text.trim()) ?? 0;

  void _setDelta(int v) {
    final clamped = v.clamp(-9999, 9999);
    _deltaCtrl.text = '$clamped';
    setState(() {});
  }

  List<Produto> _filtrar(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return widget.produtos
        .where((p) =>
            p.codigo.toLowerCase().contains(q) ||
            p.produto.toLowerCase().contains(q))
        .take(40)
        .toList();
  }

  List<Divergencia> get _divsDoProduto {
    final p = _selecionado;
    if (p == null) return const [];
    return widget.divergencias.where((d) => d.codigo == p.codigo).toList();
  }

  Future<void> _registrar() async {
    final p = _selecionado;
    final delta = _delta;
    if (p == null || delta == 0 || _salvando) return;
    setState(() => _salvando = true);
    try {
      final msg =
          await widget.service.registrarDivergencia(p, delta, _coopCtrl.text);
      await widget.onRegistrado();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: const Color(0xFF14532D)),
      );
      _setDelta(0);
      _coopCtrl.clear();
    } on TursoException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${e.message}'), backgroundColor: const Color(0xFF7F1D1D)),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final senhaDigitada = _senhaCtrl.text;
    final senhaErrada = senhaDigitada.isNotEmpty && !widget.senhaOk;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _senhaCtrl,
          obscureText: !_mostrarSenha,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: widget.onSenhaChanged,
          decoration: InputDecoration(
            labelText: '🔑 Senha para edição',
            hintText: 'Digite a senha…',
            errorText: senhaErrada ? 'Senha incorreta.' : null,
            suffixIcon: IconButton(
              icon: Icon(_mostrarSenha ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _mostrarSenha = !_mostrarSenha),
            ),
          ),
        ),
        if (widget.senhaOk) ...[
          const SizedBox(height: 12),
          const Text(
            'Selecione o produto e informe quantos estão sobrando (+) ou '
            'faltando (−) em relação ao que o sistema mostra. O valor do '
            'sistema não é alterado — apenas a divergência é registrada.',
            style: TextStyle(color: kMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          _buildBuscaProduto(),
          if (_selecionado != null) ...[
            const SizedBox(height: 12),
            _buildCardProduto(_selecionado!),
            const SizedBox(height: 16),
            _buildDelta(),
            const SizedBox(height: 12),
            TextField(
              controller: _coopCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome do cooperado',
                hintText: 'Ex: Rubens Pinto, Maria Julia…',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            if (_delta != 0) ...[
              const SizedBox(height: 12),
              Text(
                'Será registrada ${_delta > 0 ? 'sobra' : 'falta'} de '
                '${_delta > 0 ? '+' : ''}$_delta un. '
                '(físico: ${_selecionado!.qtdSistema + _delta} un. · '
                'sistema: ${_selecionado!.qtdSistema} un.)',
                style: TextStyle(
                  color: _delta > 0 ? kGreen : kRed,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kAmber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (_delta == 0 || _salvando) ? null : _registrar,
              icon: _salvando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.warning_amber_rounded),
              label: Text(_salvando ? 'Registrando…' : 'Registrar divergência'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildBuscaProduto() {
    return RawAutocomplete<Produto>(
      textEditingController: _buscaCtrl,
      focusNode: _buscaFocus,
      optionsBuilder: (v) => _filtrar(v.text),
      displayStringForOption: (p) => p.label,
      onSelected: (p) => setState(() => _selecionado = p),
      fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
        controller: ctrl,
        focusNode: focus,
        decoration: InputDecoration(
          labelText: 'Produto',
          hintText: 'Digite código ou nome do produto…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _selecionado != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    ctrl.clear();
                    setState(() => _selecionado = null);
                  },
                )
              : null,
        ),
        onChanged: (_) {
          if (_selecionado != null) setState(() => _selecionado = null);
        },
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: kCard,
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final p = options.elementAt(i);
                return ListTile(
                  dense: true,
                  title: Text(p.produto,
                      style: const TextStyle(color: kText, fontSize: 13.5)),
                  subtitle: Text('Cod: ${p.codigo} · ${p.categoria}',
                      style: const TextStyle(color: kMuted, fontSize: 11.5)),
                  trailing: Text('${p.qtdSistema} un.',
                      style: const TextStyle(color: kAmber, fontSize: 12)),
                  onTap: () => onSelected(p),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardProduto(Produto p) {
    final divs = _divsDoProduto;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Sistema: ',
                  style: TextStyle(color: kMuted, fontSize: 12)),
              Text('${p.qtdSistema} un.',
                  style: const TextStyle(
                      color: kText, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.categoria,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (divs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '⚠️ ${divs.length} divergência(s) registrada(s): '
                '${divs.map((d) => '${d.cooperado.isEmpty ? 'sem nome' : d.cooperado} (${d.deltaFmt})').join(' · ')}',
                style: const TextStyle(color: kAmber, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDelta() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _deltaCtrl,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^-?\d{0,4}')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Diferença (+sobrando / −faltando)',
              helperText: 'Ex: sistema diz 11, físico tem 12 → +1 · físico tem 9 → −2',
              helperMaxLines: 2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () => _setDelta(_delta - 1),
          icon: const Icon(Icons.remove),
        ),
        IconButton.filledTonal(
          onPressed: () => _setDelta(_delta + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
