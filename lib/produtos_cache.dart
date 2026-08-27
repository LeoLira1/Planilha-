import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Produtos do `estoque_mestre` guardados no aparelho.
///
/// O catálogo só muda quando o dashboard reimporta a planilha, então rebaixar
/// as ~800 e poucas linhas (~140 KB no formato do libsql) a cada "Recarregar"
/// é desperdício. Com o cache o app abre com a lista pronta — inclusive
/// offline — e só busca os produtos de novo quando a assinatura do estoque
/// muda (ver TursoService.fetchDivergenciasEAssinatura).
class ProdutosCache {
  /// A versão está na chave e no conteúdo: se o formato mudar, o cache antigo
  /// é ignorado em vez de ser lido errado.
  static const _chave = 'produtos_cache_v1';

  /// As linhas vão como arrays (`["cod","nome","categoria",12]`) e não como
  /// objetos: fica bem menor e cai direto no `Produto.fromRow`.
  static Future<void> gravar(List<Produto> produtos, String assinatura) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _chave,
      jsonEncode({
        'v': 1,
        'assinatura': assinatura,
        'salvo_em': DateTime.now().millisecondsSinceEpoch,
        'produtos': [
          for (final p in produtos)
            [p.codigo, p.produto, p.categoria, p.qtdSistema],
        ],
      }),
    );
  }

  /// Devolve null quando não há cache, quando a versão do formato não bate ou
  /// quando o JSON está corrompido. Em qualquer desses casos o app apenas
  /// baixa tudo de novo — cache ruim nunca vira tela de erro.
  static Future<CacheProdutos?> ler() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chave);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['v'] != 1) return null;
      final linhas = (data['produtos'] as List?) ?? const [];
      return CacheProdutos(
        produtos: [for (final l in linhas) Produto.fromRow(l as List)],
        assinatura: '${data['assinatura'] ?? ''}',
        salvoEm: DateTime.fromMillisecondsSinceEpoch(
            (data['salvo_em'] as int?) ?? 0),
      );
    } catch (_) {
      return null;
    }
  }

  /// Usado ao trocar de banco nas configurações: os produtos guardados são de
  /// outro `estoque_mestre` e não valem mais nada.
  static Future<void> limpar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chave);
  }
}

class CacheProdutos {
  final List<Produto> produtos;

  /// Assinatura do estoque no momento em que o cache foi gravado.
  final String assinatura;

  final DateTime salvoEm;

  const CacheProdutos({
    required this.produtos,
    required this.assinatura,
    required this.salvoEm,
  });
}
