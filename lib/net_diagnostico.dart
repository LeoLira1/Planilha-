import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Diagnóstico de rede para quando o app leva "Failed host lookup".
///
/// A mensagem crua do Android não diz de quem é a culpa: URL errada, celular
/// sem internet, VPN, ou o resolvedor DNS da rede/operadora falhando num nome
/// que existe. Este arquivo descobre isso e devolve texto acionável:
///
///  1. TCP direto em 1.1.1.1:53 (por IP, sem DNS) → prova se há internet.
///  2. InternetAddress.lookup(host)               → o resolvedor do aparelho.
///  3. Consulta DNS pura (UDP/53) em 1.1.1.1 e 8.8.8.8 → o nome existe mesmo?
///
/// Nenhum passo lança exceção: qualquer falha vira "não deu para checar".

enum DnsPublico { ok, naoExiste, semResposta }

class DnsResultado {
  final DnsPublico status;
  final String? ip;
  const DnsResultado(this.status, [this.ip]);
}

class DiagnosticoRede {
  final bool internetOk;
  final bool dnsLocalOk;
  final String? ipLocal;
  final DnsResultado dnsPublico;

  const DiagnosticoRede({
    required this.internetOk,
    required this.dnsLocalOk,
    required this.ipLocal,
    required this.dnsPublico,
  });

  /// Explicação em português, já com o que fazer.
  String get texto {
    if (!internetOk && !dnsLocalOk) {
      return 'O celular não conseguiu abrir nenhuma conexão (nem TCP em '
          '1.1.1.1:53). Parece falta de internet: verifique Wi‑Fi/dados '
          'móveis, modo avião e se há VPN ou proxy ligado.';
    }
    if (dnsLocalOk) {
      return 'O nome do banco até resolve neste aparelho'
          '${ipLocal != null ? ' (IP $ipLocal)' : ''}, então o problema é na '
          'conexão em si: firewall, proxy, VPN ou rede corporativa bloqueando '
          'a porta 443 — ou instabilidade momentânea. Tente de novo e, se '
          'persistir, alterne entre Wi‑Fi e dados móveis.';
    }
    switch (dnsPublico.status) {
      case DnsPublico.naoExiste:
        return 'Esse nome NÃO existe no DNS público — a URL está errada ou o '
            'banco foi renomeado/apagado. Copie a URL exata em turso.tech → '
            'seu banco → Connect (formato: '
            'libsql://nome-do-banco-usuario.aws-us-east-2.turso.io).';
      case DnsPublico.ok:
        return 'A URL está certa: o nome existe no DNS público'
            '${dnsPublico.ip != null ? ' (IP ${dnsPublico.ip})' : ''}, mas o '
            'DNS do seu celular/operadora não está resolvendo. O que costuma '
            'resolver:\n'
            '• desligar VPN / bloqueador de anúncios (AdGuard, Blokada…);\n'
            '• alternar Wi‑Fi ↔ dados móveis, ou ativar/desativar o modo avião;\n'
            '• Configurações → Conexões → Mais configurações de conexão → DNS '
            'privado → "one.one.one.one".';
      case DnsPublico.semResposta:
        return 'O DNS deste aparelho não resolveu o nome do banco e a rede '
            'também bloqueou a checagem no DNS público (porta 53). Costuma ser '
            'VPN, DNS privado mal configurado ou rede corporativa: alterne para '
            'os dados móveis e teste de novo.';
    }
  }

  /// Uma linha por checagem, para quem quiser ver o detalhe técnico.
  String get detalhes {
    final dns = switch (dnsPublico.status) {
      DnsPublico.ok => 'nome existe${dnsPublico.ip != null ? ' (${dnsPublico.ip})' : ''}',
      DnsPublico.naoExiste => 'nome inexistente (NXDOMAIN)',
      DnsPublico.semResposta => 'sem resposta (porta 53 bloqueada?)',
    };
    return 'internet (TCP 1.1.1.1:53): ${internetOk ? 'ok' : 'falhou'}\n'
        'DNS do aparelho: ${dnsLocalOk ? 'ok ($ipLocal)' : 'falhou'}\n'
        'DNS público: $dns';
  }
}

/// Roda as três checagens. Nunca lança.
Future<DiagnosticoRede> diagnosticarRede(String host) async {
  final internet = await _tcpAlcancavel('1.1.1.1', 53);

  bool dnsLocalOk = false;
  String? ipLocal;
  try {
    final addrs = await InternetAddress.lookup(host)
        .timeout(const Duration(seconds: 6));
    if (addrs.isNotEmpty) {
      dnsLocalOk = true;
      ipLocal = addrs.first.address;
    }
  } catch (_) {
    dnsLocalOk = false;
  }

  // Se o próprio aparelho resolveu, não há o que checar no DNS público.
  final publico = dnsLocalOk
      ? DnsResultado(DnsPublico.ok, ipLocal)
      : await consultarDnsPublico(host);

  return DiagnosticoRede(
    internetOk: internet,
    dnsLocalOk: dnsLocalOk,
    ipLocal: ipLocal,
    dnsPublico: publico,
  );
}

/// Conecta por IP literal (sem DNS) só para saber se existe internet.
Future<bool> _tcpAlcancavel(String ip, int porta) async {
  Socket? s;
  try {
    s = await Socket.connect(InternetAddress(ip), porta,
        timeout: const Duration(seconds: 5));
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      s?.destroy();
    } catch (_) {}
  }
}

/// Pergunta o registro A do host direto ao 1.1.1.1 e ao 8.8.8.8 (UDP/53),
/// sem passar pelo resolvedor do Android. Vale a primeira resposta que chegar.
Future<DnsResultado> consultarDnsPublico(
  String host, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  RawDatagramSocket? sock;
  try {
    sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final socket = sock;
    final id = Random().nextInt(0xFFFF);
    final consulta = _montarConsultaDns(id, host);
    final completer = Completer<DnsResultado>();

    socket.listen((evento) {
      if (evento != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      final r = _lerRespostaDns(dg.data, id);
      if (r != null && !completer.isCompleted) completer.complete(r);
    }, onError: (_) {});

    for (final servidor in const ['1.1.1.1', '8.8.8.8']) {
      try {
        socket.send(consulta, InternetAddress(servidor), 53);
      } catch (_) {}
    }

    return await completer.future.timeout(
      timeout,
      onTimeout: () => const DnsResultado(DnsPublico.semResposta),
    );
  } catch (_) {
    return const DnsResultado(DnsPublico.semResposta);
  } finally {
    try {
      sock?.close();
    } catch (_) {}
  }
}

/// Query DNS padrão (RFC 1035): cabeçalho + QNAME + QTYPE A + QCLASS IN.
Uint8List _montarConsultaDns(int id, String host) {
  final b = BytesBuilder();
  b.add([(id >> 8) & 0xFF, id & 0xFF]);
  b.add([0x01, 0x00]); // recursão desejada
  b.add([0x00, 0x01]); // 1 pergunta
  b.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]); // 0 respostas/autoridade/extra
  for (final rotulo in host.split('.')) {
    if (rotulo.isEmpty) continue;
    final bytes = utf8.encode(rotulo);
    if (bytes.isEmpty || bytes.length > 63) continue;
    b.addByte(bytes.length);
    b.add(bytes);
  }
  b.addByte(0x00); // fim do nome
  b.add([0x00, 0x01]); // QTYPE = A
  b.add([0x00, 0x01]); // QCLASS = IN
  return b.toBytes();
}

/// Devolve o primeiro registro A da resposta (seguindo CNAMEs, que o
/// resolvedor recursivo já manda junto). null = resposta de outra consulta.
DnsResultado? _lerRespostaDns(Uint8List d, int idEsperado) {
  if (d.length < 12) return null;
  if (((d[0] << 8) | d[1]) != idEsperado) return null;

  final rcode = d[3] & 0x0F;
  if (rcode == 3) return const DnsResultado(DnsPublico.naoExiste);
  if (rcode != 0) return const DnsResultado(DnsPublico.semResposta);

  final perguntas = (d[4] << 8) | d[5];
  final respostas = (d[6] << 8) | d[7];

  // Nomes podem vir comprimidos (ponteiro 0xC0 = 2 bytes e acabou).
  int pularNome(int p) {
    while (p < d.length) {
      final len = d[p];
      if (len == 0) return p + 1;
      if ((len & 0xC0) == 0xC0) return p + 2;
      p += len + 1;
    }
    return p;
  }

  var i = 12;
  for (var q = 0; q < perguntas; q++) {
    i = pularNome(i) + 4; // + QTYPE + QCLASS
  }
  for (var a = 0; a < respostas; a++) {
    i = pularNome(i);
    if (i + 10 > d.length) break;
    final tipo = (d[i] << 8) | d[i + 1];
    final rdlen = (d[i + 8] << 8) | d[i + 9];
    i += 10;
    if (tipo == 1 && rdlen == 4 && i + 4 <= d.length) {
      return DnsResultado(
          DnsPublico.ok, '${d[i]}.${d[i + 1]}.${d[i + 2]}.${d[i + 3]}');
    }
    i += rdlen;
  }
  // Nome existe (NOERROR) mas sem A — ex.: só IPv6. Ainda é "existe".
  return respostas > 0
      ? const DnsResultado(DnsPublico.ok)
      : const DnsResultado(DnsPublico.naoExiste);
}
