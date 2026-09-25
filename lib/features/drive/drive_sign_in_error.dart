import 'package:google_sign_in/google_sign_in.dart';

/// Why a Google sign-in attempt failed, in terms the user can report.
enum DriveSignInProblem { canceled, developerError, wrongClient, testUser, other }

class DriveSignInProblemReport {
  const DriveSignInProblemReport(this.problem, this.detail);

  final DriveSignInProblem problem;

  /// Short platform text kept so an unexpected failure can be reported.
  final String detail;
}

DriveSignInProblemReport describeDriveSignInError(Object error) {
  final detail = _detail(error);
  final lower = detail.toLowerCase();
  if (error is GoogleSignInException &&
      error.code == GoogleSignInExceptionCode.canceled) {
    return DriveSignInProblemReport(DriveSignInProblem.canceled, detail);
  }
  if (_wrongClient(error, lower)) {
    return DriveSignInProblemReport(DriveSignInProblem.wrongClient, detail);
  }
  if (_developerError(error, lower)) {
    return DriveSignInProblemReport(DriveSignInProblem.developerError, detail);
  }
  if (_testUser(lower)) {
    return DriveSignInProblemReport(DriveSignInProblem.testUser, detail);
  }
  return DriveSignInProblemReport(DriveSignInProblem.other, detail);
}

String _detail(Object error) {
  final raw = error is GoogleSignInException
      ? '${error.code.name}: ${error.description ?? ''}'
      : error.toString();
  final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= 240) return compact;
  return '${compact.substring(0, 240)}…';
}

bool _wrongClient(Object error, String lower) {
  if (error is GoogleSignInException &&
      error.code == GoogleSignInExceptionCode.clientConfigurationError) {
    return true;
  }
  return lower.contains('serverclientid') ||
      lower.contains('invalid_client') ||
      lower.contains('invalid audience') ||
      lower.contains('unregistered caller');
}

bool _developerError(Object error, String lower) {
  if (error is GoogleSignInException &&
      error.code == GoogleSignInExceptionCode.providerConfigurationError &&
      !lower.contains('not supported')) {
    return true;
  }
  if (lower.contains('developer_error') ||
      lower.contains('developer console is not set up') ||
      lower.contains('28444')) {
    return true;
  }
  return RegExp(
    r'(status(?:\s*code)?|error|code|api)\s*[:= ]\s*\[?10\]?(?!\d)',
  ).hasMatch(lower);
}

bool _testUser(String lower) {
  return lower.contains('access_denied') ||
      lower.contains('access blocked') ||
      lower.contains('has not completed the google verification') ||
      lower.contains('not a test user') ||
      lower.contains('403');
}
