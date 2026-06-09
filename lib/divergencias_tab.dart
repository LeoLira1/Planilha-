import 'package:flutter/material.dart';

import 'main.dart';
import 'models.dart';
import 'turso_service.dart';

/// Lista das divergências ativas (tabela `divergencias`), igual à aba
/// Divergências do dashboard. Permite resolver (apagar) um registro com a
/// mesma lógica do dashboard, exigindo a senha de edição.
class DivergenciasTab extends StatelessWidget {
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

  Future<void> _resolver(BuildContext context, Divergencia d) async {
    if (!senhaOk) {
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
      await service.resolverDivergencia(d);
      await onChanged();
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
    if (divergencias.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: kAmber,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.check_circle_outline, size: 48, color: kGreen),
            SizedBox(height: 12),
            Center(
              child: Text('Nenhuma divergência ativa. 🎉',
                  style: TextStyle(color: kMuted)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: kAmber,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: divergencias.length,
        itemBuilder: (context, i) {
          final d = divergencias[i];
          final sobra = d.delta > 0;
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
                child: Text(
                  'Cod: ${d.codigo} · ${d.categoria}\n'
                  '${d.cooperado.isEmpty ? 'sem cooperado' : d.cooperado} · ${d.criadoEm}',
                  style: const TextStyle(color: kMuted, fontSize: 11.5),
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
