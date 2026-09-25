import 'package:docscan/core/google_config.dart';
import 'package:docscan/features/drive/drive_sign_in_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  test('release builds use the Web client ID', () {
    expect(
      GoogleConfig.resolvedWebClientId,
      '759737423939-qpjr70baleq7rnksdr4essgkoogbi1ba.apps.googleusercontent.com',
    );
    expect(GoogleConfig.isConfigured, isTrue);
  });

  test('developer error 10 is the SHA-1 and package mismatch', () {
    final report = describeDriveSignInError(
      const GoogleSignInException(
        code: GoogleSignInExceptionCode.providerConfigurationError,
        description:
            'GetCredentialProviderConfigurationException: [28444] Developer console is not set up correctly.',
      ),
    );
    expect(report.problem, DriveSignInProblem.developerError);

    final status = describeDriveSignInError(
      Exception('ApiException: 10: DEVELOPER_ERROR'),
    );
    expect(status.problem, DriveSignInProblem.developerError);
  });

  test('an Android client ID used as serverClientId is a wrong-client error', () {
    final report = describeDriveSignInError(
      const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'serverClientId must be provided on Android',
      ),
    );
    expect(report.problem, DriveSignInProblem.wrongClient);

    final audience = describeDriveSignInError(
      Exception('invalid_client: invalid audience'),
    );
    expect(audience.problem, DriveSignInProblem.wrongClient);
  });

  test('a Gmail missing from test users is reported separately', () {
    final report = describeDriveSignInError(
      Exception('Error 403: access_denied'),
    );
    expect(report.problem, DriveSignInProblem.testUser);
  });

  test('cancel stays silent', () {
    final report = describeDriveSignInError(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    expect(report.problem, DriveSignInProblem.canceled);
  });
}
