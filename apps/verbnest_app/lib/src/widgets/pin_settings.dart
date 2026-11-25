import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_http/verbnest_http.dart';

import '../../l10n/l10n.dart';
import '../state/keystore_relay.dart';
import '../state/network_state.dart';
import 'ui/still_controls.dart';
import 'ui/still_tooltip.dart';

String _short(String fp) => fp.length > 23 ? '${fp.substring(0, 23)}…' : fp;
String _day(DateTime d) => d.toUtc().toIso8601String().substring(0, 10);

/// Server key pinning and the oldest TLS version (FR-HTTP-013d), shown under
/// the certificates in Settings > Network.
class PinSettingsSection extends ConsumerWidget {
  const PinSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(networkProvider);
    final n = ref.read(networkProvider.notifier);
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
          child: Text(
            l.nsPinsTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        StillSwitchListTile(
          key: const Key('pin-by-default'),
          title: Text(l.nsPinByDefault),
          subtitle: Text(l.nsPinByDefaultHint),
          value: c.pinByDefault,
          onChanged: n.setPinByDefault,
        ),
        if (c.pins.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
            child: Text(l.nsPinsNone),
          ),
        for (final p in c.pins) _pinTile(context, p, n),
        _minTlsRow(context, c, n),
        _testButton(context),
      ],
    );
  }

  Widget _pinTile(BuildContext context, PinEntry p, NetworkNotifier n) {
    final l = context.l10n;
    return ListTile(
      key: Key('pin-${p.host}:${p.port}'),
      dense: true,
      leading: const Icon(Icons.push_pin_outlined),
      title: Text(p.label),
      subtitle: Text(
        p.manual
            ? l.nsPinManual(_short(p.spki))
            : l.nsPinSub(
                _short(p.spki),
                p.firstSeen == null ? '' : _day(p.firstSeen!),
              ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            key: Key('pin-enabled-${p.host}:${p.port}'),
            value: p.enabled,
            onChanged: (v) => n.putPin(p.copyWith(enabled: v)),
          ),
          StillIconButton(
            key: Key('pin-remove-${p.host}:${p.port}'),
            tooltip: l.nsPinRemove,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => n.removePin(p),
          ),
        ],
      ),
    );
  }

  Widget _minTlsRow(BuildContext context, NetworkConfig c, NetworkNotifier n) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l.nsMinTls),
          SegmentedButton<TlsVersion?>(
            key: const Key('min-tls'),
            segments: [
              ButtonSegment(value: null, label: Text(l.nsMinTlsDefault)),
              ButtonSegment(value: TlsVersion.v12, label: Text(l.nsMinTls12)),
              ButtonSegment(value: TlsVersion.v13, label: Text(l.nsMinTls13)),
            ],
            selected: {c.minTls},
            onSelectionChanged: (s) => n.setMinTls(s.first),
          ),
        ],
      ),
    );
  }

  Widget _testButton(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, bottom: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: const Key('test-connection'),
          icon: const Icon(Icons.network_check),
          label: Text(l.nsTestConn),
          onPressed: () => showDialog<void>(
            animationStyle: AnimationStyle.noAnimation,
            context: context,
            builder: (_) => const TestConnectionDialog(),
          ),
        ),
      ),
    );
  }
}

/// How a test connection ended; overridable in tests.
typedef TlsProber = Future<TlsProbe> Function(Uri url, TlsConfig? tls);

final tlsProberProvider = Provider<TlsProber>(
  (ref) =>
      (url, tls) => probeTls(url, tls: tls),
);

/// Connects to a server with the saved certificates and pins, no request sent,
/// and shows the handshake: server certificate, trust, client certificate and
/// pin state. Lets the person pin the server or trust a changed key.
class TestConnectionDialog extends ConsumerStatefulWidget {
  const TestConnectionDialog({super.key, this.initialUrl});

  /// The address to fill in (the request's URL, from the Headers tab).
  final String? initialUrl;

  @override
  ConsumerState<TestConnectionDialog> createState() => _TestState();
}

class _TestState extends ConsumerState<TestConnectionDialog> {
  late final _url = TextEditingController(text: widget.initialUrl ?? '');
  bool _busy = false;
  String? _error;
  TlsProbe? _probe;
  Uri? _target;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Uri? _parse() {
    var t = _url.text.trim();
    if (t.isEmpty) return null;
    if (!t.contains('://')) t = 'https://$t';
    final u = Uri.tryParse(t);
    return u == null || u.host.isEmpty ? null : u;
  }

  Future<void> _run() async {
    final u = _parse();
    if (u == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _probe = null;
      _target = u;
    });
    final tls = ref
        .read(networkProvider)
        .tlsWith(relay: ref.read(keystoreRelayProvider));
    try {
      final p = await ref.read(tlsProberProvider)(u, tls);
      if (mounted) setState(() => _probe = p);
    } on TlsProbeError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pin() {
    final p = _probe!;
    final u = _target!;
    ref
        .read(networkProvider.notifier)
        .putPin(
          PinEntry.firstUse(
            u.host,
            u.hasPort ? u.port : 443,
            p.server,
            DateTime.now(),
          ),
        );
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = _probe;
    return AlertDialog(
      title: Text(l.nsTestTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('test-url'),
                controller: _url,
                autofocus: true,
                decoration: InputDecoration(labelText: l.nsTestUrl),
                onSubmitted: (_) => _run(),
              ),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  l.nsTestFailed(_error!),
                  key: const Key('test-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (p != null) ..._result(context, p),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.nsTestClose),
        ),
        FilledButton(
          key: const Key('test-run'),
          onPressed: _busy ? null : _run,
          child: Text(l.nsTestRun),
        ),
      ],
    );
  }

  List<Widget> _result(BuildContext context, TlsProbe p) {
    final l = context.l10n;
    final cc = p.clientCertificate;
    final pin = p.pin;
    final lines = <Widget>[
      Text(l.nsTestOk('${p.time.inMilliseconds}'), key: const Key('test-ok')),
      Text(l.nsTestServer(p.server.subject)),
      Text(l.nsTestExpires(_day(p.server.notAfter))),
      Text(p.trusted ? l.nsTestTrusted : l.nsTestUntrusted),
      Text(p.hostMatches ? l.nsTestName : l.nsTestNameNo),
      Text(
        cc == null
            ? l.nsTestClientNone
            : l.nsTestClient(cc.label.isEmpty ? cc.hostPattern : cc.label),
      ),
      if (p.rejectedClientCertificate) Text(l.nsTestRejected),
    ];
    {
      switch (pin.status) {
        case PinStatus.mismatch:
          lines
            ..add(
              Text(
                l.nsTestPinMismatch(
                  _short(pin.entry!.spki),
                  _short(p.server.spkiSha256),
                ),
                key: const Key('test-pin-mismatch'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            )
            ..add(
              TextButton(
                key: const Key('test-trust-new'),
                onPressed: _pin,
                child: Text(l.nsTestTrustNew),
              ),
            );
        case PinStatus.matches:
          lines.add(Text(l.nsTestPinMatches));
        case PinStatus.recorded || PinStatus.notApplicable:
          lines
            ..add(Text(l.nsTestPinRecorded))
            ..add(
              TextButton(
                key: const Key('test-pin'),
                onPressed: p.trusted ? _pin : null,
                child: Text(l.nsTestPin),
              ),
            );
        case PinStatus.disabled || PinStatus.unverified:
          break;
      }
    }
    return [
      const SizedBox(height: 4),
      for (final w in lines)
        Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: w),
    ];
  }
}
