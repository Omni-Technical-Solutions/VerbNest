import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

/// The attachment id inside a form-data file reference, or null when [ref] is
/// a plain path.
String? attachmentIdOf(String ref) {
  if (!ref.startsWith('attachment:')) return null;
  final rest = ref.substring('attachment:'.length);
  final slash = rest.indexOf('/');
  return slash < 0 ? rest : rest.substring(0, slash);
}

/// A request would send secret variables to a host the user has not approved
/// for them.
class SecretHostNotApproved extends RequestBuildError {
  SecretHostNotApproved(this.names, this.host)
    : super(
        'Secret ${names.join(', ')} has not been approved for host $host. '
        'Approve the host to send it there.',
      );

  final List<String> names;
  final String host;
}

/// Turns [item] into a ready-to-send request: inherits auth from the
/// containers above [requestId], swaps OAuth 2.0 auth for a bearer token via
/// [oauthToken], and reads attachment files from [repo].
///
/// This is the single path from a stored request to a [PreparedRequest]; the
/// app editor, the runner and the CLI all go through it.
Future<PreparedRequest> prepareRequest({
  required WorkspaceRepository repo,
  required String requestId,
  required HttpRequestItem item,
  required VariableResolver resolver,
  required HttpSettings defaults,
  required Future<Auth> Function(OAuth2Auth auth) oauthToken,
  SecretHosts? secretHosts,
}) async {
  var auth = effectiveAuth(item.auth, repo.authChain(requestId));
  if (auth is OAuth2Auth) auth = await oauthToken(auth);
  final prepared = await RequestBuilder(
    defaults: defaults,
    readFile: (ref) async => repo.attachmentBytes(attachmentIdOf(ref) ?? ref),
  ).build(item, resolver, auth: auth);
  if (secretHosts != null && prepared.secretNames.isNotEmpty) {
    final url = prepared.spec.url;
    final blocked = secretHosts.blocked(prepared.secretNames, url);
    if (blocked.isNotEmpty) {
      throw SecretHostNotApproved(blocked, SecretHosts.hostOf(url));
    }
  }
  return prepared;
}

/// Results of the enabled assertions of [item] against [response].
List<TestResult> evaluateAssertions(
  HttpRequestItem item,
  HttpResponseRecord response,
  VariableResolver resolver,
) {
  final facts = ResponseFacts(
    status: response.status,
    headers: response.headers,
    body: response.bodyText,
    timeMs: response.timings.total.inMilliseconds,
  );
  return [
    for (final a in item.assertions)
      if (a.enabled)
        a.evaluate(facts, resolve: (t) => resolver.resolve(t).value),
  ];
}

/// The user-facing message of a failure to prepare or send a request, or null
/// when [error] is not one of those.
String? requestErrorMessage(Object error) => switch (error) {
  OAuth2Error(:final message) => message,
  RequestBuildError(:final message) => message,
  HttpEngineError(:final message) => message,
  _ => null,
};
