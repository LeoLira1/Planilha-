import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'net_diagnostico.dart';

/// Exceção com a mensagem REAL do erro (DNS, HTTP 401, timeout, erro SQL…).
/// Nunca descartamos a causa — ela sempre chega até a UI.
class TursoException implements Exception {
  final String message;

  /// true quando a falha foi de rede (DNS, timeout, conexão recusada) e não
  /// do banco — nesse caso vale rodar o diagnóstico de rede.
  final bool problemaDeRede;

  TursoException(this.message, {this.problemaDeRede = false});

  @override
  String toString() => message;
}

class Stmt {
  final String sql;
  final List<dynamic> args;
  const Stmt(this.sql, [this.args = const []]);
}

/// Cliente da API HTTP do Turso/libsql (endpoint /v2/pipeline).
///
/// O dashboard CAMDA Estoque usa embedded replica (libsql sync); escrever
/// direto no banco primário via HTTP faz as divergências aparecerem no
/// dashboard no próximo sync dele.
class TursoService {
  final String baseUrl;
  final String token;

  TursoService({required String url, required this.token})
      : baseUrl = normalizeUrl(url);

  /// UM cliente para toda a vida do serviço. As funções de topo do
  /// package:http (http.post) criam e fecham um cliente por chamada, ou seja
  /// pagam DNS + TCP + TLS do zero em TODA consulta — era esse, e não o
  /// tamanho dos dados, o custo dominante do "Recarregar". Com keep-alive a
  /// segunda consulta em diante reaproveita a conexão já aberta.
  http.Client _client = http.Client();

  /// Ao trocar de Wi-Fi para dados móveis (ou vice-versa) as conexões do pool
  /// morrem e reutilizá-las falha na hora. Antes de repetir a tentativa
  /// começamos do zero — é o mesmo motivo pelo qual o retry existe.
  void _renovarCliente() {
    _client.close();
    _client = http.Client();
  }

  /// Fecha as conexões abertas. Chamar ao descartar o serviço (troca de banco
  /// nas configurações, fim da tela).
  void dispose() => _client.close();

  /// Aceita libsql://host, wss://host, https://host ou host puro, e joga fora
  /// o que o teclado/copiar-colar costuma trazer junto: espaços, caracteres
  /// invisíveis, caminho (`/v2/pipeline`), query (`?authToken=…`) e `user@`.
  /// Sobra sempre `https://host[:porta]`.
  static String normalizeUrl(String raw) {
    // Remove espaços e invisíveis (zero-width, BOM, NBSP) em qualquer posição:
    // colados pelo WhatsApp/e-mail eles fazem o DNS falhar sem motivo visível.
    var u = raw.replaceAll(RegExp(r'[\s\u00A0\u200B-\u200D\uFEFF]'), '');
    u = u.replaceFirst(RegExp(r'^(libsql|wss|ws|http|https)://', caseSensitive: false), '');
    // Query/fragmento/caminho não fazem parte do host.
    u = u.split(RegExp(r'[/?#]')).first;
    // Credenciais embutidas (user:senha@host).
    if (u.contains('@')) u = u.substring(u.lastIndexOf('@') + 1);
    return 'https://${u.toLowerCase()}';
  }

  /// Host puro, para o diagnóstico de rede e para as mensagens de erro.
  String get host => Uri.parse(baseUrl).host;

  /// Erros de rede pedem uma segunda tentativa antes de acusar o usuário: em
  /// celular, o primeiro lookup logo após trocar de Wi‑Fi/dados falha sozinho.
  static const _tentativas = 2;

  static Map<String, dynamic> _encodeArg(dynamic v) {
    if (v == null) return {'type': 'null'};
    if (v is int) return {'type': 'integer', 'value': '$v'};
    if (v is double) return {'type': 'float', 'value': v};
    return {'type': 'text', 'value': '$v'};
  }

  static dynamic _decodeCell(dynamic cell) {
    if (cell is! Map) return cell;
    switch (cell['type']) {
      case 'null':
        return null;
      case 'integer':
        return int.tryParse('${cell['value']}');
      case 'float':
        return cell['value'];
      default:
        return cell['value'];
    }
  }

  /// Executa os statements em sequência na MESMA conexão (um único request
  /// HTTP), e retorna as linhas de cada um. Erros viram TursoException com a
  /// mensagem real.
  Future<List<List<List<dynamic>>>> pipeline(List<Stmt> stmts) async {
    final body = jsonEncode({
      'requests': [
        for (final s in stmts)
          {
            'type': 'execute',
            'stmt': {
              'sql': s.sql,
              'args': s.args.map(_encodeArg).toList(),
            },
          },
        {'type': 'close'},
      ],
    });

    final resp = await _postComRetry(body);

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw TursoException(
          'HTTP ${resp.statusCode}: token inválido, expirado ou sem permissão de escrita.');
    }
    if (resp.statusCode != 200) {
      final preview =
          resp.body.length > 300 ? '${resp.body.substring(0, 300)}…' : resp.body;
      throw TursoException('HTTP ${resp.statusCode}: $preview');
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw TursoException('Resposta inesperada do servidor (não é JSON). '
          'Confira se a URL aponta para um banco Turso.');
    }

    final out = <List<List<dynamic>>>[];
    final results = (data['results'] as List?) ?? [];
    for (final r in results) {
      if (r['type'] == 'error') {
        final msg = r['error']?['message'] ?? 'erro desconhecido';
        throw TursoException('Erro SQL: $msg');
      }
      final response = r['response'];
      if (response == null || response['type'] != 'execute') continue;
      final rows = (response['result']?['rows'] as List?) ?? [];
      out.add([
        for (final row in rows) [for (final cell in (row as List)) _decodeCell(cell)],
      ]);
    }
    return out;
  }

  /// POST no /v2/pipeline com uma segunda tentativa para falhas de rede.
  /// Toda exceção vira TursoException com a causa real (nunca `catch (_)`).
  Future<http.Response> _postComRetry(String body) async {
    TursoException? ultimoErro;
    for (var tentativa = 1; tentativa <= _tentativas; tentativa++) {
      try {
        return await _client
            .post(
              Uri.parse('$baseUrl/v2/pipeline'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 25));
      } on SocketException catch (e) {
        final dns = e.message.contains('Failed host lookup');
        ultimoErro = TursoException(
          dns
              ? 'O celular não conseguiu descobrir o endereço de "$host" (DNS).'
              : 'Erro de rede: ${e.message}',
          problemaDeRede: true,
        );
      } on TimeoutException {
        ultimoErro = TursoException(
            'Tempo esgotado (25s) ao conectar em $host.',
            problemaDeRede: true);
      } on http.ClientException catch (e) {
        ultimoErro =
            TursoException('Erro de conexão: ${e.message}', problemaDeRede: true);
      } on HandshakeException catch (e) {
        ultimoErro = TursoException(
            'Falha no HTTPS/TLS com $host: ${e.message}. Se a rede usa proxy '
            'ou antivírus com inspeção de tráfego, teste nos dados móveis.',
            problemaDeRede: true);
      }
      if (tentativa < _tentativas) {
        _renovarCliente();
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    throw ultimoErro!;
  }

  Future<List<List<dynamic>>> execute(String sql,
      [List<dynamic> args = const []]) async {
    final res = await pipeline([Stmt(sql, args)]);
    return res.isEmpty ? [] : res.first;
  }

  /// Hora de Brasília (UTC−3, sem horário de verão desde 2019), no mesmo
  /// formato que o dashboard grava: "YYYY-MM-DD HH:MM:SS".
  static String agoraBrt() {
    final t = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }

  // ── Operações do app ────────────────────────────────────────────────────

  /// Testa a conexão e retorna (ok, mensagem real do resultado/erro).
  /// Quando a falha é de rede, roda o diagnóstico e diz de quem é a culpa
  /// (URL errada × DNS do celular × sem internet) e o que fazer.
  Future<(bool, String)> testConnection() async {
    try {
      final rows = await execute('SELECT COUNT(*) FROM estoque_mestre');
      final n = rows.isNotEmpty ? rows.first.first : 0;
      return (true, 'Conexão OK — $n produtos no estoque mestre.');
    } on TursoException catch (e) {
      if (!e.problemaDeRede) return (false, e.message);
      final d = await diagnosticarRede(host);
      return (false, '${e.message}\n\n${d.texto}\n\n${d.detalhes}');
    } catch (e) {
      return (false, 'Erro inesperado: $e');
    }
  }

  /// Diagnóstico avulso, sem depender de uma falha anterior.
  Future<DiagnosticoRede> diagnosticar() => diagnosticarRede(host);

  static const _sqlDivergencias =
      'SELECT id, codigo, produto, categoria, delta, status, cooperado, criado_em '
      'FROM divergencias';

  /// Assinatura do estoque: UMA linha que muda sempre que um produto entra,
  /// sai, ou tem quantidade, nome ou categoria alterados — exatamente os
  /// quatro campos que o app usa. Custa alguns bytes contra os ~140 KB da
  /// tabela inteira, então dá para conferir em todo refresh e só baixar os
  /// produtos quando algo realmente mudou.
  ///
  /// As colunas mexidas por resolverDivergencia (status, diferenca,
  /// qtd_fisica, ultima_contagem) ficam de fora de propósito: resolver uma
  /// divergência não deve invalidar o cache de produtos.
  static const _sqlAssinatura =
      'SELECT COUNT(*), COALESCE(SUM(qtd_sistema), 0), '
      'COALESCE(SUM(LENGTH(codigo) + LENGTH(produto) + LENGTH(categoria)), 0) '
      'FROM estoque_mestre';

  Future<List<Produto>> fetchProdutos() async {
    // Sem ORDER BY: ordenar ~840 linhas no aparelho é instantâneo e poupa
    // trabalho do servidor.
    final rows = await execute(
        'SELECT codigo, produto, categoria, qtd_sistema FROM estoque_mestre');
    return rows.map(Produto.fromRow).toList()
      ..sort((a, b) => a.produto.compareTo(b.produto));
  }

  /// Divergências ativas (mesma tabela que alimenta a aba Divergências do dashboard).
  Future<List<Divergencia>> fetchDivergencias({String? codigo}) async {
    final where = codigo == null ? '' : ' WHERE codigo = ?';
    final rows = await execute(
      '$_sqlDivergencias$where ORDER BY criado_em DESC',
      codigo == null ? const [] : [codigo],
    );
    return rows.map(Divergencia.fromRow).toList();
  }

  /// O caminho do "Recarregar": divergências + assinatura do estoque num
  /// ÚNICO request (o pipeline roda os dois statements na mesma conexão).
  /// Os produtos só são baixados depois, e só se a assinatura tiver mudado.
  Future<({List<Divergencia> divergencias, String assinatura})>
      fetchDivergenciasEAssinatura() async {
    final res = await pipeline([
      const Stmt('$_sqlDivergencias ORDER BY criado_em DESC'),
      const Stmt(_sqlAssinatura),
    ]);
    final divs = res.isNotEmpty
        ? res[0].map(Divergencia.fromRow).toList()
        : <Divergencia>[];
    final linha =
        (res.length > 1 && res[1].isNotEmpty) ? res[1].first : <dynamic>[];
    return (
      divergencias: divs,
      assinatura: linha.map((c) => '${c ?? 0}').join('|'),
    );
  }

  /// Mesma lógica de registrar_divergencia_manual() do dashboard:
  /// grava em `divergencias` e em `historico_divergencias` (atenção: a ordem
  /// das colunas `cooperado`/`delta` difere entre as duas tabelas).
  /// delta > 0 = sobra, delta < 0 = falta. O estoque do sistema NÃO é alterado.
  Future<String> registrarDivergencia(
      Produto p, int delta, String cooperado) async {
    if (delta == 0) throw TursoException('A diferença não pode ser zero.');
    final status = delta > 0 ? 'sobra' : 'falta';
    final coop = cooperado.trim();
    final agora = agoraBrt();
    await pipeline([
      const Stmt('BEGIN'),
      Stmt(
        'INSERT INTO divergencias (codigo, produto, categoria, delta, status, cooperado, criado_em) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [p.codigo, p.produto, p.categoria, delta, status, coop, agora],
      ),
      Stmt(
        'INSERT INTO historico_divergencias (codigo, produto, categoria, cooperado, delta, status, criado_em) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [p.codigo, p.produto, p.categoria, coop, delta, status, agora],
      ),
      const Stmt('COMMIT'),
    ]);
    final sinal = delta > 0 ? '+' : '';
    final nome = coop.isEmpty ? 'sem cooperado' : coop;
    return '✅ ${p.produto} (${p.codigo}) → $status de $sinal$delta un. registrada para $nome.';
  }

  /// Mesma lógica de resolver_divergencia() do dashboard: apaga o registro e,
  /// se não restar nenhuma divergência do produto, reseta o estoque_mestre
  /// para status 'ok'.
  ///
  /// Tudo num único request transacionado: antes eram três idas ao servidor
  /// (DELETE, COUNT, UPDATE), cada uma abrindo conexão própria, com uma
  /// corrida entre a contagem e o update. O NOT EXISTS faz o papel do COUNT já
  /// dentro da transação, depois do DELETE.
  Future<void> resolverDivergencia(Divergencia d) async {
    await pipeline([
      const Stmt('BEGIN'),
      Stmt('DELETE FROM divergencias WHERE id = ?', [d.id]),
      Stmt(
        "UPDATE estoque_mestre SET status = 'ok', diferenca = 0, "
        "qtd_fisica = qtd_sistema, ultima_contagem = ? "
        "WHERE codigo = ? AND status IN ('falta', 'sobra') "
        "AND NOT EXISTS (SELECT 1 FROM divergencias WHERE codigo = ?)",
        [agoraBrt(), d.codigo, d.codigo],
      ),
      const Stmt('COMMIT'),
    ]);
  }
}
